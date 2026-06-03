import 'package:flutter/foundation.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker/talker.dart';

/// Global Talker instance — the app's console logger.
///
/// Errors/exceptions print with their type, message and the **full,
/// untruncated stacktrace** so you can copy-paste straight into a coding
/// agent and see exactly where the failure came from.
///
/// Use it directly anywhere:
/// ```dart
/// talker.info('Fetching games...');
/// try { ... } catch (e, st) { talker.handle(e, st, 'Fetch failed'); }
/// ```
/// or via [talkerProvider] inside Riverpod scopes.
final talker = Talker(
  settings: TalkerSettings(
    // Off in release so prod gets zero console-formatting overhead.
    enabled: !kReleaseMode,
    useConsoleLogs: true,
    useHistory: true,
    maxHistoryItems: 1000,
    timeFormat: TimeFormat.timeAndSeconds,
  ),
  // The console palette lives here — it's keyed by [LogLevel] and is what
  // actually colors terminal output (TalkerSettings.colors only drives the
  // in-app TalkerScreen, which this app doesn't use).
  //
  // ── Color classification (the knob to tune) ─────────────────────────────
  // Each level gets a distinct ANSI color so logs are scannable at a glance.
  // Note: exceptions and errors both map to LogLevel.error, so they share a
  // color — they're still told apart by the `[exception]` / `[error]` title.
  logger: TalkerLogger(
    settings: TalkerLoggerSettings(
      enableColors: true,
      colors: {
        LogLevel.critical: AnsiPen()..xterm(199), // magenta-pink, loudest
        LogLevel.error: AnsiPen()..red(),
        LogLevel.warning: AnsiPen()..xterm(214), // amber
        LogLevel.info: AnsiPen()..xterm(45), // cyan
        LogLevel.debug: AnsiPen()..xterm(245), // mid gray
        LogLevel.verbose: AnsiPen()..xterm(240), // dim gray
      },
    ),
  ),
);

final talkerProvider = Provider<Talker>((ref) => talker);

/// Backward-compatible controller kept so existing `loggerProvider` call sites
/// (`logError` / `logInfo`) keep working — now backed by [talker].
final loggerProvider = Provider(_LoggerController.new);

class _LoggerController {
  _LoggerController(this._ref);
  // ignore: unused_field
  final Ref _ref;

  /// Logs an error verbose, with full stacktrace.
  ///
  /// Pass the real caught error + its stacktrace for best classification:
  /// `catch (e, st) { logError(e, st); }`. A bare message falls back to
  /// [StackTrace.current], which points at this call (less useful than the
  /// throw site, but still printed in full).
  void logError(Object error, [StackTrace? stackTrace]) {
    talker.handle(error, stackTrace ?? StackTrace.current);
  }

  void logInfo(Object info) {
    talker.info(info);
  }
}
