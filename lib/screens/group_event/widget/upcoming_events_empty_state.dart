import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// What the Upcoming tab shows when it has no events to list.
///
/// Two honest cases: the active filters hide every scheduled event (offer to
/// reset them), or nothing is scheduled yet. The body stays scrollable so the
/// Events pull-to-refresh still works on an empty tab.
class UpcomingEventsEmptyState extends StatelessWidget {
  const UpcomingEventsEmptyState({
    required this.filtersActive,
    required this.onResetFilters,
    this.scrollController,
    super.key,
  });

  final bool filtersActive;
  final VoidCallback onResetFilters;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final title = filtersActive
        ? 'No upcoming events match your filters'
        : 'Nothing scheduled yet';
    final subtitle = filtersActive
        ? 'Try widening your filters to see more.'
        : 'Events appear here as soon as organizers publish them.';

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 48.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTypography.textSmMedium.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: AppTypography.textXsRegular.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                    if (filtersActive) ...[
                      SizedBox(height: 20.h),
                      _ResetFiltersButton(onTap: onResetFilters),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ResetFiltersButton extends StatelessWidget {
  const _ResetFiltersButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        color: context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            // 44dp tap target, independent of the scaled text size.
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Center(
                widthFactor: 1,
                child: Text(
                  'Reset filters',
                  style: AppTypography.textXsMedium.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
