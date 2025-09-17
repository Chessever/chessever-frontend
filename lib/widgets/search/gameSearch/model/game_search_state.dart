import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search.dart';

class GameSearchState {
  final bool isSearching;
  final bool isInitialized;
  final String currentQuery;
  final String? errorMessage;
  final List<GameSearchResult> results;
  final DateTime? lastSearchTimestamp;

  const GameSearchState({
    this.isSearching = false,
    this.isInitialized = false,
    this.currentQuery = '',
    this.errorMessage,
    this.results = const [],
    this.lastSearchTimestamp,
  });

  GameSearchState copyWith({
    bool? isSearching,
    bool? isInitialized,
    String? currentQuery,
    String? errorMessage,
    List<GameSearchResult>? results,
    DateTime? lastSearchTimestamp,
    bool clearError = false,
  }) {
    return GameSearchState(
      isSearching: isSearching ?? this.isSearching,
      isInitialized: isInitialized ?? this.isInitialized,
      currentQuery: currentQuery ?? this.currentQuery,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      results: results ?? this.results,
      lastSearchTimestamp: lastSearchTimestamp ?? this.lastSearchTimestamp,
    );
  }

  bool get hasResults => results.isNotEmpty;
  bool get hasError => errorMessage != null;

  // Only show empty state if:
  // 1. Not currently searching
  // 2. No error
  // 3. No results
  // 4. Has a query
  // 5. Has a timestamp (meaning a search was completed)
  bool get isEmpty =>
      !isSearching &&
      !hasError &&
      results.isEmpty &&
      currentQuery.isNotEmpty &&
      lastSearchTimestamp != null;

  // Show idle state only when there's no query at all
  bool get isIdle =>
      !isSearching && !hasError && results.isEmpty && currentQuery.isEmpty;

  // New getter to check if we're in a transitioning state
  // (typing but search hasn't completed yet)
  bool get isTransitioning =>
      currentQuery.isNotEmpty &&
      !isSearching &&
      !hasError &&
      results.isNotEmpty;
}
