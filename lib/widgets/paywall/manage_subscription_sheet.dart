import 'dart:io' show Platform;

import 'package:app_settings/app_settings.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Bottom sheet that lets an active subscriber manage or cancel their plan.
///
/// Provider-aware, because where a subscription can be cancelled depends on
/// who bills it:
///   - **Stripe** (`provider == 'stripe'`, bought on the web/desktop): the
///     subscription does not exist in the phone's App Store / Play Store, so
///     we send the user to chessever.com/account, where they sign in and
///     cancel or manage in the Stripe customer portal.
///   - **App Store / Google Play** (`revenuecat` / `apple` / `google`): the
///     store owns the subscription. We show the exact store cancel steps and
///     deep-link into the device's subscription settings.
///
/// This replaces the old behaviour of reusing the post-purchase celebration
/// overlay for management, which auto-dismissed and dumped Stripe users into
/// an empty native subscriptions screen ("nothing happens").
Future<void> showManageSubscriptionSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: ResponsiveHelper.bottomSheetConstraints,
    builder: (_) => const _ManageSubscriptionSheet(),
  );
}

/// chessever.com/account — the web surface that signs the user in and opens
/// the Stripe customer portal with a valid web return URL.
final Uri _kAccountUrl = Uri.https('chessever.com', '/account');

const Color _kSheetSurface = Color(0xFF1C1C1E);

class _ManageSubscriptionSheet extends ConsumerWidget {
  const _ManageSubscriptionSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(subscriptionProvider);
    final isStripe = state.provider == 'stripe';

    return Container(
      decoration: BoxDecoration(
        color: _kSheetSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.br)),
      ),
      padding: EdgeInsets.fromLTRB(
        20.sp,
        12.sp,
        20.sp,
        20.sp + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: kWhiteColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2.br),
              ),
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            'Manage subscription',
            style: AppTypography.displaySmBold.copyWith(
              color: kWhiteColor,
              fontSize: 22.f,
            ),
          ),
          SizedBox(height: 8.h),
          _StatusLine(state: state),
          SizedBox(height: 20.h),
          if (isStripe)
            const _StripeBody()
          else
            const _StoreBody(),
          SizedBox(height: 8.h),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Done',
                style: AppTypography.textSmMedium.copyWith(color: kWhiteColor70),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.state});

  final SubscriptionState state;

  @override
  Widget build(BuildContext context) {
    if (!state.isSubscribed) {
      return Text(
        'No active subscription',
        style: AppTypography.textSmRegular.copyWith(color: kWhiteColor70),
      );
    }
    final renew = state.willRenew;
    final expiry = state.expirationDate;
    final tail = expiry != null
        ? ' · ${renew ? 'renews' : 'access until'} ${_formatDate(expiry)}'
        : '';
    return Row(
      children: [
        Icon(Icons.workspace_premium_rounded, size: 16.ic, color: kPrimaryColor),
        SizedBox(width: 6.w),
        Flexible(
          child: Text(
            '${renew ? 'Premium' : 'Premium · cancels at term end'}$tail',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
        ),
      ],
    );
  }
}

/// Stripe-billed: management lives on the web.
class _StripeBody extends StatelessWidget {
  const _StripeBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your Premium plan is billed on the web. Sign in at '
          'chessever.com/account to update your payment method, download '
          'invoices, or cancel anytime — changes sync back to the app within '
          'a few minutes.',
          style: AppTypography.textSmRegular.copyWith(
            color: kWhiteColor70,
            height: 1.45,
          ),
        ),
        SizedBox(height: 16.h),
        _PrimaryAction(
          icon: Icons.open_in_new_rounded,
          label: 'Manage on chessever.com',
          onTap: () async {
            HapticFeedbackService.buttonPress();
            await launchUrl(_kAccountUrl, mode: LaunchMode.externalApplication);
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

/// Store-billed (App Store / Google Play): management lives in the store.
class _StoreBody extends ConsumerWidget {
  const _StoreBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIOS = Platform.isIOS;
    final steps = isIOS
        ? 'To cancel, open the Settings app → tap your name at the top → '
              'Subscriptions → ChessEver → Cancel Subscription. Or tap below to '
              'jump straight there.'
        : 'To cancel, open Google Play → tap your profile icon → Payments & '
              'subscriptions → Subscriptions → ChessEver → Cancel. Or tap below '
              'to jump straight there.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your subscription is managed by ${isIOS ? 'the App Store' : 'Google Play'}.',
          style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
        ),
        SizedBox(height: 8.h),
        Text(
          steps,
          style: AppTypography.textSmRegular.copyWith(
            color: kWhiteColor70,
            height: 1.45,
          ),
        ),
        SizedBox(height: 16.h),
        _PrimaryAction(
          icon: Icons.settings_outlined,
          label: 'Open subscription settings',
          onTap: () async {
            HapticFeedbackService.buttonPress();
            final url = ref.read(subscriptionProvider).managementUrl;
            if (url != null && url.isNotEmpty) {
              final uri = Uri.tryParse(url);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
                if (context.mounted) Navigator.of(context).pop();
                return;
              }
            }
            await AppSettings.openAppSettings(
              type: AppSettingsType.subscriptions,
            );
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20.sp, vertical: 14.sp),
        decoration: BoxDecoration(
          color: kPrimaryColor,
          borderRadius: BorderRadius.circular(10.br),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18.ic, color: kBlackColor),
            SizedBox(width: 8.w),
            Text(
              label,
              style: AppTypography.textSmMedium.copyWith(
                color: kBlackColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final m = months[(date.month - 1).clamp(0, 11)];
  return '$m ${date.day}, ${date.year}';
}
