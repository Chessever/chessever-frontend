import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/services/live_updates_service.dart';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushNotificationsService {
  PushNotificationsService._();

  static final PushNotificationsService instance = PushNotificationsService._();

  static const String _notificationsEnabledKey = 'notifications_enabled';
  static const String _notificationsPromptedKey = 'notifications_prompted_once';

  bool _initialized = false;
  bool _permissionRequestInFlight = false;
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

    // Apply opt-in state based on local preference and current OS permission.
    // This prevents release builds from forcing users into opt-out when iOS
    // permission is already granted but no local preference exists yet.
    final hasPermission = OneSignal.Notifications.permission;
    final storedEnabled = await _loadLocalEnabledNullable();

    if (storedEnabled == null && hasPermission) {
      await _persistLocalEnabled(true);
      await _syncPreferenceToSupabase(true);
      OneSignal.User.pushSubscription.optIn();
    } else if (storedEnabled == true && hasPermission) {
      OneSignal.User.pushSubscription.optIn();
    } else {
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
    if (!_initialized) return false;
    if (_permissionRequestInFlight) {
      return OneSignal.Notifications.permission;
    }

    _permissionRequestInFlight = true;
    try {
      final granted = await OneSignal.Notifications.requestPermission(true);
      await _persistLocalEnabled(granted);
      await _persistPromptedOnce();
      await _syncPreferenceToSupabase(granted);
      if (granted) {
        OneSignal.User.pushSubscription.optIn();
      } else {
        OneSignal.User.pushSubscription.optOut();
      }
      return granted;
    } finally {
      _permissionRequestInFlight = false;
    }
  }

  /// Request permission only if not already granted.
  /// Safe to call repeatedly — no-ops if permission is already granted,
  /// and on iOS the OS dialog only shows once regardless.
  Future<void> requestPermissionIfNotGranted() async {
    if (!_initialized) return;
    if (OneSignal.Notifications.permission) {
      final enabled = await _loadLocalEnabledNullable();
      if (enabled != false) {
        await _persistLocalEnabled(true);
        await _persistPromptedOnce();
        await _syncPreferenceToSupabase(true);
        OneSignal.User.pushSubscription.optIn();
      }
      return;
    }

    final prompted = await _loadPromptedOnce();
    if (prompted) return;

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
    return await _loadLocalEnabledNullable() ?? false;
  }

  Future<bool?> _loadLocalEnabledNullable() async {
    try {
      final db = AppDatabase.instance;
      return await db.getBool(_notificationsEnabledKey);
    } catch (_) {
      return null;
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

  Future<bool> _loadPromptedOnce() async {
    try {
      final db = AppDatabase.instance;
      return await db.getBool(_notificationsPromptedKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persistPromptedOnce() async {
    try {
      final db = AppDatabase.instance;
      await db.setBool(_notificationsPromptedKey, true);
    } catch (_) {
      // Local storage failure isn't critical.
    }
  }

  Future<void> _syncPreferenceToSupabase(bool enabled) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final client = Supabase.instance.client;

      // Ensure a row exists with app-intended defaults (no-op if row exists).
      // This prevents the DB column defaults (which disagree with the app for
      // live_game_updates and daily_digest) from taking effect on a fresh row.
      await client
          .from('user_notification_preferences')
          .upsert(
            {
              'user_id': userId,
              'push_enabled': enabled,
              'favorite_event_alerts': true,
              'favorite_player_alerts': true,
              'heads_up_alerts': false,
              'live_game_updates': false,
              'daily_digest': false,
              'call_to_action_alerts': false,
              'book_update_alerts': true,
              'fp_classical': true,
              'fp_rapid': true,
              'fp_blitz': true,
              'se_classical': true,
              'se_rapid': true,
              'se_blitz': true,
              'heads_up_lead_minutes': 30,
            },
            onConflict: 'user_id',
            ignoreDuplicates: true,
          );

      // Always update push_enabled (covers existing rows without touching
      // other columns the user may have customised).
      await client
          .from('user_notification_preferences')
          .update({'push_enabled': enabled})
          .eq('user_id', userId);
    } catch (_) {
      // Supabase sync failures shouldn't block local UX.
    }
  }
}
