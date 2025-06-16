import 'package:chessever2/providers/notifications_settings_provider.dart';
import 'package:chessever2/providers/timezone_provider.dart';
import 'package:chessever2/widgets/blur_background.dart';
import 'package:chessever2/widgets/board_settings_dialog.dart';
import 'package:chessever2/widgets/language_settings_dialog.dart';
import 'package:chessever2/widgets/notifications_settings_dialog.dart';
import 'package:chessever2/widgets/settings_menu.dart';
import 'package:chessever2/widgets/timezone_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../localization/locale_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get the current notification settings
    final notificationsSettings = ref.watch(notificationsSettingsProvider);
    // Get current locale for displaying language
    final localeName = ref.watch(localeNameProvider);
    // Get current timezone
    final timezone = ref.watch(timezoneProvider);

    // Determine screen size for responsive layout
    final Size screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 360;
    final bool isLargeScreen = screenSize.width > 600;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Colors.white,
            size: isSmallScreen ? 20 : (isLargeScreen ? 28 : 24),
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: isSmallScreen ? 18 : (isLargeScreen ? 24 : 20),
          ),
        ),
      ),
      body: Stack(
        children: [
          const BlurBackground(),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isLargeScreen ? 600 : double.infinity,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal:
                        isSmallScreen ? 8.0 : (isLargeScreen ? 24.0 : 16.0),
                    vertical: isSmallScreen ? 8.0 : 16.0,
                  ),
                  child: SettingsMenu(
                    notificationsEnabled: notificationsSettings.enabled,
                    languageSubtitle: localeName,
                    timezoneSubtitle: timezone.display,
                    isSmallScreen: isSmallScreen,
                    isLargeScreen: isLargeScreen,
                    onBoardSettingsPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => const BoardSettingsDialog(),
                      );
                    },
                    onLanguagePressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => const LanguageSettingsDialog(),
                      );
                    },
                    onTimezonePressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => const TimezoneSettingsDialog(),
                      );
                    },
                    onNotificationsPressed: () {
                      // Show notifications settings dialog for detailed options
                      showDialog(
                        context: context,
                        builder:
                            (context) => const NotificationsSettingsDialog(),
                      );
                    },
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
