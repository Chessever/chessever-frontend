import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const defaultFilterPopupState = FilterPopupState(
  formatsAndStates: <String>{},
  eloRange: RangeValues(kFilterMinElo, kFilterMaxElo),
);

final filterPopupProvider =
    StateNotifierProvider<_FilterPopupController, FilterPopupState>(
      (ref) => _FilterPopupController(ref),
    );

final eventAppliedFilterProvider = StateProvider<FilterPopupState>(
  (ref) => defaultFilterPopupState,
);

final forYouAppliedFilterProvider = eventAppliedFilterProvider;
final currentPastAppliedFilterProvider = eventAppliedFilterProvider;
final searchAppliedFilterProvider = eventAppliedFilterProvider;

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

  void setMinimumElo(int? minimumElo) {
    state = state.copyWith(
      eloRange: RangeValues(
        minimumElo?.toDouble() ?? kFilterMinElo,
        kFilterMaxElo,
      ),
    );
  }

  void setState(FilterPopupState newState) {
    state = newState;
  }

  void resetFilters(BuildContext context) {
    Navigator.of(context).pop();
    state = defaultFilterPopupState;
  }
}
