import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Tracks expansion state for each tournament round (regular or knockout).
/// Key: round id, Value: true if expanded, false if collapsed.
final roundExpansionProvider =
    StateNotifierProvider<RoundExpansionNotifier, Map<String, bool>>((ref) {
      return RoundExpansionNotifier();
    });

final searchRoundExpansionProvider =
    StateNotifierProvider<RoundExpansionNotifier, Map<String, bool>>((ref) {
      return RoundExpansionNotifier(defaultExpanded: true);
    });

StateNotifierProvider<RoundExpansionNotifier, Map<String, bool>>
roundExpansionProviderFor(bool isSearchMode) =>
    isSearchMode ? searchRoundExpansionProvider : roundExpansionProvider;

/// Lightweight watcher for a specific round id to reduce rebuilds.
final roundExpansionStateProvider = Provider.family<bool, String>((
  ref,
  roundId,
) {
  final expansionState = ref.watch(roundExpansionProvider);
  return expansionState[roundId] ?? false; // Unvisited rounds stay collapsed
});

class RoundExpansionNotifier extends StateNotifier<Map<String, bool>> {
  RoundExpansionNotifier({this.defaultExpanded = false}) : super(const {});

  final bool defaultExpanded;

  void toggleRound(String roundId) {
    state = {...state, roundId: !(state[roundId] ?? defaultExpanded)};
  }

  bool isExpanded(String roundId) => state[roundId] ?? defaultExpanded;

  void expandRound(String roundId) {
    if (!isExpanded(roundId)) {
      state = {...state, roundId: true};
    }
  }

  void collapseRound(String roundId) {
    if (isExpanded(roundId)) {
      state = {...state, roundId: false};
    }
  }

  void collapseAll(Iterable<String> roundIds) {
    final newState = <String, bool>{...state};
    for (final id in roundIds) {
      newState[id] = false;
    }
    state = newState;
  }

  /// Expand the supplied rounds, or every previously known round when omitted.
  void expandAll([Iterable<String>? roundIds]) {
    if (roundIds == null || roundIds.isEmpty) {
      state = {for (final id in state.keys) id: true};
      return;
    }

    final newState = <String, bool>{...state};
    for (final id in roundIds) {
      newState[id] = true;
    }
    state = newState;
  }

  /// Metadata refreshes must never undo a manual collapse.
  void initializeRound(String roundId) {
    if (roundId.isNotEmpty && !state.containsKey(roundId)) {
      state = {...state, roundId: true};
    }
  }

  void reset() {
    state = const {};
  }
}
