import 'package:flutter/material.dart';

class FilterPopupState {
  const FilterPopupState({
    required this.formatsAndStates,
    required this.eloRange,
  });

  final Set<String> formatsAndStates;
  final RangeValues eloRange;

  FilterPopupState copyWith({
    Set<String>? formatsAndStates,
    RangeValues? eloRange,
  }) => FilterPopupState(
    formatsAndStates: formatsAndStates ?? this.formatsAndStates,
    eloRange: eloRange ?? this.eloRange,
  );
}
