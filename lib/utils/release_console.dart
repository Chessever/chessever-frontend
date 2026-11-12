import 'dart:async';
import 'dart:collection';

import 'package:chessever2/e2e/e2e_config.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Console output in store builds.
///
/// The app has well over a thousand `debugPrint` and `print` call sites,
/// several of them on the per-move and per-engine-line paths. In a release
/// build each call used to become a Sentry breadcrumb that was serialised and
/// pushed to the native SDK on the UI thread, and `print` also wrote to the
/// device log. Nobody reads either while a game is on screen.
///
/// In a release build this keeps the last [capacity] lines in memory instead
/// (a list append) and hands them to Sentry only when a Dart error is actually
/// reported, so error reports keep their console trail and the hot paths stop
/// paying for it. Debug and profile builds are untouched.
///
/// To see console output from a release build again (engine debugging from the
/// IDE, for example), build with `--dart-define=CHESSEVER_RELEASE_LOGS=true`.
abstract final class ReleaseConsole {
  static const bool _logsRequested = bool.fromEnvironment(
    'CHESSEVER_RELEASE_LOGS',
  );

  /// True when console output is kept in memory instead of printed.
  static const bool quiet =
      kReleaseMode && !_logsRequested && !E2eConfig.isEnabled;

  /// Matches `maxBreadcrumbs` in the Sentry options.
  static const int capacity = 50;

  static final ListQueue<({DateTime time, String message})> _lines =
      ListQueue<({DateTime time, String message})>(capacity);

  /// Routes `debugPrint` into the buffer. Call before anything logs.
  static void install() {
    if (!quiet) return;
    debugPrint = _debugPrint;
  }

  /// Zone hook that routes `print` into the buffer; null when not [quiet].
  static ZoneSpecification? get zoneSpecification {
    if (!quiet) return null;
    return ZoneSpecification(print: (self, parent, zone, line) => record(line));
  }

  static void _debugPrint(String? message, {int? wrapWidth}) {
    if (message != null) record(message);
  }

  @visibleForTesting
  static void record(String message) {
    if (_lines.length >= capacity) _lines.removeFirst();
    _lines.addLast((time: DateTime.now(), message: message));
  }

  @visibleForTesting
  static void clear() => _lines.clear();

  /// Adds the buffered lines to [event] as console breadcrumbs, in time order
  /// with the breadcrumbs it already carries.
  static void attachTo(SentryEvent event) {
    if (_lines.isEmpty) return;
    event.breadcrumbs = <Breadcrumb>[
      ...?event.breadcrumbs,
      for (final line in _lines)
        Breadcrumb.console(
          message: line.message,
          level: SentryLevel.debug,
          timestamp: line.time.toUtc(),
        ),
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }
}
