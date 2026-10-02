import 'package:dio/dio.dart';
import 'package:logarte/logarte.dart';

/// Capability-bearing requests must never enter the developer network log.
class RewardedSafeLogInterceptor extends LogarteDioInterceptor {
  RewardedSafeLogInterceptor(super.logarte);

  bool _hasCapability(RequestOptions options) => options.headers.keys.any(
    (key) => key.toLowerCase() == 'x-rewarded-session',
  );

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_hasCapability(options)) {
      handler.next(options);
    } else {
      super.onRequest(options, handler);
    }
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (_hasCapability(response.requestOptions)) {
      handler.next(response);
    } else {
      super.onResponse(response, handler);
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (_hasCapability(err.requestOptions)) {
      handler.next(err);
    } else {
      super.onError(err, handler);
    }
  }
}
