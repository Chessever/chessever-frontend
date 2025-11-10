import 'package:chessever2/screens/chessboard/chess_board_settings_page.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/settings_menu.dart';
import 'package:chessever2/widgets/svg_widget.dart';

class SettingsDialog extends ConsumerWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(20.sp)),
        color: kPopUpColor,
      ),
      child: SettingsMenu(
        boardSettingsIcon: SvgWidget(
          height: 20.h,
          width: 20.w,
          SvgAsset.boardSettings,
        ),
        onBoardSettingsPressed: () {
          // Close the current bottom sheet first
          Navigator.of(context).pop();

          // Navigate to the full ChessBoardSettingsPage
          Navigator.of(context).push(
            ChessBoardSettingsPage.route(),
          );
        },
      ),
    );
  }
}
