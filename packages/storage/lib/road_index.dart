import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:offroad_core/trails.dart';
import 'package:sqlite3/sqlite3.dart';

const _majorKinds =
    "('motorway','trunk','primary','secondary','tertiary','unclassified','track','road','motorway_link','trunk_link','primary_link','secondary_link','tertiary_link')";
const _midKinds =
    "('motorway','trunk','primary','secondary','tertiary','unclassified','track','road','residential','living_street','motorway_link','trunk_link','primary_link','secondary_link','tertiary_link')";

List<RoadLine> _query(
  Database db,
  double south,
  double west,
  double north,
  double east, {
  int? limit,
  String? kindsSql,
}) {
  final filter = kindsSql == null ? '' : 'AND kind IN $kindsSql ';
  final rows = db.select(
    'SELECT name,kind,coords FROM bounds JOIN roads USING(id) WHERE maxlat>=? AND minlat<=? AND maxlon>=? AND minlon<=? $filter${limit == null ? "" : "LIMIT ?"}',
    [south, north, west, east, ?limit],
  );
  return [
    for (final row in rows)
      RoadLine(row['name'], row['kind'], [
        for (final v
            in jsonDecode(utf8.decode(zlib.decode(row['coords']))) as List)
          LatLng(v[0] / 1e6, (v[1] / 1e6 + 180) % 360 - 180),
      ]),
  ];
}

Future<List<RoadLine>> viewportRoads(
  String path,
  double south,
  double west,
  double north,
  double east, {
  double zoom = 14,
}) => Isolate.run(() {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    final kindsSql = zoom < 12.5
        ? _majorKinds
        : zoom < 14
        ? _midKinds
        : null;
    final limit = zoom < 12.5
        ? 1200
        : zoom < 14
        ? 1800
        : 2400;
    return _query(
      db,
      south,
      west,
      north,
      east,
      limit: limit,
      kindsSql: kindsSql,
    );
  } finally {
    db.close();
  }
});

typedef RoadSnap = ({LatLng point, String roadName, double distance});

RoadSnap? _findNearest(
  Database db,
  LatLng target,
  List<Trail> saved,
  double maxMeters,
) {
  final y = target.latitude;
  final x = target.longitude % 360;
  final r = maxMeters / 95000;
  final roads = _query(db, y - r, x - r, y + r, x + r);
  RoadSnap? best;
  void consider(LatLng a, LatLng b, String name) {
    final hit = projection(target, a, b);
    if (hit.offset <= maxMeters &&
        (best == null || hit.offset < best!.distance)) {
      best = (
        point: interpolate(a, b, hit.t),
        roadName: name,
        distance: hit.offset,
      );
    }
  }

  for (final road in roads) {
    for (var i = 1; i < road.points.length; i++) {
      consider(road.points[i - 1], road.points[i], road.name);
    }
  }
  for (final trail in saved) {
    for (final part in trail.parts) {
      for (var i = 1; i < part.length; i++) {
        consider(part[i - 1], part[i], trail.name);
      }
    }
  }
  return best;
}

/// Finds the closest point on an indexed OSM road or saved trail within [maxMeters].
Future<RoadSnap?> nearestRoadPoint(
  String path,
  LatLng target,
  List<Trail> saved, {
  double maxMeters = 45,
}) => Isolate.run(() {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    return _findNearest(db, target, saved, maxMeters);
  } finally {
    db.close();
  }
});

/// Connects the start and end of each new section cleanly onto a nearby road or
/// saved trail (within [maxMeters]), closing any gap left by road matching.
Future<List<PathPart>> snapRouteEnds(
  String path,
  List<PathPart> parts,
  List<Trail> saved, {
  double maxMeters = 45,
}) => Isolate.run(() {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    return [
      for (final part in parts)
        () {
          final out = List<LatLng>.of(part);
          if (out.length < 2) return out;
          final startHit = _findNearest(db, out.first, saved, maxMeters);
          if (startHit != null && startHit.distance > 0.5) {
            out.insert(0, startHit.point);
          }
          final endHit = _findNearest(db, out.last, saved, maxMeters);
          if (endHit != null && endHit.distance > 0.5) {
            out.add(endHit.point);
          }
          return out;
        }(),
    ];
  } finally {
    db.close();
  }
});

Future<List<PathPart>> filterRoads(
  String path,
  List<PathPart> raw,
  List<Trail> saved,
) => Isolate.run(() {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  final cache = <String, List<RoadLine>>{};
  // Spatial buckets are shared across adjacent GPS samples. All queries use
  // continuous longitudes around Fiji, including points on either side of 180.
  List<RoadLine> cell(int x, int y) {
    return cache.putIfAbsent('$x/$y', () {
      final west = x / 160,
          east = (x + 1) / 160,
          south = y / 160,
          north = (y + 1) / 160;
      final roads = _query(db, south, west, north, east);
      for (final trail in saved) {
        for (final part in trail.parts) {
          for (var i = 1; i < part.length; i++) {
            final a = part[i - 1],
                b = part[i],
                ax = a.longitude % 360,
                bx = b.longitude % 360;
            if (math.max(ax, bx) >= west &&
                math.min(ax, bx) <= east &&
                math.max(a.latitude, b.latitude) >= south &&
                math.min(a.latitude, b.latitude) <= north) {
              roads.add(RoadLine(trail.name, 'track', [a, b]));
            }
          }
        }
      }
      return roads;
    });
  }

  try {
    return newSections(raw, (a, b) {
      final ax = a.longitude % 360, bx = b.longitude % 360;
      return [
        for (
          var x = ((math.min(ax, bx) - .0002) * 160).floor();
          x <= ((math.max(ax, bx) + .0002) * 160).floor();
          x++
        )
          for (
            var y = ((math.min(a.latitude, b.latitude) - .0002) * 160).floor();
            y <= ((math.max(a.latitude, b.latitude) + .0002) * 160).floor();
            y++
          )
            ...cell(x, y),
      ];
    });
  } finally {
    db.close();
  }
});
