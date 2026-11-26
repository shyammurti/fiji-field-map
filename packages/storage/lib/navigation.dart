import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:collection/collection.dart';
import 'package:latlong2/latlong.dart';
import 'package:offroad_core/trails.dart';
import 'package:sqlite3/sqlite3.dart';

typedef _Link = ({int id, LatLng point, double cost});
typedef _Segment = ({int a, int b, LatLng p, LatLng q, int direction});
typedef _Match = ({_Segment segment, double t, double distance});
Future<PathPart> drivingDirections(
  String index,
  List<Trail> saved,
  LatLng start,
  LatLng destination,
) => Isolate.run(() {
  final db = sqlite3.open(index, mode: OpenMode.readOnly);
  try {
    return _Graph(db, saved).route(start, destination);
  } finally {
    db.close();
  }
});

/// Positive IDs come from OSM nodes, preserving topology at overpasses.
/// Negative IDs exist for this calculation only, including virtual edge splits.
class _Graph {
  _Graph(this.db, List<Trail> trails) {
    final ends = <int, LatLng>{};
    final shared = <String, int>{};
    for (final trail in trails) {
      for (final path in trail.parts) {
        int? last;
        for (var i = 0; i < path.length; i++) {
          final p = path[i], endpoint = i == 0 || i == path.length - 1;
          final vid = endpoint
              ? shared.putIfAbsent(
                  '${(p.latitude * 1e6).round()},${(p.longitude * 1e6).round()}',
                  () => --serial,
                )
              : --serial;
          if (endpoint) ends[vid] = p;
          if (last != null) {
            final s = (a: last, b: vid, p: path[i - 1], q: p, direction: 0);
            userSegments.add(s);
            edge(s.a, s.b, s.p, s.q);
            edge(s.b, s.a, s.q, s.p);
          }
          last = vid;
        }
      }
    }
    for (final entry in ends.entries) {
      final m = nearest(entry.value, 45, includeUser: false);
      if (m != null) attach(entry.key, entry.value, m);
      // Also bridge trail endpoints to nearby segments of other saved trails.
      _Match? trailMatch;
      for (final s in userSegments) {
        if (s.a == entry.key || s.b == entry.key) continue;
        final h = projection(entry.value, s.p, s.q);
        if (h.offset <= 25 &&
            (trailMatch == null || h.offset < trailMatch.distance)) {
          trailMatch = (segment: s, t: h.t, distance: h.offset);
        }
      }
      if (trailMatch != null) attach(entry.key, entry.value, trailMatch);
    }
  }
  final Database db;
  int serial = 0;
  final extra = <int, List<_Link>>{};
  final userSegments = <_Segment>[];
  final cuts = <String, List<({double t, int id, LatLng pt, int dir})>>{};
  void edge(int a, int b, LatLng p, LatLng q) {
    (extra[a] ??= []).add((id: b, point: q, cost: meters(p, q)));
  }

  _Match? nearest(LatLng p, double limit, {bool includeUser = true}) {
    _Match? nearest;
    void consider(_Segment s) {
      final h = projection(p, s.p, s.q);
      if (h.offset <= limit &&
          (nearest == null || h.offset < nearest!.distance))
        nearest = (segment: s, t: h.t, distance: h.offset);
    }

    final y = p.latitude, x = p.longitude % 360, r = limit / 95000;
    final rows = db.select(
      'SELECT node_ids,coords,direction FROM bounds JOIN roads USING(id) WHERE node_ids IS NOT NULL AND maxlon>=? AND minlon<=? AND maxlat>=? AND minlat<=?',
      [x - r, x + r, y - r, y + r],
    );
    for (final row in rows) {
      final pts = jsonDecode(utf8.decode(zlib.decode(row['coords']))) as List;
      final ids = jsonDecode(utf8.decode(zlib.decode(row['node_ids']))) as List;
      LatLng coord(int i) =>
          LatLng(pts[i][0] / 1e6, (pts[i][1] / 1e6 + 180) % 360 - 180);
      for (var i = 1; i < ids.length; i++) {
        consider((
          a: ids[i - 1] as int,
          b: ids[i] as int,
          p: coord(i - 1),
          q: coord(i),
          direction: row['direction'] as int,
        ));
      }
    }
    if (includeUser) {
      for (final s in userSegments) {
        consider(s);
      }
    }
    return nearest;
  }

  void attach(int id, LatLng pt, _Match m) {
    final s = m.segment, snap = interpolate(s.p, s.q, m.t), node = --serial;
    edge(id, node, pt, snap);
    edge(node, id, snap, pt);
    if (s.direction >= 0) {
      edge(s.a, node, s.p, snap);
      edge(node, s.b, snap, s.q);
    }
    if (s.direction <= 0) {
      edge(s.b, node, s.q, snap);
      edge(node, s.a, snap, s.p);
    }
    final forward = s.a < s.b;
    final group = cuts.putIfAbsent(
      forward ? '${s.a}/${s.b}' : '${s.b}/${s.a}',
      () => [],
    );
    final t = forward ? m.t : 1 - m.t,
        dir = forward ? s.direction : -s.direction;
    for (final other in group) {
      if ((t - other.t) * dir >= 0) edge(other.id, node, other.pt, snap);
      if ((other.t - t) * dir >= 0) edge(node, other.id, snap, other.pt);
    }
    group.add((t: t, id: node, pt: snap, dir: dir));
  }

  PathPart route(LatLng from, LatLng to) {
    final a = nearest(from, 80), b = nearest(to, 80);
    if (a == null || b == null)
      throw StateError(
        'No connected road within 80 m of the position or trail entrance.',
      );
    final start = --serial, goal = --serial;
    attach(start, from, a);
    attach(goal, to, b);
    final queue = HeapPriorityQueue<({int id, double g, double f})>(
      (a, b) => a.f.compareTo(b.f),
    );
    final costs = <int, double>{start: 0},
        prior = <int, int>{},
        positions = <int, LatLng>{start: from};
    queue.add((id: start, g: 0.0, f: 0.0));
    final lookup = db.prepare('SELECT dst,lat,lon,cost FROM edges WHERE src=?');
    try {
      while (queue.isNotEmpty) {
        final at = queue.removeFirst();
        if (at.g != costs[at.id]) continue;
        if (at.id == goal) {
          final path = <LatLng>[];
          int? current = goal;
          while (current != null) {
            final p = positions[current]!;
            if (path.isEmpty || meters(path.last, p) > .2) path.add(p);
            current = prior[current];
          }
          return path.reversed.toList();
        }
        final edges = <_Link>[...?extra[at.id]];
        if (at.id > 0) {
          for (final row in lookup.select([at.id])) {
            edges.add((
              id: row['dst'],
              point: LatLng(row['lat'], (row['lon'] + 180) % 360 - 180),
              cost: row['cost'],
            ));
          }
        }
        for (final e in edges) {
          final g = at.g + e.cost;
          if (g >= (costs[e.id] ?? double.infinity)) continue;
          costs[e.id] = g;
          prior[e.id] = at.id;
          positions[e.id] = e.point;
          queue.add((id: e.id, g: g, f: g + projectionDistance(e.point, to)));
        }
      }
    } finally {
      lookup.close();
    }
    throw StateError(
      'No connected driving route. You can still follow the saved trail.',
    );
  }

  double projectionDistance(LatLng a, LatLng b) => meters(a, b) * .98;
}
