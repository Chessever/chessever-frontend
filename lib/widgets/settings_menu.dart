import 'package:flutter/material.dart';

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
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Determine appropriate font sizes based on screen size
    final double headerFontSize =
        isSmallScreen ? 16 : (isLargeScreen ? 22 : 18);
    final double sectionPadding = isSmallScreen ? 8 : (isLargeScreen ? 24 : 16);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: sectionPadding,
              top: isSmallScreen ? 4 : 8,
              bottom: isSmallScreen ? 12 : 16,
            ),
            child: Text(
              'Preferences',
              style: TextStyle(
                color: Colors.white,
                fontSize: headerFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _buildSettingsCard(
            context,
            title: 'Board Settings',
            subtitle: 'Piece style, board theme, move highlighting',
            icon: Icons.grid_4x4,
            onTap: onBoardSettingsPressed,
          ),
          _buildSettingsCard(
            context,
            title: 'Language',
            subtitle: languageSubtitle,
            icon: Icons.language,
            onTap: onLanguagePressed,
          ),
          _buildSettingsCard(
            context,
            title: 'Timezone',
            subtitle: timezoneSubtitle,
            icon: Icons.access_time,
            onTap: onTimezonePressed,
          ),
          _buildSwitchCard(
            context,
            title: 'Notifications',
            subtitle: notificationsEnabled ? 'Enabled' : 'Disabled',
            icon: Icons.notifications,
            value: notificationsEnabled,
            onChanged: (value) {
              onNotificationsPressed?.call();
            },
          ),
          SizedBox(height: isSmallScreen ? 16 : 24),
          Padding(
            padding: EdgeInsets.only(
              left: sectionPadding,
              top: isSmallScreen ? 4 : 8,
              bottom: isSmallScreen ? 12 : 16,
            ),
            child: Text(
              'About',
              style: TextStyle(
                color: Colors.white,
                fontSize: headerFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _buildAboutCard(
            context,
            title: 'ChessEver',
            subtitle: 'Version 1.0.0',
          ),
          SizedBox(height: isSmallScreen ? 16 : 24),
        ],
      ),
    );
  }

  Widget _buildSettingsCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    // Determine appropriate sizes based on screen size
    final double iconSize = isSmallScreen ? 20 : (isLargeScreen ? 28 : 24);
    final double titleFontSize = isSmallScreen ? 14 : (isLargeScreen ? 18 : 16);
    final double subtitleFontSize =
        isSmallScreen ? 12 : (isLargeScreen ? 16 : 14);
    final EdgeInsets cardMargin = EdgeInsets.symmetric(
      vertical: isSmallScreen ? 4 : 6,
      horizontal: isSmallScreen ? 4 : 8,
    );

    return Card(
      color: const Color(0xFF0C0C0E),
      margin: cardMargin,
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 12 : 16,
          vertical: isSmallScreen ? 4 : 8,
        ),
        leading: Icon(icon, color: Colors.white, size: iconSize),
        title: Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: titleFontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.grey, fontSize: subtitleFontSize),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: Colors.white,
          size: isSmallScreen ? 16 : 20,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildSwitchCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    // Determine appropriate sizes based on screen size
    final double iconSize = isSmallScreen ? 20 : (isLargeScreen ? 28 : 24);
    final double titleFontSize = isSmallScreen ? 14 : (isLargeScreen ? 18 : 16);
    final double subtitleFontSize =
        isSmallScreen ? 12 : (isLargeScreen ? 16 : 14);
    final EdgeInsets cardMargin = EdgeInsets.symmetric(
      vertical: isSmallScreen ? 4 : 6,
      horizontal: isSmallScreen ? 4 : 8,
    );

    return Card(
      color: const Color(0xFF0C0C0E),
      margin: cardMargin,
      child: SwitchListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 12 : 16,
          vertical: isSmallScreen ? 4 : 8,
        ),
        secondary: Icon(icon, color: Colors.white, size: iconSize),
        title: Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: titleFontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.grey, fontSize: subtitleFontSize),
        ),
        value: value,
        activeColor: Colors.cyan,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildAboutCard(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    // Determine appropriate sizes based on screen size
    final double iconSize = isSmallScreen ? 32 : (isLargeScreen ? 56 : 48);
    final double titleFontSize = isSmallScreen ? 16 : (isLargeScreen ? 22 : 18);
    final double subtitleFontSize =
        isSmallScreen ? 12 : (isLargeScreen ? 16 : 14);
    final double buttonFontSize =
        isSmallScreen ? 12 : (isLargeScreen ? 16 : 14);
    final EdgeInsets cardMargin = EdgeInsets.symmetric(
      vertical: isSmallScreen ? 4 : 6,
      horizontal: isSmallScreen ? 4 : 8,
    );
    final EdgeInsets contentPadding = EdgeInsets.symmetric(
      vertical: isSmallScreen ? 12 : 16,
      horizontal: isSmallScreen ? 12 : 16,
    );

    return Card(
      color: const Color(0xFF0C0C0E),
      margin: cardMargin,
      child: Padding(
        padding: contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: isSmallScreen ? 4 : 8),
            Icon(Icons.sports_esports, color: Colors.white, size: iconSize),
            SizedBox(height: isSmallScreen ? 8 : 16),
            Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: titleFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: isSmallScreen ? 4 : 8),
            Text(
              subtitle,
              style: TextStyle(color: Colors.grey, fontSize: subtitleFontSize),
            ),
            SizedBox(height: isSmallScreen ? 4 : 8),
            TextButton(
              onPressed: () {},
              child: Text(
                'Privacy Policy',
                style: TextStyle(color: Colors.cyan, fontSize: buttonFontSize),
              ),
            ),
            TextButton(
              onPressed: () {},
              child: Text(
                'Terms of Service',
                style: TextStyle(color: Colors.cyan, fontSize: buttonFontSize),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
