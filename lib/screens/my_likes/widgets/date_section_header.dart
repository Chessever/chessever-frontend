import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Collapsible date-section header — the same visual the Favorites → Games tab
/// uses for its Today / Yesterday / date buckets. Public so My Likes renders an
/// identical header (favorites keeps its own private copy).
class DateSectionHeader extends StatelessWidget {
  const DateSectionHeader({
    super.key,
    required this.dateLabel,
    required this.gameCount,
    required this.isExpanded,
    this.onToggle,
  });

  final String dateLabel;
  final int gameCount;
  final bool isExpanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(12.br),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 14.sp),
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color: context.colors.textPrimary.withValues(alpha: 0.1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 4.w,
              height: 20.h,
              decoration: BoxDecoration(
                color: kPrimaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                '$dateLabel • $gameCount ${gameCount == 1 ? 'game' : 'games'}',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onToggle != null) ...[
              SizedBox(width: 12.w),
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: context.colors.textPrimary.withValues(alpha: 0.5),
                size: 20.sp,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Formats a `yyyy-MM-dd` key as Today / Yesterday / `EEEE, MMM d` in local
/// time. Returns 'Unknown date' for the empty/sentinel key.
String formatLikedDateHeader(String dateKey) {
  if (dateKey == '0000-00-00') return 'Unknown date';

  final date = DateTime.parse(dateKey);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final day = DateTime(date.year, date.month, date.day);

  if (day == today) return 'Today';
  if (day == yesterday) return 'Yesterday';
  return DateFormat('EEEE, MMM d').format(date);
}
