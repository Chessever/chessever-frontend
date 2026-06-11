import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/group_event_filter_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/game_filter/rating_tier_filter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class FilterPopup extends ConsumerWidget {
  const FilterPopup({
    required this.onApplyFilters,
    required this.onResetFilters,
    super.key,
  });

  final ValueChanged<FilterPopupState> onApplyFilters;
  final VoidCallback onResetFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(filterPopupProvider);
    final dialogWidth = 280.w;
    final horizontalPadding = 20.w;
    final verticalPadding = 16.h;

    final readableFormat =
        ref.read(groupEventFilterProvider).getReadableFormats();
    final formats = ref.read(groupEventFilterProvider).getFormats();
    final readableGameState =
        ref.read(groupEventFilterProvider).getReadableGameState();
    final gameStates = ref.read(groupEventFilterProvider).getGameState();

    return Container(
      width: dialogWidth,
      constraints: BoxConstraints(maxHeight: 500.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(
          color: context.colors.textPrimary.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: horizontalPadding,
                right: horizontalPadding,
                top: verticalPadding,
                bottom: 0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Event Status',
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  GridView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 3,
                        ),
                    itemCount: readableGameState.length,
                    itemBuilder: (context, index) {
                      final current = readableGameState[index];
                      final raw = gameStates[index];
                      final isSelected = filterState.formatsAndStates.contains(
                        raw,
                      );
                      return GestureDetector(
                        onTap:
                            () => ref
                                .read(filterPopupProvider.notifier)
                                .toggleFormatOrState(raw),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color:
                                isSelected
                                    ? kPrimaryColor
                                    : context.colors.surfaceRecessed,
                            borderRadius: BorderRadius.circular(8.br),
                          ),
                          child: Text(
                            current,
                            style: AppTypography.textXsMedium.copyWith(
                              color:
                                  isSelected
                                      ? kBlackColor
                                      : context.colors.textPrimary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  SizedBox(height: 20.h),
                  Text(
                    'Time Control',
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  GridView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 3,
                        ),
                    itemCount: readableFormat.length,
                    itemBuilder: (context, index) {
                      final current = readableFormat[index];
                      final raw = formats[index];
                      final isSelected = filterState.formatsAndStates.contains(
                        raw,
                      );
                      return GestureDetector(
                        onTap:
                            () => ref
                                .read(filterPopupProvider.notifier)
                                .toggleFormatOrState(raw),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color:
                                isSelected
                                    ? kPrimaryColor
                                    : context.colors.surfaceRecessed,
                            borderRadius: BorderRadius.circular(8.br),
                          ),
                          child: Text(
                            current,
                            style: AppTypography.textXsMedium.copyWith(
                              color:
                                  isSelected
                                      ? kBlackColor
                                      : context.colors.textPrimary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  SizedBox(height: 20.h),
                  Text(
                    'Level',
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  RatingTierFilter(
                    selectedMinRating: filterState.minElo,
                    onChanged:
                        (value) => ref
                            .read(filterPopupProvider.notifier)
                            .setMinimumElo(value),
                  ),
                  SizedBox(height: 16.h),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.all(20.sp),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48.h,
                      child: OutlinedButton(
                        onPressed: () {
                          onResetFilters();
                          ref
                              .read(filterPopupProvider.notifier)
                              .resetFilters(context);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.colors.textPrimary,
                          backgroundColor: context.colors.surface,
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.br),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        child: Text(
                          'Reset',
                          style: AppTypography.textSmMedium.copyWith(
                            color: context.colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: SizedBox(
                      height: 48.h,
                      child: ElevatedButton(
                        onPressed: () async {
                          onApplyFilters(filterState);
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryColor,
                          foregroundColor: kBlackColor,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.br),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        child: Text(
                          'Apply Filters',
                          style: AppTypography.textSmMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
