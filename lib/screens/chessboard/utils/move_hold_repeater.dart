import 'dart:async';

/// A hold walks one move at a time, gradually faster, without queuing work
/// while an asynchronous navigation step is still settling.
enum MoveHoldStep { moved, waiting, end }

class MoveHoldRepeater {
  MoveHoldRepeater({this.onEnd});

  final void Function()? onEnd;
  Timer? _timer;
  bool _active = false;
  int _generation = 0;
  int _moves = 0;

  bool get isActive => _active;

  static Duration intervalAfter(int moves) => Duration(
    milliseconds: moves < 4
        ? 150
        : moves < 8
        ? 120
        : moves < 12
        ? 90
        : 75,
  );

  void start(FutureOr<MoveHoldStep> Function() step) {
    stop();
    _active = true;
    _moves = 0;
    final generation = _generation;
    _schedule(step, generation);
  }

  void _schedule(FutureOr<MoveHoldStep> Function() step, int generation) {
    if (!_active || generation != _generation) return;
    _timer = Timer(intervalAfter(_moves), () {
      if (!_active || generation != _generation) return;
      try {
        final result = step();
        if (result is Future<MoveHoldStep>) {
          unawaited(
            result.then(
              (value) => _finish(value, step, generation),
              onError: (Object error, StackTrace stack) {
                if (generation == _generation) stop();
                if (error is StateError) return;
                Error.throwWithStackTrace(error, stack);
              },
            ),
          );
        } else {
          _finish(result, step, generation);
        }
      } on StateError {
        // A route/provider can disappear while the pointer is still held.
        if (generation == _generation) stop();
      }
    });
  }

  void _finish(
    MoveHoldStep result,
    FutureOr<MoveHoldStep> Function() step,
    int generation,
  ) {
    if (!_active || generation != _generation) return;
    if (result == MoveHoldStep.end) {
      stop();
      onEnd?.call();
      return;
    }
    if (result == MoveHoldStep.moved) _moves++;
    _schedule(step, generation);
  }

  void stop() {
    _active = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
  }
}
