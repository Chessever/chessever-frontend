import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
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
      width: 260, // Set fixed width for hamburger menu
      child: Drawer(
        backgroundColor: kBackgroundColor,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    SizedBox(height: 24),
                    _MenuItem(
                      icon: Icons.settings,
                      customIcon: SvgWidget(
                        SvgAsset.settingsIcon,
                        semanticsLabel: 'Settings Icon',
                        height: 24,
                        width: 24,
                      ),
                      title: 'Settings',
                      onPressed:
                          () =>
                              HamburgerMenuDialogs.showSettingsDialog(context),
                      showChevron: true,
                    ),
                    SizedBox(height: 12),
                    _MenuItem(
                      customIcon: SvgWidget(
                        SvgAsset.playersIcon,
                        semanticsLabel: 'Players Icon',
                        height: 24,
                        width: 24,
                      ),
                      title: 'Players',
                      onPressed: () {
                        Navigator.pop(context); // Close drawer first
                        callbacks.onPlayersPressed();
                      },
                    ),
                    SizedBox(height: 12),
                    _MenuItem(
                      customIcon: SvgWidget(
                        SvgAsset.favouriteIcon,
                        semanticsLabel: 'Fav Icon',
                        height: 24,
                        width: 24,
                      ),
                      title: 'Favorites',
                      onPressed: () {
                        Navigator.pop(context); // Close drawer first
                        callbacks.onFavoritesPressed();
                      },
                    ),
                    SizedBox(height: 12),
                    _CountryMan(
                      onCountryManPressed: () {
                        Navigator.pop(context); // Close drawer first
                        callbacks.onCountrymanPressed();
                      },
                    ),
                    SizedBox(height: 12),
                    _MenuItem(
                      customIcon: AnalysisBoardIcon(size: 20),
                      title: 'Analysis Board',
                      onPressed: () {
                        Navigator.pop(context); // Close drawer first
                        callbacks.onAnalysisBoardPressed();
                      },
                    ),
                    SizedBox(height: 12),
                    _MenuItem(
                      customIcon: SvgWidget(
                        SvgAsset.headsetIcon,
                        semanticsLabel: 'Support Icon',
                        height: 24,
                        width: 24,
                      ),
                      title: 'Support',
                      onPressed: () {
                        Navigator.pop(context); // Close drawer first
                        callbacks.onSupportPressed();
                      },
                    ),
                    SizedBox(height: 12),
                    _MenuItem(
                      color: kBlack2Color,
                      // Premium color
                      customIcon: Image.asset(
                        PngAsset.premiumIcon,
                        width: 28,
                        height: 28,
                        fit: BoxFit.contain,
                      ),
                      title: 'Try Premium for free',
                      onPressed: () {
                        Navigator.pop(context); // Close drawer first
                        callbacks.onPremiumPressed();
                      },
                    ),
                  ],
                ),
              ),
              _LogOutButton(
                onLogoutPressed: () {
                  // Close the drawer first
                  Navigator.pop(context);
                  // Still call the original callback if provided
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
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        height: 48,
        child: Row(
          children: [
            Icon(Icons.logout, color: Colors.white, size: 24),
            SizedBox(width: 12),
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
    super.key,
  });

  final IconData? icon;
  final Widget? customIcon;
  final String title;
  final bool showChevron;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        color: color,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        height: 40,
        child: Row(
          children: [
            customIcon ?? Icon(icon, color: kWhiteColor, size: 24),
            SizedBox(width: 4),
            Text(
              title,
              style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
            ),
            Spacer(),
            showChevron
                ? Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: const Icon(
                    Icons.chevron_right_outlined,
                    color: kWhiteColor,
                    size: 24,
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
            height: 12,
            width: 24,
            shape: RoundedRectangle(0),
          ),
          title: 'Countryman',
          onPressed: onCountryManPressed,
          showChevron: false,
        );
      },
      error: (error, _) {
        return _MenuItem(
          customIcon: CountryFlag.fromCountryCode(
            'US',
            height: 12,
            width: 24,
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
            height: 12,
            width: 24,
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
