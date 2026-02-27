import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/services/live_updates_service.dart';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushNotificationsService {
  PushNotificationsService._();

  static final PushNotificationsService instance = PushNotificationsService._();

  static const String _notificationsEnabledKey = 'notifications_enabled';

  bool _initialized = false;
  String? _pendingUserId;
  final List<void Function(OSPushSubscriptionChangedState)>
  _pendingPushObservers = [];

  Future<void> initialize({required String appId}) async {
    if (_initialized) return;
    if (appId.isEmpty) {
      debugPrint(
        '[PushNotifications] Missing OneSignal app ID; skipping init.',
      );
      return;
    }

    if (kDebugMode) {
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    }

    OneSignal.initialize(appId);
    await LiveUpdatesService.instance.setup();

    // Apply stored opt-in preference so we don't accidentally opt-in users.
    final enabled = await _loadLocalEnabled();
    if (!enabled) {
      OneSignal.User.pushSubscription.optOut();
    }

    if (_pendingPushObservers.isNotEmpty) {
      for (final observer in _pendingPushObservers) {
        OneSignal.User.pushSubscription.addObserver(observer);
      }
      _pendingPushObservers.clear();
    }

    if (_pendingUserId != null && _pendingUserId!.isNotEmpty) {
      OneSignal.login(_pendingUserId!);
      _pendingUserId = null;
    }

    _initialized = true;
    debugPrint('[PushNotifications] OneSignal initialized.');
  }

  void addPushSubscriptionObserver(
    void Function(OSPushSubscriptionChangedState) observer,
  ) {
    if (_initialized) {
      OneSignal.User.pushSubscription.addObserver(observer);
      return;
    }
    _pendingPushObservers.add(observer);
  }

  /// Whether OS-level notification permission is currently granted.
  bool get hasPermission => _initialized && OneSignal.Notifications.permission;

  Future<bool> requestPermissionWithDialog() async {
    final granted = await OneSignal.Notifications.requestPermission(true);
    await _persistLocalEnabled(granted);
    await _syncPreferenceToSupabase(granted);
    if (granted) {
      OneSignal.User.pushSubscription.optIn();
    } else {
      OneSignal.User.pushSubscription.optOut();
    }
    return granted;
  }

  /// Request permission only if not already granted.
  /// Safe to call repeatedly — no-ops if permission is already granted,
  /// and on iOS the OS dialog only shows once regardless.
  Future<void> requestPermissionIfNotGranted() async {
    if (!_initialized) return;
    if (OneSignal.Notifications.permission) return;
    await requestPermissionWithDialog();
  }

  Future<void> setPushEnabled(bool enabled) async {
    await _persistLocalEnabled(enabled);
    await _syncPreferenceToSupabase(enabled);
    if (!_initialized) return;
    if (enabled) {
      OneSignal.User.pushSubscription.optIn();
    } else {
      OneSignal.User.pushSubscription.optOut();
    }
  }

  Future<void> loginUser(String userId) async {
    if (userId.isEmpty) return;
    if (!_initialized) {
      _pendingUserId = userId;
      return;
    }

    OneSignal.login(userId);
    final enabled = await _loadLocalEnabled();
    await _syncPreferenceToSupabase(enabled);
  }

  Future<void> logoutUser() async {
    if (!_initialized) return;
    OneSignal.logout();
  }

  Future<bool> _loadLocalEnabled() async {
    try {
      final db = AppDatabase.instance;
      return await db.getBool(_notificationsEnabledKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persistLocalEnabled(bool enabled) async {
    try {
      final db = AppDatabase.instance;
      await db.setBool(_notificationsEnabledKey, enabled);
    } catch (_) {
      // Local storage failure isn't critical.
    }
  }

  Future<void> _syncPreferenceToSupabase(bool enabled) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      await Supabase.instance.client
          .from('user_notification_preferences')
          .upsert({
            'user_id': userId,
            'push_enabled': enabled,
          }, onConflict: 'user_id');
    } catch (_) {
      // Supabase sync failures shouldn't block local UX.
    }
  }
}
