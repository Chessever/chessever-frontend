import 'package:chessever2/widgets/paywall/rewarded_premium/rewarded_navigation.dart';
import 'dart:async';

import 'package:chessever2/services/rewarded_premium/rewarded_ads.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef PremiumUpgrade = Future<bool> Function(BuildContext context);
bool _choiceOpen = false;

Future<bool> showRewardedAccessChoice(
  BuildContext context, {
  required PremiumUpgrade upgrade,
  bool expired = false,
}) async {
  if (_choiceOpen || !context.mounted) return false;
  _choiceOpen = true;
  try {
    return await showDialog<bool>(
          context: context,
          useRootNavigator: true,
          barrierDismissible: !expired,
          builder: (_) => _AccessChoice(upgrade: upgrade, expired: expired),
        ) ??
        false;
  } finally {
    _choiceOpen = false;
  }
}

class _AccessChoice extends ConsumerStatefulWidget {
  const _AccessChoice({required this.upgrade, required this.expired});
  final PremiumUpgrade upgrade;
  final bool expired;
  @override
  ConsumerState<_AccessChoice> createState() => _AccessChoiceState();
}

class _AccessChoiceState extends ConsumerState<_AccessChoice> {
  bool _busy = false;
  Future<void> _watch() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final unlocked = await ref
          .read(rewardedAccessProvider.notifier)
          .unlock(context);
      if (!mounted) {
        return;
      }
      if (unlocked) {
        Navigator.of(context).pop(true);
      } else if (ref.read(rewardedAccessProvider).pending) {
        showAppSnack(
          context,
          'Your reward is still being confirmed. Tap Retry confirmation.',
        );
      } else {
        showAppSnack(
          context,
          'Complete the ad to unlock 10 minutes of Premium.',
        );
      }
    } catch (_) {
      if (mounted) {
        showAppSnack(
          context,
          ref.read(rewardedAccessProvider).pending
              ? 'Could not confirm your reward. Retry without watching another ad.'
              : 'The ad is unavailable. Please try again later.',
          tone: AppSnackTone.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upgrade() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final upgraded = await widget.upgrade(context);
      if (upgraded && mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        showAppSnack(
          context,
          'Could not open Premium checkout. Please try again.',
          tone: AppSnackTone.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reward = ref.watch(rewardedAccessProvider);
    ref.listen<bool>(subscriptionProvider.select((s) => s.isSubscribed), (
      _,
      paid,
    ) {
      if (paid && mounted && !_busy) Navigator.of(context).pop(true);
    });
    return PopScope(
      canPop: !widget.expired && !_busy,
      child: AlertDialog(
        title: Text(
          widget.expired ? 'Your Premium access has ended' : 'Unlock Premium',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              reward.pending
                  ? 'Confirming your reward…'
                  : 'Watch a complete ad for 10 minutes of access to all Premium features, or upgrade for ongoing access.',
            ),
            const SizedBox(height: 16),
            if (_busy) const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _watch,
              child: Text(
                reward.pending
                    ? 'Retry confirmation'
                    : widget.expired
                    ? 'Watch ad again'
                    : 'Watch ad — unlock Premium for 10 minutes',
              ),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _upgrade,
              child: const Text('Upgrade to Premium'),
            ),
            if (widget.expired)
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        Navigator.of(context).pop(false);
                      },
                child: const Text('Go back'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Reserves space above the root Navigator, including screens with no app bar.
class RewardedAccessHost extends ConsumerStatefulWidget {
  const RewardedAccessHost({
    super.key,
    required this.child,
    required this.navigatorKey,
    required this.upgrade,
  });
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final PremiumUpgrade upgrade;
  @override
  ConsumerState<RewardedAccessHost> createState() => _RewardedAccessHostState();
}

class _RewardedAccessHostState extends ConsumerState<RewardedAccessHost>
    with WidgetsBindingObserver {
  bool _expiryOpen = false;
  int _handledExpiry = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RewardedNavigationObserver.instance.changes.addListener(_scheduleExpiry);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RewardedNavigationObserver.instance.changes.removeListener(_scheduleExpiry);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(rewardedAccessProvider.notifier).reconcile();
      _scheduleExpiry();
    }
  }

  void _scheduleExpiry() {
    if (!mounted || !RewardedAdsConfig.available) {
      return;
    }
    final reward = ref.read(rewardedAccessProvider);
    if ((reward.expiry <= _handledExpiry &&
            !RewardedNavigationObserver.instance.returningToSuspended) ||
        _expiryOpen) {
      return;
    }
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed &&
        WidgetsBinding.instance.lifecycleState != null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_expire());
    });
  }

  Future<void> _expire() async {
    if (!mounted || _expiryOpen || _choiceOpen) return;
    final reward = ref.read(rewardedAccessProvider);
    if ((reward.expiry <= _handledExpiry &&
            !RewardedNavigationObserver.instance.returningToSuspended) ||
        reward.active ||
        ref.read(subscriptionProvider).isSubscribed) {
      return;
    }
    final context = widget.navigatorKey.currentContext;
    if (context == null) return;
    _expiryOpen = true;
    _handledExpiry = reward.expiry;
    try {
      final unlocked = await showRewardedAccessChoice(
        context,
        upgrade: widget.upgrade,
        expired: true,
      );
      if (!unlocked && mounted) {
        RewardedNavigationObserver.instance.suspendCurrent();
        // Keep the route/drafts alive. Back to that route is guarded again.
        unawaited(widget.navigatorKey.currentState?.pushNamed('/home_screen'));
      }
    } finally {
      _expiryOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!RewardedAdsConfig.available) return widget.child;
    final reward = ref.watch(rewardedAccessProvider);
    final paid = ref.watch(subscriptionProvider.select((s) => s.isSubscribed));
    _scheduleExpiry();
    return Column(
      children: [
        if (reward.active && !paid)
          Material(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.timer_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Premium access · ${formatRewardedRemaining(reward.remaining)}',
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: reward.active && !paid
              ? MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: widget.child,
                )
              : widget.child,
        ),
      ],
    );
  }
}

String formatRewardedRemaining(Duration duration) {
  final seconds = (duration.inMilliseconds / 1000).ceil().clamp(0, 600);
  return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}
