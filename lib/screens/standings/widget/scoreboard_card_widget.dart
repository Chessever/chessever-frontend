import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_typography.dart';

class ScoreboardCardWidget extends ConsumerWidget {
  final String countryCode;
  final String? title; // Player title (e.g., "GM") - made nullable
  final String name; // Player name
  final int score; // Current score/rating
  final double? scoreChange; // Score change (can be positive or negative)
  final String? matchScore; // Match score (e.g., "2.5/3")
  final bool? isWhite; // Whether the player played white
  final String? roundLabel;
  final int index;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  const ScoreboardCardWidget({
    super.key,
    required this.countryCode,
    required this.name,
    required this.score,
    this.title, // Changed to optional parameter
    this.scoreChange,
    this.matchScore,
    this.isWhite,
    this.roundLabel,
    required this.index,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Color backgroundColor = const Color(0xFF0F0F0F);
    BorderRadius? borderRadius;
    if (isFirst) {
      borderRadius = BorderRadius.only(
        topLeft: Radius.circular(8.br),
        topRight: Radius.circular(8.br),
      );
    } else if (isLast) {
      borderRadius = BorderRadius.only(
        bottomLeft: Radius.circular(8.br),
        bottomRight: Radius.circular(8.br),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 12.sp),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: borderRadius,
          border:
              isLast
                  ? null
                  : Border(
                    bottom: BorderSide(
                      color: context.colors.textPrimary.withValues(alpha: 0.08),
                      width: 0.7,
                    ),
                  ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '${index + 1}.',
              style: AppTypography.textMdBold.copyWith(color: context.colors.textPrimary),
            ),
            SizedBox(width: 10.w),
            if (countryCode.trim().isNotEmpty) ...[
              SizedBox(
                width: 20.w,
                height: 14.h,
                child: FederationFlag(
                  federation: countryCode,
                  height: 14.h,
                  width: 20.w,
                  borderRadius: BorderRadius.circular(2.br),
                ),
              ),
              SizedBox(width: 10.w),
            ],
            Expanded(
              child: RichText(
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                text: TextSpan(
                  children: [
                    if (title != null && title!.isNotEmpty)
                      TextSpan(
                        text: '$title ',
                        style: AppTypography.textMdBold.copyWith(
                          color: kLightYellowColor,
                        ),
                      ),
                    TextSpan(
                      text: name,
                      style: AppTypography.textMdBold.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 12.w),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  score.toString(),
                  style: AppTypography.textMdMedium.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
                if (scoreChange != null && scoreChange != 0.0) ...[
                  SizedBox(width: 4.w),
                  Text(
                    scoreChange! > 0
                        ? '+${scoreChange!.toStringAsFixed(0)}'
                        : scoreChange!.toStringAsFixed(0),
                    style: AppTypography.textXsMedium.copyWith(
                      color: scoreChange! > 0 ? kGreenColor : kRedColor,
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(width: 14.w),
            if (isWhite != null && matchScore != null)
              Container(
                width: 28.w,
                height: 28.h,
                decoration: BoxDecoration(
                  color: isWhite! ? Colors.white : Colors.black,
                  shape: BoxShape.circle,
                  border:
                      isWhite!
                          ? null
                          : Border.all(
                            color: context.colors.textPrimary.withValues(alpha: 0.35),
                            width: 1.1,
                          ),
                ),
                child: Center(
                  child: Text(
                    matchScore!,
                    textAlign: TextAlign.center,
                    style: AppTypography.textMdBold.copyWith(
                      color: isWhite! ? Colors.black : context.colors.textPrimary,
                    ),
                  ),
                ),
              )
            else if (matchScore != null)
              Text(
                matchScore!,
                textAlign: TextAlign.start,
                style: AppTypography.textMdBold.copyWith(color: context.colors.textPrimary),
              ),
          ],
        ),
      ),
    );
  }
}
