import 'package:flutter/material.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/hamburger_menu/settings_dialog.dart';

/// Helper class to show settings dialog from the hamburger menu
class HamburgerMenuDialogs {
  /// Shows the settings dialog
  static void showSettingsDialog(BuildContext context) {
    // First close the drawer if it's open
    Navigator.pop(context);

    // Then show the settings dialog
    showAlertModal(
      context: context,
      backgroundColor: kPopUpColor,
      barrierColor: Colors.black.withOpacity(0.3),
      child: const SettingsDialog(),
    );
  }
}
