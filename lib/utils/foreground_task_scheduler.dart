import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

const Duration kForegroundRefreshDelay = Duration(milliseconds: 700);
const Duration kForegroundHeavyRefreshDelay = Duration(milliseconds: 1100);
const Duration kStartupWarmupDelay = Duration(seconds: 2);

/// Defers non-visual foreground work until after the first resumed frame.
///
/// Resume events arrive before the app has painted its first foreground frame.
/// Starting network refreshes, stream invalidations, or native engine recovery
/// in that same window makes the foreground transition feel choppy.
class ForegroundTaskScheduler {
  ForegroundTaskScheduler._();

  static final Map<String, Timer> _timers = <String, Timer>{};
  static final Map<String, int> _generations = <String, int>{};

  static void schedule({
    required String key,
    required FutureOr<void> Function() task,
    Duration delay = kForegroundRefreshDelay,
  }) {
    cancel(key);
    final generation = (_generations[key] ?? 0) + 1;
    _generations[key] = generation;
    _timers[key] = Timer(delay, () {
      _timers.remove(key);
      unawaited(_runAfterFrame(key, generation, task));
    });
  }

  static void cancel(String key) {
    final timer = _timers.remove(key);
    if (timer != null) {
      timer.cancel();
      _generations.remove(key);
      return;
    }

    final generation = _generations[key];
    if (generation != null) {
      _generations[key] = generation + 1;
    }
  }

  static Future<void> _runAfterFrame(
    String key,
    int generation,
    FutureOr<void> Function() task,
  ) async {
    try {
      if (_generations[key] != generation) return;
      await WidgetsBinding.instance.endOfFrame;
      if (_generations[key] != generation) return;

      final lifecycleState = WidgetsBinding.instance.lifecycleState;
      if (lifecycleState != null &&
          lifecycleState != AppLifecycleState.resumed) {
        return;
      }

      await task();
    } catch (error, stackTrace) {
      debugPrint('Foreground task "$key" failed: $error');
      if (kDebugMode) {
        debugPrintStack(stackTrace: stackTrace);
      }
    } finally {
      if (_generations[key] == generation) {
        _generations.remove(key);
      }
    }
  }
}
