import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:offroad_core/trails.dart';
import 'package:offroad_storage/storage.dart';
import 'package:offroad_storage/road_index.dart';
import 'package:offroad_storage/navigation.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final index = File('assets/fiji-roads.sqlite').absolute.path;
  test(
    'Suva has named street geometry and navigable road connectivity',
    () async {
      final lines = await viewportRoads(index, -18.15, 178.42, -18.13, 178.45);
      expect(lines.where((r) => r.name.isNotEmpty), isNotEmpty);
      final db = sqlite3.open(index, mode: OpenMode.readOnly);
      late List<LatLng> points;
      try {
        final row = db
            .select(
              'SELECT coords FROM bounds JOIN roads USING(id) WHERE length(name)>0 AND node_ids IS NOT NULL AND direction=0 AND minlat>-18.15 AND maxlat<-18.13 AND minlon>178.42 AND maxlon<178.45 ORDER BY length(coords) DESC LIMIT 1',
            )
            .single;
        points = [
          for (final q in jsonDecode(utf8.decode(zlib.decode(row['coords']))))
            LatLng(q[0] / 1e6, q[1] / 1e6),
        ];
      } finally {
        db.close();
      }
      expect(await filterRoads(index, [points], []), isEmpty);
      final routed = await drivingDirections(
        index,
        [],
        points.first,
        points.last,
      );
      expect(routed.length, greaterThan(1));
      expect(meters(routed.first, points.first), lessThan(1));
      expect(meters(routed.last, points.last), lessThan(1));
    },
  );
  test(
    'a saved trail is recognised on a second drive and participates in navigation',
    () async {
      const path = [LatLng(-18.34, 178.21), LatLng(-18.34, 178.215)];
      final t = Trail.create('local', 'Test track', [path]);
      expect(await filterRoads(index, [path], [t]), isEmpty);
      final route = await drivingDirections(
        index,
        [t],
        interpolate(path.first, path.last, .1),
        interpolate(path.first, path.last, .8),
      );
      expect(lengthOf(route), closeTo(lengthOf(path) * .7, 3));
    },
  );
  test(
    'local v1 migration, durable outbox, retry and concurrent renames',
    () async {
      final dir = await Directory.systemTemp.createTemp('field-upgrade-');
      final file = File.fromUri(dir.uri.resolve('project.sqlite'));
      final v1 = sqlite3.open(file.path);
      v1.execute(
        "CREATE TABLE settings(key TEXT PRIMARY KEY,value_json TEXT NOT NULL); INSERT INTO settings VALUES('night','true'); PRAGMA user_version=1",
      );
      v1.close();
      var db = ProjectDatabase(file);
      try {
        expect(await db.readValue('night'), true);
        final id = await db.deviceId();
        final t = Trail.create(id, 'Nadi ridge', [
          [const LatLng(-17.7, 177.4), const LatLng(-17.701, 177.402)],
        ]);
        await db.saveTrail(t);
        await db.close();
        db = ProjectDatabase(file);
        expect((await db.pending()).single.revision, t.rev);
        await db.applySync([t.rev], [t], 1);
        await db.applySync([t.rev], [t], 1);
        expect(await db.pending(), isEmpty);
        final a = Trail.create(id, 'Ridge East', t.parts, previous: t),
            b = Trail.create(id, 'Ridge West', t.parts, previous: t);
        await db.saveTrail(a);
        await db.applySync([], [b], 2);
        expect((await db.trails()).map((r) => r.name).toSet(), {
          'Ridge East',
          'Ridge West',
        });
        // Delete tombstone hides trail locally and queues sync.
        final deleted = Trail.create(
          id,
          a.name,
          a.parts,
          previous: a,
          deleted: true,
        );
        await db.saveTrail(deleted);
        expect((await db.trails()).map((r) => r.name).toSet(), {'Ridge West'});
        expect(
          (await db.pending()).map((v) => v.revision),
          contains(deleted.rev),
        );
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'nearestRoadPoint and snapRouteEnds connect nearby off-road sections to OSM roads',
    () async {
      final db = sqlite3.open(index, mode: OpenMode.readOnly);
      late LatLng roadPoint;
      try {
        final row = db
            .select(
              'SELECT coords FROM bounds JOIN roads USING(id) WHERE length(name)>0 AND node_ids IS NOT NULL AND minlat>-18.15 AND maxlat<-18.13 AND minlon>178.42 AND maxlon<178.45 LIMIT 1',
            )
            .single;
        final pts = jsonDecode(utf8.decode(zlib.decode(row['coords']))) as List;
        roadPoint = LatLng(pts[0][0] / 1e6, pts[0][1] / 1e6);
      } finally {
        db.close();
      }
      // Offset ~20 m north of the road.
      final nearby = LatLng(roadPoint.latitude + 0.00018, roadPoint.longitude);
      final farEnd = LatLng(roadPoint.latitude + 0.002, roadPoint.longitude);
      final snap = await nearestRoadPoint(index, nearby, [], maxMeters: 45);
      expect(snap, isNotNull);
      expect(snap!.distance, lessThan(25));
      final connected = await snapRouteEnds(
        index,
        [
          [nearby, farEnd],
        ],
        [],
        maxMeters: 45,
      );
      expect(connected.single.length, 3);
      expect(meters(connected.single.first, snap.point), lessThan(1));
    },
  );
  test(
    'offline searchPlaces finds Fiji OSM roads and saved trails and routes A to B',
    () async {
      final saved = [
        Trail.create('local', 'Sigatoka Ridge Track', [
          [const LatLng(-18.14, 177.51), const LatLng(-18.142, 177.512)],
        ]),
      ];
      final savedHits = await searchPlaces(index, 'sigatoka ridge', saved);
      expect(savedHits.first.isSavedTrail, isTrue);
      expect(savedHits.first.name, 'Sigatoka Ridge Track');
      final roadA = await searchPlaces(index, 'victoria parade', saved);
      final roadB = await searchPlaces(index, 'gladstone road', saved);
      expect(roadA, isNotEmpty);
      expect(roadB, isNotEmpty);
      final route = await drivingDirections(
        index,
        saved,
        roadA.first.point,
        roadB.first.point,
      );
      expect(route.length, greaterThan(2));
      expect(lengthOf(route), greaterThan(100));
    },
  );
}
