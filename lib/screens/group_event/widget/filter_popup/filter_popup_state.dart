import 'package:flutter/material.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';

const double kFilterMinElo = 0;
const double kFilterMaxElo = 3200;

class FilterPopupState {
  const FilterPopupState({
    required this.formatsAndStates,
    required this.eloRange,
    this.eco = GameEcoFilter.all,
  });

  final Set<String> formatsAndStates;
  final RangeValues eloRange;
  final GameEcoFilter eco;

  bool get hasEloFilter =>
      eloRange.start > kFilterMinElo || eloRange.end < kFilterMaxElo;

  int? get minElo => hasEloFilter ? eloRange.start.round() : null;

  int? get maxElo => hasEloFilter ? eloRange.end.round() : null;

  FilterPopupState copyWith({
    Set<String>? formatsAndStates,
    RangeValues? eloRange,
    GameEcoFilter? eco,
  }) => FilterPopupState(
    formatsAndStates: formatsAndStates ?? this.formatsAndStates,
    eloRange: eloRange ?? this.eloRange,
    eco: eco ?? this.eco,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FilterPopupState &&
        _setsEqual(other.formatsAndStates, formatsAndStates) &&
        other.eloRange.start == eloRange.start &&
        other.eloRange.end == eloRange.end &&
        other.eco == eco;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(formatsAndStates),
    eloRange.start,
    eloRange.end,
    eco,
  );

  static bool _setsEqual(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final value in a) {
      if (!b.contains(value)) return false;
    }
    return true;
  }
}
