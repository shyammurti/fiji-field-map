import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

typedef PathPart = List<LatLng>;
const _earth = Distance(roundResult: false);
double meters(LatLng a, LatLng b) => _earth(a, b);
double deltaLon(double a, double b) => (b - a + 540) % 360 - 180;
double bearing(LatLng a, LatLng b) => (_earth.bearing(a, b) + 360) % 360;
double lengthOf(PathPart p) {
  double total = 0;
  for (var i = 1; i < p.length; i++) {
    total += meters(p[i - 1], p[i]);
  }
  return total;
}

LatLng interpolate(LatLng a, LatLng b, double t) => LatLng(
  a.latitude + (b.latitude - a.latitude) * t,
  (a.longitude + deltaLon(a.longitude, b.longitude) * t + 540) % 360 - 180,
);

class Trail {
  Trail(
    this.id,
    this.rev,
    this.parent,
    this.device,
    this.name,
    this.parts,
    this.created,
    this.updated, {
    this.deleted = false,
  });
  final String id, rev, device, name;
  final String? parent;
  final int created, updated;
  final List<PathPart> parts;
  final bool deleted;
  double get distance => parts.fold(0.0, (n, p) => n + lengthOf(p));
  factory Trail.create(
    String device,
    String name,
    List<PathPart> parts, {
    Trail? previous,
    bool deleted = false,
  }) {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return Trail(
      previous?.id ?? const Uuid().v4(),
      const Uuid().v4(),
      previous?.rev,
      device,
      name.trim(),
      parts,
      previous?.created ?? now,
      now,
      deleted: deleted,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'rev': rev,
    'parent': parent,
    'device': device,
    'name': name,
    'created': created,
    'updated': updated,
    'parts': encodeParts(parts),
    if (deleted) 'deleted': true,
  };
  factory Trail.fromJson(Map<String, dynamic> m) => Trail(
    m['id'],
    m['rev'],
    m['parent'],
    m['device'],
    m['name'],
    decodeParts(m['parts'] as List),
    m['created'],
    m['updated'],
    deleted: m['deleted'] == true,
  );
}

List<List<List<double>>> encodeParts(List<PathPart> parts) => [
  for (final p in parts)
    [
      for (final q in p) [q.latitude, q.longitude],
    ],
];
List<PathPart> decodeParts(List parts) => [
  for (final p in parts)
    [
      for (final q in p)
        LatLng((q[0] as num).toDouble(), (q[1] as num).toDouble()),
    ],
];

({double t, double offset}) projection(LatLng point, LatLng a, LatLng b) {
  final scale = math.cos(point.latitude * math.pi / 180);
  final dx = deltaLon(a.longitude, b.longitude) * scale,
      dy = b.latitude - a.latitude;
  final px = deltaLon(a.longitude, point.longitude) * scale,
      py = point.latitude - a.latitude;
  final square = dx * dx + dy * dy;
  final t = square == 0 ? 0.0 : ((px * dx + py * dy) / square).clamp(0.0, 1.0);
  return (
    t: t,
    offset:
        math.sqrt(math.pow(px - t * dx, 2) + math.pow(py - t * dy, 2)) * 111195,
  );
}

class RoadLine {
  RoadLine(this.name, this.kind, this.points);
  final String name, kind;
  final PathPart points;
}

/// Sample along the movement, requiring matching direction as well as proximity.
/// A known interval always closes the current part, preserving gaps in the drive.
List<PathPart> newSections(
  List<PathPart> input,
  List<RoadLine> Function(LatLng, LatLng) candidates, {
  double tolerance = 12,
}) {
  final result = <PathPart>[];
  for (final p in input) {
    PathPart part = [];
    void finish() {
      if (part.length >= 2 && lengthOf(part) >= 3) result.add(part);
      part = [];
    }

    for (var i = 1; i < p.length; i++) {
      final a = p[i - 1], b = p[i], len = meters(a, b);
      if (len < 0.5) continue;
      final bins = (len / 500).ceil();
      for (var j = 0; j < bins; j++) {
        final u = interpolate(a, b, j / bins),
            v = interpolate(a, b, (j + 1) / bins);
        final near = candidates(u, v);
        final count = (meters(u, v) / 10).ceil().clamp(1, 100);
        final course = bearing(u, v);
        for (var k = 0; k < count; k++) {
          final start = interpolate(u, v, k / count),
              end = interpolate(u, v, (k + 1) / count);
          final mid = interpolate(start, end, .5);
          bool matched = false;
          for (final road in near) {
            for (var s = 1; s < road.points.length; s++) {
              final r = road.points[s - 1], q = road.points[s];
              if (projection(mid, r, q).offset > tolerance) continue;
              final angle = (bearing(r, q) - course).abs() % 180;
              if (math.min(angle, 180 - angle) <= 35) {
                matched = true;
                break;
              }
            }
            if (matched) break;
          }
          if (matched) {
            finish();
          } else {
            if (part.isEmpty) part.add(start);
            // Keep original turns, plus boundaries of novel sections.
            if (part.length >= 2 &&
                (deltaLon(
                      bearing(part[part.length - 2], part.last),
                      bearing(part.last, end),
                    )).abs() <
                    .1) {
              part[part.length - 1] = end;
            } else {
              part.add(end);
            }
          }
        }
      }
    }
    finish();
  }
  return result;
}

enum TurnKind {
  straight,
  slightLeft,
  left,
  sharpLeft,
  slightRight,
  right,
  sharpRight,
  uTurn,
  arrive,
}

class Guidance {
  Guidance(
    this.remaining,
    this.bearingDeg,
    this.offset,
    this.next,
    this.arrived, {
    this.turn = TurnKind.straight,
    this.turnDistance = 0,
  });
  final double remaining, bearingDeg, offset, turnDistance;
  final int next;
  final bool arrived;
  final TurnKind turn;

  String get instruction {
    if (arrived) return 'Arrived';
    return switch (turn) {
      TurnKind.arrive => 'Arrive at destination',
      TurnKind.straight => 'Continue straight',
      TurnKind.slightLeft => 'Keep left',
      TurnKind.left => 'Turn left',
      TurnKind.sharpLeft => 'Sharp left',
      TurnKind.slightRight => 'Keep right',
      TurnKind.right => 'Turn right',
      TurnKind.sharpRight => 'Sharp right',
      TurnKind.uTurn => 'Make a U-turn',
    };
  }
}

LatLng _pointAlong(PathPart path, int fromIndex, double targetMeters, int dir) {
  var acc = 0.0;
  var idx = fromIndex;
  while (idx + dir >= 0 && idx + dir < path.length) {
    final seg = meters(path[idx], path[idx + dir]);
    if (acc + seg >= targetMeters && seg > 0.1) {
      return interpolate(
        path[idx],
        path[idx + dir],
        (targetMeters - acc) / seg,
      );
    }
    acc += seg;
    idx += dir;
  }
  return path[idx];
}

Guidance guide(PathPart path, LatLng here) {
  var index = 1, t = 0.0, best = double.infinity;
  for (var i = 1; i < path.length; i++) {
    final hit = projection(here, path[i - 1], path[i]);
    if (hit.offset < best) {
      best = hit.offset;
      index = i;
      t = hit.t;
    }
  }
  final segLeft = (1 - t) * meters(path[index - 1], path[index]);
  var left = segLeft;
  for (var i = index + 1; i < path.length; i++) {
    left += meters(path[i - 1], path[i]);
  }
  final arrived = left < 18 && meters(here, path.last) < 18;
  var turn = TurnKind.arrive;
  var turnDist = left;
  if (!arrived) {
    var distToVertex = segLeft;
    for (var i = index; i < path.length - 1; i++) {
      // Sample ~20 m before and after vertex i so tiny road-curve vertices don't trigger false turns.
      final before = _pointAlong(path, i, 20, -1);
      final after = _pointAlong(path, i, 20, 1);
      if (meters(before, path[i]) >= 4 && meters(path[i], after) >= 4) {
        final angle = deltaLon(
          bearing(before, path[i]),
          bearing(path[i], after),
        );
        final absAngle = angle.abs();
        if (absAngle >= 28) {
          if (absAngle >= 145) {
            turn = TurnKind.uTurn;
          } else if (absAngle >= 110) {
            turn = angle > 0 ? TurnKind.sharpRight : TurnKind.sharpLeft;
          } else if (absAngle >= 50) {
            turn = angle > 0 ? TurnKind.right : TurnKind.left;
          } else {
            turn = angle > 0 ? TurnKind.slightRight : TurnKind.slightLeft;
          }
          turnDist = distToVertex;
          break;
        }
      }
      distToVertex += meters(path[i], path[i + 1]);
    }
    if (turn == TurnKind.arrive && left > 180) {
      turn = TurnKind.straight;
    }
  }
  return Guidance(
    left,
    bearing(here, path[index]),
    best,
    index,
    arrived,
    turn: turn,
    turnDistance: turnDist,
  );
}

class EtaEstimate {
  const EtaEstimate({
    required this.duration,
    required this.arrival,
    required this.speedKmh,
    required this.liveBased,
  });
  final Duration duration;
  final DateTime arrival;
  final double speedKmh;
  final bool liveBased;
}

/// Smooths live GPS speed and computes steady remaining time and arrival clock
/// ETA, falling back to a realistic Fiji road/track baseline when stationary.
class EtaEstimator {
  EtaEstimator({this.baselineMps = 10.0}); // ~36 km/h Fiji mixed road baseline
  final double baselineMps;
  double? _smoothedMps;

  void reset() => _smoothedMps = null;

  void recordSpeed(double? speedMps) {
    if (speedMps == null || !speedMps.isFinite || speedMps < 1.2) return;
    final clamped = speedMps.clamp(1.2, 36.0);
    _smoothedMps = _smoothedMps == null
        ? clamped
        : _smoothedMps! * 0.72 + clamped * 0.28;
  }

  EtaEstimate estimate(
    double remainingMeters, {
    double? liveSpeedMps,
    DateTime? now,
  }) {
    final kmh =
        liveSpeedMps != null && liveSpeedMps.isFinite && liveSpeedMps >= 0.4
        ? liveSpeedMps * 3.6
        : 0.0;
    final hasLive = _smoothedMps != null && _smoothedMps! >= 1.5;
    final effectiveMps = hasLive
        ? (_smoothedMps! * 0.75 + baselineMps * 0.25)
        : baselineMps;
    final seconds = remainingMeters <= 0
        ? 0
        : (remainingMeters / effectiveMps).round();
    final duration = Duration(seconds: seconds);
    final clock = (now ?? DateTime.now()).add(duration);
    return EtaEstimate(
      duration: duration,
      arrival: clock,
      speedKmh: kmh,
      liveBased: hasLive,
    );
  }
}

String formatDuration(Duration d) {
  final mins = (d.inSeconds / 60).ceil();
  if (mins <= 0) return '< 1 min';
  if (mins < 60) return '$mins min';
  final h = mins ~/ 60;
  final m = mins % 60;
  return m == 0 ? '$h hr' : '$h hr $m min';
}

String formatClock(DateTime dt) {
  final local = dt.toLocal();
  final h24 = local.hour;
  final suffix = h24 >= 12 ? 'PM' : 'AM';
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  final mm = local.minute.toString().padLeft(2, '0');
  return '$h12:$mm $suffix';
}

/// A gap or poor fix breaks continuity. Never draw a straight segment across it.
List<PathPart> driveParts(List samples) {
  final parts = <PathPart>[];
  PathPart? current;
  int? lastTime;
  for (final row in samples) {
    final stamp = row[2] as int;
    if ((row[3] as num) > 18) {
      current = null;
      lastTime = null;
      continue;
    }
    final pt = LatLng((row[0] as num).toDouble(), (row[1] as num).toDouble());
    if (lastTime != null && stamp <= lastTime) continue;
    if (current == null ||
        lastTime == null ||
        stamp - lastTime > 35000 ||
        meters(current.last, pt) > (stamp - lastTime) * .07 + 25) {
      current = [pt];
      parts.add(current);
    } else if (meters(current.last, pt) >= 3) {
      current.add(pt);
    }
    lastTime = stamp;
  }
  return parts.where((p) => p.length >= 2).toList();
}
