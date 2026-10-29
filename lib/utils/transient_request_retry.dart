import 'dart:async';
import 'dart:io';

import 'package:chessever2/repository/api_utils/api_exceptions.dart';

const List<Duration> _defaultTransientReadRetryDelays = [
  Duration(milliseconds: 250),
  Duration(milliseconds: 750),
];

bool isTransientReadRequestError(Object error) {
  if (error is TimeoutException) return true;

  final raw = error.toString().toLowerCase();
  if (raw.contains('request timeout') ||
      raw.contains('timed out') ||
      raw.contains('timeout')) {
    return true;
  }

  if (error is SocketException) {
    return raw.contains('connection reset') ||
        raw.contains('connection closed') ||
        raw.contains('connection aborted') ||
        raw.contains('connection error');
  }

  if (error is NetworkException) {
    return raw.contains('connection reset') ||
        raw.contains('connection closed') ||
        raw.contains('connection aborted') ||
        raw.contains('connection error');
  }

  return false;
}

/// Runs [request], retrying transient failures after each of [delays].
///
/// [canRetry] is checked before every retry; returning false rethrows the
/// last error instead, so a caller whose result is no longer wanted does not
/// send another request.
Future<T> retryTransientRead<T>(
  Future<T> Function() request, {
  List<Duration> delays = _defaultTransientReadRetryDelays,
  bool Function()? canRetry,
}) async {
  for (var attempt = 0; ; attempt += 1) {
    try {
      return await request();
    } catch (e) {
      if (attempt >= delays.length ||
          !isTransientReadRequestError(e) ||
          (canRetry != null && !canRetry())) {
        rethrow;
      }
      await Future<void>.delayed(delays[attempt]);
      if (canRetry != null && !canRetry()) rethrow;
    }
  }
}
