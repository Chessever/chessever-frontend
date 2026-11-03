import 'dart:async';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/services/native_push_permission.dart';
import 'package:chessever2/services/direct_push_service.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// OS permission and account preference management, independent of a push vendor.
class PushNotificationsService with WidgetsBindingObserver {
  PushNotificationsService._();
  static final instance = PushNotificationsService._();
  static const _notificationsEnabledKey = 'notifications_enabled';
  static const _notificationsPromptedKey = 'notifications_prompted_once';
  bool _initialized = false;
  bool _permissionRequestInFlight = false;
  Future<void>? _initializeFuture;
  final _permissionObservers = <void Function(bool)>[];

  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initializeFuture ??= _initialize().whenComplete(() {
      if (!_initialized) _initializeFuture = null;
    });
  }

  Future<void> _initialize() async {
    final granted = await readNativePushPermission();
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    await setPushEnabled(granted);
  }

  Future<void> _waitForInitializeIfPending() async {
    final pending = _initializeFuture;
    if (!_initialized && pending != null) {
      try {
        await pending;
      } catch (_) {
        /* Keep unavailable distinct from denied. */
      }
    }
  }

  Future<bool> isPermissionGranted() async {
    await _waitForInitializeIfPending();
    if (!_initialized) {
      throw StateError('Push notifications are not initialized');
    }
    return readNativePushPermission();
  }

  Future<bool> canRequestPermission() async {
    await _waitForInitializeIfPending();
    if (!_initialized) return false;
    return canRequestNativePushPermission();
  }

  void addNativePermissionObserver(void Function(bool) observer) =>
      _permissionObservers.add(observer);
  void removeNativePermissionObserver(void Function(bool) observer) =>
      _permissionObservers.remove(observer);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _initialized) {
      unawaited(_refreshPermission());
    }
  }

  Future<void> _refreshPermission() async {
    try {
      final granted = await readNativePushPermission();
      await setPushEnabled(granted);
      for (final observer in List.of(_permissionObservers)) {
        observer(granted);
      }
    } catch (e) {
      debugPrint('[PushNotifications] Permission refresh deferred: $e');
    }
  }

  Future<bool> requestPermissionWithDialog() async {
    await _waitForInitializeIfPending();
    if (!_initialized) return false;
    if (_permissionRequestInFlight) return readNativePushPermission();
    _permissionRequestInFlight = true;
    try {
      final granted = await requestNativePushPermission();
      await _persistPromptedOnce();
      await setPushEnabled(granted);
      for (final observer in List.of(_permissionObservers)) {
        observer(granted);
      }
      return granted;
    } finally {
      _permissionRequestInFlight = false;
    }
  }

  Future<void> requestPermissionIfNotGranted() async {
    await _waitForInitializeIfPending();
    if (!_initialized) return;
    if (await readNativePushPermission()) {
      await _persistPromptedOnce();
      await setPushEnabled(true);
    } else if (await canRequestNativePushPermission()) {
      await requestPermissionWithDialog();
    } else {
      await _persistPromptedOnce();
      await setPushEnabled(false);
    }
  }

  Future<bool> shouldOfferPermissionPrompt() async {
    await _waitForInitializeIfPending();
    if (!_initialized) return false;
    try {
      if (await AppDatabase.instance.getBool(_notificationsPromptedKey) ==
          true) {
        return false;
      }
      if (await readNativePushPermission()) return false;
      return await canRequestNativePushPermission();
    } catch (_) {
      return false;
    }
  }

  Future<void> setPushEnabled(bool enabled) async {
    await _persistLocalEnabled(enabled);
    await _syncPreferenceToSupabase(enabled);
    unawaited(DirectPushService.instance.sync());
  }

  Future<void> loginUser(String userId) async {
    if (userId.isEmpty) return;
    await _waitForInitializeIfPending();
    if (!_initialized) return;
    try {
      await setPushEnabled(await readNativePushPermission());
    } catch (e) {
      debugPrint('[PushNotifications] Login permission sync deferred: $e');
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
              'daily_digest': false,
              'call_to_action_alerts': false,
              'book_update_alerts': true,
              'fp_classical': true,
              'fp_rapid': true,
              // Blitz notifications OFF by default — users opt in manually.
              'fp_blitz': false,
              'se_classical': true,
              'se_rapid': true,
              'se_blitz': false,
              // Legacy shared filters for older dispatchers/builds. Blitz is
              // off by default, matching the split category defaults above.
              'notify_classical': true,
              'notify_rapid': true,
              'notify_blitz': false,
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
