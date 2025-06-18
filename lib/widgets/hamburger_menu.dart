import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/icons/analysis_board_icon.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

class HamburgerMenu extends StatelessWidget {
  final VoidCallback? onSettingsPressed;
  final VoidCallback? onPlayersPressed;
  final VoidCallback? onFavoritesPressed;
  final VoidCallback? onCountrymanPressed;
  final VoidCallback? onAnalysisBoardPressed;
  final VoidCallback? onSupportPressed;
  final VoidCallback? onPremiumPressed;
  final VoidCallback? onLogoutPressed;

  const HamburgerMenu({
    super.key,
    this.onSettingsPressed,
    this.onPlayersPressed,
    this.onFavoritesPressed,
    this.onCountrymanPressed,
    this.onAnalysisBoardPressed,
    this.onSupportPressed,
    this.onPremiumPressed,
    this.onLogoutPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260, // Set fixed width for hamburger menu
      child: Drawer(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _buildMenuItem(
                      icon: Icons.settings,
                      customIcon: SvgWidget(
                        SvgAsset.settingsIcon,
                        semanticsLabel: 'Settings Icon',
                        height: 24,
                        width: 24,
                      ),
                      title: 'Settings',
                      onPressed: () {
                        // Close the drawer first
                        Navigator.pop(context);
                        // Navigate to settings page
                        Navigator.of(context).pushNamed('/settings');
                        // Still call the original callback if provided
                        if (onSettingsPressed != null) {
                          onSettingsPressed!();
                        }
                      },
                      showChevron: true,
                    ),
                    SizedBox(height: 12),
                    _buildMenuItem(
                      customIcon: SvgWidget(
                        SvgAsset.playersIcon,
                        semanticsLabel: 'Players Icon',
                        height: 24,
                        width: 24,
                      ),
                      title: 'Players',
                      onPressed: () {
                        // Close the drawer first
                        Navigator.pop(context);
                        // Navigate using the correct route name
                        Navigator.of(context).pushNamed('/playerList');
                        // Still call the original callback if provided
                        if (onPlayersPressed != null) {
                          onPlayersPressed!();
                        }
                      },
                      showChevron: false,
                    ),
                    SizedBox(height: 12),
                    _buildMenuItem(
                      customIcon: SvgWidget(
                        SvgAsset.favouriteIcon,
                        semanticsLabel: 'Fav Icon',
                        height: 24,
                        width: 24,
                      ),
                      title: 'Favorites',
                      onPressed: () {
                        // Close the drawer first
                        Navigator.pop(context);
                        // Navigate to favorites screen
                        Navigator.of(context).pushNamed('/favorites');
                        // Still call the original callback if provided
                        if (onFavoritesPressed != null) {
                          onFavoritesPressed!();
                        }
                      },
                      showChevron: false,
                    ),
                    SizedBox(height: 12),
                    _buildMenuItem(
                      customIcon: CountryFlag.fromCurrencyCode(
                        'USD',
                        height: 12,
                        width: 24,
                        shape: RoundedRectangle(0),
                      ),
                      title: 'Countryman',
                      onPressed: onCountrymanPressed,
                      showChevron: false,
                    ),
                    SizedBox(height: 12),
                    _buildMenuItem(
                      customIcon: AnalysisBoardIcon(size: 20),
                      title: 'Analysis Board',
                      onPressed: onAnalysisBoardPressed,
                      showChevron: false,
                    ),
                    SizedBox(height: 12),
                    _buildMenuItem(
                      customIcon: SvgWidget(
                        SvgAsset.headsetIcon,
                        semanticsLabel: 'Support Icon',
                        height: 24,
                        width: 24,
                      ),
                      title: 'Support',
                      onPressed: onSupportPressed,
                      showChevron: false,
                    ),
                    SizedBox(height: 12),
                    _buildPremiumItem(onPressed: onPremiumPressed),
                  ],
                ),
              ),
              _buildLogoutButton(onPressed: onLogoutPressed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    IconData? icon,
    Widget? customIcon,
    required String title,
    required bool showChevron,
    VoidCallback? onPressed,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 12),
      minLeadingWidth: 40,
      horizontalTitleGap: 4,
      leading: customIcon ?? Icon(icon, color: kWhiteColor, size: 24),
      title: Text(
        title,
        style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
      ),
      trailing:
          showChevron
              ? Padding(
                padding: EdgeInsets.only(right: 12),
                child: const Icon(
                  Icons.chevron_right_outlined,
                  color: kWhiteColor,
                  size: 24,
                ),
              )
              : null,
      onTap: onPressed,
    );
  }

  Widget _buildPremiumItem({VoidCallback? onPressed}) {
    return Container(
      alignment: Alignment.centerLeft,
      width: 260,
      decoration: BoxDecoration(color: kLightBlack),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 12),
        minLeadingWidth: 40,
        horizontalTitleGap: 4,
        leading: Image.asset(
          PngAsset.premiumIcon,
          width: 28,
          height: 28,
          fit: BoxFit.contain,
        ),
        title: Text(
          'Try Premium for free',
          style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
        ),
        onTap: onPressed,
      ),
    );
  }

  Widget _buildLogoutButton({VoidCallback? onPressed}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      leading: Icon(Icons.logout, color: Colors.white, size: 24),
      horizontalTitleGap: 24,
      title: Text(
        'Log out',
        style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
      ),
      onTap: onPressed,
    );
  }
}
