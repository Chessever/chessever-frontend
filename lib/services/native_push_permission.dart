import 'package:flutter/services.dart';

const _channel = MethodChannel('com.chessever/push_permission');

Future<bool> _read(String method) async {
  final result = await _channel.invokeMethod<bool>(method);
  if (result == null) {
    throw StateError('Native notification permission is unavailable');
  }
  return result;
}

/// Read native OS state without treating loading/failure as a denial.
Future<bool> readNativePushPermission() => _read('permission');
Future<bool> canRequestNativePushPermission() => _read('canRequest');
Future<bool> requestNativePushPermission() => _read('requestPermission');

/// Replays an early native APNs token to initialized Firebase and retries Apple
/// registration. Returns the latest native error, without exposing device tokens.
Future<String?> refreshNativeAPNsRegistration() =>
    _channel.invokeMethod<String>('refreshAPNsRegistration');
