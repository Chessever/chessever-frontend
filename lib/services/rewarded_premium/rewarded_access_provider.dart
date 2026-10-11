import 'package:chessever2/services/rewarded_premium/rewarded_unlock_flow.dart';
import 'dart:async';

import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_ads.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_ad_diagnostics.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_session.dart';
import 'package:chessever2/widgets/paywall/rewarded_premium/rewarded_interstitial_intro.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RewardedAccessState {
  const RewardedAccessState({
    this.remaining = Duration.zero,
    this.busy = false,
    this.pending = false,
    this.expiry = 0,
  });
  final Duration remaining;
  final bool busy;
  final bool pending;
  final int expiry;
  bool get active => remaining > Duration.zero;
}

final rewardedAccessProvider =
    StateNotifierProvider<RewardedAccessNotifier, RewardedAccessState>((ref) {
      final notifier = RewardedAccessNotifier();
      ref.listen<bool>(subscriptionProvider.select((s) => s.isSubscribed), (
        _,
        subscribed,
      ) {
        if (subscribed) notifier.clear();
      });
      return notifier;
    });

final premiumAccessProvider = Provider<bool>(
  (ref) =>
      ref.watch(subscriptionProvider.select((s) => s.isSubscribed)) ||
      (RewardedAdsConfig.available &&
          ref.watch(rewardedAccessProvider.select((s) => s.active))),
);

/// Feature-only projection. Billing and purchase UI keep subscriptionProvider.
final featureAccessStateProvider = Provider<SubscriptionState>((ref) {
  final subscription = ref.watch(subscriptionProvider);
  return subscription.copyWith(isSubscribed: ref.watch(premiumAccessProvider));
});

class RewardedAccessNotifier extends StateNotifier<RewardedAccessState> {
  RewardedAccessNotifier() : super(const RewardedAccessState()) {
    if (!RewardedAdsConfig.available) return;
    final auth = Supabase.instance.client.auth;
    _session.bindUser(auth.currentUser?.id);
    _auth = auth.onAuthStateChange.listen((event) {
      final next = event.session?.user.id;
      if (_userId != next) {
        _userId = next;
        clear();
        _session.bindUser(next);
      }
    });
    _userId = auth.currentUser?.id;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => reconcile());
  }

  final RewardedAds ads = RewardedAds();
  final _session = RewardedSession.instance;
  StreamSubscription<AuthState>? _auth;
  Timer? _timer;
  String? _userId;
  late final _flow = RewardedUnlockFlow(_session);
  int _generation = 0;

  void clear() {
    _generation++;
    _flow.clear();
    _session.reset();
    if (mounted) state = RewardedAccessState(expiry: state.expiry);
  }

  void reconcile() {
    if (!mounted) return;
    final remaining = _session.remaining;
    state = RewardedAccessState(
      remaining: remaining,
      busy: state.busy,
      pending: state.pending,
      expiry:
          state.expiry + (state.active && remaining == Duration.zero ? 1 : 0),
    );
  }

  Future<Map<String, dynamic>> _request(
    String action,
    String token, {
    String? attempt,
    String? adUnit,
  }) async {
    final result = await Supabase.instance.client.functions.invoke(
      'rewarded-premium',
      body: {
        'action': action,
        'session_token': token,
        if (attempt != null) 'attempt_id': attempt,
        if (action == 'prepare') 'ad_unit': adUnit ?? RewardedAdsConfig.unitId,
      },
    );
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Returns false without another ad when a previous reward is still pending.
  Future<bool> unlock(BuildContext context) async {
    if (state.busy || !RewardedAdsConfig.available) return false;
    if (_session.active) return true;
    final generation = _generation;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw StateError('Your guest session is not ready yet');
    final diagnostics = RewardedAdDiagnostics(
      userId: user.id,
      adUnit: _flow.pending ? null : RewardedAdsConfig.unitId,
    )..attemptId = _flow.attemptId;
    diagnostics.event(
      'unlock',
      'started',
      properties: {'retry_confirmation': _flow.pending},
    );
    state = RewardedAccessState(
      expiry: state.expiry,
      busy: true,
      pending: _flow.pending,
    );
    try {
      final unlocked = await _flow.unlock(
        prepareAds: () async {
          if (!context.mounted) throw StateError('Feature was closed');
          await diagnostics.step(
            'prepare_ads',
            () => ads.prepare(context, diagnostics: diagnostics),
          );
        },
        showAd: (attempt) {
          diagnostics.attemptId = attempt;
          return ads.show(
            attemptId: attempt,
            userId: user.id,
            diagnostics: diagnostics,
          );
        },
        request: (action, token, {attempt}) => diagnostics.step(
          'backend_$action',
          () async {
            final result = await _request(action, token, attempt: attempt);
            if (action == 'prepare') {
              diagnostics.attemptId = result['attempt_id'] as String?;
            }
            diagnostics.event(
              'backend_$action',
              'response',
              properties: {
                if (result['status'] != null) 'reward_status': result['status'],
              },
            );
            return result;
          },
          timeout: const Duration(seconds: 30),
        ),
        shouldUseFallback: RewardedAds.canUseInterstitialFallback,
        prepareFallback: !RewardedAdsConfig.interstitialConfigured
            ? null
            : (token) async {
                if (!context.mounted || generation != _generation) return null;
                diagnostics.event('interstitial_intro', 'started');
                final accepted = await showRewardedInterstitialIntro(context);
                if (!accepted ||
                    !context.mounted ||
                    generation != _generation) {
                  diagnostics.event('interstitial_intro', 'skipped');
                  return null;
                }
                diagnostics.event('interstitial_intro', 'accepted');
                diagnostics.adUnit = RewardedAdsConfig.interstitialUnitId;
                diagnostics.attemptId = null;
                return diagnostics.step(
                  'backend_prepare_interstitial',
                  () async {
                    final prepared = await _request(
                      'prepare',
                      token,
                      adUnit: RewardedAdsConfig.interstitialUnitId,
                    );
                    diagnostics.attemptId = prepared['attempt_id'] as String;
                    return prepared;
                  },
                  timeout: const Duration(seconds: 30),
                );
              },
        showFallbackAd: (attempt) => ads.showInterstitial(
          attemptId: attempt,
          userId: user.id,
          diagnostics: diagnostics,
        ),
        onPending: () {
          if (mounted && generation == _generation) {
            state = RewardedAccessState(
              expiry: state.expiry,
              busy: true,
              pending: true,
            );
          }
        },
      );
      if (unlocked && mounted && generation == _generation) {
        state = RewardedAccessState(
          remaining: _session.remaining,
          expiry: state.expiry,
        );
      }
      diagnostics.event(
        'unlock',
        unlocked
            ? 'activated'
            : _flow.pending
            ? 'pending'
            : 'not_earned',
      );
      return unlocked;
    } catch (error) {
      if (error is! RewardedAdFailure) {
        diagnostics.event(
          'unlock',
          'failed',
          properties: RewardedAdDiagnostics.errorProperties(error),
        );
      }
      rethrow;
    } finally {
      if (mounted && generation == _generation) {
        state = RewardedAccessState(
          remaining: _session.remaining,
          pending: _flow.pending,
          expiry: state.expiry,
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _auth?.cancel();
    _flow.clear();
    _session.reset();
    super.dispose();
  }
}
