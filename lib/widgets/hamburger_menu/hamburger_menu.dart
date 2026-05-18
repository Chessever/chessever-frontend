import 'dart:io';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:chessever2/providers/app_version_provider.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/hamburger_menu/hamburger_menu_dialogs.dart';
import 'package:chessever2/widgets/paywall/premium_celebration_overlay.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:chessever2/widgets/user_avatar.dart';
import 'package:chessever2/services/review_prompt_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:logarte/logarte.dart';
import 'package:chessever2/main.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Handler for hamburger menu callbacks
class HamburgerMenuCallbacks {
  final VoidCallback onPlayersPressed;
  final VoidCallback onAnalysisBoardPressed;
  final VoidCallback onOpeningExplorerPressed;
  final VoidCallback onFavoritesPressed;
  final VoidCallback onSupportPressed;
  final VoidCallback onPremiumPressed;
  final VoidCallback onLogoutPressed;

  const HamburgerMenuCallbacks({
    required this.onPlayersPressed,
    required this.onAnalysisBoardPressed,
    required this.onOpeningExplorerPressed,
    required this.onFavoritesPressed,
    required this.onSupportPressed,
    required this.onPremiumPressed,
    required this.onLogoutPressed,
  });
}

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
  showDialog(
    context: context,
    builder: (context) => _AboutDialog(version: version),
  );
}

class HamburgerMenu extends HookConsumerWidget {
  final HamburgerMenuCallbacks callbacks;

  const HamburgerMenu({super.key, required this.callbacks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logarteTapCount = useState(0);
    final isTablet = ResponsiveHelper.isTablet;
    final drawerWidth = isTablet ? 320.0 : 260.w;
    final version = ref.watch(appVersionProvider);
    final versionString = version.valueOrNull ?? '';

    return SizedBox(
      width: drawerWidth,
      child: Drawer(
        key: e2eKey(E2eIds.homeDrawer),
        backgroundColor: context.colors.background,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            logarteTapCount.value++;
            if (logarteTapCount.value >= 7) {
              logarteTapCount.value = 0;
              if (logarte.isOverlayAttached) {
                logarte.detachOverlay();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Logarte Debug Console Disabled')),
                );
              } else {
                logarte.attach(context: context, visible: true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Logarte Debug Console Enabled')),
                );
              }
            }
          },
          child: SafeArea(
            bottom: true,
            child: Column(
              children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    if (isTablet)
                      Padding(
                        padding: EdgeInsets.only(
                          left: 8.sp,
                          top: 8.h,
                          bottom: 8.h,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: InkWell(
                            onTap: () {
                              HapticFeedbackService.buttonPress();
                              Navigator.of(context).pop();
                            },
                            borderRadius: BorderRadius.circular(12.br),
                            child: Container(
                              width: 44.w,
                              height: 44.h,
                              decoration: BoxDecoration(
                                color: context.colors.surfaceRecessed,
                                borderRadius: BorderRadius.circular(12.br),
                              ),
                              child: Icon(
                                Icons.menu_rounded,
                                color: context.colors.iconPrimary,
                                size: 24.0,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      SizedBox(height: 16.h),

                    // User profile header (avatar + name + PRO badge)
                    const _UserProfileHeader(),
                    SizedBox(height: 8.h),

                    // Menu items
                    //
                    // Each utility SVG is shipped with white-ish tints baked
                    // in (looks correct on the dark drawer). In light theme
                    // that bakes a white-on-light-grey contrast bug, so we
                    // recolour to `iconPrimary` only when the theme is light;
                    // dark theme renders the asset unchanged.
                    _MenuItem(
                      key: e2eKey(E2eIds.drawerOpeningExplorer),
                      customIcon: SvgWidget(
                        SvgAsset.openingExplorer,
                        semanticsLabel: 'Opening Explorer Icon',
                        height: 20.h,
                        width: 20.w,
                        colorFilter: context.isLightTheme
                            ? ColorFilter.mode(
                                context.colors.iconPrimary,
                                BlendMode.srcIn,
                              )
                            : null,
                      ),
                      icon: Icons.explore_outlined,
                      title: 'Opening Explorer',
                      textStyle: AppTypography.textSmMedium.copyWith(
                        color: context.colors.iconPrimary,
                        height: 1.0,
                        letterSpacing: -0.14,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        callbacks.onOpeningExplorerPressed();
                      },
                      showChevron: true,
                    ),
                    _MenuItem(
                      key: e2eKey(E2eIds.drawerAnalysisBoard),
                      customIcon: SvgWidget(
                        SvgAsset.analysisBoard,
                        semanticsLabel: 'Analysis Board Icon',
                        height: 20.h,
                        width: 20.w,
                        // Multi-colour mini-chessboard artwork — must keep
                        // its baked white/grey/dark squares in both themes.
                        // Tinting collapses it into a single solid blob.
                        preserveOriginalColors: true,
                      ),
                      icon: Icons.grid_view_rounded,
                      title: 'Board Editor',
                      textStyle: AppTypography.textSmRegular.copyWith(
                        color: context.colors.iconPrimary,
                        height: 20.h / 14.h,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        callbacks.onAnalysisBoardPressed();
                      },
                      showChevron: true,
                    ),
                    _MenuItem(
                      icon: Icons.favorite_border,
                      title: 'Favorites',
                      textStyle: AppTypography.textSmRegular.copyWith(
                        color: context.colors.iconPrimary,
                        height: 20.h / 14.h,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        callbacks.onFavoritesPressed();
                      },
                      showChevron: true,
                    ),
                    _MenuItem(
                      key: e2eKey(E2eIds.drawerSettings),
                      customIcon: SvgWidget(
                        SvgAsset.settings,
                        semanticsLabel: 'Settings Icon',
                        height: 20.h,
                        width: 20.w,
                        colorFilter: context.isLightTheme
                            ? ColorFilter.mode(
                                context.colors.iconPrimary,
                                BlendMode.srcIn,
                              )
                            : null,
                      ),
                      title: 'Settings',
                      textStyle: AppTypography.textSmRegular.copyWith(
                        color: context.colors.iconPrimary,
                        height: 20.h / 14.h,
                      ),
                      onPressed: () => showSettingsDialog(context),
                      showChevron: true,
                    ),
                    _MenuItem(
                      customIcon: SvgWidget(
                        SvgAsset.leaveFeedback,
                        semanticsLabel: 'Leave Feedback Icon',
                        height: 20.h,
                        width: 20.w,
                        colorFilter: context.isLightTheme
                            ? ColorFilter.mode(
                                context.colors.iconPrimary,
                                BlendMode.srcIn,
                              )
                            : null,
                      ),
                      icon: Icons.rate_review_outlined,
                      title: 'Leave Feedback',
                      textStyle: AppTypography.textSmRegular.copyWith(
                        color: context.colors.iconPrimary,
                        height: 20.h / 14.h,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        ReviewPromptService.instance.maybePrompt(
                          context: context,
                          trigger: ReviewPromptTrigger.sidebar,
                          force: true,
                        );
                      },
                      showChevron: true,
                    ),
                    _MenuItem(
                      icon: Icons.star_outline,
                      title: 'Rate this app',
                      textStyle: AppTypography.textSmRegular.copyWith(
                        color: context.colors.iconPrimary,
                        height: 20.h / 14.h,
                      ),
                      onPressed: () {
                        _openStoreListing();
                      },
                      showChevron: true,
                    ),
                    _MenuItem(
                      customIcon: SvgWidget(
                        SvgAsset.versionIcon,
                        semanticsLabel: 'Info Icon',
                        height: 20.h,
                        width: 20.w,
                        colorFilter: context.isLightTheme
                            ? ColorFilter.mode(
                                context.colors.iconPrimary,
                                BlendMode.srcIn,
                              )
                            : null,
                      ),
                      title:
                          versionString.isNotEmpty
                              ? 'Version $versionString'
                              : 'Version',
                      textStyle: AppTypography.textSmRegular.copyWith(
                        color: context.colors.iconPrimary,
                        height: 20.h / 14.h,
                      ),
                      onPressed: () {
                        _showAboutDialog(context, versionString);
                      },
                      showChevron: true,
                    ),
                  ],
                ),
              ),

              // Footer: Get Premium card + Restore Purchases + Divider + Log Out
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: ResponsiveHelper.isTablet ? 280.0 : 0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // "Get Premium" card — shown only for non-premium users
                    _GetPremiumCard(),

                    // Restore Purchases
                    _RestorePurchasesRow(),

                    // Divider
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.sp),
                      child: Container(
                        height: 1,
                        color: context.colors.divider,
                      ),
                    ),

                    _LogOutButton(
                      key: e2eKey(E2eIds.drawerLogout),
                      onLogoutPressed: () {
                        callbacks.onLogoutPressed();
                      },
                    ),

                    if (ResponsiveHelper.isTablet) SizedBox(height: 16.0),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// User profile header — displays avatar, display name, and PRO badge (if subscribed)
class _UserProfileHeader extends ConsumerWidget {
  const _UserProfileHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final subscriptionState = ref.watch(subscriptionProvider);
    final isPremium = subscriptionState.isSubscribed;
    final managementUrl = subscriptionState.managementUrl;
    final name = user?.displayName?.trim();
    final displayName = (name?.isNotEmpty ?? false) ? name! : 'Anonymous';

    return GestureDetector(
      onTap:
          isPremium
              ? () async {
                Navigator.of(context).pop();
                if (!context.mounted) return;
                await showPremiumCelebration(
                  context,
                  managementUrl: managementUrl,
                );
              }
              : null,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 12.sp),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            UserAvatar(size: 40, showPremiumBorder: true),
            SizedBox(width: 12.w),

            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      displayName,
                      style: AppTypography.textSmSemiBold.copyWith(
                        color: context.colors.iconPrimary,
                        height: 20.h / 14.h,
                        letterSpacing: -0.14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isPremium) ...[SizedBox(width: 8.w), _ProBadge()],
                ],
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 300.ms).slideX(begin: -0.1, end: 0),
    );
  }
}

/// Small "PRO" pill badge shown next to the user's name for premium subscribers
class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4.sp, vertical: 2.sp),
      decoration: BoxDecoration(
        color: kPrimaryColor,
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(color: kPrimaryColor.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        'PRO',
        style: AppTypography.textXsRegular.copyWith(
          color: context.colors.textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Dismissible "Get Premium" card shown at the bottom for non-premium users.
/// Dismissed state is session-only (resets on app restart).
class _GetPremiumCard extends ConsumerStatefulWidget {
  const _GetPremiumCard();

  @override
  ConsumerState<_GetPremiumCard> createState() => _GetPremiumCardState();
}

class _GetPremiumCardState extends ConsumerState<_GetPremiumCard> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final isPremium = ref.watch(subscriptionProvider).isSubscribed;

    if (isPremium || _dismissed) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(16.sp, 0.sp, 16.sp, 12.sp),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(16.br),
          border: Border.all(
            color: context.colors.divider,
            width: 1,
          ),
        ),
        padding: EdgeInsets.only(left: 12.sp, top: 4.sp, bottom: 12.sp),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row with X button
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'Get Premium',
                    style: AppTypography.textSmSemiBold.copyWith(
                      color: context.colors.iconPrimary,
                      height: 17.5.h / 14.h,
                    ),
                  ),
                ),

                IconButton(
                  style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(
                      context.colors.background,
                    ),
                    foregroundColor: WidgetStatePropertyAll(
                      context.colors.iconPrimary,
                    ),
                    shape: WidgetStatePropertyAll(CircleBorder()),
                  ),
                  onPressed: () {
                    HapticFeedbackService.buttonPress();
                    setState(() => _dismissed = true);
                  },
                  icon: Icon(
                    Icons.close,
                    color: context.colors.iconPrimary.withValues(alpha: 0.6),
                    size: 14.ic,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 20.w, minHeight: 20.h),
                ),
              ],
            ),
            SizedBox(height: 4.h),
            Text(
              'Unlock all premium features to improve your chess game!',
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.iconPrimary,
                height: 19.5.h / 12.h,
              ),
            ),
            SizedBox(height: 12.h),
            // GestureDetector wraps the whole pill so the full padded area
            // is tappable. Previously an InkWell sat *inside* the Container,
            // so only the bare Text glyph was hit-testable and the pill
            // appeared unresponsive on tablet sizes where the padding is
            // large relative to the text.
            //
            // Calls showPremiumPaywallSheet directly instead of
            // requirePremiumGuard because the guard short-circuits to `true`
            // in kDebugMode — which made this button silently no-op for
            // anyone running a debug build.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                HapticFeedbackService.buttonPress();
                final authOk = await requireFullAuthGuard(context);
                if (!authOk || !context.mounted) return;
                await showPremiumPaywallSheet(context: context);
              },
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 12.sp,
                  vertical: 8.sp,
                ),
                decoration: BoxDecoration(
                  color: kPrimaryColor,
                  borderRadius: BorderRadius.circular(69.br),
                ),
                child: Text(
                  'Upgrade to Premium',
                  style: AppTypography.textXsMedium.copyWith(
                    color: context.colors.textPrimary,
                    height: 16.h / 12.h,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Restore Purchases row — kept for App Store compliance
class _RestorePurchasesRow extends ConsumerWidget {
  const _RestorePurchasesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () async {
        HapticFeedbackService.buttonPress();
        final success =
            await ref.read(subscriptionProvider.notifier).restorePurchases();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? 'Purchases restored successfully!'
                    : 'No purchases found to restore',
              ),
              backgroundColor: success
                  ? context.colors.successStrong
                  : context.colors.surfaceRecessed,
            ),
          );
        }
      },
      child: Container(
        padding: EdgeInsets.only(
          left: 16.sp,
          top: 10.sp,
          bottom: 10.sp,
          right: 8.sp,
        ),
        child: Row(
          children: [
            Icon(
              Icons.restore_rounded,
              size: 24.ic,
              color: context.colors.iconPrimary.withValues(alpha:0.5),
            ),
            SizedBox(width: 12.w),
            Text(
              'Restore Purchases',
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.iconPrimary.withValues(alpha:0.5),
              ),
            ),
          ],
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
    final isAnonymous =
        Supabase.instance.client.auth.currentUser?.isAnonymous == true;

    return InkWell(
      onTap:
          onLogoutPressed != null
              ? () {
                HapticFeedbackService.buttonPress();
                onLogoutPressed!();
              }
              : null,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 12.sp),
        height: 65.h,
        child: Row(
          children: [
            Icon(
              isAnonymous ? Icons.person_add_outlined : Icons.logout,
              color: isAnonymous ? null : context.colors.danger,
              size: 24.ic,
            ),
            SizedBox(width: 12.w),
            Text(
              isAnonymous ? 'Sign up' : 'Log out',
              style: AppTypography.textSmMedium.copyWith(
                color: isAnonymous ? context.colors.iconPrimary : context.colors.danger,
                height: 20.h / 14.h,
              ),
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
    this.textStyle,
    this.maxLines = 1,
    super.key,
  });

  final int? maxLines;
  final IconData? icon;
  final Widget? customIcon;
  final String title;
  final bool showChevron;
  final VoidCallback? onPressed;
  final TextStyle? textStyle;

  VoidCallback? get _onTap =>
      onPressed != null
          ? () {
            HapticFeedbackService.navigation();
            onPressed!();
          }
          : null;

  Widget _buildRowContent(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        customIcon ??
            Icon(
              icon,
              color: context.colors.iconPrimary.withValues(alpha: 0.8),
              size: 22.ic,
            ),
        SizedBox(width: 12.w),
        Expanded(
          child: Text(
            title,
            maxLines: maxLines,
            style:
                textStyle ??
                AppTypography.textSmRegular.copyWith(
                  color: context.colors.iconPrimary,
                  height: 20.h / 14.h,
                ),
          ),
        ),
        if (showChevron)
          Icon(
            Icons.chevron_right_outlined,
            color: context.colors.iconPrimary.withValues(alpha: 0.4),
            size: 22.ic,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Menu items: InkWell wraps the full Padding so the 4 sp vertical gaps
    // above/below are part of the tap surface (larger hit area, same UI).
    return InkWell(
      onTap: _onTap,
      customBorder: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(1000),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 16.sp,
          right: 8.sp,
          top: 4.sp,
          bottom: 4.sp,
        ),
        child: SizedBox(
          height: 44.h,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.sp),
            child: _buildRowContent(context),
          ),
        ),
      ),
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
              color: context.colors.surfaceElevated,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: context.colors.divider,
                width: 1,
              ),
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
                        context.colors.iconPrimary.withValues(alpha:0.05),
                        context.colors.iconPrimary.withValues(alpha:0.02),
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
                              color: context.colors.iconPrimary.withValues(alpha:0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: context.colors.iconPrimary.withValues(alpha:0.2),
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
                                    (56 *
                                            MediaQuery.devicePixelRatioOf(
                                              context,
                                            ))
                                        .toInt(),
                                cacheHeight:
                                    (56 *
                                            MediaQuery.devicePixelRatioOf(
                                              context,
                                            ))
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
                          color: context.colors.iconPrimary.withValues(alpha:0.5),
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
                            backgroundColor: context.colors.iconPrimary.withValues(alpha:0.05),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Close',
                            style: AppTypography.textSmMedium.copyWith(
                              color: context.colors.iconPrimary.withValues(alpha:0.7),
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
          )
          .animate()
          .scale(
            begin: const Offset(0.8, 0.8),
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
              color: context.colors.iconPrimary.withValues(alpha:0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: context.colors.iconPrimary.withValues(alpha:0.08),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.h,
                  decoration: BoxDecoration(
                    color: context.colors.iconPrimary.withValues(alpha:0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 20.ic,
                    color: context.colors.iconPrimary.withValues(alpha:0.8),
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
                          color: context.colors.iconPrimary.withValues(alpha:0.9),
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        subtitle,
                        style: AppTypography.textXsRegular.copyWith(
                          color: context.colors.iconPrimary.withValues(alpha:0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14.ic,
                  color: context.colors.iconPrimary.withValues(alpha:0.4),
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
