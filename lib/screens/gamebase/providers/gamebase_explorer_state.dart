import 'package:dart_mappable/dart_mappable.dart';
import '../models/models.dart';

part 'gamebase_explorer_state.mapper.dart';

/// Filter settings for Gamebase explorer queries.
@MappableClass()
class GamebaseFilters with GamebaseFiltersMappable {
  const GamebaseFilters({
    this.timeControls = const [],
    this.minRating,
    this.maxRating,
    this.playerIds = const [],
    this.selectedPlayers = const [],
  });

  /// Selected time controls (empty = all)
  final List<TimeControl> timeControls;

  /// Minimum rating filter
  final int? minRating;

  /// Maximum rating filter
  final int? maxRating;

  /// Selected player IDs to filter by
  final List<String> playerIds;

  /// Selected players (for display purposes)
  final List<GamebasePlayer> selectedPlayers;
}

/// State for the Gamebase explorer screen.
@MappableClass()
class GamebaseExplorerState with GamebaseExplorerStateMappable {
  const GamebaseExplorerState({
    this.currentFen = '', // Empty by default; setPosition() sets the real FEN
    this.moveHistory = const [],
    this.currentMoveIndex = -1,
    this.moveAggregates = const [],
    this.isLoading = false,
    this.error,
    this.filters = const GamebaseFilters(),
    this.selectedGame,
  });

  /// Current position in FEN notation
  final String currentFen;

  /// Move history as list of UCI moves
  final List<String> moveHistory;

  /// Current move index in history (-1 = initial position)
  final int currentMoveIndex;

  /// Move aggregates for current position
  final List<MoveAggregate> moveAggregates;

  /// Whether data is being loaded
  final bool isLoading;

  /// Error message if any
  final String? error;

  /// Filter settings
  final GamebaseFilters filters;

  /// Currently selected game (when viewing a specific game)
  final GamebaseGame? selectedGame;

  /// Check if at initial position
  bool get isAtInitialPosition => currentMoveIndex == -1;

  /// Check if at latest move
  bool get isAtLatestMove => currentMoveIndex == moveHistory.length - 1;

  /// Check if can go back
  bool get canGoBack => currentMoveIndex >= 0;

  /// Check if can go forward
  bool get canGoForward => currentMoveIndex < moveHistory.length - 1;

  /// Get total games in current position
  int get totalGames => moveAggregates.fold(0, (sum, agg) => sum + agg.total);

  /// Check if has any active filters
  bool get hasActiveFilters =>
      filters.timeControls.isNotEmpty ||
      filters.minRating != null ||
      filters.maxRating != null ||
      filters.playerIds.isNotEmpty;
}
