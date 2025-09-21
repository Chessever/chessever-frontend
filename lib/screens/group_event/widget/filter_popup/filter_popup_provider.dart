import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final filterPopupProvider =
    StateNotifierProvider<_FilterPopupController, FilterPopupState>(
      (ref) => _FilterPopupController(ref),
    );

class _FilterPopupController extends StateNotifier<FilterPopupState> {
  _FilterPopupController(this.ref)
    : super(
        const FilterPopupState(
          formatsAndStates: <String>{},
          eloRange: RangeValues(800, 3200),
        ),
      );

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

  Future<void> resetFilters(BuildContext context) async {
    Navigator.of(context).pop();
    await ref.read(groupEventScreenProvider.notifier).resetFilters();
    state = const FilterPopupState(
      formatsAndStates: <String>{},
      eloRange: RangeValues(800, 3200),
    );
  }
}
