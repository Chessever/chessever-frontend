import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

final errorLoggerProvider = AutoDisposeProvider<_ErrorLoggerService>((ref) {
  return _ErrorLoggerService();
});

class _ErrorLoggerService {
  /// Log error to Sentry - returns immediately, capture happens async
  /// Never throws, never blocks the caller significantly
  /// Has a 2s timeout to prevent hanging
  Future<void> logError(dynamic error, StackTrace stackTrace) async {
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
