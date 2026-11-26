import 'package:latlong2/latlong.dart';
import 'package:offroad_core/trails.dart';
import 'package:test/test.dart';

void main() {
  const a = LatLng(-18, 178), b = LatLng(-18, 178.002);
  final road = RoadLine('Existing road', 'track', [a, b]);
  test('forward and reverse on a mapped road produce no new trail', () {
    for (final path in [
      [a, b],
      [b, a],
    ]) {
      expect(newSections([path], (_, _) => [road]), isEmpty);
    }
  });
  test('leaving and rejoining preserves only separate new pieces', () {
    const left = LatLng(-18, 177.999), right = LatLng(-18, 178.003);
    final parts = newSections([
      [left, right],
    ], (_, _) => [road]);
    expect(parts.length, 2);
    for (final p in parts) {
      expect(lengthOf(p), inInclusiveRange(80, 115));
    }
    expect(parts.first.last.longitude, lessThan(parts.last.first.longitude));
  });
  test('crossing and nearby separate parallel trails are retained', () {
    const crossing = [LatLng(-18.001, 178.001), LatLng(-17.999, 178.001)];
    expect(
      lengthOf(newSections([crossing], (_, _) => [road]).single),
      closeTo(lengthOf(crossing), 1),
    );
    const parallel = [LatLng(-18.0003, 178), LatLng(-18.0003, 178.002)];
    expect(newSections([parallel], (_, _) => [road]), hasLength(1));
  });
  test('bad accuracy and GPS gaps cannot connect disjoint drives', () {
    final parts = driveParts([
      [-18, 178, 1000, 4],
      [-18, 178.0001, 3000, 4],
      [-18, 178.0002, 5000, 60],
      [-18, 178.001, 9000, 4],
      [-18, 178.0011, 12000, 4],
    ]);
    expect(parts, hasLength(2));
  });
  test('guidance uses short date-line crossing and detects arrival', () {
    const p = [LatLng(-16.8, 179.999), LatLng(-16.8, -179.999)];
    expect(guide(p, p.first).remaining, inInclusiveRange(180, 240));
    expect(guide(p, p.last).arrived, isTrue);
  });
  test(
    'guidance scans ahead for real turns and EtaEstimator smooths speed',
    () {
      const route = [
        LatLng(-18.140, 178.440),
        LatLng(-18.1385, 178.440),
        LatLng(-18.1373, 178.440),
        LatLng(-18.1373, 178.443),
      ];
      final g = guide(route, route.first);
      expect(g.turn, TurnKind.right);
      expect(g.turnDistance, inInclusiveRange(280, 320));
      final eta = EtaEstimator(baselineMps: 10);
      final base = eta.estimate(1000, liveSpeedMps: 0);
      expect(base.liveBased, isFalse);
      expect(base.speedKmh, 0);
      expect(base.duration.inSeconds, 100);
      eta.recordSpeed(20);
      eta.recordSpeed(20);
      final moving = eta.estimate(1000, liveSpeedMps: 20);
      expect(moving.liveBased, isTrue);
      expect(moving.speedKmh, closeTo(72, 0.1));
      expect(moving.duration.inSeconds, lessThan(base.duration.inSeconds));
      expect(formatDuration(const Duration(minutes: 75)), '1 hr 15 min');
    },
  );
}
