import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/providers/notifications_settings_provider.dart';
import 'package:chessever2/providers/timezone_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/board_settings_dialog.dart';
import 'package:chessever2/widgets/language_settings_dialog.dart';
import 'package:chessever2/widgets/settings_menu.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:chessever2/widgets/timezone_settings_dialog.dart';
import 'package:chessever2/localization/locale_provider.dart';

class SettingsDialog extends ConsumerWidget {
  const SettingsDialog({super.key});

  void _showSubDialog(BuildContext context, Widget child) {
    // Close settings menu first
    Navigator.pop(context);

    // Add a small delay before showing the next dialog
    Future.delayed(Duration(milliseconds: 100), () {
      showAlertModal(
        context: context,
        horizontalPadding: 24.w,
        verticalPadding: 24.h,
        backgroundColor: kPopUpColor,
        barrierColor: Colors.black.withOpacity(0.3),
        child: child,
      );
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsSettings = ref.watch(notificationsSettingsProvider);
    final localeName = ref.watch(localeNameProvider);
    final timezone = ref.watch(timezoneProvider);

    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        decoration: BoxDecoration(
          color: kPopUpColor,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(12.br),
            topRight: Radius.circular(12.br),
            bottomLeft: Radius.circular(20.br),
            bottomRight: Radius.circular(20.br),
          ),
        ),
        margin: EdgeInsets.all(24.sp),
        child: SettingsMenu(
          notificationsEnabled: notificationsSettings.enabled,
          languageSubtitle: localeName,
          timezoneSubtitle: timezone.display,
          boardSettingsIcon: SvgWidget(
            height: 20.h,
            width: 20.w,
            SvgAsset.boardSettings,
          ),
          languageIcon: SvgWidget(
            height: 20.h,
            width: 20.w,
            SvgAsset.languageIcon,
          ),
          timezoneIcon: SvgWidget(
            height: 20.h,
            width: 20.w,
            SvgAsset.timezoneIcon,
          ),
          onBoardSettingsPressed:
              () => _showSubDialog(context, BoardSettingsDialog()),
          onLanguagePressed:
              () => _showSubDialog(context, LanguageSettingsDialog()),
          onTimezonePressed:
              () => _showSubDialog(context, TimezoneSettingsDialog()),
          onNotificationsPressed: () {
            ref.read(notificationsSettingsProvider.notifier).toggleEnabled();
          },
        ),
      ),
    );
  }
}
