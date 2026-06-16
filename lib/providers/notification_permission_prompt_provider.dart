import 'dart:async';

import 'package:chessever2/e2e/e2e_config.dart';
import 'package:chessever2/services/push_notifications_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final notificationPermissionPromptProvider =
    Provider<NotificationPermissionPromptController>((ref) {
      final controller = NotificationPermissionPromptController();
      controller.start();
      ref.onDispose(controller.dispose);
      return controller;
    });

class NotificationPermissionPromptController {
  bool _started = false;
  bool _disposed = false;

  void start() {
    if (_started || E2eConfig.suppressInterruptivePrompts) return;
    _started = true;
    unawaited(_requestWhenReady());
  }

  Future<void> _requestWhenReady() async {
    await Future<void>.delayed(Duration.zero);
    if (_disposed) return;
    await PushNotificationsService.instance.requestPermissionIfNotGranted();
  }

  void dispose() {
    _disposed = true;
  }
}
