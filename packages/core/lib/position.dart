import 'dart:async';

enum FixStatus {
  idle,
  searching,
  live,
  stale,
  lost,
  disabled,
  denied,
  blocked,
  unavailable,
  manual,
}

class Fix {
  const Fix(
    this.lat,
    this.lon,
    this.time, {
    this.altitude,
    this.speed,
    this.accuracy,
    this.course,
  });
  final double lat, lon;
  final DateTime time;
  final double? altitude, speed, accuracy, course;

  bool get valid =>
      lat.isFinite && lat.abs() <= 90 && lon.isFinite && lon.abs() <= 180;
}

class PositionState {
  const PositionState(this.status, [this.fix, this.compass]);
  final FixStatus status;
  final Fix? fix;
  final double? compass;
}

/// Platform implementations handle permission and hardware. Time and state
/// transitions stay in this package so a desktop test can exercise GPS loss.
abstract interface class PositionSource {
  Future<FixStatus> prepare();
  Stream<Fix> fixes();
  Stream<double?> headings();
}

class PositionTracker {
  PositionTracker(this.source, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final PositionSource source;
  final DateTime Function() clock;
  final _changes = StreamController<PositionState>.broadcast();
  Stream<PositionState> get changes => _changes.stream;
  PositionState state = const PositionState(FixStatus.idle);
  StreamSubscription<Fix>? _fixes;
  StreamSubscription<double?>? _headings;
  Timer? _timer;
  int _generation = 0;
  DateTime? _started, _headingTime;
  bool _followingSource = false;
  double? _heading;
  Fix? _last;

  void _emit(FixStatus status) {
    if (_changes.isClosed) return;
    if (state.status == status &&
        identical(_last, state.fix) &&
        _heading == state.compass)
      return;
    state = PositionState(status, _last, _heading);
    _changes.add(state);
  }

  void _disconnect() {
    _generation++;
    _followingSource = false;
    _timer?.cancel();
    _fixes?.cancel();
    _headings?.cancel();
    _heading = null;
    _headingTime = null;
  }

  void manual(double lat, double lon) {
    final point = Fix(lat, lon, clock());
    if (!point.valid) throw ArgumentError('Invalid manual position');
    _disconnect();
    _last = point;
    _emit(FixStatus.manual);
  }

  void stop() {
    _disconnect();
    _last = null;
    _emit(FixStatus.idle);
  }

  Future<void> start() async {
    _disconnect();
    final generation = _generation;
    _last = null;
    _started = clock();
    _emit(FixStatus.searching);
    try {
      final ready = await source.prepare();
      if (generation != _generation) return;
      if (ready != FixStatus.searching) {
        _emit(ready);
        return;
      }
      _followingSource = true;
      _started = clock();
      _fixes = source.fixes().listen(
        (fix) {
          if (generation != _generation || !fix.valid) return;
          if (_last != null && fix.time.isBefore(_last!.time)) return;
          if (fix.time.isAfter(clock().add(const Duration(seconds: 5)))) return;
          _last = fix;
          refresh();
        },
        onError: (Object e) =>
            _endStream(generation, e is FixStatus ? e : FixStatus.unavailable),
        onDone: () => _endStream(generation, FixStatus.lost),
      );
      _headings = source.headings().listen(
        (angle) {
          if (generation != _generation) return;
          _heading = angle != null && angle.isFinite && angle >= 0
              ? angle.roundToDouble() % 360
              : null;
          _headingTime = clock();
          refresh();
        },
        onError: (Object _) {
          if (generation == _generation) {
            _heading = null;
            refresh();
          }
        },
      );
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
    } catch (e) {
      _endStream(generation, e is FixStatus ? e : FixStatus.unavailable);
    }
  }

  void _endStream(int generation, FixStatus status) {
    if (generation != _generation) return;
    _disconnect();
    _emit(status);
  }

  /// The last coordinates remain visible and explicitly labelled after loss.
  void refresh() {
    if (!_followingSource) return;
    final now = clock();
    if (_headingTime != null &&
        now.difference(_headingTime!) > const Duration(seconds: 10)) {
      _heading = null;
    }
    final age = now.difference(_last?.time ?? _started!);
    if (age >= const Duration(seconds: 45)) {
      _emit(FixStatus.lost);
    } else if (_last == null) {
      _emit(FixStatus.searching);
    } else {
      _emit(
        age >= const Duration(seconds: 15) ? FixStatus.stale : FixStatus.live,
      );
    }
  }

  void dispose() {
    _disconnect();
    _changes.close();
  }
}
