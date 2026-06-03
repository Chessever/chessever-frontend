import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/material.dart';

/// Pixel-identical search + filter row shared by My Likes and the
/// folder/database view. Pure presentational: parent owns the controller,
/// focus node, and the debounce-aware onChanged.
class GameSearchFilterBar extends StatelessWidget {
  const GameSearchFilterBar({
    super.key,
    required this.controller,
    required this.currentFilter,
    required this.onChanged,
    required this.onClear,
    required this.onFilterTap,
    this.focusNode,
    this.hintText = 'Search',
    this.trailing,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final GameFilter currentFilter;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onFilterTap;
  final String hintText;

  /// Optional trailing widget rendered after the filter button (e.g. a sort
  /// affordance on the folder screen). Sized to match the bar height.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final hasActiveFilters = currentFilter.hasActiveFilters;
    final activeFilterCount = currentFilter.activeFilterCount;
    final height = 48.h;

    return SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(color: context.colors.surfaceRecessed),
              ),
              child: Row(
                children: [
                  SizedBox(width: 12.w),
                  Icon(
                    Icons.search,
                    size: 20.sp,
                    color: context.colors.textSecondary,
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: controller,
                      builder: (_, __) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          style: AppTypography.textSmRegular.copyWith(
                            color: context.colors.textPrimary,
                          ),
                          onChanged: onChanged,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: hintText,
                            hintStyle: AppTypography.textSmRegular.copyWith(
                              color: context.colors.textSecondary,
                            ),
                            border: InputBorder.none,
                            contentPadding:
                                EdgeInsets.symmetric(vertical: 14.h),
                          ),
                        );
                      },
                    ),
                  ),
                  AnimatedBuilder(
                    animation: controller,
                    builder: (_, __) {
                      if (controller.text.isEmpty) return const SizedBox.shrink();
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: onClear,
                            child: Icon(
                              Icons.close,
                              size: 20.sp,
                              color: context.colors.textSecondary,
                            ),
                          ),
                          SizedBox(width: 8.w),
                        ],
                      );
                    },
                  ),
                  SizedBox(width: 8.w),
                ],
              ),
            ),
          ),
          SizedBox(width: 8.w),
          GestureDetector(
            onTap: onFilterTap,
            child: Container(
              width: height,
              height: height,
              decoration: BoxDecoration(
                color: hasActiveFilters
                    ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                    : context.colors.background,
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(
                  color: hasActiveFilters
                      ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                      : context.colors.surfaceRecessed,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 20.sp,
                    color: hasActiveFilters
                        ? const Color(0xFFEF4444)
                        : context.colors.textSecondary,
                  ),
                  if (hasActiveFilters)
                    Positioned(
                      right: 6.w,
                      top: 6.h,
                      child: Container(
                        width: 14.w,
                        height: 14.h,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$activeFilterCount',
                            style: AppTypography.textXsBold.copyWith(
                              color: context.colors.textPrimary,
                              fontSize: 9.sp,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: 8.w),
            SizedBox(width: height, height: height, child: trailing),
          ],
        ],
      ),
    );
  }
}
