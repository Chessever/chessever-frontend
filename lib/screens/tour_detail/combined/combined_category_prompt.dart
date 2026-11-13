import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:flutter/material.dart';

/// The viewer's answer to "combine this event's categories?".
enum CombinePromptAnswer {
  /// Open the event in Combined.
  combine,

  /// Not for this event. It is not asked here again.
  notNow,

  /// Not for any event. Combined stays in the picker and the event menu.
  neverAsk,
}

/// Names the categories being merged, the way a person would list them:
/// "Group A, Group B, Group C and Group D", or the first three and a count.
@visibleForTesting
String combinedCategoryNames(List<String> labels) {
  final names = [
    for (final label in labels)
      if (label.trim().isNotEmpty) label.trim(),
  ];
  if (names.isEmpty) return '';
  if (names.length == 1) return names.first;
  if (names.length <= 4) {
    return '${names.sublist(0, names.length - 1).join(', ')} '
        'and ${names.last}';
  }
  return '${names.take(3).join(', ')} and ${names.length - 3} more';
}

/// Asks, once per event, whether to open it in Combined.
///
/// Resolves with the button the viewer chose, or null when the question was
/// dismissed without one.
Future<CombinePromptAnswer?> showCombineCategoriesPrompt(
  BuildContext context, {
  required CombinedCategories categories,
  required bool isPremium,
}) {
  return showAlertModal<CombinePromptAnswer>(
    context: context,
    horizontalPadding: 24,
    verticalPadding: 24,
    child: _CombineCategoriesPrompt(
      categories: categories,
      isPremium: isPremium,
    ),
  );
}

class _CombineCategoriesPrompt extends StatelessWidget {
  const _CombineCategoriesPrompt({
    required this.categories,
    required this.isPremium,
  });

  final CombinedCategories categories;
  final bool isPremium;

  void _answer(BuildContext context, CombinePromptAnswer answer) {
    HapticFeedbackService.buttonPress();
    Navigator.of(context).pop(answer);
  }

  @override
  Widget build(BuildContext context) {
    final count = categories.items.length;
    final names = combinedCategoryNames([
      for (final category in categories.items) category.label,
    ]);

    return Container(
      constraints: BoxConstraints(maxWidth: 360.w),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(20.br),
        border: Border.all(
          color: context.colors.textPrimary.withValues(alpha: 0.08),
        ),
      ),
      padding: EdgeInsets.fromLTRB(20.sp, 22.sp, 20.sp, 12.sp),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Watch all $count categories together?',
            style: AppTypography.textLgBold.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          SizedBox(height: 8.sp),
          Text(
            '$kCombinedCategoryLabel puts $names in one Games list, so you '
            'never switch between them.',
            style: AppTypography.textSmRegular.copyWith(
              color: context.textInk(0.7),
              height: 1.4,
            ),
          ),
          if (!isPremium) ...[
            SizedBox(height: 8.sp),
            Text(
              'Included with ChessEver Premium.',
              style: AppTypography.textXsMedium.copyWith(
                color: context.colors.accentText,
              ),
            ),
          ],
          SizedBox(height: 20.sp),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => _answer(context, CombinePromptAnswer.notNow),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12.sp),
                    backgroundColor: context.colors.textPrimary.withValues(
                      alpha: 0.06,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.br),
                    ),
                  ),
                  child: Text(
                    'Not now',
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10.sp),
              Expanded(
                child: TextButton(
                  onPressed: () =>
                      _answer(context, CombinePromptAnswer.combine),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12.sp),
                    backgroundColor: kPrimaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.br),
                    ),
                  ),
                  child: Text(
                    'Combine',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kBlackColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 2.sp),
          Center(
            child: TextButton(
              onPressed: () => _answer(context, CombinePromptAnswer.neverAsk),
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: 16.sp,
                  vertical: 10.sp,
                ),
                // 44dp tap target without growing the visual row.
                minimumSize: const Size(44, 44),
              ),
              child: Text(
                'Never ask',
                style: AppTypography.textSmRegular.copyWith(
                  color: context.textInk(0.6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
