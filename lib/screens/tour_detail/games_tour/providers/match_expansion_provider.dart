import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Provider to track which matches are expanded or collapsed in knockout tournaments
/// Key: match key (e.g., "Player1|Player2")
/// Value: true if expanded, false if collapsed
final matchExpansionProvider =
    StateNotifierProvider<MatchExpansionNotifier, Map<String, bool>>((ref) {
  return MatchExpansionNotifier();
});

/// Family provider to watch individual match expansion states
/// This prevents unnecessary rebuilds when other matches are toggled
final matchExpansionStateProvider = Provider.family<bool, String>((ref, matchKey) {
  final expansionState = ref.watch(matchExpansionProvider);
  return expansionState[matchKey] ?? true; // Default to expanded
});

class MatchExpansionNotifier extends StateNotifier<Map<String, bool>> {
  MatchExpansionNotifier() : super({});

  /// Toggle a specific match's expansion state
  void toggleMatch(String matchKey) {
    state = {
      ...state,
      matchKey: !(state[matchKey] ?? true), // Default to expanded
    };
  }

  /// Check if a match is expanded (default: true)
  bool isExpanded(String matchKey) {
    return state[matchKey] ?? true;
  }

  /// Expand a specific match
  void expandMatch(String matchKey) {
    if (!isExpanded(matchKey)) {
      state = {...state, matchKey: true};
    }
  }

  /// Collapse a specific match
  void collapseMatch(String matchKey) {
    if (isExpanded(matchKey)) {
      state = {...state, matchKey: false};
    }
  }

  /// Expand all matches
  void expandAll() {
    state = {};
  }

  /// Collapse all matches
  void collapseAll(List<String> matchKeys) {
    final newState = <String, bool>{};
    for (final key in matchKeys) {
      newState[key] = false;
    }
    state = newState;
  }

  /// Reset to default (all expanded)
  void reset() {
    state = {};
  }
}
