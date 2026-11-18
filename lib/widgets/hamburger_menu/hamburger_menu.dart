import 'package:chessever2/services/rewarded_premium/rewarded_ads.dart';
import 'package:chessever2/services/native_ads_config.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'dart:io';

import 'package:chessever2/widgets/app_snack.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_animate/flutter_animate.dart';

Future<void> _launchEmail() async {
  final Uri emailUri = Uri(scheme: 'mailto', path: 'info@chessever.com');
  if (await canLaunchUrl(emailUri)) {
    await launchUrl(emailUri);
  }
}

Future<void> _openStoreListing() async {
  try {
    await InAppReview.instance.openStoreListing(appStoreId: '6752567269');
  } catch (_) {
    // Fallback to web URLs if the native store sheet can't open.
    final Uri fallback = Uri.parse(
      Platform.isIOS
          ? 'https://apps.apple.com/app/id6752567269'
          : 'https://play.google.com/store/apps/details?id=com.chessEver.app',
    );
    if (await canLaunchUrl(fallback)) {
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
  }
}

void _showAboutDialog(BuildContext context, String version) {
  showAlertModal<void>(
    context: context,
    child: _AboutDialog(version: version),
  );
}

/// The ChessEver About sheet: version, X, privacy, contact.
void showChessEverAbout(BuildContext context, String version) =>
    _showAboutDialog(context, version);

/// The app's store page, where Rate leads.
Future<void> openChessEverStoreListing() => _openStoreListing();

/// About Dialog with social media and privacy policy
class _AboutDialog extends ConsumerWidget {
  const _AboutDialog({required this.version});

  final String version;

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(rewardedAccessProvider);
    final rewarded = (RewardedAdsConfig.available || NativeAdsConfig.available)
        ? ref.read(rewardedAccessProvider.notifier)
        : null;
    return Container(
      constraints: BoxConstraints(maxWidth: 340.w),
      decoration: BoxDecoration(
        color: context.colors.surfaceElevated,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.colors.divider, width: 1),
        boxShadow: [
          BoxShadow(
            color: context.colors.shadow,
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(24.sp),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  context.colors.iconPrimary.withValues(alpha: 0.05),
                  context.colors.iconPrimary.withValues(alpha: 0.02),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                Container(
                      width: 56.w,
                      height: 56.h,
                      decoration: BoxDecoration(
                        color: context.colors.iconPrimary.withValues(
                          alpha: 0.1,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: context.colors.iconPrimary.withValues(
                            alpha: 0.2,
                          ),
                          width: 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Image.asset(
                          'assets/app_icon.png',
                          width: 56.w,
                          height: 56.h,
                          fit: BoxFit.cover,
                          cacheWidth:
                              (56 * MediaQuery.devicePixelRatioOf(context))
                                  .toInt(),
                          cacheHeight:
                              (56 * MediaQuery.devicePixelRatioOf(context))
                                  .toInt(),
                        ),
                      ),
                    )
                    .animate()
                    .scale(
                      delay: 100.ms,
                      duration: 600.ms,
                      curve: Curves.elasticOut,
                    )
                    .fadeIn(duration: 300.ms),
                SizedBox(height: 16.h),
                Text(
                      'ChessEver',
                      style: AppTypography.textXlBold.copyWith(
                        color: context.colors.iconPrimary,
                        letterSpacing: 0.5,
                      ),
                    )
                    .animate()
                    .fadeIn(delay: 200.ms, duration: 400.ms)
                    .slideY(begin: 0.3, end: 0),
                SizedBox(height: 8.h),
                Text(
                  'Version $version',
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.iconPrimary.withValues(alpha: 0.5),
                  ),
                ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
              ],
            ),
          ),

          // Links section
          Padding(
            padding: EdgeInsets.all(20.sp),
            child: Column(
              children: [
                _LinkButton(
                  icon: Icons.language,
                  label: 'Follow us on X',
                  subtitle: '@chesseverapp',
                  onTap: () {
                    HapticFeedbackService.buttonPress();
                    _launchUrl('https://x.com/chesseverapp');
                  },
                  delay: 400,
                ),
                SizedBox(height: 12.h),
                if (rewarded?.ads.privacyOptionsRequired == true) ...[
                  _LinkButton(
                    icon: Icons.tune,
                    label: 'Ad privacy options',
                    subtitle: 'Manage your advertising privacy choices',
                    onTap: () async {
                      try {
                        await rewarded!.ads.showPrivacyOptions();
                      } catch (_) {
                        if (context.mounted) {
                          showAppSnack(
                            context,
                            'Privacy options are unavailable. Please try again.',
                          );
                        }
                      }
                    },
                    delay: 450,
                  ),
                  SizedBox(height: 12.h),
                ],
                _LinkButton(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Privacy Policy',
                  subtitle: 'How we protect your data',
                  onTap: () {
                    HapticFeedbackService.buttonPress();
                    _launchUrl('https://chessever.com/privacy-policy');
                  },
                  delay: 500,
                ),
                SizedBox(height: 12.h),
                _LinkButton(
                  icon: Icons.email_outlined,
                  label: 'Contact us',
                  subtitle: 'info@chessever.com',
                  onTap: () {
                    HapticFeedbackService.buttonPress();
                    _launchEmail();
                  },
                  delay: 600,
                ),
              ],
            ),
          ),

          // Close button
          Padding(
                padding: EdgeInsets.only(
                  bottom: 20.sp,
                  left: 20.sp,
                  right: 20.sp,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      HapticFeedbackService.buttonPress();
                      Navigator.of(context).pop();
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      backgroundColor: context.colors.iconPrimary.withValues(
                        alpha: 0.05,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Close',
                      style: AppTypography.textSmMedium.copyWith(
                        color: context.colors.iconPrimary.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .animate()
              .fadeIn(delay: 700.ms, duration: 400.ms)
              .slideY(begin: 0.3, end: 0),
        ],
      ),
    );
  }
}

/// Link button widget for the about dialog
class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    required this.delay,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final int delay;

  @override
  Widget build(BuildContext context) {
    return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.all(16.sp),
            decoration: BoxDecoration(
              color: context.colors.iconPrimary.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: context.colors.iconPrimary.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.h,
                  decoration: BoxDecoration(
                    color: context.colors.iconPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 20.ic,
                    color: context.colors.iconPrimary.withValues(alpha: 0.8),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppTypography.textSmMedium.copyWith(
                          color: context.colors.iconPrimary.withValues(
                            alpha: 0.9,
                          ),
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        subtitle,
                        style: AppTypography.textXsRegular.copyWith(
                          color: context.colors.iconPrimary.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14.ic,
                  color: context.colors.iconPrimary.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        )
        .animate()
        .fadeIn(delay: delay.ms, duration: 400.ms)
        .slideX(begin: 0.2, end: 0);
  }
}
