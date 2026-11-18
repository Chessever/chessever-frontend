import 'package:chessever2/widgets/paywall/rewarded_premium/rewarded_navigation.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/services/rewarded_premium/rewarded_ads.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_theme.dart' show kPrimaryColor;
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
          barrierColor: Colors.black.withValues(alpha: 0.56),
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
    const card = Color(0xFF242A30);
    // Upgrade is the popup's one brand-blue action, first in line. Watch ad
    // follows as the neutral outlined alternative (Trello #1416).
    const primary = kPrimaryColor;
    const primaryInk = Color(0xFF07232B);
    const titleInk = Color(0xFFF5F7FA);
    const bodyInk = Color(0xFFC5CDD6);
    const outline = Color(0xFF74818E);
    const disabledFill = Color(0xFF334149);
    final confirming = reward.pending;
    final watching = _busy && !_upgrading;
    final upgrading = _busy && _upgrading;
    // The title's first line and the close button's padded 48 px tap target
    // share one centre line at every text size; whichever is shorter is
    // inset by half the difference.
    const closeSize = 44.0;
    const closeTarget = kMinInteractiveDimension;
    final titleLine = MediaQuery.textScalerOf(context).scale(24) * 1.25;
    final titleInset = widget.expired
        ? 0.0
        : math.max(0.0, (closeTarget - titleLine) / 2);
    final closeInset = math.max(0.0, (titleLine - closeTarget) / 2);
    ref.listen<bool>(subscriptionProvider.select((s) => s.isSubscribed), (
      _,
      paid,
    ) {
      if (paid && mounted && !_busy) Navigator.of(context).pop(true);
    });
    return PopScope(
      canPop: !widget.expired && !_busy,
      child: Dialog(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        constraints: const BoxConstraints(maxWidth: 352),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF39454D)),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: titleInset),
                        child: Semantics(
                          namesRoute: true,
                          header: true,
                          child: Text(
                            widget.expired
                                ? 'Your Premium access has ended'
                                : 'Unlock Premium',
                            style: const TextStyle(
                              color: titleInk,
                              fontSize: 24,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!widget.expired)
                      Padding(
                        padding: EdgeInsets.only(top: closeInset),
                        child: IconButton(
                          tooltip: 'Close',
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).pop(false),
                          constraints: const BoxConstraints(
                            minWidth: closeSize,
                            minHeight: closeSize,
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.standard,
                          style: const ButtonStyle(
                            tapTargetSize: MaterialTapTargetSize.padded,
                          ),
                          color: bodyInk,
                          disabledColor: outline,
                          icon: const Icon(Icons.close, size: 20),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  confirming
                      ? 'Confirming your reward…'
                      : 'Watch an ad for 10 minutes of access to all Premium features.',
                  style: const TextStyle(
                    color: bodyInk,
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _upgrade,
                  style: FilledButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: primaryInk,
                    disabledBackgroundColor: upgrading ? primary : disabledFill,
                    disabledForegroundColor: upgrading ? primaryInk : outline,
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (upgrading) ...[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: primaryInk,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          upgrading ? 'Opening…' : 'Upgrade',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy ? null : _watch,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: titleInk,
                    disabledForegroundColor: watching ? titleInk : outline,
                    side: const BorderSide(color: outline),
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (watching)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: titleInk,
                          ),
                        )
                      else if (!confirming)
                        const Icon(Icons.play_arrow_rounded, size: 20),
                      if (watching || !confirming) const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          watching
                              ? confirming
                                    ? 'Confirming…'
                                    : 'Loading ad…'
                              : confirming
                              ? 'Retry confirmation'
                              : widget.expired
                              ? 'Watch ad again'
                              : 'Watch ad',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: bodyInk,
                    disabledForegroundColor: outline,
                    minimumSize: const Size(0, 44),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: Text(widget.expired ? 'Go back' : 'Not now'),
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
