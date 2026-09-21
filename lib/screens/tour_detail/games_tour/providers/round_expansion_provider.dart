import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Tracks expansion state for each tournament round (regular or knockout).
/// Key: round id, Value: true if expanded, false if collapsed.
final roundExpansionProvider =
    StateNotifierProvider<RoundExpansionNotifier, Map<String, bool>>((ref) {
      return RoundExpansionNotifier();
    });

/// Lightweight watcher for a specific round id to reduce rebuilds.
final roundExpansionStateProvider = Provider.family<bool, String>((
  ref,
  roundId,
) {
  final expansionState = ref.watch(roundExpansionProvider);
  return expansionState[roundId] ?? true; // Default expanded
});

class RoundExpansionNotifier extends StateNotifier<Map<String, bool>> {
  RoundExpansionNotifier() : super(const {});

  void toggleRound(String roundId) {
    state = {...state, roundId: !(state[roundId] ?? true)};
  }

  bool isExpanded(String roundId) => state[roundId] ?? true;

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

  /// Expand specific rounds by ID. If no IDs provided, expands all rounds (resets state)
  void expandAll([Iterable<String>? roundIds]) {
    if (roundIds == null || roundIds.isEmpty) {
      reset();
      return;
    }

    final newState = <String, bool>{...state};
    for (final id in roundIds) {
      newState[id] = true;
    }
    state = newState;
  }

  void reset() {
    state = const {};
  }
}
