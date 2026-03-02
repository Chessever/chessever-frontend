import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:dart_mappable/dart_mappable.dart';
import '../models/models.dart';

part 'gamebase_explorer_state.mapper.dart';

/// Player color filter for Gamebase explorer queries.
enum GamebasePlayerColor { white, black }

/// Game result filter for Gamebase explorer queries.
enum GamebaseGameResult { whiteWins, blackWins, draw }

extension GamebaseGameResultX on GamebaseGameResult {
  /// API value sent to the backend (W/B/D).
  String get apiValue {
    switch (this) {
      case GamebaseGameResult.whiteWins:
        return 'W';
      case GamebaseGameResult.blackWins:
        return 'B';
      case GamebaseGameResult.draw:
        return 'D';
    }
  }

  /// Display text for UI chips.
  String get displayText {
    switch (this) {
      case GamebaseGameResult.whiteWins:
        return '1-0';
      case GamebaseGameResult.blackWins:
        return '0-1';
      case GamebaseGameResult.draw:
        return '½-½';
    }
  }
}

/// Filter settings for Gamebase explorer queries.
@MappableClass()
class GamebaseFilters with GamebaseFiltersMappable {
  const GamebaseFilters({
    this.timeControls = const [],
    this.minRating,
    this.maxRating,
    this.playerIds = const [],
    this.selectedPlayers = const [],
    this.playerColor,
    this.gameResult,
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

  /// Player color filter (null = both sides)
  final GamebasePlayerColor? playerColor;

  /// Game result filter (null = all results)
  final GamebaseGameResult? gameResult;
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
  bool get isAtLatestMove => currentMoveIndex == maxNavigableMoveIndex;

  /// Check if can go back
  bool get canGoBack => currentMoveIndex >= 0;

  /// Check if can go forward (either replay a stored move or play the most-played aggregate)
  bool get canGoForward =>
      currentMoveIndex < maxNavigableMoveIndex || moveAggregates.isNotEmpty;

  /// Current backend move_number (1-indexed ply position).
  int get currentMoveNumber => currentMoveIndex + 2;

  /// Last move index available in the explored line.
  int get maxNavigableMoveIndex =>
      moveHistory.isEmpty ? -1 : moveHistory.length - 1;

  /// Explored move line up to the currently selected position.
  List<String> get exploredMoves =>
      currentMoveIndex >= 0
          ? moveHistory.sublist(0, currentMoveIndex + 1)
          : const <String>[];

  /// Get total games in current position
  int get totalGames => moveAggregates.fold(0, (sum, agg) => sum + agg.total);

  /// Check if has any active filters
  bool get hasActiveFilters =>
      filters.timeControls.isNotEmpty ||
      filters.minRating != null ||
      filters.maxRating != null ||
      filters.playerIds.isNotEmpty ||
      filters.playerColor != null ||
      filters.gameResult != null;
}

/// Maps a [GameFilter] (player profile) into [GamebaseFilters] (explorer).
///
/// Time control, rating range, color, and result have equivalents in the
/// explorer. ECO and year filters are dropped (no explorer equivalent).
extension GameFilterToGamebaseFilters on GameFilter {
  GamebaseFilters toGamebaseFilters() {
    final List<TimeControl> timeControls;
    switch (timeControl) {
      case GameTimeControlFilter.classical:
        timeControls = [TimeControl.classical];
      case GameTimeControlFilter.rapid:
        timeControls = [TimeControl.rapid];
      case GameTimeControlFilter.blitz:
        timeControls = [TimeControl.blitz];
      case GameTimeControlFilter.all:
        timeControls = [];
    }

    // Explorer slider range is 1000–3500. Clamp and null-out when at boundary.
    final clampedMin = minRating.clamp(1000, 3500);
    final clampedMax = maxRating.clamp(1000, 3500);

    final GamebasePlayerColor? playerColor;
    switch (color) {
      case GameColorFilter.white:
        playerColor = GamebasePlayerColor.white;
      case GameColorFilter.black:
        playerColor = GamebasePlayerColor.black;
      case GameColorFilter.all:
        playerColor = null;
    }

    final GamebaseGameResult? gameResult;
    switch (result) {
      case GameResultFilter.whiteWins:
        gameResult = GamebaseGameResult.whiteWins;
      case GameResultFilter.blackWins:
        gameResult = GamebaseGameResult.blackWins;
      case GameResultFilter.draw:
        gameResult = GamebaseGameResult.draw;
      case GameResultFilter.all:
        gameResult = null;
    }

    return GamebaseFilters(
      timeControls: timeControls,
      minRating: clampedMin > 1000 ? clampedMin : null,
      maxRating: clampedMax < 3500 ? clampedMax : null,
      playerColor: playerColor,
      gameResult: gameResult,
    );
  }

  /// Whether this filter has any fields that map to explorer filters.
  bool get hasExplorerMappableFilters =>
      timeControl != GameTimeControlFilter.all ||
      color != GameColorFilter.all ||
      result != GameResultFilter.all ||
      minRating != 1000 ||
      maxRating != 3500;
}
