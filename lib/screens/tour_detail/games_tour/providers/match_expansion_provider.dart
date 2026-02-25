import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Provider to track which matches are expanded or collapsed in knockout tournaments
/// Key: match key (e.g., "Player1|Player2")
/// Value: true if expanded, false if collapsed
final matchExpansionProvider =
    StateNotifierProvider<MatchExpansionNotifier, Map<String, bool>>((ref) {
      return MatchExpansionNotifier();
    });

/// Special key used to store the collapse all mode flag in the state
const String _kCollapseAllModeKey = '__COLLAPSE_ALL_MODE__';

/// Resolves whether a given match key should be expanded based on the current
/// state map, including the global collapse-all flag.
bool resolveMatchExpansionState(
  Map<String, bool> expansionState,
  String matchKey,
) {
  final isCollapseAllMode = expansionState[_kCollapseAllModeKey] == true;
  return expansionState[matchKey] ?? !isCollapseAllMode;
}

/// Family provider to watch individual match expansion states
/// This prevents unnecessary rebuilds when other matches are toggled
final matchExpansionStateProvider = Provider.family<bool, String>((
  ref,
  matchKey,
) {
  final expansionState = ref.watch(matchExpansionProvider);
  return resolveMatchExpansionState(expansionState, matchKey);
});

class MatchExpansionNotifier extends StateNotifier<Map<String, bool>> {
  MatchExpansionNotifier() : super({});

  /// Check if collapse all mode is currently active
  bool get isInCollapseAllMode => state[_kCollapseAllModeKey] == true;

  /// Toggle a specific match's expansion state
  void toggleMatch(String matchKey) {
    // Respect collapse all mode when toggling unknown keys
    final currentValue = resolveMatchExpansionState(state, matchKey);
    state = {...state, matchKey: !currentValue};
  }

  /// Check if a match is expanded
  bool isExpanded(String matchKey) {
    // Respect collapse all mode for unknown keys
    return resolveMatchExpansionState(state, matchKey);
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
    // Clear collapse all mode and reset all matches to expanded (default)
    state = {};
  }

  /// Collapse all matches
  void collapseAll(List<String> matchKeys) {
    // Set collapse all mode flag and collapse all known matches
    final newState = <String, bool>{_kCollapseAllModeKey: true};
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
