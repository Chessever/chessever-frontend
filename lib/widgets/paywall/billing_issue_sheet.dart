import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// SharedPreferences key for the "Remind me later" snooze timestamp.
const _kBillingIssueSnoozeKey = 'billing_issue_sheet_snoozed_until_ms';

/// How long to wait after the sheet closes (any way: button, swipe, barrier
/// tap) before showing it again. The popup is a nudge, not a wall —
/// surfacing it every app open would feel hostile. 24h gives the user time
/// to find their card and update it without our app interrupting them every
/// session.
const _kSnoozeDuration = Duration(hours: 24);

/// chessever.com/account — where Stripe-billed users manage payment methods.
/// RevenueCat's managementURL is null for subscriptions that don't exist in
/// the device's store, so web-billed users need this web surface instead
/// (same routing as manage_subscription_sheet.dart).
final Uri _kAccountUrl = Uri.https('chessever.com', '/account');

/// Imperatively show the billing-issue sheet. Reads provider, expiration and
/// management URL live from [subscriptionProvider]. Returns `true` if the
/// user tapped through to fix their payment method, `false` otherwise.
Future<bool> showBillingIssueSheet({required BuildContext context}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: ResponsiveHelper.bottomSheetConstraints,
    builder: (_) => const _BillingIssueSheet(),
  );
  return result ?? false;
}

/// Mount this near the top of an authenticated screen (e.g. HomeScreen). It
/// silently watches the subscription provider and pops the billing-issue
/// sheet once the user enters a billing-grace window, then snoozes itself
/// for 24h after the sheet closes. The child renders unchanged.
class BillingIssueGate extends HookConsumerWidget {
  const BillingIssueGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<SubscriptionState>(subscriptionProvider, (prev, next) {
      // Only react to transitions into the grace window — re-entering the
      // screen with the flag already set must not re-trigger the sheet.
      final wasInGrace = prev?.inBillingGracePeriod ?? false;
      if (wasInGrace) return;
      if (!next.inBillingGracePeriod) return;
      if (!next.isSubscribed) return;

      // Debug builds bypass premium gating elsewhere — keep this consistent
      // so devs aren't surprised by an unrelated popup.
      if (kDebugMode) return;

      unawaited(_maybeShow(context));
    });

    // Also surface the popup on a cold start where the flag is already set
    // when this gate mounts (e.g. user reopens the app a day after first
    // payment failure). Done once per mount via post-frame.
    final didCheckOnMount = useRef(false);
    final state = ref.read(subscriptionProvider);
    if (!didCheckOnMount.value &&
        state.isSubscribed &&
        state.inBillingGracePeriod &&
        !kDebugMode) {
      didCheckOnMount.value = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybeShow(context));
      });
    }

    return child;
  }

  Future<void> _maybeShow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final snoozedUntilMs = prefs.getInt(_kBillingIssueSnoozeKey) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch < snoozedUntilMs) return;
    if (!context.mounted) return;
    await showBillingIssueSheet(context: context);
    // Snooze regardless of HOW the sheet closed — swipe-down and barrier
    // taps don't run the button handlers, and without this the popup would
    // re-fire on the next cold start or layout remount.
    final next = DateTime.now().add(_kSnoozeDuration).millisecondsSinceEpoch;
    await prefs.setInt(_kBillingIssueSnoozeKey, next);
  }
}

class _BillingIssueSheet extends ConsumerWidget {
  const _BillingIssueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(subscriptionProvider);
    final isStripe = state.provider == 'stripe';
    final topPadding = MediaQuery.of(context).padding.top;

    return Padding(
      padding: EdgeInsets.only(top: topPadding + 80.h),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface.withValues(alpha: 0.98),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28.sp)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 24.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      color: context.colors.textPrimary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2.br),
                    ),
                  ),
                ),
                SizedBox(height: 24.h),
                Container(
                  width: 64.w,
                  height: 64.h,
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.credit_card_off_rounded,
                    color: kPrimaryColor,
                    size: 32.ic,
                  ),
                ),
                SizedBox(height: 20.h),
                Text(
                  'Update your payment method',
                  textAlign: TextAlign.center,
                  style: AppTypography.textLgBold.copyWith(
                    color: context.colors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: 12.h),
                Text(
                  _bodyCopy(state.expirationDate, isStripe: isStripe),
                  textAlign: TextAlign.center,
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                ),
                SizedBox(height: 24.h),
                _PrimaryButton(
                  label: isStripe
                      ? 'Manage on chessever.com'
                      : 'Update payment method',
                  onTap: () => _openBillingManagement(
                    context,
                    isStripe: isStripe,
                    managementUrl: state.managementUrl,
                  ),
                ),
                SizedBox(height: 12.h),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).pop(false),
                  style: TextButton.styleFrom(
                    minimumSize: Size(double.infinity, 48.h),
                    foregroundColor:
                        context.colors.textPrimary.withValues(alpha: 0.6),
                  ),
                  child: Text(
                    'Remind me later',
                    style: AppTypography.textSmMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Same provider routing as manage_subscription_sheet.dart: Stripe subs
  /// don't exist in the device's store (managementURL is null), so they go
  /// to the web account page; store subs go to the store's subscription
  /// screen, falling back to the OS subscription settings.
  Future<void> _openBillingManagement(
    BuildContext context, {
    required bool isStripe,
    required String? managementUrl,
  }) async {
    if (isStripe) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop(true);
      }
      unawaited(launchUrl(_kAccountUrl, mode: LaunchMode.externalApplication));
      return;
    }

    if (managementUrl != null && managementUrl.isNotEmpty) {
      final uri = Uri.tryParse(managementUrl);
      if (uri != null) {
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop(true);
        }
        unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
        return;
      }
    }

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop(true);
    }
    unawaited(AppSettings.openAppSettings(type: AppSettingsType.subscriptions));
  }

  String _bodyCopy(DateTime? expirationDate, {required bool isStripe}) {
    final where = isStripe
        ? 'Update your card at chessever.com/account'
        : 'Update your card';
    final exp = expirationDate;
    if (exp == null) {
      return "We couldn't process your latest ChessEver Premium payment. "
          '$where to keep your subscription active.';
    }
    final daysLeft = exp.difference(DateTime.now()).inDays;
    if (daysLeft <= 0) {
      return "We couldn't process your latest ChessEver Premium payment. "
          '$where to keep your Premium benefits.';
    }
    if (daysLeft == 1) {
      return "We couldn't process your latest ChessEver Premium payment. "
          "You'll lose Premium access tomorrow unless you update your card.";
    }
    return "We couldn't process your latest ChessEver Premium payment. "
        "You'll lose Premium access in $daysLeft days unless you update your card.";
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54.h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [kPrimaryColor, kDarkBlue],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16.br),
          boxShadow: [
            BoxShadow(
              color: kPrimaryColor.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16.br),
            child: Center(
              child: Text(
                label,
                style: AppTypography.textMdBold.copyWith(
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
