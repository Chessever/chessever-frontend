import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:chessever2/services/push_notifications_service.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Live OS notification-permission state for the master "Push Notifications"
/// toggle.
///
/// Notification permission is NOT an app preference — it belongs to the operating
/// system. So this provider mirrors the real OS grant (read reliably through the
/// SDK cache race, see [PushNotificationsService.isPermissionGranted]) and never
/// keeps its own on/off bool. Flipping the toggle routes the user to the native
/// controls: the system prompt the first time, the OS notification-settings page
/// afterwards (only the OS can revoke a granted permission).
final notificationPermissionProvider =
    StateNotifierProvider<NotificationPermissionNotifier, AsyncValue<bool>>(
      (ref) => NotificationPermissionNotifier(),
    );

class NotificationPermissionNotifier extends StateNotifier<AsyncValue<bool>>
    with WidgetsBindingObserver {
  NotificationPermissionNotifier() : super(const AsyncValue.loading()) {
    WidgetsBinding.instance.addObserver(this);
    // Fires when the user flips the system notification switch outside the app.
    _service.addNativePermissionObserver(_onNativePermissionChanged);
    unawaited(refresh());
  }

  final PushNotificationsService _service = PushNotificationsService.instance;

  void _onNativePermissionChanged(bool granted) => _set(granted);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may have changed the OS switch while we were backgrounded (e.g.
    // after we sent them to the settings page). Re-read on resume.
    if (state == AppLifecycleState.resumed) {
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    final granted = await _service.isPermissionGranted();
    _set(granted);
  }

  /// Master toggle tap handler. We never set permission from code — we hand the
  /// user to native controls and then reflect whatever they chose.
  Future<void> handleMasterToggle() async {
    final granted = await _service.isPermissionGranted();
    if (!granted && await _service.canRequestPermission()) {
      // Never prompted before: show the native system permission dialog.
      await _service.requestPermissionWithDialog();
    } else {
      // Already granted (only the OS can revoke) or the prompt is no longer
      // available: open the phone's notification settings for this app.
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    }
    await refresh();
  }

  void _set(bool granted) {
    if (!mounted) return;
    final previous = state.valueOrNull;
    state = AsyncValue.data(granted);
    // Keep the OneSignal subscription + server `push_enabled` flag aligned with
    // the OS truth, so the backend never pushes to a muted device and resumes
    // once the user re-enables. Only write on an actual change to avoid churn.
    if (previous != granted) {
      unawaited(_service.setPushEnabled(granted));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.removeNativePermissionObserver(_onNativePermissionChanged);
    super.dispose();
  }
}
