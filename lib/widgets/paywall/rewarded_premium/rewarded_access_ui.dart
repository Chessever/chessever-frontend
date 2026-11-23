import 'package:chessever2/widgets/paywall/rewarded_premium/rewarded_navigation.dart';
import 'dart:async';

import 'package:chessever2/services/rewarded_premium/rewarded_ads.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/glass_dialog_route.dart';
import 'package:chessever2/widgets/paywall/rewarded_premium/choice_plate.dart';
import 'package:chessever2/widgets/paywall/rewarded_premium/premium_marks.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef PremiumUpgrade = Future<bool> Function(BuildContext context);
bool _choiceOpen = false;

/// Forgets a popup a failed test left open, so the next test can show one.
@visibleForTesting
void debugResetRewardedAccessChoice() => _choiceOpen = false;

Future<bool> showRewardedAccessChoice(
  BuildContext context, {
  required PremiumUpgrade upgrade,
  bool expired = false,
}) async {
  if (_choiceOpen || !context.mounted) return false;
  _choiceOpen = true;
  try {
    // No fade, so the card's glass is frosted from its first frame. An
    // outside tap still asks the card's PopScope (never while busy). The
    // card follows the theme, so it stands on the popups' own scrim.
    return await showGlassDialog<bool>(
          context: context,
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
  bool _upgrading = false;
  Future<void> _watch() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _upgrading = false;
    });
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
    setState(() {
      _busy = true;
      _upgrading = true;
    });
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
    final colors = context.colors;
    final light = context.isLightTheme;
    final confirming = reward.pending;
    final watching = _busy && !_upgrading;
    final upgrading = _busy && _upgrading;
    ref.listen<bool>(subscriptionProvider.select((s) => s.isSubscribed), (
      _,
      paid,
    ) {
      if (paid && mounted && !_busy) Navigator.of(context).pop(true);
    });
    return PopScope(
      canPop: !widget.expired && !_busy,
      // The popups' glass in the reader's theme, as every centred popup.
      // Not now and an outside tap dismiss it, so it carries no close X.
      child: GlassDialog(
        tone: colors.popup,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        constraints: const BoxConstraints(maxWidth: 352),
        borderRadius: BorderRadius.circular(20),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: PremiumMark()),
                const SizedBox(height: 16),
                Semantics(
                  namesRoute: true,
                  header: true,
                  child: Text(
                    widget.expired
                        ? 'Your Premium time is up'
                        : 'Unlock Premium',
                    textAlign: TextAlign.center,
                    style: premiumPopupType(
                      22,
                      1.25,
                      FontWeight.w700,
                      colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  confirming
                      ? 'Confirming your reward…'
                      // The two ways in, in the buttons' order: the duration
                      // belongs to the ad, never to the upgrade.
                      : widget.expired
                      ? 'Unlimited, or 10 more minutes for one ad.'
                      : 'Unlimited, or 10 minutes for one ad.',
                  textAlign: TextAlign.center,
                  style: premiumPopupType(
                    15,
                    1.4,
                    FontWeight.w400,
                    colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                // Upgrade leads (Trello #1416): the premium plate, wearing
                // the mark. Watch ad follows in the same construction, a
                // quiet step off the card.
                ChoicePlate(
                  label: 'Upgrade',
                  busyLabel: 'Opening…',
                  glyph: ChoiceGlyph.premium,
                  tone: ChoicePlateTone.upgrade(light: light),
                  onTap: _busy ? null : _upgrade,
                  busy: upgrading,
                  dimmed: watching,
                  pressMovesGlyph: true,
                ),
                const SizedBox(height: 10),
                ChoicePlate(
                  label: confirming
                      ? 'Retry confirmation'
                      : widget.expired
                      ? 'Watch ad again'
                      : 'Watch ad',
                  busyLabel: confirming ? 'Confirming…' : 'Loading ad…',
                  glyph: confirming ? ChoiceGlyph.retry : ChoiceGlyph.play,
                  tone: ChoicePlateTone.watch(colors, light: light),
                  onTap: _busy ? null : _watch,
                  busy: watching,
                  dimmed: upgrading,
                ),
                const SizedBox(height: 4),
                ChoiceDismissButton(
                  label: widget.expired ? 'Go back' : 'Not now',
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ),
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
    // Keep expiry handling active without adding a countdown or changing the
    // screen's safe-area padding.
    ref.listen(rewardedAccessProvider, (_, _) => _scheduleExpiry());
    ref.listen(subscriptionProvider, (_, _) => _scheduleExpiry());
    _scheduleExpiry();
    return widget.child;
  }
}
