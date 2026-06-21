import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/services/live_updates_service.dart';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushNotificationsService {
  PushNotificationsService._();

  static final PushNotificationsService instance = PushNotificationsService._();

  static const String _notificationsEnabledKey = 'notifications_enabled';
  static const String _notificationsPromptedKey = 'notifications_prompted_once';

  bool _initialized = false;
  Future<void>? _initializeFuture;
  bool _permissionRequestInFlight = false;
  String? _pendingUserId;
  final List<void Function(OSPushSubscriptionChangedState)>
  _pendingPushObservers = [];
  final List<void Function(bool)> _pendingPermissionObservers = [];

  Future<void> initialize({required String appId}) {
    if (_initialized) return Future.value();
    final existingInitializeFuture = _initializeFuture;
    if (existingInitializeFuture != null) {
      return existingInitializeFuture;
    }

    final initializeFuture = _initialize(appId).whenComplete(() {
      if (!_initialized) {
        _initializeFuture = null;
      }
    });
    _initializeFuture = initializeFuture;
    return initializeFuture;
  }

  Future<void> _initialize(String appId) async {
    final normalizedAppId = appId.trim();
    if (normalizedAppId.isEmpty) {
      debugPrint(
        '[PushNotifications] Missing OneSignal app ID; skipping init.',
      );
      return;
    }

    if (kDebugMode) {
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    }

    // OneSignal.LiveActivities.setupDefault() MUST run AFTER OneSignal.initialize().
    // Called before init, the LiveActivities module has no appId/subscription, so it
    // never forwards the Live Activity push token to OneSignal → server-side updates
    // reach 0 recipients and the iOS card never updates. Order is load-bearing.
    OneSignal.initialize(normalizedAppId);
    LiveUpdatesService.instance.markOneSignalReady();
    await LiveUpdatesService.instance.setup();

    // The OS notification permission is the single source of truth for whether
    // push is "on" — it is not a separate app preference. Align the OneSignal
    // subscription and the server flag with the real OS grant.
    //
    // We read it via _isPermissionGranted(), NOT the raw `permission` cache: that
    // cache defaults to false and is hydrated by an un-awaited native call inside
    // OneSignal.initialize(), so reading it here returns a stale false — the Android
    // upgrade bug that silently opted granted users out.
    final granted = await _isPermissionGranted();
    if (granted) {
      await _persistLocalEnabled(true);
      await _syncPreferenceToSupabase(true);
      OneSignal.User.pushSubscription.optIn();
    } else {
      await _persistLocalEnabled(false);
      await _syncPreferenceToSupabase(false);
      OneSignal.User.pushSubscription.optOut();
    }

    if (_pendingPushObservers.isNotEmpty) {
      for (final observer in _pendingPushObservers) {
        OneSignal.User.pushSubscription.addObserver(observer);
      }
      _pendingPushObservers.clear();
    }

    if (_pendingPermissionObservers.isNotEmpty) {
      for (final observer in _pendingPermissionObservers) {
        OneSignal.Notifications.addPermissionObserver(observer);
      }
      _pendingPermissionObservers.clear();
    }

    // Keep RC's customer profile in sync with the device's OneSignal subscription
    // ID. RC uses this to route subscription-state push notifications via the
    // OneSignal integration (e.g. "your trial converted"). The subscription ID
    // can be null at boot before APNs/FCM registers, and can change later, so
    // we forward both the current value and any subsequent changes.
    _forwardSubscriptionIdToRevenueCat(OneSignal.User.pushSubscription.id);
    OneSignal.User.pushSubscription.addObserver((state) {
      _forwardSubscriptionIdToRevenueCat(state.current.id);
    });

    if (_pendingUserId != null && _pendingUserId!.isNotEmpty) {
      OneSignal.login(_pendingUserId!);
      _pendingUserId = null;
    }

    _initialized = true;
    debugPrint('[PushNotifications] OneSignal initialized.');
  }

  Future<void> _waitForInitializeIfPending() async {
    final initializeFuture = _initializeFuture;
    if (_initialized || initializeFuture == null) return;

    try {
      await initializeFuture;
    } catch (_) {
      // Initialization failures should not make permission checks crash startup.
    }
  }

  /// Read the current OneSignal subscription ID — used by RevenueCatService.logIn
  /// to re-tag the RC customer profile when a new user signs in on the same
  /// device. The subscription ID itself is device-scoped, so it doesn't change
  /// across user switches; what changes is which RC customer it's stamped on.
  String? get currentOneSignalSubscriptionId =>
      _initialized ? OneSignal.User.pushSubscription.id : null;

  void _forwardSubscriptionIdToRevenueCat(String? id) {
    if (id == null || id.isEmpty) return;
    Purchases.setOnesignalID(id).catchError((Object e) {
      debugPrint('[PushNotifications] Purchases.setOnesignalID failed: $e');
    });
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

  /// Robustly resolve whether the OS currently allows notifications.
  ///
  /// `OneSignal.Notifications.permission` is a Dart-side cache that starts as
  /// `false` and is hydrated from native by `lifecycleInit()` — a call that
  /// `OneSignal.initialize()` fires but does NOT await. Reading the cache right
  /// after init can therefore return a stale `false` even when notifications are
  /// granted. This is exactly what bit Android upgrades: an existing grant is
  /// carried forward by the OS, but the cache hasn't caught up yet.
  ///
  /// `canRequest()` is a fresh native round-trip on the same MethodChannel as the
  /// pending `OneSignal#permission` hydration call. Method channels are FIFO, so
  /// once `canRequest()` resolves the cache has been populated — we re-read it.
  Future<bool> _isPermissionGranted() async {
    if (OneSignal.Notifications.permission) return true;
    // Force/await a native hop; the permission cache hydration lands before this
    // resolves (same channel, enqueued earlier during initialize()).
    await OneSignal.Notifications.canRequest();
    return OneSignal.Notifications.permission;
  }

  /// Live OS notification-permission state, read reliably (see [_isPermissionGranted]).
  Future<bool> isPermissionGranted() async {
    await _waitForInitializeIfPending();
    if (!_initialized) return false;
    return _isPermissionGranted();
  }

  /// Whether the OS will still show a permission prompt (true only if never asked).
  /// false ⇒ already granted OR permanently denied — in both cases the only way
  /// to change it is the system settings page.
  Future<bool> canRequestPermission() async {
    await _waitForInitializeIfPending();
    if (!_initialized) return false;
    return OneSignal.Notifications.canRequest();
  }

  /// Subscribe to OS notification-permission changes. Fires when the user flips
  /// the system notification switch outside the app (Settings), so the toggle can
  /// reflect the live native state instead of a stored guess.
  void addNativePermissionObserver(void Function(bool) observer) {
    if (_initialized) {
      OneSignal.Notifications.addPermissionObserver(observer);
      return;
    }
    _pendingPermissionObservers.add(observer);
  }

  void removeNativePermissionObserver(void Function(bool) observer) {
    if (_initialized) {
      OneSignal.Notifications.removePermissionObserver(observer);
    }
    _pendingPermissionObservers.remove(observer);
  }

  Future<bool> requestPermissionWithDialog() async {
    await _waitForInitializeIfPending();
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
  /// Safe to call repeatedly: it only opens the native prompt when the OS says
  /// it can still be shown, so denied users are not bounced to Settings.
  Future<void> requestPermissionIfNotGranted() async {
    await _waitForInitializeIfPending();
    if (!_initialized) return;

    // Reliable read — hydrates the SDK permission cache via a native hop, so an
    // already-granted device (e.g. Android upgrade carrying the grant forward) is
    // never misread as denied.
    if (await _isPermissionGranted()) {
      await _persistLocalEnabled(true);
      await _persistPromptedOnce();
      await _syncPreferenceToSupabase(true);
      OneSignal.User.pushSubscription.optIn();
      return;
    }

    // Not granted. If the OS will still show a prompt, show it. Otherwise do NOT
    // try to "fix" anything from here — the user changes the permission via the
    // system settings page (surfaced by the notification toggle UI). We only
    // mirror the real OS state so the backend doesn't push to a muted device.
    if (await OneSignal.Notifications.canRequest()) {
      await requestPermissionWithDialog();
    } else {
      await _persistLocalEnabled(false);
      await _persistPromptedOnce();
      await _syncPreferenceToSupabase(false);
      OneSignal.User.pushSubscription.optOut();
    }
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
              // Blitz notifications OFF by default — users opt in manually.
              'fp_blitz': false,
              'se_classical': true,
              'se_rapid': true,
              'se_blitz': false,
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
