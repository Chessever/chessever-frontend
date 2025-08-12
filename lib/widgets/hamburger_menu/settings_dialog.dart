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
    Future.delayed(const Duration(milliseconds: 100), () {
      showModalBottomSheet(
        context: context,
        isScrollControlled: false,
        builder: (BuildContext context) {
          return Builder(
            builder: (BuildContext newContext) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(newContext).viewInsets.bottom,
                ),
                child: Wrap(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: kPopUpColor,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20.sp),
                        ),
                      ),
                      child: SafeArea(top: false, child: child),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsSettings = ref.watch(notificationsSettingsProvider);
    final localeName = ref.watch(localeNameProvider);
    final timezone = ref.watch(timezoneProvider);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(20.sp)),
        color: kPopUpColor,
      ),
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
            () => _showSubDialog(context, const BoardSettingsDialog()),
        onLanguagePressed:
            () => _showSubDialog(context, const LanguageSettingsDialog()),
        onTimezonePressed:
            () => _showSubDialog(context, const TimezoneSettingsDialog()),
        onNotificationsPressed: () {
          ref.read(notificationsSettingsProvider.notifier).toggleEnabled();
        },
      ),
    );
  }
}
