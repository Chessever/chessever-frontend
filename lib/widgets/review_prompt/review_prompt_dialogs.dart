import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

Future<int?> showAppRatingDialog(BuildContext context) {
  return showDialog<int>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      int selectedRating = 0;

      return StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              constraints: BoxConstraints(maxWidth: 340.w),
              padding: EdgeInsets.all(20.sp),
              decoration: BoxDecoration(
                color: kBackgroundColor,
                borderRadius: BorderRadius.circular(20.br),
                border: Border.all(
                  color: kWhiteColor.withValues(alpha: 0.08),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.star_rounded,
                    color: kPrimaryColor,
                    size: 42.ic,
                  ),
                  SizedBox(height: 12.sp),
                  Text(
                    'Enjoying ChessEver?',
                    style: AppTypography.textLgBold.copyWith(
                      color: kWhiteColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 6.sp),
                  Text(
                    'Tap a star to rate your experience',
                    style: AppTypography.textSmRegular.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16.sp),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final isActive = index < selectedRating;
                      return IconButton(
                        onPressed: () {
                          HapticFeedbackService.selection();
                          setState(() {
                            selectedRating = index + 1;
                          });
                        },
                        icon: Icon(
                          isActive
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color:
                              isActive
                                  ? kPrimaryColor
                                  : kWhiteColor.withValues(alpha: 0.35),
                          size: 30.ic,
                        ),
                      );
                    }),
                  ),
                  SizedBox(height: 12.sp),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 12.sp),
                            backgroundColor: kWhiteColor.withValues(alpha: 0.04),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.br),
                            ),
                          ),
                          child: Text(
                            'Not now',
                            style: AppTypography.textSmMedium.copyWith(
                              color: kWhiteColor.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 10.sp),
                      Expanded(
                        child: TextButton(
                          onPressed:
                              selectedRating == 0
                                  ? null
                                  : () {
                                    Navigator.of(context).pop(selectedRating);
                                  },
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 12.sp),
                            backgroundColor:
                                selectedRating == 0
                                    ? kDarkGreyColor
                                    : kPrimaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.br),
                            ),
                          ),
                          child: Text(
                            'Continue',
                            style: AppTypography.textSmMedium.copyWith(
                              color: kBlackColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Future<String?> showAppFeedbackDialog(
  BuildContext context, {
  required int rating,
}) {
  return showDialog<String?>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      final controller = TextEditingController();
      bool canSubmit = false;

      return StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              constraints: BoxConstraints(maxWidth: 360.w),
              padding: EdgeInsets.all(20.sp),
              decoration: BoxDecoration(
                color: kBackgroundColor,
                borderRadius: BorderRadius.circular(20.br),
                border: Border.all(
                  color: kWhiteColor.withValues(alpha: 0.08),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Thanks for the rating',
                    style: AppTypography.textLgBold.copyWith(
                      color: kWhiteColor,
                    ),
                  ),
                  SizedBox(height: 4.sp),
                  Text(
                    'What could we improve?',
                    style: AppTypography.textSmRegular.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.6),
                    ),
                  ),
                  SizedBox(height: 12.sp),
                  Row(
                    children: List.generate(5, (index) {
                      final isActive = index < rating;
                      return Icon(
                        isActive
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color:
                            isActive
                                ? kPrimaryColor
                                : kWhiteColor.withValues(alpha: 0.25),
                        size: 18.ic,
                      );
                    }),
                  ),
                  SizedBox(height: 12.sp),
                  TextField(
                    controller: controller,
                    onChanged: (value) {
                      final trimmed = value.trim();
                      setState(() {
                        canSubmit = trimmed.isNotEmpty;
                      });
                    },
                    maxLines: 5,
                    minLines: 3,
                    maxLength: 500,
                    style: AppTypography.textSmRegular.copyWith(
                      color: kWhiteColor,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Tell us what went wrong or what’s missing',
                      hintStyle: AppTypography.textSmRegular.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.35),
                      ),
                      filled: true,
                      fillColor: kBlack2Color,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.br),
                        borderSide: BorderSide(
                          color: kWhiteColor.withValues(alpha: 0.08),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.br),
                        borderSide: BorderSide(
                          color: kWhiteColor.withValues(alpha: 0.08),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.br),
                        borderSide: const BorderSide(color: kPrimaryColor),
                      ),
                      counterStyle: AppTypography.textXsRegular.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                  SizedBox(height: 12.sp),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 12.sp),
                            backgroundColor: kWhiteColor.withValues(alpha: 0.04),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.br),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: AppTypography.textSmMedium.copyWith(
                              color: kWhiteColor.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 10.sp),
                      Expanded(
                        child: TextButton(
                          onPressed:
                              canSubmit
                                  ? () {
                                    HapticFeedbackService.buttonPress();
                                    Navigator.of(context).pop(
                                      controller.text.trim(),
                                    );
                                  }
                                  : null,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 12.sp),
                            backgroundColor:
                                canSubmit ? kPrimaryColor : kDarkGreyColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.br),
                            ),
                          ),
                          child: Text(
                            'Send',
                            style: AppTypography.textSmMedium.copyWith(
                              color: kBlackColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
