import '../services/direct_push_service.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/push_notifications_service.dart';
import 'auth_state_provider.dart';
import 'push_token_sync_retry_state.dart';

final pushTokenSyncProvider = Provider<PushTokenSyncController>((ref) {
  final controller = PushTokenSyncController(ref);
  controller.start();
  ref.onDispose(controller.dispose);
  return controller;
});

class PushTokenSyncController with WidgetsBindingObserver {
  PushTokenSyncController(this.ref);

  final Ref ref;
  bool _started = false;
  bool _disposed = false;
  String? _userId;
  final PushTokenSyncRetryState _retryState = PushTokenSyncRetryState(maxAttempts: 8);
  final Set<String> _inFlightSignatures = <String>{};
  Timer? _retryTimer;
  Timer? _readinessTimer;
  int _readinessAttempts = 0;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);

    ref.listen(currentUserProvider, (previous, next) {
      final previousUserId = previous?.id;
      if (previousUserId != null && next == null) {
        unawaited(_markCurrentSubscriptionDeprecated(previousUserId));
      }

      _userId = next?.id;
      _readinessAttempts = 0;
      _readinessTimer?.cancel();
      if (_userId == null) return;
      unawaited(_syncCurrentSubscription());
    }, fireImmediately: true);

    PushNotificationsService.instance.addPushSubscriptionObserver(
      _handlePushSubscriptionChanged,
    );
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _readinessTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _disposed) return;
    _readinessAttempts = 0;
    _retryState.reset();
    unawaited(_syncCurrentSubscription());
  }

  void _retrySubscriptionReadiness() {
    if (_disposed || _userId == null || _readinessAttempts >= 10) return;
    _readinessAttempts++;
    _readinessTimer?.cancel();
    _readinessTimer = Timer(const Duration(seconds: 3), () {
      unawaited(_syncCurrentSubscription());
    });
  }

  void _handlePushSubscriptionChanged(OSPushSubscriptionChangedState state) {
    if (_disposed) return;
    unawaited(
      _syncSubscription(current: state.current, previous: state.previous),
    );
  }

  Future<void> _syncCurrentSubscription() async {
    if (_disposed) return;
    final userId = _userId;
    if (userId == null) return;

    try {
      final dynamic subscription = OneSignal.User.pushSubscription;
      final String? id = subscription.id as String?;
      if (id == null || id.isEmpty) {
        _retrySubscriptionReadiness();
        return;
      }
      _readinessTimer?.cancel();
      _readinessAttempts = 0;

      final String? token = subscription.token as String?;
      final bool? optedIn = subscription.optedIn as bool?;

      await _upsertSubscription(
        userId: userId,
        subscriptionId: id,
        token: token,
        optedIn: optedIn ?? true,
      );
    } catch (_) {
      // The SDK may finish initializing without emitting a subscription change.
      _retrySubscriptionReadiness();
    }
  }

  Future<void> _syncSubscription({
    required OSPushSubscriptionState current,
    OSPushSubscriptionState? previous,
  }) async {
    if (_disposed) return;
    final userId = _userId;
    if (userId == null) return;

    final currentId = current.id;
    if (currentId == null || currentId.isEmpty) return;

    if (previous?.id != null && previous!.id != currentId) {
      await _markDeprecated(userId, previous.id!);
    }

    await _upsertSubscription(
      userId: userId,
      subscriptionId: currentId,
      token: current.token,
      optedIn: current.optedIn,
    );
  }

  Future<void> _markDeprecated(String userId, String subscriptionId) async {
    try {
      await Supabase.instance.client
          .from('user_push_tokens')
          .update({
            'opted_in': false,
            'last_seen_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('provider', 'onesignal')
          .eq('user_id', userId)
          .eq('subscription_id', subscriptionId);
    } catch (_) {
      // Don't block app flow on token updates.
    }
  }

  Future<void> _markCurrentSubscriptionDeprecated(String userId) async {
    try {
      final dynamic subscription = OneSignal.User.pushSubscription;
      final String? id = subscription.id as String?;
      if (id == null || id.isEmpty) return;
      await _markDeprecated(userId, id);
    } catch (_) {
      // Don't block logout on OneSignal/Supabase state races.
    }
  }

  Future<void> _upsertSubscription({
    required String userId,
    required String subscriptionId,
    String? token,
    required bool optedIn,
  }) async {
    if (_disposed) return;

    final signature = '$userId|$subscriptionId|$token|$optedIn';
    if (!_retryState.shouldSync(signature) ||
        !_inFlightSignatures.add(signature)) {
      return;
    }

    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser?.id != userId) return;
      try {
        await client.from('user_push_tokens').upsert({
          'user_id': userId,
          'provider': 'onesignal',
          'subscription_id': subscriptionId,
          'push_token': token,
          'platform': _platformLabel(),
          'opted_in': optedIn,
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'provider,subscription_id');
      } on PostgrestException catch (error) {
        if (error.code != '42501' || token == null || token.isEmpty) rethrow;
        // Only the server may move a subscription between accounts. It verifies
        // both OneSignal's current user identity and possession of this token.
        await client.functions.invoke('push-token-sync', body: {
          'subscriptionId': subscriptionId,
          'token': token,
          'platform': _platformLabel(),
          'optedIn': optedIn,
        });
      }
      if (_disposed || _userId != userId || client.auth.currentUser?.id != userId) return;
      await DirectPushService.instance.mirrorReady(subscriptionId, optedIn);
      _retryState.recordSuccess(signature);
      _retryTimer?.cancel();
      _retryTimer = null;
    } catch (error) {
      final delay = _retryState.recordFailure(signature);
      if (!_disposed && _userId == userId && delay != null) {
        _retryTimer?.cancel();
        _retryTimer = Timer(delay, () {
          if (!_disposed && _userId == userId) {
            unawaited(_syncCurrentSubscription());
          }
        });
      }
      if (error is PostgrestException) {
        // Exclude details/hint: database errors can include device tokens.
        debugPrint('[PushTokenSync] Database error code=${error.code}: ${error.message}');
      }
      debugPrint(
        '[PushTokenSync] Subscription sync failed '
        '(${error.runtimeType}); ${delay == null ? 'retry limit reached' : 'retry scheduled'}',
      );
    } finally {
      _inFlightSignatures.remove(signature);
    }
  }

  String _platformLabel() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}
