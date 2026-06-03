import 'package:chessever2/utils/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

final errorLoggerProvider = AutoDisposeProvider<_ErrorLoggerService>((ref) {
  return _ErrorLoggerService();
});

class _ErrorLoggerService {
  /// Log error to Sentry (remote) AND Talker (local console).
  ///
  /// Talker prints it verbose with the full stacktrace so caught errors that
  /// never bubble to the global handlers are still visible/copy-pasteable.
  /// Sentry capture returns immediately, never throws, 2s timeout.
  Future<void> logError(dynamic error, StackTrace stackTrace) async {
    // Local console first — always runs even if Sentry is down/slow.
    talker.handle(error, stackTrace);
    try {
      await Sentry.captureException(
        error,
        stackTrace: stackTrace,
      ).timeout(const Duration(seconds: 2));
    } catch (e) {
      // Silently ignore - monitoring should never break the app
      debugPrint('⚠️ Sentry capture failed: $e');
    }
  }
}
