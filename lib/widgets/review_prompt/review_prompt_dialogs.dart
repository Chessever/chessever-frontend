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

/// Feature suggestions for the survey - users can quick-tap these
const List<String> _featureSuggestions = [
  'Offline mode',
  'Opening preparation',
  'Advanced analysis',
  'Player tracking',
];

Future<String?> showAppFeedbackDialog(
  BuildContext context, {
  required int rating,
}) {
  final isHighRating = rating >= 4;

  return showDialog<String?>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      final controller = TextEditingController();
      bool canSubmit = false;
      final selectedFeatures = <String>{};

      return StatefulBuilder(
        builder: (context, setState) {
          // Update canSubmit based on text or selected features
          void updateCanSubmit() {
            setState(() {
              canSubmit = controller.text.trim().isNotEmpty ||
                  selectedFeatures.isNotEmpty;
            });
          }

          // Build the feedback string from selections + text
          String buildFeedback() {
            final parts = <String>[];
            if (selectedFeatures.isNotEmpty) {
              parts.add('Interested in: ${selectedFeatures.join(', ')}');
            }
            if (controller.text.trim().isNotEmpty) {
              parts.add(controller.text.trim());
            }
            return parts.join('\n\n');
          }

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
                  // Rating-aware header
                  Text(
                    isHighRating ? 'Thanks for the love!' : 'Thanks for the feedback',
                    style: AppTypography.textLgBold.copyWith(
                      color: kWhiteColor,
                    ),
                  ),
                  SizedBox(height: 4.sp),
                  Text(
                    isHighRating
                        ? 'What premium feature would you love to see?'
                        : 'What can we do better?',
                    style: AppTypography.textSmRegular.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.6),
                    ),
                  ),
                  SizedBox(height: 12.sp),
                  // Star rating display
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
                  SizedBox(height: 16.sp),
                  // Quick-tap feature suggestions (only for high ratings)
                  if (isHighRating) ...[
                    Text(
                      'Quick picks (tap to select)',
                      style: AppTypography.textXsRegular.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.5),
                      ),
                    ),
                    SizedBox(height: 8.sp),
                    Wrap(
                      spacing: 8.sp,
                      runSpacing: 8.sp,
                      children: _featureSuggestions.map((feature) {
                        final isSelected = selectedFeatures.contains(feature);
                        return GestureDetector(
                          onTap: () {
                            HapticFeedbackService.selection();
                            setState(() {
                              if (isSelected) {
                                selectedFeatures.remove(feature);
                              } else {
                                selectedFeatures.add(feature);
                              }
                            });
                            updateCanSubmit();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: EdgeInsets.symmetric(
                              horizontal: 12.sp,
                              vertical: 8.sp,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? kPrimaryColor.withValues(alpha: 0.15)
                                  : kWhiteColor.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(20.br),
                              border: Border.all(
                                color: isSelected
                                    ? kPrimaryColor.withValues(alpha: 0.5)
                                    : kWhiteColor.withValues(alpha: 0.1),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              feature,
                              style: AppTypography.textXsMedium.copyWith(
                                color: isSelected
                                    ? kPrimaryColor
                                    : kWhiteColor.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 12.sp),
                  ],
                  // Text input
                  TextField(
                    controller: controller,
                    onChanged: (_) => updateCanSubmit(),
                    maxLines: isHighRating ? 3 : 5,
                    minLines: isHighRating ? 2 : 3,
                    maxLength: 500,
                    style: AppTypography.textSmRegular.copyWith(
                      color: kWhiteColor,
                    ),
                    decoration: InputDecoration(
                      hintText: isHighRating
                          ? 'Or share your own feature idea...'
                          : 'Tell us what went wrong or what we can improve...',
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
                  // Action buttons
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
                            'Skip',
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
                                    Navigator.of(context).pop(buildFeedback());
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
