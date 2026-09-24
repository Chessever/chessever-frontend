import 'dart:io';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:chessever2/providers/app_version_provider.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/my_profile/my_profile_screen.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_flame.dart';
import 'package:chessever2/screens/streaks/streaks_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/board_navigation_icon.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/hamburger_menu/hamburger_menu_dialogs.dart';
import 'package:chessever2/widgets/hamburger_menu/sidebar_month_calendar.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:chessever2/widgets/user_avatar.dart';
import 'package:chessever2/services/review_prompt_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:chessever2/main.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:motor/motor.dart';

/// Handler for hamburger menu callbacks
class HamburgerMenuCallbacks {
  final VoidCallback onPlayersPressed;
  final VoidCallback onBoardPressed;
  final VoidCallback onFavoritesPressed;
  final VoidCallback onSupportPressed;
  final VoidCallback onPremiumPressed;
  final VoidCallback onLogoutPressed;

  /// Opens the streak wall. When null the drawer pushes it itself.
  final VoidCallback? onStreaksPressed;

  const HamburgerMenuCallbacks({
    required this.onPlayersPressed,
    required this.onBoardPressed,
    required this.onFavoritesPressed,
    required this.onSupportPressed,
    required this.onPremiumPressed,
    required this.onLogoutPressed,
    this.onStreaksPressed,
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
  showAlertModal<void>(context: context, child: _AboutDialog(version: version));
}

/// Closes the drawer and pushes the calendar, on [day] when one was tapped.
/// The drawer stays mounted through its closing animation, so its context
/// is still good for the push.
void _openCalendar(BuildContext context, DateTime? day) {
  Navigator.of(context).pop();
  openCalendarScreen(context, day: day, source: 'sidebar');
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
                showAppSnack(context, 'Logarte Debug Console Disabled');
              } else {
                logarte.attach(context: context, visible: true);
                showAppSnack(context, 'Logarte Debug Console Enabled');
              }
            }
          },
          // One list, top to bottom: nothing is pinned over the rows, so the
          // account actions at the end scroll into view like any other row.
          // Eager rather than lazy, so the month view and the premium card
          // keep their state while scrolled out of sight. The bottom inset is
          // padding inside the scroll, so the last row clears the home
          // indicator without a band of dead space under the list.
          child: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewPaddingOf(context).bottom + 16.h,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isTablet)
                    Padding(
                      padding: EdgeInsets.only(left: 8.sp, top: 8.h),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox.square(
                          dimension: 48,
                          child: IconButton(
                            tooltip: 'Close menu',
                            padding: EdgeInsets.zero,
                            color: context.colors.iconPrimary,
                            icon: const Icon(Icons.menu_rounded, size: 24),
                            onPressed: () {
                              HapticFeedbackService.buttonPress();
                              Navigator.of(context).pop();
                            },
                          ),
                        ),
                      ),
                    )
                  else
                    SizedBox(height: 16.h),

                  // User profile header (avatar + name + PRO mark)
                  const _UserProfileHeader(),
                  SizedBox(height: 8.h),

                  // The calendar left the bottom bar for here: a compact
                  // month that opens the full calendar on a tapped day.
                  SidebarMonthCalendar(
                    onDaySelected: (day) => _openCalendar(context, day),
                    onOpenFullCalendar: () => _openCalendar(context, null),
                  ),
                  SizedBox(height: 8.h),

                  // Menu items
                  //
                  // Each utility SVG is shipped with white-ish tints baked
                  // in (looks correct on the dark drawer). In light theme
                  // that bakes a white-on-light-grey contrast bug, so we
                  // recolour to `iconPrimary` only when the theme is light;
                  // dark theme renders the asset unchanged.
                  _MenuItem(
                    key: e2eKey(E2eIds.drawerBoard),
                    customIcon: BoardNavigationIcon(
                      size: 20.sp,
                      semanticsLabel: 'Board Icon',
                    ),
                    icon: Icons.grid_view_rounded,
                    title: 'Board',
                    textStyle: AppTypography.textSmMedium.copyWith(
                      color: context.colors.iconPrimary,
                      height: 1.0,
                      letterSpacing: -0.14,
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      callbacks.onBoardPressed();
                    },
                    showChevron: true,
                  ),
                  _MenuItem(
                    icon: Icons.leaderboard_outlined,
                    title: 'Rankings',
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
                    // The streak mark itself, at the size of its
                    // neighbours' icons.
                    customIcon: SizedBox.square(
                      dimension: 22.ic,
                      child: Center(
                        child: PixelFlame(streak: 5, size: 20.ic),
                      ),
                    ),
                    title: 'Streaks',
                    textStyle: AppTypography.textSmRegular.copyWith(
                      color: context.colors.iconPrimary,
                      height: 20.h / 14.h,
                    ),
                    onPressed: () {
                      final navigator = Navigator.of(context);
                      navigator.pop();
                      final open = callbacks.onStreaksPressed;
                      if (open != null) {
                        open();
                      } else {
                        navigator.push(
                          MaterialPageRoute<void>(
                            builder: (_) => const StreaksScreen(),
                          ),
                        );
                      }
                    },
                    showChevron: true,
                  ),
                  _MenuItem(
                    icon: Icons.desktop_mac_outlined,
                    title: 'Desktop',
                    textStyle: AppTypography.textSmRegular.copyWith(
                      color: context.colors.iconPrimary,
                      height: 20.h / 14.h,
                    ),
                    onPressed: () async {
                      final uri = Uri.parse(
                        'https://chessever.com/desktop',
                      );
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    showChevron: true,
                  ),

                  _MenuItem(
                    key: e2eKey(E2eIds.drawerSettings),
                    customIcon: SvgWidget(
                      SvgAsset.settings,
                      semanticsLabel: 'Settings Icon',
                      height: 20.ic,
                      width: 20.ic,
                      colorFilter:
                          context.isLightTheme
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
                      semanticsLabel: 'Feedback Icon',
                      height: 20.ic,
                      width: 20.ic,
                      colorFilter:
                          context.isLightTheme
                              ? ColorFilter.mode(
                                context.colors.iconPrimary,
                                BlendMode.srcIn,
                              )
                              : null,
                    ),
                    icon: Icons.rate_review_outlined,
                    title: 'Feedback',
                    textStyle: AppTypography.textSmRegular.copyWith(
                      color: context.colors.iconPrimary,
                      height: 20.h / 14.h,
                    ),
                    onPressed: () {
                      ReviewPromptService.instance.openSidebarDirectFeedback(
                        context,
                      );
                    },
                    showChevron: true,
                  ),
                  _MenuItem(
                    icon: Icons.star_outline,
                    title: 'Rate',
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
                      height: 20.ic,
                      width: 20.ic,
                      colorFilter:
                          context.isLightTheme
                              ? ColorFilter.mode(
                                context.colors.iconPrimary,
                                BlendMode.srcIn,
                              )
                              : null,
                    ),
                    title: 'About',
                    textStyle: AppTypography.textSmRegular.copyWith(
                      color: context.colors.iconPrimary,
                      height: 20.h / 14.h,
                    ),
                    onPressed: () {
                      _showAboutDialog(context, versionString);
                    },
                    showChevron: true,
                  ),

                  // Account: the upgrade offer, restore and sign-out close
                  // the list, set apart by space rather than a rule.
                  SizedBox(height: 16.h),
                  const _GetPremiumCard(),
                  const _RestorePurchasesRow(),
                  _LogOutButton(
                    key: e2eKey(E2eIds.drawerLogout),
                    onLogoutPressed: callbacks.onLogoutPressed,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// User profile header: avatar, display name and, for subscribers, a PRO
/// mark. Opens My Profile.
class _UserProfileHeader extends ConsumerWidget {
  const _UserProfileHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final subscriptionState = ref.watch(subscriptionProvider);
    final isPremium = subscriptionState.isSubscribed;
    final name = user?.displayName?.trim();
    final displayName = (name?.isNotEmpty ?? false) ? name! : 'Guest';

    // Opens My Profile for everyone. Subscribers used to land straight on
    // Manage Subscription here; that sheet now sits on the profile's plan row.
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedbackService.navigation();
          final navigator = Navigator.of(context);
          navigator.pop();
          navigator.push(
            MaterialPageRoute<void>(builder: (_) => const MyProfileScreen()),
          );
        },
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
                    Flexible(
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
                    if (isPremium) ...[SizedBox(width: 8.w), const _ProMark()],
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Icon(
                Icons.chevron_right_outlined,
                color: context.colors.iconSecondary,
                size: 22.ic,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "PRO" beside a subscriber's name: set in accent ink, no capsule around it.
class _ProMark extends StatelessWidget {
  const _ProMark();

  @override
  Widget build(BuildContext context) {
    return Text(
      'PRO',
      style: AppTypography.textXsRegular.copyWith(
        color: context.colors.accentText,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// The session's "not now" on the upgrade card. Kept outside the card so it
/// survives the drawer closing; a fresh launch offers the card again.
final _premiumCardDismissedProvider = StateProvider<bool>((ref) => false);

/// Scales its child to 0.97 while pressed and back on release, on a spring
/// that can be interrupted mid-way. Reduced motion snaps instead.
class _PressScale extends StatefulWidget {
  const _PressScale({required this.onTap, required this.child, super.key});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  static const _press = CupertinoMotion.snappy(
    duration: Duration(milliseconds: 260),
  );

  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: SingleMotionBuilder(
        motion: _press,
        value: _pressed ? 0.97 : 1.0,
        active: !MediaQuery.disableAnimationsOf(context),
        builder:
            (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
        child: widget.child,
      ),
    );
  }
}

/// The upgrade offer for non-subscribers, at the foot of the list.
class _GetPremiumCard extends ConsumerWidget {
  const _GetPremiumCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPremium = ref.watch(subscriptionProvider).isSubscribed;
    final dismissed = ref.watch(_premiumCardDismissedProvider);
    if (isPremium || dismissed) return const SizedBox.shrink();

    final colors = context.colors;
    // Title over button, not beside it: the phone drawer is 238 wide on a
    // 360dp phone, and "Get Premium" beside Upgrade and the dismiss cross
    // broke mid-word there. Stacked, the title keeps one line up to a large
    // text scale and the button keeps its full label.
    return Padding(
      padding: EdgeInsets.fromLTRB(16.sp, 0, 16.sp, 8.sp),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12.br),
        ),
        child: Padding(
          padding: EdgeInsets.only(left: 12.sp, right: 2.sp, bottom: 6.sp),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Get Premium',
                      maxLines: 2,
                      style: AppTypography.textSmSemiBold.copyWith(
                        color: colors.iconPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    onPressed: () {
                      HapticFeedbackService.buttonPress();
                      ref.read(_premiumCardDismissedProvider.notifier).state =
                          true;
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    color: colors.iconSecondary,
                    icon: Icon(Icons.close_rounded, size: 18.ic),
                  ),
                ],
              ),
              // Calls showPremiumPaywallSheet directly instead of
              // requirePremiumGuard because the guard short-circuits to
              // `true` in kDebugMode, which made this button silently no-op
              // for anyone running a debug build.
              Semantics(
                button: true,
                child: _PressScale(
                  key: e2eKey(E2eIds.drawerPremium),
                  onTap: () async {
                    HapticFeedbackService.buttonPress();
                    final authOk = await requireFullAuthGuard(context);
                    if (!authOk || !context.mounted) return;
                    await showPremiumPaywallSheet(context: context);
                  },
                  // 44 tall to tap; the fill sits inside it.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Center(
                      widthFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.brand,
                          borderRadius: BorderRadius.circular(8.br),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14.sp,
                            vertical: 7.sp,
                          ),
                          child: Text(
                            'Upgrade',
                            style: AppTypography.textXsMedium.copyWith(
                              color: colors.inkOnAccent,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Restore purchases, kept for App Store compliance. A plain row in the list,
/// in secondary ink so it reads quieter than the destinations above it.
class _RestorePurchasesRow extends ConsumerWidget {
  const _RestorePurchasesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = context.colors.textSecondary;
    return _MenuItem(
      icon: Icons.restore_rounded,
      iconColor: ink,
      title: 'Restore purchases',
      textStyle: AppTypography.textSmRegular.copyWith(
        color: ink,
        height: 20.h / 14.h,
      ),
      onPressed: () async {
        final success =
            await ref.read(subscriptionProvider.notifier).restorePurchases();
        if (context.mounted) {
          showAppSnack(
            context,
            success ? 'Purchases restored' : 'No purchases found to restore',
            tone: success ? AppSnackTone.success : AppSnackTone.neutral,
          );
        }
      },
    );
  }
}

/// Log out, or Sign up for a guest.
class _LogOutButton extends ConsumerWidget {
  const _LogOutButton({required this.onLogoutPressed, super.key});

  final VoidCallback? onLogoutPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Selected, not read off currentUserProvider: AppUser equality is by id,
    // so a guest upgrading in place would not rebuild this row.
    final isAnonymous = ref.watch(
      authStateProvider.select(
        (auth) => auth.valueOrNull?.user?.isAnonymous == true,
      ),
    );
    final colors = context.colors;
    final ink = isAnonymous ? colors.iconPrimary : colors.danger;

    // A row like every other: its icon and label sit on the same lines as
    // the destinations above, only the ink differs.
    return _MenuItem(
      icon: isAnonymous ? Icons.person_add_outlined : Icons.logout,
      iconColor: ink,
      title: isAnonymous ? 'Sign up' : 'Log out',
      textStyle: AppTypography.textSmMedium.copyWith(
        color: ink,
        height: 20.h / 14.h,
      ),
      onPressed: onLogoutPressed,
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    this.icon,
    this.iconColor,
    this.customIcon,
    required this.title,
    this.showChevron = false,
    this.onPressed,
    this.textStyle,
    super.key,
  });

  final IconData? icon;

  /// Ink for [icon]; defaults to primary ink at 80%.
  final Color? iconColor;
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
        // Every mark sits in the same 22 square, so labels start on one line
        // whatever the icon's own size.
        SizedBox.square(
          dimension: 22.ic,
          child: Center(
            child:
                customIcon ??
                Icon(
                  icon,
                  color:
                      iconColor ??
                      context.colors.iconPrimary.withValues(alpha: 0.8),
                  size: 22.ic,
                ),
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          // Two lines before anything is cut: "Restore purchases" at a large
          // text scale does not fit the phone drawer on one.
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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
            color: context.colors.iconSecondary,
            size: 22.ic,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Menu items: InkWell wraps the full Padding so the 4 sp vertical gaps
    // above/below are part of the tap surface (larger hit area, same UI).
    // The mark starts 16 in, on the edge the avatar, the month and the
    // upgrade card share, so the drawer has one left margin.
    return Semantics(
      button: true,
      child: InkWell(
        onTap: _onTap,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(1000),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: 4.sp,
            right: 8.sp,
            top: 4.sp,
            bottom: 4.sp,
          ),
          // A floor, not a fixed height: `44.h` is 33 on a short phone, and a
          // row that wraps at a large text scale needs to grow.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.sp),
              child: _buildRowContent(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// About: the app mark, its version and three links.
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
    final colors = context.colors;
    final iconSide = 56.ic;
    final iconPixels = (iconSide * MediaQuery.devicePixelRatioOf(context))
        .round();
    return Container(
      constraints: BoxConstraints(maxWidth: 340.w),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(24.sp, 28.sp, 24.sp, 8.sp),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    'assets/app_icon.png',
                    width: iconSide,
                    height: iconSide,
                    fit: BoxFit.cover,
                    cacheWidth: iconPixels,
                    cacheHeight: iconPixels,
                  ),
                ),
                SizedBox(height: 16.h),
                Text(
                  'ChessEver',
                  style: AppTypography.textXlBold.copyWith(
                    color: colors.iconPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'Version $version',
                  style: AppTypography.textSmRegular.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Links section
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
            child: Column(
              children: [
                _LinkButton(
                  // X's own mark, not a stand-in globe.
                  mark: SvgWidget(
                    SvgAsset.xLogo,
                    width: 18.ic,
                    height: 18.ic,
                    colorFilter: ColorFilter.mode(
                      colors.iconPrimary,
                      BlendMode.srcIn,
                    ),
                  ),
                  label: 'Follow us on X',
                  subtitle: '@chesseverapp',
                  onTap: () {
                    HapticFeedbackService.buttonPress();
                    _launchUrl('https://x.com/chesseverapp');
                  },
                ),
                _LinkButton(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Privacy Policy',
                  subtitle: 'How we protect your data',
                  onTap: () {
                    HapticFeedbackService.buttonPress();
                    _launchUrl('https://chessever.com/privacy-policy');
                  },
                ),
                _LinkButton(
                  icon: Icons.email_outlined,
                  label: 'Contact us',
                  subtitle: 'info@chessever.com',
                  onTap: () {
                    HapticFeedbackService.buttonPress();
                    _launchEmail();
                  },
                ),
              ],
            ),
          ),

          // Close button
          Padding(
            padding: EdgeInsets.fromLTRB(20.sp, 4.sp, 20.sp, 20.sp),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  HapticFeedbackService.buttonPress();
                  Navigator.of(context).pop();
                },
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  backgroundColor: colors.surface,
                  foregroundColor: colors.iconPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Close',
                  style: AppTypography.textSmMedium.copyWith(
                    color: colors.iconPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One link row in About: a bare icon, a label over a line of detail, and a
/// chevron. No box around it; the row is the tap target.
class _LinkButton extends StatelessWidget {
  const _LinkButton({
    this.icon,
    this.mark,
    required this.label,
    required this.subtitle,
    required this.onTap,
  }) : assert(icon != null || mark != null);

  final IconData? icon;

  /// A drawn mark in place of [icon], such as a brand's own logo.
  final Widget? mark;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 22.ic,
                  child: Center(
                    child:
                        mark ??
                        Icon(icon, size: 22.ic, color: colors.iconPrimary),
                  ),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppTypography.textSmMedium.copyWith(
                          color: colors.iconPrimary,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        subtitle,
                        style: AppTypography.textXsRegular.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20.ic,
                  color: colors.iconSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
