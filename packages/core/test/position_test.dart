import 'dart:async';
import 'package:offroad_core/position.dart';
import 'package:test/test.dart';

class FakeSource implements PositionSource {
  final prepareResult = Completer<FixStatus>();
  final positions = StreamController<Fix>.broadcast(sync: true);
  final compass = StreamController<double?>.broadcast(sync: true);
  @override
  Future<FixStatus> prepare() => prepareResult.future;
  @override
  Stream<Fix> fixes() => positions.stream;
  @override
  Stream<double?> headings() => compass.stream;
}

void main() {
  late FakeSource source;
  late PositionTracker tracker;
  late DateTime now;
  setUp(() {
    now = DateTime.utc(2026, 11, 24);
    source = FakeSource();
    tracker = PositionTracker(source, clock: () => now);
  });
  tearDown(() async {
    tracker.dispose();
    await source.positions.close();
    await source.compass.close();
  });
  test(
    'Suva fix ages offline, remains visible, and can recover east of 180',
    () async {
      source.prepareResult.complete(FixStatus.searching);
      await tracker.start();
      final suva = Fix(-18.14, 178.44, now);
      source.positions.add(suva);
      source.compass.add(45);
      expect(tracker.state.compass, 45);
      expect(tracker.state.status, FixStatus.live);
      now = now.add(const Duration(seconds: 16));
      tracker.refresh();
      expect(tracker.state.status, FixStatus.stale);
      expect(tracker.state.compass, isNull);
      now = now.add(const Duration(seconds: 30));
      tracker.refresh();
      expect(tracker.state.status, FixStatus.lost);
      expect(tracker.state.fix, same(suva));
      source.positions.add(Fix(-16.8, -179.9, now));
      expect(tracker.state.status, FixStatus.live);
      source.positions.add(suva);
      expect(tracker.state.fix!.lon, -179.9);
    },
  );
  test('manual selection wins over a delayed OS permission response', () async {
    final pending = tracker.start();
    tracker.manual(-17.8, 177.4);
    source.prepareResult.complete(FixStatus.searching);
    await pending;
    source.positions.add(Fix(0, 0, now));
    expect(tracker.state.status, FixStatus.manual);
    expect(tracker.state.fix!.lon, 177.4);
  });
  test('reports blocked permissions and disabled location', () async {
    source.prepareResult.complete(FixStatus.blocked);
    await tracker.start();
    expect(tracker.state.status, FixStatus.blocked);
    expect(tracker.state.fix, isNull);
  });
  test(
    'no initial fix times out; invalid points cannot become current',
    () async {
      source.prepareResult.complete(FixStatus.searching);
      await tracker.start();
      source.positions.add(Fix(double.nan, 0, now));
      now = now.add(const Duration(seconds: 46));
      tracker.refresh();
      expect(tracker.state.status, FixStatus.lost);
      expect(tracker.state.fix, isNull);
      source.positions.addError(FixStatus.disabled);
      expect(tracker.state.status, FixStatus.disabled);
    },
  );
}
