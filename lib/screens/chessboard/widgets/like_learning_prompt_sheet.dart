import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:flutter/material.dart';

/// Compact, contextual question shown after the user reaches the end of an
/// eligible completed game at the configured learning cadence.
class LikeLearningPromptSheet extends StatelessWidget {
  const LikeLearningPromptSheet({super.key, required this.onResult});

  final ValueChanged<bool> onResult;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 20.h),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22.br)),
          border: Border(
            top: BorderSide(
              color: context.colors.divider.withValues(alpha: 0.55),
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: context.colors.textSecondary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            SizedBox(height: 18.h),
            Container(
              width: 46.w,
              height: 46.w,
              decoration: BoxDecoration(
                color: context.colors.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14.br),
              ),
              child: Icon(
                Icons.favorite_rounded,
                size: 25.sp,
                color: context.colors.danger,
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              'Did you like this game?',
              textAlign: TextAlign.center,
              style: AppTypography.textLgBold.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            SizedBox(height: 7.h),
            Text(
              'Like it to save it in My Likes and find it again later.',
              textAlign: TextAlign.center,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
                height: 1.4,
              ),
            ),
            SizedBox(height: 20.h),
            Row(
              children: [
                Flexible(
                  flex: 1,
                  child: AppButton(
                    key: const ValueKey('like-learning-no'),
                    text: 'No',
                    height: 48.h,
                    padding: EdgeInsets.symmetric(horizontal: 8.w),
                    isOutlined: true,
                    onPressed: () => onResult(false),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  flex: 2,
                  child: AppButton(
                    key: const ValueKey('like-learning-yes'),
                    text: 'Yes, like it',
                    height: 48.h,
                    padding: EdgeInsets.symmetric(horizontal: 8.w),
                    backgroundColor: context.colors.brand,
                    textColor: Colors.white,
                    onPressed: () => onResult(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
