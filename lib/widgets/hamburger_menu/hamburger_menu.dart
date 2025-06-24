import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/icons/analysis_board_icon.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

class HamburgerMenu extends StatelessWidget {
  final VoidCallback onSettingsPressed;
  final VoidCallback onPlayersPressed;
  final VoidCallback onFavoritesPressed;
  final VoidCallback onCountrymanPressed;
  final VoidCallback onAnalysisBoardPressed;
  final VoidCallback onSupportPressed;
  final VoidCallback onPremiumPressed;
  final VoidCallback onLogoutPressed;

  const HamburgerMenu({
    super.key,
    required this.onSettingsPressed,
    required this.onPlayersPressed,
    required this.onFavoritesPressed,
    required this.onCountrymanPressed,
    required this.onAnalysisBoardPressed,
    required this.onSupportPressed,
    required this.onPremiumPressed,
    required this.onLogoutPressed,
  });

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
                    _buildMenuItem(
                      icon: Icons.settings,
                      customIcon: SvgWidget(
                        SvgAsset.settingsIcon,
                        semanticsLabel: 'Settings Icon',
                        height: 24,
                        width: 24,
                      ),
                      title: 'Settings',
                      onPressed: onSettingsPressed,
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
                      onPressed: onPlayersPressed,
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
                      onPressed: onFavoritesPressed,
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
                      onPressed: onFavoritesPressed,
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
                    _buildMenuItem(
                      color: kBlack2Color,
                      // Premium color
                      customIcon: Image.asset(
                        PngAsset.premiumIcon,
                        width: 28,
                        height: 28,
                        fit: BoxFit.contain,
                      ),
                      title: 'Try Premium for free',
                      onPressed: onPremiumPressed,
                      showChevron: false,
                    ),
                  ],
                ),
              ),
              _buildLogoutButton(
                onPressed: () {
                  // Close the drawer first
                  Navigator.pop(context);
                  // Still call the original callback if provided
                  if (onLogoutPressed != null) {
                    onLogoutPressed!();
                  }
                },
              ),
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
    Color? color,
  }) {
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

  Widget _buildLogoutButton({VoidCallback? onPressed}) {
    return InkWell(
      onTap: onPressed,
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
