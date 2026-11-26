import 'dart:async';

import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:offroad_core/position.dart';
import 'package:offroad_core/trails.dart';
import 'package:offroad_storage/road_index.dart';

String formatDistance(double m) =>
    m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';

IconData turnIcon(TurnKind kind, {bool offRoute = false}) {
  if (offRoute) return Icons.warning_amber_rounded;
  return switch (kind) {
    TurnKind.arrive => Icons.flag_rounded,
    TurnKind.straight => Icons.straight_rounded,
    TurnKind.slightLeft => Icons.turn_slight_left_rounded,
    TurnKind.left => Icons.turn_left_rounded,
    TurnKind.sharpLeft => Icons.turn_sharp_left_rounded,
    TurnKind.slightRight => Icons.turn_slight_right_rounded,
    TurnKind.right => Icons.turn_right_rounded,
    TurnKind.sharpRight => Icons.turn_sharp_right_rounded,
    TurnKind.uTurn => Icons.u_turn_left_rounded,
  };
}

/// Top Google-Maps-style maneuver banner shown during active navigation.
class NavTurnBanner extends StatelessWidget {
  const NavTurnBanner({
    super.key,
    required this.destinationName,
    required this.path,
    required this.state,
  });

  final String destinationName;
  final PathPart path;
  final PositionState state;

  @override
  Widget build(BuildContext context) {
    final fix = state.fix;
    final valid =
        (state.status == FixStatus.live || state.status == FixStatus.manual) &&
        fix != null;
    IconData icon = Icons.navigation_rounded;
    String primary = 'Waiting for GPS fix…';
    String secondary = 'To $destinationName';
    Color bg = const Color(0xff143d2d);

    if (valid) {
      final g = guide(path, LatLng(fix.lat, fix.lon));
      final offThreshold = fix.accuracy != null && fix.accuracy! * 1.5 > 25
          ? fix.accuracy! * 1.5
          : 25.0;
      final off = !g.arrived && g.offset > offThreshold;
      icon = turnIcon(g.turn, offRoute: off);
      if (g.arrived) {
        primary = 'Arrived at $destinationName';
        secondary = 'Navigation complete';
      } else if (off) {
        bg = const Color(0xff8c2d19);
        primary = 'Off route · ${formatDistance(g.offset)} away';
        secondary = 'Head ${g.bearingDeg.round()}° back to route';
      } else {
        primary = g.turn == TurnKind.straight
            ? '${g.instruction} · ${formatDistance(g.turnDistance)}'
            : '${g.instruction} in ${formatDistance(g.turnDistance)}';
        secondary = 'To $destinationName · ${g.bearingDeg.round()}°';
      }
    }

    return Material(
      elevation: 4,
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    primary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    secondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xd9ffffff),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom live navigation bar showing active speed (km/h), live ETA, clock
/// arrival time, remaining distance, follow button, and end button.
class NavHudBar extends StatelessWidget {
  const NavHudBar({
    super.key,
    required this.destinationName,
    required this.path,
    required this.state,
    required this.estimator,
    required this.following,
    required this.onFollow,
    required this.onEnd,
  });

  final String destinationName;
  final PathPart path;
  final PositionState state;
  final EtaEstimator estimator;
  final bool following;
  final VoidCallback onFollow;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final fix = state.fix;
    final valid =
        (state.status == FixStatus.live || state.status == FixStatus.manual) &&
        fix != null;
    final remaining = valid
        ? guide(path, LatLng(fix.lat, fix.lon)).remaining
        : lengthOf(path);
    final arrived = valid && guide(path, LatLng(fix.lat, fix.lon)).arrived;
    final eta = estimator.estimate(remaining, liveSpeedMps: fix?.speed);
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${eta.speedKmh.round()}',
                  style: TextStyle(
                    fontSize: 20,
                    height: 1.0,
                    fontWeight: FontWeight.w800,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                Text(
                  'km/h',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  arrived
                      ? 'Arrived'
                      : '${eta.liveBased ? "" : "~"}${formatDuration(eta.duration)}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: arrived ? Colors.green.shade700 : colors.onSurface,
                  ),
                ),
                Text(
                  arrived
                      ? destinationName
                      : 'ETA ${formatClock(eta.arrival)} · ${formatDistance(remaining)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: following ? 'Following' : 'Recenter on route',
            isSelected: following,
            onPressed: onFollow,
            icon: const Icon(Icons.my_location),
          ),
          FilledButton.tonal(
            onPressed: onEnd,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text('End'),
          ),
        ],
      ),
    );
  }
}

/// Compact floating speedometer shown on the map when GPS is live without active navigation.
class LiveSpeedChip extends StatelessWidget {
  const LiveSpeedChip({super.key, required this.speedMps});
  final double? speedMps;

  @override
  Widget build(BuildContext context) {
    final kmh = speedMps != null && speedMps!.isFinite && speedMps! >= 0.4
        ? (speedMps! * 3.6).round()
        : 0;
    return Material(
      elevation: 2,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$kmh',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 4),
            const Text('km/h', style: TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// Offline search modal across all named Fiji OSM roads and saved custom trails.
Future<PlaceMatch?> showOfflinePlaceSearch(
  BuildContext context, {
  required String title,
  required String indexPath,
  required List<Trail> savedTrails,
  LatLng? near,
}) async {
  return showModalBottomSheet<PlaceMatch>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _PlaceSearchSheet(
      title: title,
      indexPath: indexPath,
      savedTrails: savedTrails,
      near: near,
    ),
  );
}

class _PlaceSearchSheet extends StatefulWidget {
  const _PlaceSearchSheet({
    required this.title,
    required this.indexPath,
    required this.savedTrails,
    required this.near,
  });
  final String title, indexPath;
  final List<Trail> savedTrails;
  final LatLng? near;

  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  final controller = TextEditingController();
  List<PlaceMatch> results = [];
  bool loading = true;
  Timer? debounce;
  int reqId = 0;

  @override
  void initState() {
    super.initState();
    _run('');
  }

  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 140), () => _run(value));
  }

  Future<void> _run(String query) async {
    final id = ++reqId;
    if (mounted) setState(() => loading = true);
    try {
      final rows = await searchPlaces(
        widget.indexPath,
        query,
        widget.savedTrails,
        near: widget.near,
      );
      if (mounted && id == reqId) {
        setState(() {
          results = rows;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted && id == reqId) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search Fiji roads or saved routes…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: _onChanged,
              ),
              const SizedBox(height: 8),
              if (loading) const LinearProgressIndicator(),
              Expanded(
                child: results.isEmpty && !loading
                    ? const Center(
                        child: Text('No matching Fiji roads or routes found.'),
                      )
                    : ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (ctx, i) {
                          final item = results[i];
                          return ListTile(
                            leading: Icon(
                              item.isSavedTrail
                                  ? Icons.route
                                  : Icons.add_road_rounded,
                            ),
                            title: Text(item.name),
                            subtitle: Text(item.subtitle),
                            onTap: () => Navigator.pop(ctx, item),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
