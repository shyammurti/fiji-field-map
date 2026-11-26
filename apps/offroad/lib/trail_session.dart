import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:offroad_core/position.dart';
import 'package:offroad_core/trails.dart';
import 'package:offroad_platform/device_position.dart';
import 'package:offroad_storage/road_index.dart';
import 'package:offroad_storage/storage.dart';

const syncHost = 'homeserver.tailc1c7b7.ts.net';
const _drive = MethodChannel('fieldmap/drive');

class TrailSession extends ChangeNotifier {
  TrailSession(this.db, this.index);
  final ProjectDatabase db;
  final String index;
  List<Trail> trails = [];
  Set<String> hiddenIds = {};
  PathPart draft = [];
  List<PathPart> recent = [];
  bool drawing = false, recording = false, syncing = false;
  int samples = 0;
  String? driveId;
  String key = '', syncState = 'Sync off';
  late String device;
  Timer? _retry, _poll;
  Future<void> _draftWrite = Future.value();

  bool isHidden(String id) => hiddenIds.contains(id);
  bool get allHidden =>
      trails.isNotEmpty && trails.every((t) => hiddenIds.contains(t.id));
  List<Trail> get visibleTrails =>
      trails.where((t) => !hiddenIds.contains(t.id)).toList();

  Future<void> initialize() async {
    device = await db.deviceId();
    trails = await db.trails();
    final hidden = await db.readValue('hidden_trails');
    if (hidden is List) {
      hiddenIds = hidden.whereType<String>().toSet();
    }
    final data = await db.readValue('draft');
    if (data is List && data.isNotEmpty) {
      draft = decodeParts([data]).first;
      drawing = draft.isNotEmpty;
    }
    key = (await db.readValue('field_sync_key') as String?) ?? '';
    if (Platform.isAndroid) await driveStatus();
    _retry = Timer.periodic(const Duration(minutes: 1), (_) => sync());
    unawaited(sync());
  }

  Future<void> driveStatus() async {
    final s = await _drive.invokeMapMethod<String, dynamic>('status');
    recent = driveParts((s?['recent'] as List?) ?? []);
    driveId = s?['id'];
    recording = s?['active'] == true;
    samples = s?['count'] ?? 0;
    if (recording && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 4), (_) async {
        try {
          await driveStatus();
        } catch (_) {}
      });
    }
    if (!recording) {
      _poll?.cancel();
      _poll = null;
    }
    notifyListeners();
  }

  void changeDraft(PathPart next) {
    draft = next;
    final data = encodeParts([next]).first;
    _draftWrite = _draftWrite
        .catchError((Object _) {})
        .then((_) => db.saveValue('draft', data));
    unawaited(
      _draftWrite.catchError((Object _) {
        syncState = 'Draft could not be saved';
        notifyListeners();
      }),
    );
    notifyListeners();
  }

  Future<void> startDrive() async {
    if (await DevicePosition().prepare() != FixStatus.searching) {
      throw StateError('Enable precise GPS location to record a drive.');
    }
    await _drive.invokeMethod('start');
    await driveStatus();
  }

  Future<List<PathPart>> review({required bool drive}) async {
    List<PathPart> input;
    if (drive) {
      final rows = await _drive.invokeListMethod('finish') ?? [];
      await driveStatus();
      input = driveParts(rows);
    } else {
      await _draftWrite;
      input = [List.of(draft)];
    }
    return filterRoads(index, input, trails);
  }

  Future<void> discard(bool drive) async {
    if (drive && driveId != null) {
      await _drive.invokeMethod('clear', driveId);
      await driveStatus();
    }
    if (!drive) {
      drawing = false;
      changeDraft([]);
      await _draftWrite;
    }
    notifyListeners();
  }

  Future<void> save(
    String name,
    List<PathPart> parts, {
    required bool drive,
  }) async {
    if (parts.expand((p) => p).length > 50000) {
      throw StateError('This route exceeds 50,000 vertices.');
    }
    var t = Trail.create(device, name, parts);
    if (drive) {
      t = Trail(
        driveId!,
        driveId!,
        null,
        device,
        t.name,
        t.parts,
        t.created,
        t.updated,
      );
    }
    await db.saveTrail(t, clearDraft: !drive);
    trails = await db.trails();
    await discard(drive);
    notifyListeners();
    unawaited(sync());
  }

  Future<void> rename(Trail old, String name) async {
    await db.saveTrail(Trail.create(device, name, old.parts, previous: old));
    trails = await db.trails();
    notifyListeners();
    unawaited(sync());
  }

  Future<void> deleteTrail(Trail old) async {
    await db.saveTrail(
      Trail.create(device, old.name, old.parts, previous: old, deleted: true),
    );
    if (hiddenIds.remove(old.id)) {
      await db.saveValue('hidden_trails', hiddenIds.toList());
    }
    trails = await db.trails();
    notifyListeners();
    unawaited(sync());
  }

  Future<void> toggleHidden(String id) async {
    if (!hiddenIds.remove(id)) hiddenIds.add(id);
    await db.saveValue('hidden_trails', hiddenIds.toList());
    notifyListeners();
  }

  Future<void> setAllHidden(bool hide) async {
    if (hide) {
      hiddenIds = trails.map((t) => t.id).toSet();
    } else {
      hiddenIds.clear();
    }
    await db.saveValue('hidden_trails', hiddenIds.toList());
    notifyListeners();
  }

  Future<RoadSnap?> snapPoint(LatLng point, {double maxMeters = 45}) =>
      nearestRoadPoint(index, point, trails, maxMeters: maxMeters);

  Future<List<PathPart>> connectEnds(
    List<PathPart> parts, {
    double maxMeters = 45,
  }) => snapRouteEnds(index, parts, trails, maxMeters: maxMeters);

  Future<void> pair(String value) async {
    key = value.trim();
    await db.saveValue('field_sync_key', key);
    if (key.isEmpty) syncState = 'Sync off';
    notifyListeners();
    await sync();
  }

  Future<void> sync() async {
    if (syncing || key.isEmpty) return;
    final usedKey = key;
    syncing = true;
    syncState = 'Syncing…';
    notifyListeners();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      while (key == usedKey) {
        final batch = await db.pending();
        final cursor = (await db.readValue('sync_cursor') as int?) ?? 0;
        final req = await client
            .postUrl(Uri.https(syncHost, '/dash/api/field-map/sync'))
            .timeout(const Duration(seconds: 10));
        req.followRedirects = false;
        req.headers.contentType = ContentType.json;
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $usedKey');
        req.write(
          jsonEncode({
            'cursor': cursor,
            'push': [for (final item in batch) jsonDecode(item.payload)],
          }),
        );
        final res = await req.close().timeout(const Duration(seconds: 15));
        if (res.statusCode == 401) {
          throw const FormatException('Check the sync key');
        }
        if (res.statusCode != 200) {
          throw HttpException('Sync returned ${res.statusCode}');
        }
        final body = jsonDecode(
          await res
              .transform(utf8.decoder)
              .join()
              .timeout(const Duration(seconds: 20)),
        );
        if (key != usedKey) break;
        final ack = List<String>.from(body['ack']);
        if (!setEquals(ack.toSet(), batch.map((r) => r.revision).toSet())) {
          throw const FormatException('Incomplete sync reply');
        }
        await db.applySync(ack, [
          for (final change in body['changes']) Trail.fromJson(change),
        ], body['cursor']);
        if (body['more'] != true && batch.length < 4) break;
      }
      trails = await db.trails();
      if (key == usedKey) syncState = 'Synced';
    } on FormatException catch (e) {
      if (key == usedKey) syncState = e.message;
    } catch (_) {
      if (key == usedKey) syncState = 'Saved locally · retrying when online';
    } finally {
      client.close(force: true);
      syncing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    _poll?.cancel();
    super.dispose();
  }
}
