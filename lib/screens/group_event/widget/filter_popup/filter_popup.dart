import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/group_event_filter_provider.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class FilterPopup extends ConsumerWidget {
  const FilterPopup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTourEvent = ref.watch(selectedGroupCategoryProvider);
    final filterState = ref.watch(filterPopupProvider);
    final dialogWidth = 280.w;
    final horizontalPadding = 20.w;
    final verticalPadding = 16.h;

    final readableFormat =
        ref
            .read(groupEventFilterProvider(selectedTourEvent))
            .getReadableFormats();
    final formats =
        ref.read(groupEventFilterProvider(selectedTourEvent)).getFormats();
    final readableGameState =
        ref
            .read(groupEventFilterProvider(selectedTourEvent))
            .getReadableGameState();
    final gameStates =
        ref.read(groupEventFilterProvider(selectedTourEvent)).getGameState();

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Stack(
        children: [
          const Positioned.fill(child: BackDropFilterWidget()),
          GestureDetector(
            onTap: () {},
            child: Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: EdgeInsets.zero,
              child: Container(
                width: dialogWidth,
                constraints: BoxConstraints(maxHeight: 500.h),
                decoration: BoxDecoration(
                  color: kBlackColor,
                  borderRadius: BorderRadius.circular(4.br),
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
                              'Format',
                              style: AppTypography.textXsMedium.copyWith(
                                color: kWhiteColor,
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
                                final isSelected = filterState.formatsAndStates
                                    .contains(raw);
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
                                              : kBlack2Color,
                                      borderRadius: BorderRadius.circular(8.br),
                                    ),
                                    child: Text(
                                      current,
                                      style: AppTypography.textXsMedium
                                          .copyWith(
                                            color:
                                                isSelected
                                                    ? kBlackColor
                                                    : kWhiteColor,
                                          ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            SizedBox(height: 24.h),
                            Text(
                              'Event Status',
                              style: AppTypography.textXsMedium.copyWith(
                                color: kWhiteColor,
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
                                final isSelected = filterState.formatsAndStates
                                    .contains(raw);
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
                                              : kBlack2Color,
                                      borderRadius: BorderRadius.circular(8.br),
                                    ),
                                    child: Text(
                                      current,
                                      style: AppTypography.textXsMedium
                                          .copyWith(
                                            color:
                                                isSelected
                                                    ? kBlackColor
                                                    : kWhiteColor,
                                          ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            SizedBox(height: 24.h),
                            Text(
                              'ELO Range',
                              style: AppTypography.textXsMedium.copyWith(
                                color: kWhiteColor,
                              ),
                            ),
                            SizedBox(height: 8.h),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16.sp,
                                vertical: 12.sp,
                              ),
                              decoration: BoxDecoration(
                                color: kBlack2Color,
                                borderRadius: BorderRadius.circular(8.br),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${filterState.eloRange.start.round()}',
                                        style: AppTypography.textXsMedium
                                            .copyWith(color: kWhiteColor),
                                      ),
                                      Text(
                                        '${filterState.eloRange.end.round()}',
                                        style: AppTypography.textXsMedium
                                            .copyWith(color: kWhiteColor),
                                      ),
                                    ],
                                  ),
                                  RangeSlider(
                                    values: filterState.eloRange,
                                    min: 800,
                                    max: 3200,
                                    divisions: 48,
                                    labels: RangeLabels(
                                      '${filterState.eloRange.start.round()}',
                                      '${filterState.eloRange.end.round()}',
                                    ),
                                    activeColor: kPrimaryColor,
                                    inactiveColor: kDividerColor,
                                    onChanged:
                                        (v) => ref
                                            .read(filterPopupProvider.notifier)
                                            .setEloRange(v),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 16.h),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(20.sp),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            SizedBox(
                              width: 116.w,
                              height: 40.h,
                              child: OutlinedButton(
                                onPressed: () async {
                                  await ref
                                      .read(filterPopupProvider.notifier)
                                      .resetFilters(context);
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: kWhiteColor,
                                  backgroundColor: kBlack2Color,
                                  side: BorderSide.none,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4.br),
                                  ),
                                  padding: EdgeInsets.zero,
                                ),
                                child: Text(
                                  'Reset',
                                  style: AppTypography.textSmMedium.copyWith(
                                    color: kWhiteColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.visible,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 116.w,
                              height: 40.h,
                              child: ElevatedButton(
                                onPressed:
                                    () => _applyFilters(
                                      context,
                                      ref,
                                      selectedTourEvent,
                                      filterState,
                                    ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimaryColor,
                                  foregroundColor: kBlackColor,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4.br),
                                  ),
                                  padding: EdgeInsets.zero,
                                ),
                                child: Text(
                                  'Apply Filters',
                                  style: AppTypography.textSmMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.visible,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _applyFilters(
    BuildContext context,
    WidgetRef ref,
    selectedTourEvent,
    FilterPopupState filterState,
  ) async {
    final filtered = await ref
        .read(groupEventFilterProvider(selectedTourEvent))
        .applyAllFilters(
          filters: filterState.formatsAndStates.toList(),
          eloRange: filterState.eloRange,
        );

    ref.read(groupEventScreenProvider.notifier).setFilteredModels(filtered);

    Navigator.of(context).pop();
  }
}
