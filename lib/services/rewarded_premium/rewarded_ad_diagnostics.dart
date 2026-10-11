import 'dart:async';

import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:clarity_flutter/clarity_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps SDK errors intact while identifying the stage that failed.
class RewardedAdFailure implements Exception {
  RewardedAdFailure(this.stage, this.cause);
  final String stage;
  final Object cause;
  @override
  String toString() => 'Rewarded ad failed at $stage: $cause';
}

typedef RewardedDiagnosticSink =
    void Function(Map<String, dynamic> properties, bool failure);

class RewardedAdDiagnostics {
  RewardedAdDiagnostics({required this.userId, this.adUnit, this.sink})
    : flowId = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  static int _sequence = 0;
  final String userId;
  final String flowId;
  String? adUnit;
  final RewardedDiagnosticSink? sink;
  String? attemptId;

  Future<T> step<T>(
    String stage,
    Future<T> Function() operation, {
    Duration? timeout,
  }) async {
    final elapsed = Stopwatch()..start();
    event(stage, 'started');
    try {
      final future = operation();
      final result = await (timeout == null ? future : future.timeout(timeout));
      event(
        stage,
        'succeeded',
        properties: {'duration_ms': elapsed.elapsedMilliseconds},
      );
      return result;
    } catch (error) {
      if (error is RewardedAdFailure) rethrow;
      event(
        stage,
        'failed',
        properties: {
          'duration_ms': elapsed.elapsedMilliseconds,
          ...errorProperties(error),
        },
      );
      throw RewardedAdFailure(stage, error);
    }
  }

  static Map<String, dynamic> errorProperties(Object error) => {
    'error_type': error.runtimeType.toString(),
    'error_message': error is AdError
        ? error.message
        : error is FormError
        ? error.message
        : error is FunctionException
        ? error.reasonPhrase ?? 'Reward service request failed'
        : error.toString(),
    if (error is TimeoutException) 'timed_out': true,
    if (error is AdError) ...{
      'error_code': error.code,
      'error_domain': error.domain,
    },
    if (error is FormError) 'error_code': error.errorCode,
    if (error is FunctionException) 'http_status': error.status,
    if (error is FunctionException &&
        error.details is Map &&
        (error.details as Map)['error'] is String)
      'backend_error': (error.details as Map)['error'],
    if (error is LoadAdError && error.responseInfo != null) ...{
      'response_id': error.responseInfo!.responseId,
      'response_info': error.responseInfo.toString(),
    },
  };

  void event(String stage, String status, {Map<String, dynamic>? properties}) {
    final data = <String, dynamic>{
      'stage': stage,
      'status': status,
      'flow_id': flowId,
      'user_id': userId,
      if (adUnit != null) 'ad_unit': adUnit,
      if (attemptId != null) 'attempt_id': attemptId,
      ...?properties,
    };
    final failure = status == 'failed';
    // Observability must never prevent loading, showing, or granting a reward.
    try {
      if (sink != null) {
        sink!(data, failure);
        return;
      }
      try {
        final recording = Clarity.getCurrentSessionUrl();
        if (recording != null) data['clarity_recording_url'] = recording;
        Clarity.sendCustomEvent('rewarded_${stage}_$status');
      } catch (_) {}
      unawaited(_trackAnalytics(data));
      Sentry.addBreadcrumb(
        Breadcrumb(
          category: 'rewarded_ad',
          message: '$stage: $status',
          data: data,
        ),
      );
      if (failure) {
        // A stable message preserves network failures that the global exception
        // filter intentionally drops. SDK details live in this event's context.
        unawaited(_captureFailure(stage, data));
      }
    } catch (_) {}
  }

  Future<void> _trackAnalytics(Map<String, dynamic> data) async {
    try {
      // Detailed correlation lives in Sentry. Amplitude only needs outcomes
      // and codes for aggregate failure rates, with no advertising forwarding.
      await AnalyticsService.instance.trackEvent(
        'Rewarded Ad',
        properties: {
          for (final key in [
            'stage',
            'status',
            'duration_ms',
            'error_type',
            'error_code',
            'error_domain',
            'http_status',
            'timed_out',
            'reward_status',
            'retry_confirmation',
          ])
            if (data.containsKey(key)) key: data[key],
        },
        forwardToAppsFlyer: false,
      );
    } catch (_) {}
  }

  Future<void> _captureFailure(String stage, Map<String, dynamic> data) async {
    try {
      await Sentry.captureMessage(
        'Rewarded ad failed: $stage',
        level: SentryLevel.warning,
        withScope: (scope) {
          scope.setUser(SentryUser(id: userId));
          scope.setTag('rewarded_stage', stage);
          scope.setContexts('rewarded_ad', data);
          scope.fingerprint = [
            'rewarded_ad',
            stage,
            '${data['error_domain'] ?? data['error_type']}',
            '${data['error_code'] ?? data['http_status'] ?? ''}',
          ];
        },
      ).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }
}
