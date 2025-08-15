import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/hamburger_menu/hamburger_menu_dialogs.dart';
import 'package:chessever2/widgets/icons/analysis_board_icon.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
                    SizedBox(height: 12.h),
                    _MenuItem(
                      customIcon: SvgWidget(
                        SvgAsset.playersIcon,
                        semanticsLabel: 'Players Icon',
                        height: 24.h,
                        width: 24.w,
                      ),
                      title: 'Players',
                      onPressed: () {
                        Navigator.pop(context); // Close drawer first
                        callbacks.onPlayersPressed();
                      },
                    ),
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
                    // SizedBox(height: 12.h),
                    // _CountryMan(
                    //   onCountryManPressed: () {
                    //     Navigator.pop(context); // Close drawer first
                    //     callbacks.onCountrymanPressed();
                    //   },
                    // ),
                    // SizedBox(height: 12.h),
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
      onTap: onLogoutPressed,
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
      onTap: onPressed,
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

class _CountryMan extends ConsumerWidget {
  const _CountryMan({required this.onCountryManPressed, super.key});

  final VoidCallback onCountryManPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countryMan = ref.watch(countryDropdownProvider);
    return countryMan.when(
      data: (data) {
        return _MenuItem(
          customIcon: CountryFlag.fromCountryCode(
            data.countryCode,
            height: 12.h,
            width: 24.w,
            shape: RoundedRectangle(0),
          ),
          title: 'Countryman',
          textColors: kGreenColor,
          onPressed: onCountryManPressed,
          showChevron: false,
        );
      },
      error: (error, _) {
        return _MenuItem(
          customIcon: CountryFlag.fromCountryCode(
            'US',
            height: 12.h,
            width: 24.w,
            shape: RoundedRectangle(0),
          ),
          title: 'Countryman',
          onPressed: onCountryManPressed,
          showChevron: false,
        );
      },
      loading: () {
        return _MenuItem(
          customIcon: CountryFlag.fromCountryCode(
            'US',
            height: 12.h,
            width: 24.w,
            shape: RoundedRectangle(0),
          ),
          title: 'Countryman',
          onPressed: onCountryManPressed,
          showChevron: false,
        );
      },
    );
  }
}
