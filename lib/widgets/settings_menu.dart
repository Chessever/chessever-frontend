import 'package:flutter/material.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';

class SettingsMenu extends StatelessWidget {
  final bool notificationsEnabled;
  final String languageSubtitle;
  final String timezoneSubtitle;
  final bool isSmallScreen;
  final bool isLargeScreen;
  final VoidCallback? onBoardSettingsPressed;
  final VoidCallback? onLanguagePressed;
  final VoidCallback? onTimezonePressed;
  final VoidCallback? onNotificationsPressed;
  final Widget? boardSettingsIcon;
  final Widget? languageIcon;
  final Widget? timezoneIcon;

  const SettingsMenu({
    Key? key,
    required this.notificationsEnabled,
    this.languageSubtitle = "English",
    this.timezoneSubtitle = "UTC+0",
    this.isSmallScreen = false,
    this.isLargeScreen = false,
    this.onBoardSettingsPressed,
    this.onLanguagePressed,
    this.onTimezonePressed,
    this.onNotificationsPressed,
    this.boardSettingsIcon,
    this.languageIcon,
    this.timezoneIcon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Determine appropriate font sizes based on screen size
    final double headerFontSize =
        isSmallScreen ? 16 : (isLargeScreen ? 22 : 18);
    final double sectionPadding = isSmallScreen ? 8 : (isLargeScreen ? 24 : 16);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _buildMenuItem(
          customIcon: boardSettingsIcon ?? Icon(Icons.grid_4x4, color: Colors.white, size: 24),
          title: 'Board Settings',
          subtitle: 'Piece style, board theme, move highlighting',
          onPressed: onBoardSettingsPressed,
          showChevron: true,
        ),
        SizedBox(height: 12),
        _buildMenuItem(
          customIcon: languageIcon ?? Icon(Icons.language, color: Colors.white, size: 24),
          title: 'Language',
          subtitle: languageSubtitle,
          onPressed: onLanguagePressed,
          showChevron: true,
        ),
        SizedBox(height: 12),
        _buildMenuItem(
          customIcon: timezoneIcon ?? Icon(Icons.access_time, color: Colors.white, size: 24),
          title: 'Timezone',
          subtitle: timezoneSubtitle,
          onPressed: onTimezonePressed,
          showChevron: true,
        ),
        SizedBox(height: 12),
        _buildSwitchItem(
          icon: Icons.notifications,
          title: 'Notifications',
          subtitle: notificationsEnabled ? 'Enabled' : 'Disabled',
          value: notificationsEnabled,
          onChanged: (value) {
            onNotificationsPressed?.call();
          },
        ),
      ],
    );
  }

  Widget _buildMenuItem({
    IconData? icon,
    Widget? customIcon,
    required String title,
    String? subtitle,
    required bool showChevron,
    VoidCallback? onPressed,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 12),
      minLeadingWidth: 40,
      horizontalTitleGap: 4,
      leading: customIcon ?? Icon(icon!, color: Colors.white, size: 24),
      title: Text(
        title,
        style: AppTypography.textSmMedium.copyWith(color: Colors.white),
      ),
      subtitle: subtitle != null 
          ? Text(
              subtitle,
              style: TextStyle(color: Colors.grey, fontSize: isSmallScreen ? 12 : 14),
            ) 
          : null,
      trailing: showChevron
          ? const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(
                Icons.chevron_right_outlined,
                color: Colors.white,
                size: 24,
              ),
            )
          : null,
      onTap: onPressed,
    );
  }

  Widget _buildSwitchItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.only(left: 12, right: 12),
      secondary: null, // Removed the icon to match the requirement
      title: Text(
        title,
        style: AppTypography.textSmMedium.copyWith(color: Colors.white),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey, fontSize: isSmallScreen ? 12 : 14),
      ),
      value: value,
      activeColor: const Color(0xFF0FB4E5),
      onChanged: onChanged,
    );
  }
}
