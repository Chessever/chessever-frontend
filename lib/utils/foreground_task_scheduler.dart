import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

const Duration kForegroundRefreshDelay = Duration(milliseconds: 700);
const Duration kForegroundHeavyRefreshDelay = Duration(milliseconds: 1100);
const Duration kStartupWarmupDelay = Duration(seconds: 2);

/// Delay before warming up the native audio engine on startup.
///
/// Native audio init (engine spin-up + extracting the SFX assets to temp
/// files) briefly stalls the main thread. At the old 2s delay that stall landed
/// on the splash→auth brand-logo *assemble* (splash holds ~3s, the auth logo
/// assembles right after), and because the logo's [AnimationController] is
/// wall-clock driven, the stall made it skip frames — a visible "jump" + FPS
/// dip at the end of the assemble. Audio is one-time and isn't needed until a
/// board move (well past any startup flow), so we push it past the entrance
/// animations; by ~6s the logo is in its idle loop where sub-pixel motion hides
/// any stall.
const Duration kAudioWarmupDelay = Duration(seconds: 6);

/// Defers non-visual foreground work until after the first resumed frame.
///
/// Resume events arrive before the app has painted its first foreground frame.
/// Starting network refreshes, stream invalidations, or native engine recovery
/// in that same window makes the foreground transition feel choppy.
class ForegroundTaskScheduler {
  ForegroundTaskScheduler._();

  static final Map<String, Timer> _timers = <String, Timer>{};
  static final Map<String, int> _generations = <String, int>{};

  /// Runs [task] after [delay] and the next frame, if the app is in the
  /// foreground then. A task due while the app is not resumed is dropped,
  /// unless [runWhenResumed]: then it waits for the next resume and runs
  /// once. Use that for work that must happen once per launch (the startup
  /// intake of a shared file or an attribution link), never for refreshes.
  static void schedule({
    required String key,
    required FutureOr<void> Function() task,
    Duration delay = kForegroundRefreshDelay,
    bool runWhenResumed = false,
  }) {
    cancel(key);
    final generation = (_generations[key] ?? 0) + 1;
    _generations[key] = generation;
    _timers[key] = Timer(delay, () {
      _timers.remove(key);
      unawaited(
        _runAfterFrame(key, generation, task, runWhenResumed: runWhenResumed),
      );
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
    FutureOr<void> Function() task, {
    bool runWhenResumed = false,
  }) async {
    try {
      if (_generations[key] != generation) return;
      await WidgetsBinding.instance.endOfFrame;
      if (_generations[key] != generation) return;

      var lifecycleState = WidgetsBinding.instance.lifecycleState;
      if (lifecycleState != null &&
          lifecycleState != AppLifecycleState.resumed) {
        if (!runWhenResumed) return;
        _addBreadcrumb(
          key,
          'foreground task waiting for resume',
          data: {'lifecycle_state': lifecycleState.name},
        );
        await _nextResume();
        if (_generations[key] != generation) return;
        lifecycleState = WidgetsBinding.instance.lifecycleState;
      }

      _addBreadcrumb(
        key,
        'foreground task started',
        data: {'lifecycle_state': lifecycleState?.name},
      );
      final stopwatch = Stopwatch()..start();
      await task();
      stopwatch.stop();
      _addBreadcrumb(
        key,
        'foreground task completed',
        data: {
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'lifecycle_state': lifecycleState?.name,
        },
      );
    } catch (error, stackTrace) {
      debugPrint('Foreground task "$key" failed: $error');
      _addBreadcrumb(
        key,
        'foreground task failed',
        data: {'error': error.toString()},
        level: SentryLevel.warning,
      );
      if (kDebugMode) {
        debugPrintStack(stackTrace: stackTrace);
      }
    } finally {
      if (_generations[key] == generation) {
        _generations.remove(key);
      }
    }
  }

  /// Completes the next time the app is resumed (at once if it already is).
  static Future<void> _nextResume() {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      return Future<void>.value();
    }
    final resumed = Completer<void>();
    late final AppLifecycleListener listener;
    listener = AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed || resumed.isCompleted) return;
        listener.dispose();
        resumed.complete();
      },
    );
    return resumed.future;
  }

  static void _addBreadcrumb(
    String key,
    String message, {
    Map<String, dynamic>? data,
    SentryLevel level = SentryLevel.info,
  }) {
    try {
      Sentry.addBreadcrumb(
        Breadcrumb(
          category: 'foreground_task',
          message: message,
          type: 'debug',
          data: <String, dynamic>{'key': key, ...?data},
          level: level,
        ),
      );
    } catch (_) {
      // Diagnostics must never affect scheduled work.
    }
  }
}
