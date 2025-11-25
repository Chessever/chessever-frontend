import 'package:chessever2/providers/app_version_provider.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/hamburger_menu/hamburger_menu_dialogs.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Handler for hamburger menu callbacks
class HamburgerMenuCallbacks {
  final VoidCallback onPlayersPressed;
  final VoidCallback onFavoritesPressed;
  final VoidCallback onCountrymanPressed;
  final VoidCallback onAnalysisBoardPressed;
  final VoidCallback onSupportPressed;
  final VoidCallback onPremiumPressed;
  final VoidCallback onLogoutPressed;

  const HamburgerMenuCallbacks({
    required this.onPlayersPressed,
    required this.onFavoritesPressed,
    required this.onCountrymanPressed,
    required this.onAnalysisBoardPressed,
    required this.onSupportPressed,
    required this.onPremiumPressed,
    required this.onLogoutPressed,
  });
}

class HamburgerMenu extends StatelessWidget {
  final HamburgerMenuCallbacks callbacks;

  const HamburgerMenu({super.key, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260.w, // Set fixed width for hamburger menu
      child: Drawer(
        backgroundColor: kBackgroundColor,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    SizedBox(height: 24.h),
                    _MenuItem(
                      icon: Icons.settings,
                      customIcon: SvgWidget(
                        SvgAsset.settingsIcon,
                        semanticsLabel: 'Settings Icon',
                        height: 24.h,
                        width: 24.w,
                      ),
                      title: 'Settings',
                      onPressed: () => showSettingsDialog(context),
                      showChevron: true,
                    ),
                    // SizedBox(height: 12.h),
                    // _MenuItem(
                    //   customIcon: SvgWidget(
                    //     SvgAsset.playersIcon,
                    //     semanticsLabel: 'Players Icon',
                    //     height: 24.h,
                    //     width: 24.w,
                    //   ),
                    //   title: 'Players',
                    //   onPressed: () {
                    //     Navigator.pop(context); // Close drawer first
                    //     callbacks.onPlayersPressed();
                    //   },
                    // ),
                    SizedBox(height: 12.h),
                    _MenuItem(
                      customIcon: SvgWidget(
                        SvgAsset.favouriteIcon,
                        semanticsLabel: 'Fav Icon',
                        height: 24.h,
                        width: 24.w,
                      ),
                      title: 'Favorites',
                      onPressed: () {
                        Navigator.pop(context); // Close drawer first
                        callbacks.onFavoritesPressed();
                      },
                    ),
                    SizedBox(height: 12.h),
                    _CountryMan(
                      onCountryManPressed: () {
                        requireFullAuthGuard(context).then((allowed) {
                          if (!allowed) return;
                          if (!context.mounted) return;
                          Navigator.pop(context); // Close drawer first
                          callbacks.onCountrymanPressed();
                        });
                      },
                    ),
                    SizedBox(height: 12.h),
                    // _MenuItem(
                    //   customIcon: AnalysisBoardIcon(size: 20.ic),
                    //   title: 'Board',
                    //   onPressed: () {
                    //     callbacks.onAnalysisBoardPressed();
                    //   },
                    // ),
                    // SizedBox(height: 12.h),
                    // _MenuItem(
                    //   customIcon: SvgWidget(
                    //     SvgAsset.headsetIcon,
                    //     semanticsLabel: 'Support Icon',
                    //     height: 24.h,
                    //     width: 24.w,
                    //   ),
                    //   title: 'Support',
                    //   onPressed: () {
                    //     Navigator.pop(context); // Close drawer first
                    //     callbacks.onSupportPressed();
                    //   },
                    // ),
                    // SizedBox(height: 12.h),
                    // Container(
                    //   decoration: BoxDecoration(
                    //     gradient: LinearGradient(
                    //       colors: [kgradientEndColors, kgradientStartColors],
                    //       begin: Alignment.topLeft,
                    //       end: Alignment.bottomRight,
                    //     ),
                    //   ),
                    //   child: _MenuItem(
                    //     color: Colors.transparent,
                    //     customIcon: Image.asset(
                    //       PngAsset.premiumIcon,
                    //       width: 28.w,
                    //       height: 28.h,
                    //       fit: BoxFit.contain,
                    //     ),
                    //     title: 'Try Premium for free',
                    //     onPressed: () {
                    //       callbacks.onPremiumPressed();
                    //     },
                    //   ),
                    // ),
                  ],
                ),
              ),
              _VersionFooter(),
              _LogOutButton(
                onLogoutPressed: () {
                  callbacks.onLogoutPressed();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogOutButton extends StatelessWidget {
  const _LogOutButton({required this.onLogoutPressed, super.key});

  final VoidCallback? onLogoutPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onLogoutPressed != null
          ? () {
              HapticFeedbackService.buttonPress();
              onLogoutPressed!();
            }
          : null,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 12.sp),
        height: 48.h,
        child: Row(
          children: [
            Icon(Icons.logout, color: Colors.white, size: 24.ic),
            SizedBox(width: 12.w),
            Text(
              'Log out',
              style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    this.icon,
    this.customIcon,
    required this.title,
    this.showChevron = false,
    this.onPressed,
    this.color,
    this.textColors,
    super.key,
  });

  final IconData? icon;
  final Widget? customIcon;
  final String title;
  final bool showChevron;
  final Color? textColors;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed != null
          ? () {
              HapticFeedbackService.navigation();
              onPressed!();
            }
          : null,
      child: Container(
        color: color,
        padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
        height: 40.h,
        child: Row(
          children: [
            customIcon ?? Icon(icon, color: kWhiteColor, size: 24.ic),
            SizedBox(width: 4.w),
            Text(
              title,
              style: AppTypography.textMdMedium.copyWith(
                color: textColors ?? kWhiteColor,
              ),
            ),
            Spacer(),
            showChevron
                ? Padding(
                  padding: EdgeInsets.only(right: 12.sp),
                  child: Icon(
                    Icons.chevron_right_outlined,
                    color: kWhiteColor,
                    size: 24.ic,
                  ),
                )
                : SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}

class _VersionFooter extends ConsumerWidget {
  const _VersionFooter({super.key});

  Future<void> _launchEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'info@chessever.com',
    );
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    }
  }

  static Future<void> _launchPrivacyPolicy() async {
    final Uri privacyPolicyUri = Uri.parse(
      'https://chessever.com/gtc',
    );
    if (await canLaunchUrl(privacyPolicyUri)) {
      await launchUrl(privacyPolicyUri, mode: LaunchMode.externalApplication);
    }
  }

  void _showAboutDialog(BuildContext context, String version) {
    showDialog(
      context: context,
      builder: (context) => _AboutDialog(version: version),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider);
    return version.when(
      data: (versionString) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Divider
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 12.sp),
              child: Container(
                height: 1,
                color: kWhiteColor.withOpacity(0.1),
              ),
            )
                .animate()
                .fadeIn(duration: 400.ms)
                .slideX(begin: -0.2, end: 0),

            // Email - Now tappable
            InkWell(
              onTap: () {
                HapticFeedbackService.buttonPress();
                _launchEmail();
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
                height: 40.h,
                child: Row(
                  children: [
                    Icon(
                      Icons.email_outlined,
                      size: 18.ic,
                      color: kWhiteColor.withOpacity(0.7),
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      'info@chessever.com',
                      style: AppTypography.textSmRegular.copyWith(
                        color: kWhiteColor.withOpacity(0.7),
                        decoration: TextDecoration.underline,
                        decorationColor: kWhiteColor.withOpacity(0.3),
                      ),
                    ),
                  ],
                ),
              ),
            )
                .animate()
                .fadeIn(delay: 100.ms, duration: 400.ms)
                .slideX(begin: -0.2, end: 0),

            // Version - Now tappable
            InkWell(
              onTap: () {
                HapticFeedbackService.buttonPress();
                _showAboutDialog(context, versionString);
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
                height: 40.h,
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18.ic,
                      color: kWhiteColor.withOpacity(0.5),
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      'Version $versionString',
                      style: AppTypography.textSmRegular.copyWith(
                        color: kWhiteColor.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            )
                .animate()
                .fadeIn(delay: 200.ms, duration: 400.ms)
                .slideX(begin: -0.2, end: 0),

            // Privacy Policy Button
            InkWell(
              onTap: () {
                HapticFeedbackService.buttonPress();
                _launchPrivacyPolicy();
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
                height: 40.h,
                child: Row(
                  children: [
                    Container(
                      width: 20.w,
                      height: 20.h,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            kGreenColor.withOpacity(0.6),
                            kGreenColor.withOpacity(0.4),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        Icons.privacy_tip_outlined,
                        size: 14.ic,
                        color: kWhiteColor,
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      'Privacy Policy',
                      style: AppTypography.textSmRegular.copyWith(
                        color: kWhiteColor.withOpacity(0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Spacer(),
                    Icon(
                      Icons.open_in_new,
                      size: 14.ic,
                      color: kWhiteColor.withOpacity(0.4),
                    ),
                  ],
                ),
              ),
            )
                .animate()
                .fadeIn(delay: 300.ms, duration: 400.ms)
                .slideX(begin: -0.2, end: 0),

            // Delete Account Button
            InkWell(
              onTap: () async {
                HapticFeedbackService.buttonPress();
                final Uri deleteAccountUri = Uri.parse(
                  'https://sites.google.com/view/chessever-delete',
                );
                if (await canLaunchUrl(deleteAccountUri)) {
                  await launchUrl(deleteAccountUri, mode: LaunchMode.externalApplication);
                }
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
                height: 40.h,
                child: Row(
                  children: [
                    Icon(
                      Icons.person_remove_outlined,
                      size: 18.ic,
                      color: Colors.red.withOpacity(0.6),
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      'Delete Account',
                      style: AppTypography.textSmRegular.copyWith(
                        color: Colors.red.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            )
                .animate()
                .fadeIn(delay: 400.ms, duration: 400.ms)
                .slideX(begin: -0.2, end: 0),

            SizedBox(height: 8.h),
          ],
        );
      },
      error: (_, __) => SizedBox.shrink(),
      loading: () => SizedBox.shrink(),
    );
  }
}

class _CountryMan extends ConsumerWidget {
  const _CountryMan({required this.onCountryManPressed, super.key});

  final VoidCallback onCountryManPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countryMan = ref.watch(countryDropdownProvider);
    return countryMan.when(
      data: (data) {
        return _MenuItem(
          customIcon: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.w),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: CountryFlag.fromCountryCode(
                data.countryCode,
                height: 20.h,
                width: 20.w,
                shape: RoundedRectangle(0),
              ),
            ),
          ),
          title: 'Countryman',
          textColors: kGreenColor,
          onPressed: onCountryManPressed,
          showChevron: false,
        );
      },
      error: (error, _) {
        return SkeletonWidget(
          ignoreContainers: true,
          child: _MenuItem(
            customIcon: CountryFlag.fromCountryCode(
              'US',
              height: 20.h,
              width: 20.w,
              shape: RoundedRectangle(0),
            ),
            title: 'Countryman',
            onPressed: onCountryManPressed,
            showChevron: false,
          ),
        );
      },
      loading: () {
        return SkeletonWidget(
          ignoreContainers: true,
          child: _MenuItem(
            customIcon: CountryFlag.fromCountryCode(
              'US',
              height: 20.h,
              width: 20.w,
              shape: RoundedRectangle(0),
            ),
            title: 'Countryman',
            onPressed: onCountryManPressed,
            showChevron: false,
          ),
        );
      },
    );
  }
}

/// About Dialog with social media and privacy policy
class _AboutDialog extends StatelessWidget {
  const _AboutDialog({required this.version});

  final String version;

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxWidth: 340.w),
        decoration: BoxDecoration(
          color: kBackgroundColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: kWhiteColor.withOpacity(0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with chess piece accent
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(24.sp),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    kWhiteColor.withOpacity(0.05),
                    kWhiteColor.withOpacity(0.02),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  // App icon
                  Container(
                    width: 56.w,
                    height: 56.h,
                    decoration: BoxDecoration(
                      color: kWhiteColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: kWhiteColor.withOpacity(0.2),
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
                      color: kWhiteColor,
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
                      color: kWhiteColor.withOpacity(0.5),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 300.ms, duration: 400.ms),
                ],
              ),
            ),

            // Links section
            Padding(
              padding: EdgeInsets.all(20.sp),
              child: Column(
                children: [
                  // Social Media Link
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

                  // Privacy Policy Link
                  _LinkButton(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Privacy Policy',
                    subtitle: 'How we protect your data',
                    onTap: () {
                      HapticFeedbackService.buttonPress();
                      _launchUrl(
                        'https://chessever.com/gtc',
                      );
                    },
                    delay: 500,
                  ),
                ],
              ),
            ),

            // Close button
            Padding(
              padding: EdgeInsets.only(bottom: 20.sp, left: 20.sp, right: 20.sp),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    HapticFeedbackService.buttonPress();
                    Navigator.of(context).pop();
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    backgroundColor: kWhiteColor.withOpacity(0.05),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Close',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor.withOpacity(0.7),
                    ),
                  ),
                ),
              ),
            )
                .animate()
                .fadeIn(delay: 600.ms, duration: 400.ms)
                .slideY(begin: 0.3, end: 0),
          ],
        ),
      )
          .animate()
          .scale(
            begin: Offset(0.8, 0.8),
            duration: 300.ms,
            curve: Curves.easeOutBack,
          )
          .fadeIn(duration: 200.ms),
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
          color: kWhiteColor.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: kWhiteColor.withOpacity(0.08),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40.w,
              height: 40.h,
              decoration: BoxDecoration(
                color: kWhiteColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20.ic,
                color: kWhiteColor.withOpacity(0.8),
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
                      color: kWhiteColor.withOpacity(0.9),
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    subtitle,
                    style: AppTypography.textXsRegular.copyWith(
                      color: kWhiteColor.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 14.ic,
              color: kWhiteColor.withOpacity(0.4),
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
