import 'package:flutter/services.dart';

/// Uses the permission query implemented by OneSignal Flutter 5.6.7 on iOS and
/// Android. Unlike its public Dart getter, this awaits a fresh native response.
/// Keep this channel contract covered when upgrading OneSignal.
Future<bool> readNativePushPermission() async {
  const channel = MethodChannel('OneSignal#notifications');
  final granted = await channel.invokeMethod<bool>('OneSignal#permission');
  if (granted == null) {
    throw StateError('Native notification permission is unavailable');
  }
  return granted;
}
