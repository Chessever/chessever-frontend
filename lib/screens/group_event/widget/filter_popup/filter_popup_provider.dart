import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const defaultFilterPopupState = FilterPopupState(
  formatsAndStates: <String>{},
  eloRange: RangeValues(2200, 3200),
);

final filterPopupProvider =
    StateNotifierProvider<_FilterPopupController, FilterPopupState>(
      (ref) => _FilterPopupController(ref),
    );

final forYouAppliedFilterProvider = StateProvider<FilterPopupState>(
  (ref) => defaultFilterPopupState,
);

final currentPastAppliedFilterProvider = StateProvider<FilterPopupState>(
  (ref) => defaultFilterPopupState,
);

final searchAppliedFilterProvider = StateProvider<FilterPopupState>(
  (ref) => defaultFilterPopupState,
);

class _FilterPopupController extends StateNotifier<FilterPopupState> {
  _FilterPopupController(this.ref) : super(defaultFilterPopupState);

  final Ref ref;

  void toggleFormatOrState(String formatOrState) {
    final newSet = Set<String>.from(state.formatsAndStates);
    if (newSet.contains(formatOrState)) {
      newSet.remove(formatOrState);
    } else {
      newSet.add(formatOrState);
    }
    state = state.copyWith(formatsAndStates: newSet);
  }

  void setEloRange(RangeValues newRange) {
    state = state.copyWith(eloRange: newRange);
  }

  void setState(FilterPopupState newState) {
    state = newState;
  }

  void resetFilters(BuildContext context) {
    Navigator.of(context).pop();
    state = defaultFilterPopupState;
  }
}
