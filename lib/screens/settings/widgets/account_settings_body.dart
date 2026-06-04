import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/settings/widgets/settings_primitives.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/hamburger_menu/hamburger_menu_dialogs.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

class AccountSettingsBody extends ConsumerWidget {
  const AccountSettingsBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscription = ref.watch(subscriptionProvider);
    final statusText =
        subscription.isLoading
            ? 'Checking...'
            : subscription.isSubscribed
            ? 'PRO active'
            : 'Free account';
    final renewalText =
        subscription.isSubscribed && !subscription.willRenew
            ? 'Access remains active until the current period ends.'
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingCard(
          child: Row(
            children: [
              _IconTile(
                icon: Icons.workspace_premium_outlined,
                color:
                    subscription.isSubscribed
                        ? kPrimaryColor
                        : context.colors.iconPrimary,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Subscription Status',
                      style: AppTypography.textMdMedium.copyWith(
                        color: context.colors.textPrimary,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      renewalText ?? statusText,
                      style: AppTypography.textSmRegular.copyWith(
                        color:
                            subscription.isSubscribed
                                ? kPrimaryColor
                                : context.colors.textSecondary,
                        fontSize: 11.f,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12.h),
        _AccountActionRow(
          icon: Icons.settings_outlined,
          title: 'Manage Subscription',
          subtitle:
              subscription.isSubscribed
                  ? 'Open Apple or Google subscription settings.'
                  : 'Upgrade or manage your plan.',
          onTap: () => _handleManageSubscription(context, ref, subscription),
        ),
        SizedBox(height: 10.h),
        _AccountActionRow(
          icon: Icons.restore_rounded,
          title: 'Restore Purchases',
          subtitle: 'Recover an existing App Store or Google Play purchase.',
          onTap: () => _handleRestorePurchases(context, ref),
        ),
        SizedBox(height: 16.h),
        _AccountActionRow(
          key: e2eKey(E2eIds.settingsDeleteAccount),
          icon: Icons.delete_forever_outlined,
          title: 'Delete Account',
          subtitle: 'Permanently remove your ChessEver account.',
          destructive: true,
          onTap: () {
            HapticFeedbackService.navigation();
            showDeleteAccountDialog(context);
          },
        ),
      ],
    );
  }

  Future<void> _handleManageSubscription(
    BuildContext context,
    WidgetRef ref,
    SubscriptionState subscription,
  ) async {
    HapticFeedbackService.buttonPress();

    if (!subscription.isSubscribed) {
      final authOk = await requireFullAuthGuard(context);
      if (!authOk || !context.mounted) return;
      await showPremiumPaywallSheet(context: context);
      return;
    }

    final opened = await _openSubscriptionManagement(
      subscription.managementUrl,
    );
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? 'Opening subscription settings...'
              : 'Could not open subscription settings. Please manage it from the App Store or Google Play.',
        ),
        backgroundColor:
            opened ? context.colors.surfaceRecessed : context.colors.danger,
      ),
    );
  }

  Future<void> _handleRestorePurchases(
    BuildContext context,
    WidgetRef ref,
  ) async {
    HapticFeedbackService.buttonPress();
    final success =
        await ref.read(subscriptionProvider.notifier).restorePurchases();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Purchases restored successfully!'
              : 'No purchases found to restore',
        ),
        backgroundColor:
            success
                ? context.colors.successStrong
                : context.colors.surfaceRecessed,
      ),
    );
  }

  Future<bool> _openSubscriptionManagement(String? managementUrl) async {
    final url = managementUrl;
    if (url != null && url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
    }

    try {
      await AppSettings.openAppSettings(type: AppSettingsType.subscriptions);
      return true;
    } catch (_) {
      final fallback = Uri.parse(
        Platform.isIOS
            ? 'https://apps.apple.com/account/subscriptions'
            : 'https://play.google.com/store/account/subscriptions',
      );
      if (await canLaunchUrl(fallback)) {
        await launchUrl(fallback, mode: LaunchMode.externalApplication);
        return true;
      }
    }

    return false;
  }
}

class _AccountActionRow extends StatelessWidget {
  const _AccountActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color =
        destructive ? context.colors.danger : context.colors.textPrimary;

    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(18.br),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18.br),
        splashColor: color.withValues(alpha: 0.08),
        highlightColor: color.withValues(alpha: 0.04),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18.br),
            border: Border.all(
              color:
                  destructive
                      ? context.colors.danger.withValues(alpha: 0.45)
                      : context.colors.divider.withValues(alpha: 0.4),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 12.sp),
            child: Row(
              children: [
                _IconTile(icon: icon, color: color),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.textMdMedium.copyWith(
                          color: color,
                          fontSize: 13.f,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 3.h),
                      Text(
                        subtitle,
                        style: AppTypography.textSmRegular.copyWith(
                          color:
                              destructive
                                  ? color.withValues(alpha: 0.72)
                                  : context.colors.textSecondary,
                          fontSize: 11.f,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8.w),
                Icon(Icons.chevron_right_rounded, color: color, size: 22.ic),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38.w,
      height: 38.h,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Icon(icon, color: color, size: 20.ic),
    );
  }
}
