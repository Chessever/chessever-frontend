import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:flutter/material.dart';

void showSimpleDialog({
  required BuildContext context,
  String title = 'Notice',
  required String message,
  String buttonText = 'OK',
}) {
  showAlertModal<void>(
    context: context,
    child: PopupGlass(
      width: double.infinity,
      padding: EdgeInsets.all(24.sp),
      borderRadius: BorderRadius.circular(16.br),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: AppTypography.textMdBold.copyWith(
              color: context.colors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 12.h),
          Text(
            message,
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 24.h),
          SizedBox(
            width: double.infinity,
            height: 44.h,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: kBlackColor,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.br),
                ),
              ),
              child: Text(
                buttonText,
                style: AppTypography.textSmBold.copyWith(color: kBlackColor),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
