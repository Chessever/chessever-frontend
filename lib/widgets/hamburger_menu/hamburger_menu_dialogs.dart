import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/blur_background.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/hamburger_menu/settings_dialog.dart';

void showSettingsDialog(BuildContext context) {
  // Close drawer if open
  Navigator.pop(context);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    // backgroundColor: Colors.transparent,
    builder: (BuildContext bottomSheetContext) {
      final bottomPadding = MediaQuery.of(bottomSheetContext).viewInsets.bottom;

      return Padding(
        padding: EdgeInsets.only(
          // left: 24.w,
          // right: 24.w,
          bottom: bottomPadding + 24.h,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          child: Container(
            color: kPopUpColor,
            child: IntrinsicHeight(
              // Prevent it from expanding full height
              child: SingleChildScrollView(child: const SettingsDialog()),
            ),
          ),
        ),
      );
    },
  );
}
