import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';

class PlayerInfoWidget extends StatelessWidget {
  const PlayerInfoWidget({
    required this.name,
    required this.rating,
    required this.time,
    required this.isTop,
    super.key,
  });

  final String name;
  final String rating;
  final String time;
  final bool isTop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 8.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (isTop) ...[
            // For top player (black)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTypography.textXsMedium.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
                SizedBox(width: 2.w),
                Text(
                  rating,
                  style: AppTypography.textXsMedium.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ],
            ),
            Text(
              time,
              style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
            ),
          ] else ...[
            // For bottom player (white)
            Text(
              time,
              style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  name,
                  style: AppTypography.textSmMedium.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
                SizedBox(width: 2.w),
                Text(
                  rating,
                  style: AppTypography.textXsMedium.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
