import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/push_notifications_service.dart';
import 'auth_state_provider.dart';

final pushTokenSyncProvider = Provider<PushTokenSyncController>((ref) {
  final controller = PushTokenSyncController(ref);
  controller.start();
  ref.onDispose(controller.dispose);
  return controller;
});

class PushTokenSyncController {
  PushTokenSyncController(this.ref);

  final Ref ref;
  bool _started = false;
  bool _disposed = false;
  String? _userId;
  String? _lastSyncedSignature;

  void start() {
    if (_started) return;
    _started = true;

    ref.listen(currentUserProvider, (previous, next) {
      _userId = next?.id;
      if (_userId == null) return;
      unawaited(_syncCurrentSubscription());
    }, fireImmediately: true);

    PushNotificationsService.instance.addPushSubscriptionObserver(
      _handlePushSubscriptionChanged,
    );
  }

  void dispose() {
    _disposed = true;
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
      if (id == null || id.isEmpty) return;

      final String? token = subscription.token as String?;
      final bool? optedIn = subscription.optedIn as bool?;

      await _upsertSubscription(
        userId: userId,
        subscriptionId: id,
        token: token,
        optedIn: optedIn ?? true,
      );
    } catch (_) {
      // No-op if OneSignal isn't ready yet.
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
      optedIn: current.optedIn ?? true,
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

  Future<void> _upsertSubscription({
    required String userId,
    required String subscriptionId,
    String? token,
    required bool optedIn,
  }) async {
    if (_disposed) return;

    final signature = '$userId|$subscriptionId|$token|$optedIn';
    if (_lastSyncedSignature == signature) return;
    _lastSyncedSignature = signature;

    try {
      await Supabase.instance.client.from('user_push_tokens').upsert({
        'user_id': userId,
        'provider': 'onesignal',
        'subscription_id': subscriptionId,
        'push_token': token,
        'platform': _platformLabel(),
        'opted_in': optedIn,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'provider,subscription_id');
    } catch (_) {
      // Don't block app flow on token updates.
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
