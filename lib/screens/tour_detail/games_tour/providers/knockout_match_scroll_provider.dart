import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/match_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Provider to track and manage scroll position for knockout tournament matches
/// This enables the dropdown to show which match is currently visible
/// and allows scrolling to specific matches
final knockoutMatchScrollProvider =
    StateNotifierProvider<KnockoutMatchScrollNotifier, KnockoutMatchScrollState>((ref) {
  return KnockoutMatchScrollNotifier(ref);
});

class KnockoutMatchScrollState {
  final String? visibleMatchKey;
  final String? selectedMatchKey;
  final bool userSelected;

  const KnockoutMatchScrollState({
    this.visibleMatchKey,
    this.selectedMatchKey,
    this.userSelected = false,
  });

  KnockoutMatchScrollState copyWith({
    String? visibleMatchKey,
    String? selectedMatchKey,
    bool? userSelected,
  }) {
    return KnockoutMatchScrollState(
      visibleMatchKey: visibleMatchKey ?? this.visibleMatchKey,
      selectedMatchKey: selectedMatchKey ?? this.selectedMatchKey,
      userSelected: userSelected ?? this.userSelected,
    );
  }
}

class KnockoutMatchScrollNotifier extends StateNotifier<KnockoutMatchScrollState> {
  KnockoutMatchScrollNotifier(this.ref) : super(const KnockoutMatchScrollState());

  final Ref ref;

  /// Update the currently visible match based on scroll position
  void updateVisibleMatch(String? matchKey) {
    if (matchKey != state.visibleMatchKey) {
      state = state.copyWith(
        visibleMatchKey: matchKey,
        // Auto-select visible match if user hasn't manually selected one
        selectedMatchKey: state.userSelected ? state.selectedMatchKey : matchKey,
      );
    }
  }

  /// User manually selected a match from dropdown
  void selectMatch(String matchKey) {
    state = state.copyWith(
      selectedMatchKey: matchKey,
      userSelected: true,
    );
  }

  /// Reset user selection (will auto-follow scroll position)
  void resetSelection() {
    state = state.copyWith(
      selectedMatchKey: state.visibleMatchKey,
      userSelected: false,
    );
  }

  /// Calculate the item index for a specific match in the list
  /// Takes into account:
  /// - Tournament header (index 0)
  /// - Match headers
  /// - Expanded/collapsed state
  /// - Grid vs List mode
  int calculateMatchHeaderIndex(String matchKey) {
    final referenceGames = _getReferenceGames();
    if (referenceGames.isEmpty) return 0;

    final matches = KnockoutMatchDetector.groupByMatchesAcrossAllRounds(referenceGames);
    final expansionState = ref.read(matchExpansionProvider);
    final isGrid = ref.read(gamesListViewModeProvider) == GamesListViewMode.chessBoardGrid;

    int currentIndex = 1; // Start after tournament header

    for (final entry in matches.entries) {
      final currentMatchKey = entry.key;
      final matchGames = entry.value;

      // If this is the target match, return current index
      if (currentMatchKey == matchKey) {
        return currentIndex;
      }

      // Move past match header
      currentIndex++;

      // Add games if match is expanded
      final isExpanded = expansionState[currentMatchKey] ?? true;
      if (isExpanded) {
        if (isGrid) {
          currentIndex += (matchGames.length / 2).ceil();
        } else {
          currentIndex += matchGames.length;
        }
      }
    }

    return 0; // Fallback to start
  }

  /// Get the match key from a given item index in the list
  /// Used to determine which match is visible during scrolling
  String? getMatchKeyFromIndex(int itemIndex) {
    final referenceGames = _getReferenceGames();
    if (referenceGames.isEmpty) return null;

    final matches = KnockoutMatchDetector.groupByMatchesAcrossAllRounds(referenceGames);
    final expansionState = ref.read(matchExpansionProvider);
    final isGrid = ref.read(gamesListViewModeProvider) == GamesListViewMode.chessBoardGrid;

    // Tournament header is at index 0
    if (itemIndex == 0) return null;

    int currentIndex = 1; // Start after tournament header

    for (final entry in matches.entries) {
      final matchKey = entry.key;
      final matchGames = entry.value;

      // Check if index is the match header
      if (itemIndex == currentIndex) {
        return matchKey;
      }

      currentIndex++; // Move past match header

      // Check if index is within match games
      final isExpanded = expansionState[matchKey] ?? true;
      if (isExpanded) {
        final gamesCount = isGrid ? (matchGames.length / 2).ceil() : matchGames.length;

        if (itemIndex < currentIndex + gamesCount) {
          return matchKey; // Index is within this match's games
        }

        currentIndex += gamesCount;
      }
    }

    return null;
  }

  /// Get sorted list of all matches with their metadata
  List<MatchHeaderModel> getMatchHeaders() {
    final referenceGames = _getReferenceGames();
    if (referenceGames.isEmpty) return [];

    final matches = KnockoutMatchDetector.groupByMatchesAcrossAllRounds(referenceGames);

    final headers = matches.entries.map((entry) {
      return KnockoutMatchDetector.createMatchHeader(entry.key, entry.value);
    }).toList();

    // Sort: incomplete first, then alphabetically
    headers.sort((a, b) {
      if (a.isComplete != b.isComplete) {
        return a.isComplete ? 1 : -1;
      }
      return a.matchTitle.compareTo(b.matchTitle);
    });

    return headers;
  }

  List<GamesTourModel> _getReferenceGames() {
    final tourId =
        ref.read(tourDetailScreenProvider).value?.aboutTourModel.id;
    if (tourId != null) {
      final knockoutState =
          ref.read(knockoutTournamentStateProvider(tourId));
      if (knockoutState.isKnockout && knockoutState.allGames.isNotEmpty) {
        return knockoutState.allGames;
      }
    }

    return ref
            .read(gamesTourScreenProvider)
            .valueOrNull
            ?.gamesTourModels ??
        const <GamesTourModel>[];
  }
}
