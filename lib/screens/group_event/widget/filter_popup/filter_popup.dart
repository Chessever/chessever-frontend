import 'package:chessever2/widgets/game_filter/filter_popup_components.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/group_event_filter_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/widgets/game_filter/rating_tier_filter.dart';
import 'package:chessever2/widgets/game_filter/eco_filter_dropdown.dart';
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

    final readableFormat = ref
        .read(groupEventFilterProvider)
        .getReadableFormats();
    final formats = ref.read(groupEventFilterProvider).getFormats();
    final readableGameState = ref
        .read(groupEventFilterProvider)
        .getReadableGameState();
    final gameStates = ref.read(groupEventFilterProvider).getGameState();

    return FilterPopupFrame(
      onReset: () {
        onResetFilters();
        ref.read(filterPopupProvider.notifier).resetFilters(context);
      },
      onApply: () {
        onApplyFilters(filterState);
        Navigator.of(context).pop();
      },
      sections: [
        FilterSectionLabel('Event Status'),
        SizedBox(height: 8.h),
        FilterChoiceGrid<String>(
          values: gameStates,
          label: (value) => readableGameState[gameStates.indexOf(value)],
          isSelected: filterState.formatsAndStates.contains,
          onTap: (value) =>
              ref.read(filterPopupProvider.notifier).toggleFormatOrState(value),
        ),
        SizedBox(height: 20.h),
        FilterSectionLabel('Time Control'),
        SizedBox(height: 8.h),
        FilterChoiceGrid<String>(
          values: formats,
          label: (value) => readableFormat[formats.indexOf(value)],
          isSelected: filterState.formatsAndStates.contains,
          onTap: (value) =>
              ref.read(filterPopupProvider.notifier).toggleFormatOrState(value),
        ),
        SizedBox(height: 20.h),
        FilterSectionLabel('Opening'),
        SizedBox(height: 8.h),
        EcoFilterDropdown(
          value: filterState.eco,
          onChanged: (value) =>
              ref.read(filterPopupProvider.notifier).setEco(value),
        ),
        SizedBox(height: 20.h),
        FilterSectionLabel('Level'),
        SizedBox(height: 8.h),
        RatingTierFilter(
          selectedMinRating: filterState.minElo,
          onChanged: (value) =>
              ref.read(filterPopupProvider.notifier).setMinimumElo(value),
        ),
        SizedBox(height: 16.h),
      ],
    );
  }
}
