import 'dart:math' as math;

/// The highest progress shown while a report is still being computed.
/// Completion is reserved for the final report payload.
const double kRunningGameReportProgressCeiling = 0.96;

/// Keeps the report progress bar moving between sparse progress callbacks.
///
/// Two modes, because the two report paths have different problems:
///
/// * **Local (engine) passes** call back once per analysed position, which is
///   already a truthful, evenly-spaced bar. Left [start]ed-less, this only
///   clamps and enforces monotonicity — the local path keeps the progress it
///   always had.
/// * **The server path** answers once per poll (seconds apart), and the job
///   spends most of its life inside one phase, so the raw fraction sits still
///   long enough to read as a hang. [start] arms a time curve that carries the
///   bar between polls.
///
/// The curve is a presentation layer and nothing more: it never overtakes a
/// higher real callback, never moves backwards, and cannot reach 1 — completion
/// belongs to the arrival of the report itself.
class GameReportProgressSimulator {
  GameReportProgressSimulator({
    DateTime Function()? now,
    this.fakeDuration = const Duration(minutes: 3),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// Roughly how long a server report is expected to take. The curve is
  /// asymptotic, so overrunning it slows the bar rather than stalling it.
  final Duration fakeDuration;

  DateTime? _startedAt;
  double _reportedTarget = 0;
  double _value = 0;

  double get value => _value;

  /// Arms the time curve. Called when a run that needs it begins.
  void start({double initial = 0}) {
    _startedAt = _now();
    _reportedTarget = _clampRunning(initial);
    _value = _reportedTarget;
  }

  /// Disarms the curve and forgets the run.
  ///
  /// Called when a run ends however it ends, so the pass that follows a failed
  /// server attempt reports its own real progress rather than inheriting the
  /// abandoned run's curve.
  void reset() {
    _startedAt = null;
    _reportedTarget = 0;
    _value = 0;
  }

  /// Accepts a real progress callback and returns the value to display.
  double observe(double reportedProgress) {
    _reportedTarget = math.max(
      _reportedTarget,
      _clampRunning(reportedProgress),
    );
    if (_startedAt == null) {
      // No curve armed: pass the real fraction through, monotonically.
      _value = math.max(_value, _reportedTarget);
      return _value;
    }
    return _advance();
  }

  /// Advances the display while the server is between polling callbacks.
  double tick() {
    if (_startedAt == null) return _value;
    return _advance();
  }

  /// Marks the actual report payload as complete.
  double finish() {
    _value = 1;
    _reportedTarget = 1;
    return _value;
  }

  double _advance() {
    final startedAt = _startedAt;
    if (startedAt == null) return _value;

    final elapsedSeconds = _seconds(_now().difference(startedAt));
    final durationSeconds = math.max(1.0, _seconds(fakeDuration));
    // Asymptotic: fast at first, then ever slower, so a long job keeps creeping
    // instead of parking at the ceiling and looking stuck.
    final curveProgress =
        _curveFloor +
        (kRunningGameReportProgressCeiling - _curveFloor) *
            (1 - math.exp(-elapsedSeconds / (durationSeconds / 2.5)));
    final desired = math
        .max(_reportedTarget, curveProgress)
        .clamp(0.0, kRunningGameReportProgressCeiling);
    final remaining = desired - _value;
    if (remaining <= 0) return _value;

    // Ease toward the target instead of jumping to an optimistic callback.
    final step = math.max(_minStep, remaining * 0.35);
    _value = math.min(kRunningGameReportProgressCeiling, _value + step);
    return _value;
  }

  double _clampRunning(double progress) {
    if (!progress.isFinite) return 0;
    return progress.clamp(0.0, kRunningGameReportProgressCeiling).toDouble();
  }

  static double _seconds(Duration duration) =>
      duration.inMilliseconds / Duration.millisecondsPerSecond;

  /// Where the curve starts, so the bar is visibly non-empty immediately.
  static const double _curveFloor = 0.02;

  /// Floor on a single step, so the bar always moves on a tick that is due.
  static const double _minStep = 0.004;
}
