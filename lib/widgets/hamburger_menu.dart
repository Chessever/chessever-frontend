import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
      width: 240, // Set fixed width for hamburger menu
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
                      customIcon: SvgPicture.asset(
                        SvgAsset.settingsIcon,
                        semanticsLabel: 'Settings Icon',
                      ),
                      title: 'Settings',
                      onPressed: onSettingsPressed,
                      showChevron: true,
                    ),
                    _buildMenuItem(
                      icon: Icons.group,
                      title: 'Players',
                      onPressed: onPlayersPressed,
                      showChevron: false,
                    ),
                    _buildMenuItem(
                      customIcon: SvgPicture.asset(
                        SvgAsset.favouriteIcon,
                        semanticsLabel: 'Fav Icon',
                      ),
                      title: 'Favorites',
                      onPressed: onFavoritesPressed,
                      showChevron: false,
                    ),
                    _buildMenuItem(
                      customIcon: const Text(
                        '🇺🇸',
                        style: TextStyle(fontSize: 18),
                      ),
                      title: 'Countryman',
                      onPressed: onCountrymanPressed,
                      showChevron: false,
                    ),
                    _buildMenuItem(
                      customIcon: const Icon(
                        Icons.grid_view,
                        color: Color(0xFFADD8E6), // Light blue color
                        size: 24,
                      ),
                      title: 'Analysis Board',
                      onPressed: onAnalysisBoardPressed,
                      showChevron: false,
                    ),
                    _buildMenuItem(
                      customIcon: const Icon(
                        Icons.headset_mic,
                        color: Colors.white,
                        size: 24,
                      ),
                      title: 'Support',
                      onPressed: onSupportPressed,
                      showChevron: false,
                    ),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      minLeadingWidth: 40, // Set to 40px as requested
      horizontalTitleGap: 4,
      leading: SizedBox(
        width: 40, // Set fixed width for each item icon
        child: Center(
          child: customIcon ?? Icon(icon, color: kWhiteColor, size: 24),
        ),
      ),
      title: Text(
        title,
        style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
      ),
      trailing:
          showChevron
              ? const Icon(
                Icons.chevron_right_outlined,
                color: kWhiteColor,
                size: 24,
              )
              : null,
      onTap: onPressed,
    );
  }

  Widget _buildPremiumItem({VoidCallback? onPressed}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      decoration: const BoxDecoration(color: Color(0xFF222222)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        minLeadingWidth: 40, // Set to 40px as requested
        leading: SizedBox(
          width: 40, // Fixed width for premium icon
          child: Center(
            child: SvgPicture.asset(
              SvgAsset.premiumIcon,
              semanticsLabel: 'Premium Icon',
              width: 24,
              height: 24,
              fit: BoxFit.contain,
            ),
          ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12.0),
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onPressed,
        child: Row(
          children: [
            SizedBox(
              width: 40, // Fixed width for logout icon
              child: Center(
                child: const Icon(Icons.logout, color: Colors.white, size: 24),
              ),
            ),
            Text(
              'Log out',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
