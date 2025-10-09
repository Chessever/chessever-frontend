import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

final errorLoggerProvider = AutoDisposeProvider<_ErrorLoggerService>((ref) {
  return _ErrorLoggerService();
});

class _ErrorLoggerService {
  Future<void> logError(dynamic error, StackTrace stackTrace) async {
    Sentry.captureException(error, stackTrace: stackTrace);
  }
}
