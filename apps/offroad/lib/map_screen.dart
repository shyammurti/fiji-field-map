import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:offroad_core/fiji.dart';
import 'package:offroad_core/position.dart';
import 'package:offroad_core/trails.dart';
import 'package:offroad_maps/overview.dart';
import 'package:offroad_platform/device_position.dart';
import 'package:offroad_storage/navigation.dart';
import 'package:offroad_storage/road_index.dart';

import 'main.dart';
import 'navigation_ui.dart';
import 'position_panel.dart';
import 'trail_session.dart';

const fijiCenter = LatLng(FijiStarter.centerLat, FijiStarter.centerLon);
const _sea = Color(0xffcadfe0);
const _satSea = Color(0xff102a33);
const _nightMap = ColorFilter.matrix([
  -.65,
  0,
  0,
  0,
  188,
  0,
  -.52,
  0,
  0,
  165,
  0,
  0,
  -.39,
  0,
  139,
  0,
  0,
  0,
  1,
  0,
]);

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({
    super.key,
    required this.project,
    required this.night,
    required this.onTheme,
  });
  final LocalProject project;
  final bool night;
  final VoidCallback onTheme;
  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with WidgetsBindingObserver {
  final map = MapController();
  final desktop = !Platform.isAndroid && !Platform.isIOS;
  bool ready = false, follow = false, compass = false, picking = false;
  bool zoomedIn = false, outside = false;
  bool resumeGps = false, zoomOnFix = false, satellite = false, busy = false;
  bool connectToRoad = true;
  TrailSession? get field => widget.project.field;
  List<RoadLine> detail = [];
  List<Polyline> _roadPolylines = const [];
  ({double south, double west, double north, double east, int tier})?
  _roadsBounds;
  Timer? roadsTimer;
  int cameraGeneration = 0;
  int _satEpoch = 0;
  String? activeTrailId, activeName, snapNote, pickingNav;
  LatLng? snapPoint, navStart, navDest, rerouteGoal;
  String navStartLabel = 'My location', navDestLabel = '';
  bool navUseGpsStart = true;
  final EtaEstimator eta = EtaEstimator();
  PathPart? activePath, approachTo;
  List<PathPart>? reviewedRaw, reviewedSnapped;
  List<PathPart>? get reviewed => connectToRoad ? reviewedSnapped : reviewedRaw;
  bool reviewedDrive = false, rerouting = false;
  int offFixes = 0;
  DateTime? lastReroute;
  Fix? lastGuidanceFix;
  ProviderSubscription<AsyncValue<PositionState>>? _positionSub;

  void _rebuildRoadPolylines() {
    if (detail.isEmpty) {
      _roadPolylines = const [];
      return;
    }
    final ink = widget.night || satellite
        ? Colors.amber.shade300
        : const Color(0xff93582a);
    _roadPolylines = [
      for (final r in detail)
        Polyline(
          points: r.points,
          strokeWidth: r.kind == 'path' || r.kind == 'track' ? 1.8 : 3,
          color: ink,
        ),
    ];
  }

  void _endNavigation() {
    eta.reset();
    setState(() {
      activeTrailId = null;
      activeName = null;
      activePath = null;
      approachTo = null;
      rerouteGoal = null;
      navStart = null;
      navDest = null;
      navDestLabel = '';
      offFixes = 0;
    });
  }

  Future<void> reroute(PositionState s) async {
    final fix = s.fix, target = approachTo, goal = rerouteGoal;
    final current = activePath;
    if ((target == null && goal == null) ||
        current == null ||
        fix == null ||
        s.status != FixStatus.live ||
        identical(fix, lastGuidanceFix)) {
      return;
    }
    lastGuidanceFix = fix;
    final here = LatLng(fix.lat, fix.lon);
    // Once on the saved trail, guidance stays on that trail.
    if (target != null && guide(target, here).offset < 20) {
      approachTo = null;
      return;
    }
    final off =
        guide(current, here).offset > math.max(30, (fix.accuracy ?? 0) * 1.5);
    offFixes = off ? offFixes + 1 : 0;
    if (!off ||
        offFixes < 3 ||
        rerouting ||
        (lastReroute != null &&
            DateTime.now().difference(lastReroute!).inSeconds < 35)) {
      return;
    }
    rerouting = true;
    lastReroute = DateTime.now();
    try {
      final dest = target != null ? target.first : goal!;
      final p = await drivingDirections(
        field!.index,
        field!.trails,
        here,
        dest,
      );
      if (mounted &&
          ((target != null && identical(approachTo, target)) ||
              (goal != null && rerouteGoal == goal))) {
        setState(
          () => activePath = target != null ? [...p, ...target.skip(1)] : p,
        );
        toast('Updated driving directions');
      }
    } catch (_) {
      if (mounted &&
          ((target != null && identical(approachTo, target)) ||
              (goal != null && rerouteGoal == goal))) {
        toast(
          'No connected detour from this position. Showing the saved directions.',
        );
      }
    } finally {
      rerouting = false;
    }
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  void toast(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void loadRoads(MapCamera camera) {
    final session = field;
    if (session == null) return;
    if (camera.zoom < 11) {
      roadsTimer?.cancel();
      ++cameraGeneration;
      if (detail.isNotEmpty || _roadsBounds != null) {
        setState(() {
          detail = [];
          _roadPolylines = const [];
          _roadsBounds = null;
        });
      }
      return;
    }
    final tier = camera.zoom < 12.5
        ? 0
        : camera.zoom < 14
        ? 1
        : 2;
    final bounds = camera.visibleBounds;
    final west = bounds.west % 360, east = bounds.east % 360;
    final cached = _roadsBounds;
    if (cached != null &&
        cached.tier == tier &&
        bounds.south >= cached.south &&
        bounds.north <= cached.north &&
        west >= cached.west &&
        east <= cached.east) {
      return;
    }
    final generation = ++cameraGeneration;
    roadsTimer?.cancel();
    roadsTimer = Timer(const Duration(milliseconds: 170), () async {
      final padLat = math.max((bounds.north - bounds.south) * 0.35, 0.005);
      final padLon = math.max((east - west) * 0.35, 0.005);
      final south = bounds.south - padLat;
      final north = bounds.north + padLat;
      final paddedWest = west - padLon;
      final paddedEast = east + padLon;
      try {
        final rows = await viewportRoads(
          session.index,
          south,
          paddedWest,
          north,
          paddedEast,
          zoom: camera.zoom,
        );
        if (mounted && generation == cameraGeneration) {
          setState(() {
            detail = rows;
            _roadsBounds = (
              south: south,
              west: paddedWest,
              north: north,
              east: paddedEast,
              tier: tier,
            );
            _rebuildRoadPolylines();
          });
        }
      } catch (e) {
        if (mounted && generation == cameraGeneration) {
          toast('Street detail could not load.');
        }
      }
    });
  }

  void zoom(double change) {
    map.move(map.camera.center, (map.camera.zoom + change).clamp(5, 20));
  }

  @override
  void initState() {
    super.initState();
    field?.addListener(refresh);
    WidgetsBinding.instance.addObserver(this);
    _positionSub = ref.listenManual(positionProvider, (_, next) {
      final value = next.asData?.value;
      if (value != null) {
        if (value.status == FixStatus.live) {
          eta.recordSpeed(value.fix?.speed);
        }
        _center(value);
        reroute(value);
      }
    });
    final saved = widget.project.manual;
    if (desktop && saved != null) {
      ref.read(trackerProvider).manual(saved[0], saved[1]);
    }
  }

  @override
  void didUpdateWidget(MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.night != widget.night) {
      _rebuildRoadPolylines();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      field?.sync();
      if (Platform.isAndroid) field?.driveStatus();
    }
    if (desktop) return;
    if (state == AppLifecycleState.paused) {
      final tracker = ref.read(trackerProvider);
      resumeGps = {
        FixStatus.searching,
        FixStatus.live,
        FixStatus.stale,
        FixStatus.lost,
      }.contains(tracker.state.status);
      if (resumeGps) tracker.stop();
    } else if (state == AppLifecycleState.resumed && resumeGps) {
      resumeGps = false;
      ref.read(trackerProvider).start();
    }
  }

  @override
  void dispose() {
    _positionSub?.close();
    WidgetsBinding.instance.removeObserver(this);
    roadsTimer?.cancel();
    field?.removeListener(refresh);
    map.dispose();
    super.dispose();
  }

  void _center(PositionState state) {
    if (!ready) return;
    final fix = state.fix;
    final valid =
        state.status == FixStatus.live || state.status == FixStatus.manual;
    final bearing = compass && valid ? state.compass : null;
    final center = follow && valid && fix != null
        ? LatLng(fix.lat, fix.lon)
        : map.camera.center;
    if (follow || compass) {
      map.moveAndRotate(
        center,
        zoomOnFix && valid ? math.max(16, map.camera.zoom) : map.camera.zoom,
        bearing == null ? 0 : -bearing,
      );
      if (valid) zoomOnFix = false;
    }
  }

  Future<void> _locate() async {
    setState(() {
      follow = true;
      zoomOnFix = true;
      picking = false;
    });
    final started = ref.read(trackerProvider).start();
    if (desktop) await _saveManual([]);
    await started;
  }

  Future<void> _saveManual(List<double> value) async {
    try {
      await widget.project.db.saveValue('manual', value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save position preference.')),
        );
      }
    }
  }

  Future<String> _labelForPoint(LatLng pt) async {
    final session = field;
    if (session != null) {
      try {
        final hit = await session.snapPoint(pt, maxMeters: 80);
        if (hit != null && hit.roadName.isNotEmpty) {
          return 'Near ${hit.roadName}';
        }
      } catch (_) {}
    }
    return '${pt.latitude.toStringAsFixed(4)}, ${pt.longitude.toStringAsFixed(4)}';
  }

  Future<void> _longPressDestination(LatLng pt) async {
    final session = field;
    if (session == null ||
        session.drawing ||
        reviewed != null ||
        picking ||
        pickingNav != null ||
        busy) {
      return;
    }
    final dest = LatLng(pt.latitude, FijiStarter.longitude(pt.longitude));
    final label = await _labelForPoint(dest);
    if (!mounted) return;
    setState(() {
      navDest = dest;
      navDestLabel = label;
      if (navStart == null) {
        navUseGpsStart = true;
        navStartLabel = 'My location';
      }
    });
    await openNavigate();
  }

  Future<void> _pick(LatLng pt) async {
    final session = field;
    if (reviewed != null) return;
    if (pickingNav != null && session != null) {
      final which = pickingNav!;
      final chosen = LatLng(pt.latitude, FijiStarter.longitude(pt.longitude));
      final label = await _labelForPoint(chosen);
      if (!mounted) return;
      setState(() {
        pickingNav = null;
        if (which == 'A') {
          navUseGpsStart = false;
          navStart = chosen;
          navStartLabel = label;
        } else {
          navDest = chosen;
          navDestLabel = label;
        }
      });
      await openNavigate();
      return;
    }
    if (session != null && session.drawing) {
      if (busy) return;
      var nextPt = LatLng(pt.latitude, FijiStarter.longitude(pt.longitude));
      String? note;
      LatLng? snapped;
      if (connectToRoad) {
        try {
          final hit = await session.snapPoint(nextPt, maxMeters: 45);
          if (!mounted || !session.drawing || busy) return;
          if (hit != null) {
            nextPt = hit.point;
            snapped = hit.point;
            note = hit.roadName.isNotEmpty
                ? 'Connected to ${hit.roadName}'
                : 'Connected to road';
          }
        } catch (_) {}
      }
      session.changeDraft([...session.draft, nextPt]);
      if (mounted) {
        setState(() {
          snapNote = note;
          snapPoint = snapped;
        });
      }
      return;
    }
    if (!picking) return;
    final lon = FijiStarter.longitude(pt.longitude);
    ref.read(trackerProvider).manual(pt.latitude, lon);
    setState(() {
      picking = false;
      follow = true;
    });
    zoomOnFix = true;
    _center(ref.read(trackerProvider).state);
    await _saveManual([pt.latitude, lon]);
  }

  void _cameraChanged(MapCamera camera, bool gesture) {
    loadRoads(camera);
    final isOutside = !FijiStarter.covers(
      camera.center.latitude,
      camera.center.longitude,
    );
    final over = camera.zoom > 10.5;
    if ((gesture && (follow || compass)) ||
        outside != isOutside ||
        over != zoomedIn) {
      setState(() {
        outside = isOutside;
        zoomedIn = over;
        if (gesture) {
          follow = false;
          compass = false;
        }
      });
    }
  }

  List<Widget> trailLayers() {
    final session = field;
    if (session == null) return [];
    final nav = activePath;
    final labels = <String, LatLng>{};
    if (ready && map.camera.zoom >= 14) {
      final bounds = map.camera.visibleBounds;
      for (final r in detail) {
        if (r.name.isEmpty) continue;
        final pt = r.points[r.points.length ~/ 2];
        if (bounds.contains(pt)) {
          labels.putIfAbsent(r.name, () => pt);
        }
        if (labels.length >= 16) break;
      }
    }
    final userPolylines = <Polyline>[
      for (final t in session.visibleTrails)
        for (final p in t.parts)
          Polyline(
            points: p,
            strokeWidth: 4,
            color: const Color(0xffab2874),
            borderColor: Colors.white,
            borderStrokeWidth: 1,
          ),
      for (final p in session.recent)
        Polyline(
          points: p,
          strokeWidth: 5,
          color: Colors.deepOrange,
          borderColor: Colors.white,
          borderStrokeWidth: 1,
        ),
      if (session.draft.length > 1)
        Polyline(
          points: session.draft,
          strokeWidth: 5,
          color: Colors.orange.shade800,
          borderColor: Colors.white,
          borderStrokeWidth: 1,
        ),
      for (final p in reviewed ?? <PathPart>[])
        Polyline(
          points: p,
          color: Colors.green.shade800,
          borderColor: Colors.white,
          borderStrokeWidth: 2,
          strokeWidth: 6,
        ),
      if (nav != null)
        Polyline(
          points: nav,
          strokeWidth: 6,
          color: const Color(0xff005aba),
          borderColor: Colors.white,
          borderStrokeWidth: 2,
        ),
    ];
    return [
      if (_roadPolylines.isNotEmpty)
        PolylineLayer(polylines: _roadPolylines, simplificationTolerance: 0.6),
      if (labels.isNotEmpty)
        MarkerLayer(
          markers: [
            for (final e in labels.entries)
              Marker(
                point: e.value,
                width: 110,
                height: 18,
                child: IgnorePointer(
                  child: Center(
                    child: Text(
                      e.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black,
                        backgroundColor: Color(0xdbfff9dd),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      if (userPolylines.isNotEmpty) PolylineLayer(polylines: userPolylines),
      if (session.draft.isNotEmpty ||
          nav != null ||
          snapPoint != null ||
          navStart != null ||
          navDest != null)
        MarkerLayer(
          markers: [
            if (snapPoint != null && session.drawing)
              Marker(
                point: snapPoint!,
                width: 24,
                height: 24,
                child: const Icon(
                  Icons.radio_button_checked,
                  color: Colors.green,
                  size: 20,
                ),
              ),
            if (session.draft.isNotEmpty)
              Marker(
                point: session.draft.last,
                child: const Icon(
                  Icons.add_location_alt,
                  color: Colors.deepOrange,
                ),
              ),
            if (navStart != null)
              Marker(
                point: navStart!,
                width: 28,
                height: 28,
                child: const CircleAvatar(
                  backgroundColor: Color(0xff1b6b3a),
                  foregroundColor: Colors.white,
                  child: Text(
                    'A',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
              ),
            if (navDest != null)
              Marker(
                point: navDest!,
                width: 28,
                height: 28,
                child: const CircleAvatar(
                  backgroundColor: Color(0xffc62828),
                  foregroundColor: Colors.white,
                  child: Text(
                    'B',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
              )
            else if (nav != null)
              Marker(
                point: nav.last,
                child: const Icon(Icons.flag, color: Color(0xff005aba)),
              ),
          ],
        ),
    ];
  }

  String distance(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';
  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await work();
    } catch (e) {
      toast(
        e is PlatformException ? e.message ?? 'Device error' : e.toString(),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> promptText(
    String title,
    String initial, {
    String? hint,
    bool pairing = false,
  }) async {
    String text = initial;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, redraw) => AlertDialog(
          title: Text(title),
          content: TextFormField(
            initialValue: initial,
            maxLength: pairing ? 128 : 96,
            autofocus: true,
            decoration: InputDecoration(labelText: hint ?? 'Route name'),
            onChanged: (s) => redraw(() => text = s),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, text.trim()),
              child: Text(pairing ? 'Connect' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> confirm(String title, String message, String button) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(button),
            ),
          ],
        ),
      ) ??
      false;

  Future<bool> _confirmDelete(Trail trail) async {
    final ok = await confirm(
      'Delete route?',
      'Delete "${trail.name}" from this device and synced devices?',
      'Delete',
    );
    if (!ok || !mounted) return false;
    await field!.deleteTrail(trail);
    if (activeTrailId == trail.id && mounted) {
      setState(() {
        activeTrailId = null;
        activeName = null;
        activePath = null;
        approachTo = null;
      });
    }
    toast('Deleted ${trail.name}');
    return true;
  }

  Future<void> review(bool drive) async {
    final session = field!;
    final rawParts = await session.review(drive: drive);
    if (!mounted) return;
    if (rawParts.isEmpty) {
      final discard = await confirm(
        'No new road to save',
        drive
            ? 'The usable GPS points match existing roads, or there were too few accurate fixes.'
            : 'This line follows registered roads or is too short.',
        drive ? 'Discard drive' : 'Discard drawing',
      );
      if (discard) await session.discard(drive);
      return;
    }
    final snappedParts = await session.connectEnds(rawParts, maxMeters: 45);
    if (!mounted) return;
    setState(() {
      reviewedRaw = rawParts;
      reviewedSnapped = snappedParts;
      reviewedDrive = drive;
      snapNote = null;
      snapPoint = null;
      follow = false;
      compass = false;
    });
    showPath(reviewed!.expand((p) => p).toList());
  }

  Future<void> nameReviewed() async {
    final parts = reviewed!;
    final total = parts.fold(0.0, (a, p) => a + lengthOf(p));
    final name = await promptText(
      'Save ${distance(total)} in ${parts.length} new ${parts.length == 1 ? "section" : "sections"}',
      '',
    );
    if (name != null) {
      await field!.save(name, parts, drive: reviewedDrive);
      setState(() {
        reviewedRaw = null;
        reviewedSnapped = null;
      });
      toast('Saved $name on this device');
    }
  }

  void showPath(PathPart p) {
    final first = p.first.longitude;
    final coords = [
      for (final q in p)
        LatLng(q.latitude, first + deltaLon(first, q.longitude)),
    ];
    map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(coords),
        padding: const EdgeInsets.all(50),
        maxZoom: 17,
      ),
    );
  }

  Future<void> _openSatelliteCache() async {
    final cache = widget.project.satelliteCache;
    if (cache == null || !ready) return;
    final bounds = map.camera.visibleBounds;
    var targetMaxZoom = map.camera.zoom >= 14 ? 17 : 16;
    var plan = SatelliteTileCache.planTiles(
      bounds.south,
      bounds.west,
      bounds.north,
      bounds.east,
      minZoom: 13,
      maxZoom: targetMaxZoom,
    );
    if (plan.length > 600 && targetMaxZoom > 16) {
      targetMaxZoom = 16;
      plan = SatelliteTileCache.planTiles(
        bounds.south,
        bounds.west,
        bounds.north,
        bounds.east,
        minZoom: 13,
        maxZoom: targetMaxZoom,
      );
    }
    var downloading = false, cancelled = false;
    var done = 0, total = plan.length;
    String? statusNote;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, redraw) {
          final st = cache.stats();
          final sizeMb = (st.bytes / (1024 * 1024)).toStringAsFixed(1);
          final estMb = (plan.length * 18 / 1024).toStringAsFixed(1);
          final tooLarge = plan.length > 600 || plan.isEmpty;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'High-res satellite cache',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text('${st.count} tiles saved offline ($sizeMb MB)'),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'Zoomed-in satellite tiles (zoom 13–18) load from Esri World Imagery when online and save automatically for offline use. Uncached areas fall back to the bundled Fiji Sentinel-2 map.',
                    ),
                  ),
                  if (downloading) ...[
                    LinearProgressIndicator(
                      value: total == 0 ? null : done / total,
                    ),
                    const SizedBox(height: 6),
                    Text('Downloading $done / $total tiles…'),
                  ] else if (statusNote != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(statusNote!),
                    )
                  else if (plan.length > 600)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Zoom in closer to save this area offline (max 600 tiles per download).',
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (!downloading)
                        FilledButton.icon(
                          onPressed: tooLarge
                              ? null
                              : () async {
                                  redraw(() {
                                    downloading = true;
                                    cancelled = false;
                                    done = 0;
                                    total = plan.length;
                                    statusNote = null;
                                  });
                                  final res = await cache.prefetch(
                                    plan,
                                    onProgress: (d, t) {
                                      if (ctx.mounted) {
                                        redraw(() {
                                          done = d;
                                          total = t;
                                        });
                                      }
                                    },
                                    cancelled: () => cancelled,
                                  );
                                  if (mounted) {
                                    setState(() => _satEpoch++);
                                  }
                                  if (ctx.mounted) {
                                    redraw(() {
                                      downloading = false;
                                      statusNote =
                                          'Saved ${res.downloaded} new tiles'
                                          '${res.skipped > 0 ? ", ${res.skipped} already cached" : ""}'
                                          '${res.failed > 0 ? ", ${res.failed} unavailable" : ""}.';
                                    });
                                  }
                                },
                          icon: const Icon(Icons.download),
                          label: Text(
                            'Save view z13–$targetMaxZoom (${plan.length} tiles · ~$estMb MB)',
                          ),
                        )
                      else
                        OutlinedButton(
                          onPressed: () => cancelled = true,
                          child: const Text('Cancel download'),
                        ),
                      if (!downloading && st.count > 0)
                        TextButton(
                          onPressed: () async {
                            if (await confirm(
                              'Clear satellite cache?',
                              'Remove ${st.count} cached high-res tiles ($sizeMb MB)? The bundled offline Fiji satellite map stays installed.',
                              'Clear',
                            )) {
                              cache.clear();
                              if (mounted) setState(() => _satEpoch++);
                              if (ctx.mounted) {
                                redraw(() => statusNote = 'Cache cleared.');
                              }
                            }
                          },
                          child: const Text('Clear cache'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> openSync() async {
    final s = field!;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListenableBuilder(
          listenable: s,
          builder: (ctx, _) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Route sync', style: Theme.of(ctx).textTheme.titleLarge),
                Text(s.syncState),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Get your private key from Dashboard → Downloads → Route sync key. Paired devices exchange named routes while the app is open.',
                  ),
                ),
                if (s.key.isEmpty)
                  FilledButton(
                    onPressed: () async {
                      final value = await promptText(
                        'Connect to your dashboard',
                        '',
                        hint: 'Route sync key',
                        pairing: true,
                      );
                      if (value != null) await s.pair(value);
                    },
                    child: const Text('Enter sync key'),
                  )
                else
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: s.syncing ? null : s.sync,
                        child: const Text('Sync now'),
                      ),
                      TextButton(
                        onPressed: () async {
                          await s.pair('');
                        },
                        child: const Text('Disconnect'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openRoutes() async {
    final s = field!;
    final selected = await showModalBottomSheet<Trail>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListenableBuilder(
          listenable: s,
          builder: (ctx, _) => Column(
            children: [
              ListTile(
                title: const Text('My routes'),
                trailing: Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (s.trails.isNotEmpty)
                      IconButton(
                        tooltip: s.allHidden
                            ? 'Show all routes'
                            : 'Hide all routes',
                        onPressed: () => s.setAllHidden(!s.allHidden),
                        icon: Icon(
                          s.allHidden
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        openSync();
                      },
                      icon: const Icon(Icons.sync),
                      label: const Text('Sync'),
                    ),
                  ],
                ),
              ),
              if (s.trails.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Draw a trail or record a drive to save your first route.',
                  ),
                ),
              Expanded(
                child: ListView(
                  children: [
                    for (final t in s.trails)
                      Builder(
                        builder: (ctx) {
                          final hidden = s.isHidden(t.id);
                          return ListTile(
                            leading: Icon(
                              Icons.route,
                              color: hidden
                                  ? Theme.of(ctx).disabledColor
                                  : null,
                            ),
                            title: Text(
                              t.name,
                              style: hidden
                                  ? TextStyle(
                                      color: Theme.of(ctx).disabledColor,
                                    )
                                  : null,
                            ),
                            subtitle: Text(
                              '${distance(t.distance)} · ${t.parts.length} section(s)${hidden ? " · hidden" : ""}${s.trails.where((other) => other.id == t.id).length > 1 ? " · concurrent edit" : ""}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: hidden ? 'Show route' : 'Hide route',
                                  onPressed: () => s.toggleHidden(t.id),
                                  icon: Icon(
                                    hidden
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Delete route',
                                  onPressed: () => _confirmDelete(t),
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: Theme.of(ctx).colorScheme.error,
                                  ),
                                ),
                              ],
                            ),
                            onTap: () => Navigator.pop(ctx, t),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final hidden = s.isHidden(selected.id);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(selected.name),
              subtitle: hidden ? const Text('Hidden on map') : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'rename'),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Rename'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'hide'),
                    icon: Icon(
                      hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                    ),
                    label: Text(hidden ? 'Show' : 'Hide'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'delete'),
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Theme.of(ctx).colorScheme.error,
                    ),
                    label: Text(
                      'Delete',
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            for (var i = 0; i < selected.parts.length; i++) ...[
              if (ref.read(trackerProvider).state.fix != null)
                ListTile(
                  leading: const Icon(Icons.directions_car),
                  title: Text('Drive to section ${i + 1}, then follow it'),
                  onTap: () => Navigator.pop(ctx, '$i/drive'),
                ),
              ListTile(
                title: Text(
                  'Section ${i + 1} · ${distance(lengthOf(selected.parts[i]))}',
                ),
                subtitle: const Text('Navigate along the saved line'),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Navigate forward',
                      onPressed: () => Navigator.pop(ctx, '$i/+'),
                      icon: const Icon(Icons.navigation),
                    ),
                    IconButton(
                      tooltip: 'Navigate in reverse',
                      onPressed: () => Navigator.pop(ctx, '$i/-'),
                      icon: const Icon(Icons.u_turn_left),
                    ),
                  ],
                ),
                onTap: () => Navigator.pop(ctx, '$i/+'),
              ),
            ],
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'rename') {
      final n = await promptText('Rename route', selected.name);
      if (n != null) await s.rename(selected, n);
      return;
    }
    if (choice == 'hide') {
      await s.toggleHidden(selected.id);
      return;
    }
    if (choice == 'delete') {
      await _confirmDelete(selected);
      return;
    }
    final i = int.parse(choice.split('/').first);
    final p = choice.endsWith('-')
        ? selected.parts[i].reversed.toList()
        : selected.parts[i];
    PathPart path = p;
    if (choice.endsWith('/drive')) {
      final state = ref.read(trackerProvider).state;
      if (state.fix == null ||
          (state.status != FixStatus.live &&
              state.status != FixStatus.manual)) {
        toast('Set your position first.');
        return;
      }
      final fix = state.fix!;
      final approach = await drivingDirections(
        s.index,
        s.trails,
        LatLng(fix.lat, fix.lon),
        p.first,
      );
      if (!mounted) return;
      path = [...approach, ...p.skip(1)];
    }
    eta.reset();
    setState(() {
      activeTrailId = selected.id;
      activeName = selected.name;
      activePath = path;
      approachTo = choice.endsWith('/drive') ? p : null;
      rerouteGoal = null;
      navStart = null;
      navDest = null;
      offFixes = 0;
      follow = false;
      compass = false;
    });
    showPath(path);
    if (!desktop && ref.read(trackerProvider).state.status != FixStatus.live) {
      await ref.read(trackerProvider).start();
    }
  }

  Future<void> openNavigate() async {
    final s = field;
    if (s == null) return;
    PathPart? previewPath;
    String? routeError;
    bool computing = false;
    int calcId = 0;

    LatLng? resolveStart() {
      if (navUseGpsStart) {
        final st = ref.read(trackerProvider).state;
        final fix = st.fix;
        if (fix != null &&
            (st.status == FixStatus.live || st.status == FixStatus.manual)) {
          return LatLng(fix.lat, fix.lon);
        }
        return null;
      }
      return navStart;
    }

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        bool startedCalc = false;
        return StatefulBuilder(
          builder: (ctx, redraw) {
            Future<void> compute() async {
              final startPt = resolveStart();
              final destPt = navDest;
              final id = ++calcId;
              if (startPt == null || destPt == null) {
                redraw(() {
                  previewPath = null;
                  routeError = null;
                  computing = false;
                });
                return;
              }
              redraw(() {
                computing = true;
                routeError = null;
              });
              try {
                final routed = await drivingDirections(
                  s.index,
                  s.trails,
                  startPt,
                  destPt,
                );
                if (ctx.mounted && id == calcId) {
                  redraw(() {
                    previewPath = routed;
                    routeError = null;
                    computing = false;
                  });
                }
              } catch (e) {
                if (ctx.mounted && id == calcId) {
                  redraw(() {
                    previewPath = null;
                    routeError = e.toString().replaceFirst('Bad state: ', '');
                    computing = false;
                  });
                }
              }
            }

            if (!startedCalc) {
              startedCalc = true;
              Future.microtask(compute);
            }

            final startPt = resolveStart();
            final destPt = navDest;
            final previewLen = previewPath == null
                ? null
                : lengthOf(previewPath!);
            final previewEta = previewLen == null
                ? null
                : eta.estimate(previewLen);

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Navigate A → B',
                            style: Theme.of(ctx).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Swap A and B',
                          onPressed:
                              (startPt == null && destPt == null) || computing
                              ? null
                              : () {
                                  final oldStart = startPt;
                                  final oldStartLabel = navUseGpsStart
                                      ? 'My location'
                                      : navStartLabel;
                                  setState(() {
                                    navUseGpsStart = false;
                                    navStart = destPt;
                                    navStartLabel = destPt == null
                                        ? 'Choose start'
                                        : navDestLabel;
                                    navDest = oldStart;
                                    navDestLabel = oldStart == null
                                        ? ''
                                        : oldStartLabel;
                                  });
                                  compute();
                                },
                          icon: const Icon(Icons.swap_vert),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Point A (Start)
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Color(0xff1b6b3a),
                                  foregroundColor: Colors.white,
                                  child: Text(
                                    'A',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    navUseGpsStart
                                        ? (startPt != null
                                              ? 'My GPS location'
                                              : 'My GPS location (waiting for fix)')
                                        : navStartLabel,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    setState(() {
                                      navUseGpsStart = true;
                                      navStart = null;
                                      navStartLabel = 'My location';
                                    });
                                    if (resolveStart() == null && !desktop) {
                                      await ref.read(trackerProvider).start();
                                    }
                                    await compute();
                                  },
                                  icon: const Icon(Icons.my_location, size: 16),
                                  label: const Text('My GPS'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => Navigator.pop(ctx, 'pickA'),
                                  icon: const Icon(
                                    Icons.touch_app_outlined,
                                    size: 16,
                                  ),
                                  label: const Text('Pick on map'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final hit = await showOfflinePlaceSearch(
                                      ctx,
                                      title: 'Choose start (Point A)',
                                      indexPath: s.index,
                                      savedTrails: s.trails,
                                      near: startPt ?? map.camera.center,
                                    );
                                    if (hit != null && mounted) {
                                      setState(() {
                                        navUseGpsStart = false;
                                        navStart = hit.point;
                                        navStartLabel = hit.name;
                                      });
                                      await compute();
                                    }
                                  },
                                  icon: const Icon(Icons.search, size: 16),
                                  label: const Text('Search'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Point B (Destination)
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Color(0xffc62828),
                                  foregroundColor: Colors.white,
                                  child: Text(
                                    'B',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    destPt == null
                                        ? 'Choose destination'
                                        : navDestLabel,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: destPt == null
                                          ? Theme.of(ctx).hintColor
                                          : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => Navigator.pop(ctx, 'pickB'),
                                  icon: const Icon(
                                    Icons.touch_app_outlined,
                                    size: 16,
                                  ),
                                  label: const Text('Pick on map'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final hit = await showOfflinePlaceSearch(
                                      ctx,
                                      title: 'Choose destination (Point B)',
                                      indexPath: s.index,
                                      savedTrails: s.trails,
                                      near: startPt ?? map.camera.center,
                                    );
                                    if (hit != null && mounted) {
                                      setState(() {
                                        navDest = hit.point;
                                        navDestLabel = hit.name;
                                      });
                                      await compute();
                                    }
                                  },
                                  icon: const Icon(Icons.search, size: 16),
                                  label: const Text('Search'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (computing)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      )
                    else if (routeError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          routeError!,
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.error,
                          ),
                        ),
                      )
                    else if (previewLen != null && previewEta != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${formatDistance(previewLen)} · ~${formatDuration(previewEta.duration)} · ETA ${formatClock(previewEta.arrival)}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Tip: you can also long-press anywhere on the map to set Point B.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    FilledButton.icon(
                      onPressed: previewPath == null || computing
                          ? null
                          : () => Navigator.pop(ctx, 'start'),
                      icon: const Icon(Icons.navigation_rounded),
                      label: const Text('Start navigation'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (!mounted || result == null) return;
    if (result == 'pickA' || result == 'pickB') {
      setState(() {
        pickingNav = result == 'pickA' ? 'A' : 'B';
        picking = false;
        follow = false;
        compass = false;
      });
      return;
    }
    if (result == 'start' && previewPath != null && navDest != null) {
      eta.reset();
      setState(() {
        activeTrailId = null;
        activeName = navDestLabel.isEmpty ? 'Destination' : navDestLabel;
        activePath = previewPath;
        approachTo = null;
        rerouteGoal = navDest;
        offFixes = 0;
        follow = navUseGpsStart;
        zoomOnFix = navUseGpsStart;
        compass = false;
      });
      if (!navUseGpsStart) {
        showPath(previewPath!);
      } else {
        final st = ref.read(trackerProvider).state;
        if (st.status == FixStatus.live || st.status == FixStatus.manual) {
          _center(st);
        } else {
          showPath(previewPath!);
        }
      }
      if (!desktop &&
          ref.read(trackerProvider).state.status != FixStatus.live) {
        await ref.read(trackerProvider).start();
      }
    }
  }

  Widget trailBar(PositionState state) {
    final s = field!, nav = activePath;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (nav != null)
            NavHudBar(
              destinationName: activeName ?? 'Route',
              path: nav,
              state: state,
              estimator: eta,
              following: follow,
              onFollow: () {
                final live =
                    state.status == FixStatus.live ||
                    state.status == FixStatus.manual;
                if (!live) {
                  _locate();
                } else {
                  setState(() {
                    follow = true;
                    zoomOnFix = true;
                  });
                  _center(state);
                }
              },
              onEnd: _endNavigation,
            ),
          if (busy) const LinearProgressIndicator(),
          if (reviewed != null)
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: const Text('Connect to road'),
                  selected: connectToRoad,
                  onSelected: busy
                      ? null
                      : (v) => setState(() => connectToRoad = v),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          reviewedRaw = null;
                          reviewedSnapped = null;
                        }),
                  child: const Text('Back'),
                ),
                FilledButton(
                  onPressed: busy ? null : () => action(nameReviewed),
                  child: Text('Name & save ${reviewed!.length} new section(s)'),
                ),
              ],
            )
          else if (s.drawing)
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: const Text('Connect to road'),
                  selected: connectToRoad,
                  onSelected: busy
                      ? null
                      : (v) => setState(() {
                          connectToRoad = v;
                          if (!v) {
                            snapNote = null;
                            snapPoint = null;
                          }
                        }),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (await confirm(
                            'Discard drawing?',
                            'Remove these unsaved points?',
                            'Discard',
                          )) {
                            setState(() {
                              snapNote = null;
                              snapPoint = null;
                            });
                            await s.discard(false);
                          }
                        },
                  child: const Text('Cancel'),
                ),
                IconButton(
                  tooltip: 'Undo point',
                  onPressed: busy || s.draft.isEmpty
                      ? null
                      : () {
                          setState(() {
                            snapNote = null;
                            snapPoint = null;
                          });
                          s.changeDraft(
                            s.draft.take(s.draft.length - 1).toList(),
                          );
                        },
                  icon: const Icon(Icons.undo),
                ),
                FilledButton(
                  onPressed: busy || s.draft.length < 2
                      ? null
                      : () => action(() => review(false)),
                  child: Text('Review (${s.draft.length})'),
                ),
              ],
            )
          else if (s.driveId != null)
            FilledButton.icon(
              onPressed: busy ? null : () => action(() => review(true)),
              icon: const Icon(Icons.stop_circle),
              label: Text(
                '${s.recording ? "Finish drive" : "Review recovered drive"} · ${s.samples} fixes',
              ),
            )
          else
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : () => action(openNavigate),
                  icon: const Icon(Icons.directions),
                  label: const Text('Navigate'),
                ),
                TextButton.icon(
                  onPressed: busy ? null : () => action(openRoutes),
                  icon: const Icon(Icons.route),
                  label: const Text('Routes'),
                ),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          s.drawing = true;
                          snapNote = null;
                          snapPoint = null;
                          picking = false;
                          pickingNav = null;
                          follow = false;
                          compass = false;
                        }),
                  icon: const Icon(Icons.edit_road),
                  label: const Text('Draw'),
                ),
                if (Platform.isAndroid)
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => action(() async {
                            await s.startDrive();
                            await _locate();
                          }),
                    icon: const Icon(Icons.directions_car),
                    label: const Text('Drive'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.project.manual;
    final session = field;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xff233c31),
        foregroundColor: Colors.white,
        leading: const Icon(Icons.terrain_rounded, size: 32),
        titleSpacing: 0,
        title: const Text(
          'Fiji Field Map',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (satellite && widget.project.satelliteCache != null)
            IconButton(
              tooltip: 'Save satellite area offline',
              onPressed: _openSatelliteCache,
              icon: const Icon(Icons.download_for_offline_outlined),
            ),
          if (widget.project.satellite != null)
            IconButton(
              tooltip: satellite ? 'Street map' : 'Satellite view',
              onPressed: () => setState(() {
                satellite = !satellite;
                _rebuildRoadPolylines();
              }),
              icon: Icon(satellite ? Icons.map_outlined : Icons.satellite_alt),
            ),
          IconButton(
            tooltip: widget.night ? 'Day map' : 'Night map',
            onPressed: widget.onTheme,
            icon: Icon(
              widget.night
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
        ],
      ),
      bottomNavigationBar: session == null
          ? null
          : SafeArea(
              top: false,
              child: Consumer(
                builder: (context, ref, _) {
                  final tracker = ref.watch(trackerProvider);
                  final state =
                      ref.watch(positionProvider).asData?.value ??
                      tracker.state;
                  return trailBar(state);
                },
              ),
            ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, size) {
            final wide = size.maxWidth >= 780;
            final panel = Consumer(
              builder: (context, ref, _) {
                final tracker = ref.watch(trackerProvider);
                final state =
                    ref.watch(positionProvider).asData?.value ?? tracker.state;
                return PositionPanel(
                  state: state,
                  desktop: desktop,
                  wide: wide,
                  picking: picking,
                  onLocate: _locate,
                  onStop: () {
                    tracker.stop();
                    setState(() {
                      follow = false;
                      compass = false;
                    });
                  },
                  onManual: () => setState(() => picking = !picking),
                  onSettings: () async {
                    try {
                      if (await DevicePosition().openSettings(state.status)) {
                        return;
                      }
                    } catch (_) {
                      /* Some desktop adapters have no settings shortcut. */
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Open location permissions in system settings.',
                          ),
                        ),
                      );
                    }
                  },
                );
              },
            );
            return Flex(
              direction: wide ? Axis.horizontal : Axis.vertical,
              verticalDirection: VerticalDirection.up,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: wide ? 294 : null,
                  height: wide
                      ? null
                      : (size.maxHeight * .34).clamp(136, 210).toDouble(),
                  child: panel,
                ),
                Expanded(
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: map,
                        options: MapOptions(
                          initialCenter: initial != null && desktop
                              ? LatLng(initial[0], initial[1])
                              : fijiCenter,
                          initialZoom: 7.1,
                          minZoom: 5,
                          maxZoom: 20,
                          backgroundColor: satellite
                              ? _satSea
                              : widget.night
                              ? const Color(0xff223638)
                              : zoomedIn && detail.isNotEmpty
                              ? const Color(0xffeef0e6)
                              : _sea,
                          onMapReady: () {
                            ready = true;
                            loadRoads(map.camera);
                          },
                          onTap: (_, pt) => _pick(pt),
                          onLongPress: (_, pt) => _longPressDestination(pt),
                          onPositionChanged: _cameraChanged,
                        ),
                        children: [
                          TileLayer(
                            key: ValueKey(
                              satellite ? 'satellite-base' : 'street',
                            ),
                            urlTemplate: satellite ? 'satellite' : 'map',
                            tileProvider: sharedTileProvider(
                              satellite
                                  ? widget.project.satellite!
                                  : widget.project.tiles,
                            ),
                            // At street scale the indexed road vectors carry the detail.
                            maxZoom: !satellite && detail.isNotEmpty ? 12 : 20,
                            minNativeZoom: FijiStarter.minZoom,
                            maxNativeZoom: satellite ? 12 : FijiStarter.maxZoom,
                            panBuffer: 1,
                            keepBuffer: 2,
                            evictErrorTileStrategy:
                                EvictErrorTileStrategy.dispose,
                            tileDisplay: const TileDisplay.instantaneous(),
                            tileBuilder: widget.night && !satellite
                                ? (context, tile, image) => ColorFiltered(
                                    colorFilter: _nightMap,
                                    child: tile,
                                  )
                                : null,
                            errorTileCallback: (tile, error, stack) =>
                                debugPrint(
                                  'Offline tile ${tile.coordinates}: $error',
                                ),
                          ),
                          if (satellite &&
                              widget.project.satelliteCache != null)
                            TileLayer(
                              key: ValueKey('satellite-hi-$_satEpoch'),
                              tileProvider: CachedSatelliteTileProvider(
                                widget.project.satelliteCache!,
                              ),
                              minZoom: 13,
                              maxZoom: 20,
                              minNativeZoom: 13,
                              maxNativeZoom: 18,
                              panBuffer: 0,
                              keepBuffer: 2,
                              tileDisplay: const TileDisplay.instantaneous(),
                            ),
                          ...trailLayers(),
                          Consumer(
                            builder: (context, ref, _) {
                              final tracker = ref.watch(trackerProvider);
                              final state =
                                  ref.watch(positionProvider).asData?.value ??
                                  tracker.state;
                              final fix = state.fix;
                              if (fix == null) return const SizedBox.shrink();
                              final live =
                                  state.status == FixStatus.live ||
                                  state.status == FixStatus.manual;
                              return Stack(
                                children: [
                                  if (live && fix.accuracy != null)
                                    CircleLayer(
                                      circles: [
                                        CircleMarker(
                                          point: LatLng(fix.lat, fix.lon),
                                          radius: fix.accuracy!,
                                          useRadiusInMeter: true,
                                          color: const Color(0x260052a1),
                                          borderColor: const Color(0x880052a1),
                                          borderStrokeWidth: 1,
                                        ),
                                      ],
                                    ),
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: LatLng(fix.lat, fix.lon),
                                        width: 32,
                                        height: 32,
                                        child: Semantics(
                                          label: live
                                              ? 'Position'
                                              : 'Last known position',
                                          child: Icon(
                                            Icons.adjust,
                                            size: 32,
                                            shadows: const [
                                              Shadow(
                                                color: Colors.white,
                                                blurRadius: 4,
                                              ),
                                            ],
                                            color: live
                                                ? const Color(0xff0052a1)
                                                : Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                      if (activePath != null)
                        Positioned(
                          left: 10,
                          top: 10,
                          right: 64,
                          child: Consumer(
                            builder: (context, ref, _) {
                              final tracker = ref.watch(trackerProvider);
                              final state =
                                  ref.watch(positionProvider).asData?.value ??
                                  tracker.state;
                              return NavTurnBanner(
                                destinationName: activeName ?? 'Destination',
                                path: activePath!,
                                state: state,
                              );
                            },
                          ),
                        )
                      else if (picking ||
                          pickingNav != null ||
                          outside ||
                          (session?.drawing == true && reviewed == null))
                        Positioned(
                          left: 10,
                          top: 10,
                          right: 70,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        pickingNav != null
                                            ? (pickingNav == 'A'
                                                  ? 'Tap Start (Point A) on map'
                                                  : 'Tap Destination (Point B) on map')
                                            : picking
                                            ? 'Tap the map to set your position'
                                            : outside
                                            ? 'Outside Fiji starter coverage'
                                            : snapNote ??
                                                  'Tap points along the new route',
                                      ),
                                    ),
                                    if (pickingNav != null) ...[
                                      const SizedBox(width: 8),
                                      TextButton(
                                        onPressed: () =>
                                            setState(() => pickingNav = null),
                                        style: TextButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        child: const Text('Cancel'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Material(
                          elevation: 2,
                          borderRadius: BorderRadius.circular(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Show Fiji',
                                icon: const Icon(Icons.public),
                                onPressed: () {
                                  setState(() {
                                    follow = false;
                                    compass = false;
                                  });
                                  map.moveAndRotate(fijiCenter, 7.1, 0);
                                },
                              ),
                              Consumer(
                                builder: (context, ref, _) {
                                  final tracker = ref.watch(trackerProvider);
                                  final state =
                                      ref
                                          .watch(positionProvider)
                                          .asData
                                          ?.value ??
                                      tracker.state;
                                  final live =
                                      state.status == FixStatus.live ||
                                      state.status == FixStatus.manual;
                                  return IconButton(
                                    tooltip: follow
                                        ? 'Stop following'
                                        : 'Follow position',
                                    isSelected: follow,
                                    onPressed: !live
                                        ? _locate
                                        : () {
                                            setState(() {
                                              follow = !follow;
                                              zoomOnFix = follow;
                                            });
                                            _center(state);
                                          },
                                    icon: const Icon(Icons.my_location),
                                  );
                                },
                              ),
                              IconButton(
                                tooltip: 'Zoom in',
                                onPressed: () => zoom(1),
                                icon: const Icon(Icons.add),
                              ),
                              IconButton(
                                tooltip: 'Zoom out',
                                onPressed: () => zoom(-1),
                                icon: const Icon(Icons.remove),
                              ),
                              if (session != null && session.trails.isNotEmpty)
                                IconButton(
                                  tooltip: session.allHidden
                                      ? 'Show routes'
                                      : 'Hide routes',
                                  isSelected: session.allHidden,
                                  onPressed: () =>
                                      session.setAllHidden(!session.allHidden),
                                  icon: Icon(
                                    session.allHidden
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              if (!desktop)
                                Consumer(
                                  builder: (context, ref, _) {
                                    final tracker = ref.watch(trackerProvider);
                                    final state =
                                        ref
                                            .watch(positionProvider)
                                            .asData
                                            ?.value ??
                                        tracker.state;
                                    final live =
                                        state.status == FixStatus.live ||
                                        state.status == FixStatus.manual;
                                    return IconButton(
                                      tooltip: compass
                                          ? 'North up'
                                          : 'Compass up',
                                      isSelected: compass,
                                      onPressed:
                                          (!live || state.compass == null) &&
                                              !compass
                                          ? null
                                          : () {
                                              setState(
                                                () => compass = !compass,
                                              );
                                              if (compass) {
                                                _center(state);
                                              } else {
                                                map.rotate(0);
                                              }
                                            },
                                      icon: const Icon(Icons.explore_outlined),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (activePath == null)
                        Positioned(
                          left: 8,
                          bottom: 32,
                          child: Consumer(
                            builder: (context, ref, _) {
                              final tracker = ref.watch(trackerProvider);
                              final state =
                                  ref.watch(positionProvider).asData?.value ??
                                  tracker.state;
                              if (state.status != FixStatus.live) {
                                return const SizedBox.shrink();
                              }
                              return LiveSpeedChip(speedMps: state.fix?.speed);
                            },
                          ),
                        ),
                      Positioned(
                        left: 6,
                        bottom: 4,
                        child: Material(
                          color: Theme.of(context).colorScheme.surface,
                          child: InkWell(
                            onTap: () => showMapLicense(context),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 5,
                              ),
                              child: Text(
                                satellite
                                    ? 'Esri World Imagery · ESA Sentinel-2'
                                    : '© OpenStreetMap contributors',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
