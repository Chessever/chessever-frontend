import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
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
    this.isOnline,
    this.yearFrom,
    this.yearTo,
    this.sortBy = GamebaseSortField.date,
    this.sortDirection = GamebaseSortDirection.desc,
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

  final bool? isOnline;

  /// Minimum game year filter
  final int? yearFrom;

  /// Maximum game year filter
  final int? yearTo;

  /// Field to sort by
  final GamebaseSortField sortBy;

  /// Direction of sorting
  final GamebaseSortDirection sortDirection;
}

/// State for the Gamebase explorer screen.
@MappableClass()
class GamebaseExplorerState with GamebaseExplorerStateMappable {
  const GamebaseExplorerState({
    this.currentFen = '', // Empty by default; setPosition() sets the real FEN
    this.moveAggregates = const [],
    this.isLoading = false,
    this.error,
    this.filters = const GamebaseFilters(),
    this.selectedGame,
    this.game,
    this.movePointer = const [],
  });

  /// Current position in FEN notation
  final String currentFen;

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

  /// The underlying game model with variations
  final ChessGame? game;

  /// The current position in the game tree
  final ChessMovePointer movePointer;

  /// Check if at initial position
  bool get isAtInitialPosition => game != null ? movePointer.isEmpty : true;

  /// Check if can go back
  bool get canGoBack => game != null ? movePointer.isNotEmpty : false;

  /// Check if can go forward (either replay a stored move or play the most-played aggregate)
  bool get canGoForward {
    if (game != null) {
      // Logic from ChessGameNavigatorState
      final nextPointer = _nextPointerInGame(game!, movePointer);
      return nextPointer != null || moveAggregates.isNotEmpty;
    }
    return moveAggregates.isNotEmpty;
  }

  /// Current backend move_number (1-indexed ply position).
  int get currentMoveNumber =>
      game != null ? _pointerToPly(game!, movePointer) + 1 : 1;

  /// Explored move line up to the currently selected position.
  List<String> get exploredMoves {
    if (game != null) {
      return _pointerToUciPath(game!, movePointer);
    }
    return const <String>[];
  }

  /// Get total games in current position
  int get totalGames => moveAggregates.fold(0, (sum, agg) => sum + agg.total);

  /// Check if has any active filters
  bool get hasActiveFilters =>
      filters.timeControls.isNotEmpty ||
      filters.minRating != null ||
      filters.maxRating != null ||
      filters.playerIds.isNotEmpty ||
      filters.playerColor != null ||
      filters.gameResult != null ||
      filters.yearFrom != null ||
      filters.yearTo != null ||
      filters.isOnline != null;

  // Helper methods to replicate navigator logic within state
  static int _pointerToPly(ChessGame game, ChessMovePointer pointer) {
    if (pointer.isEmpty) {
      return 0; // Assuming start from ply 0 for now or calculate from FEN
    }
    // For simplicity, let's just count moves in the pointer path
    // Actually ply should be depth in tree if we count properly.
    // A pointer like [5] is ply 5 (if starting from 0).
    // A pointer like [2, 0, 1] is move 2 in mainline, then variation 0, move 1 in that variation.
    // Total ply = 2 + 1 + 1? No.
    // Let's use a more accurate way if needed.
    return _pointerToUciPath(game, pointer).length;
  }

  static List<String> _pointerToUciPath(
    ChessGame game,
    ChessMovePointer pointer,
  ) {
    final path = <String>[];
    if (pointer.isEmpty) return path;

    ChessLine? currentList = game.mainline;
    ChessMove? currentMove;

    for (var i = 0; i < pointer.length; i++) {
      final index = pointer[i];
      if (i.isEven) {
        final line = currentList;
        if (line == null || index >= line.length) {
          break;
        }
        // Take all moves up to and including the index
        for (var j = 0; j <= index; j++) {
          path.add(line[j].uci);
        }
        currentMove = line[index];
        // If this is the last element, we are done.
        if (i == pointer.length - 1) {
          break;
        }
      } else {
        final variations = currentMove?.variations;
        if (currentMove == null ||
            variations == null ||
            index >= variations.length) {
          break;
        }
        final variation = variations[index];
        if (variation.isNotEmpty) {
          if (variation.first.turn == currentMove.turn) {
            if (path.isNotEmpty) {
              path.removeLast();
            }
          }
        }
        currentList = variation;
        // After switching to a variation, we don't add the move yet,
        // it will be added in the next (even) iteration.
      }
    }
    return path;
  }

  static ChessMovePointer? _nextPointerInGame(
    ChessGame game,
    ChessMovePointer pointer,
  ) {
    // Replicate _nextPointerInGame from ChessGameNavigator for canGoForward logic
    if (game.mainline.isEmpty) return null;
    if (pointer.isEmpty) return [0];

    final currentLine = _lineForPointer(game, pointer);
    if (currentLine == null) return null;

    final lastIndex = pointer.last;
    if (lastIndex + 1 < currentLine.length) {
      final next = List<int>.of(pointer);
      next.last = lastIndex + 1;
      return next;
    }
    return null;
  }

  static ChessLine? _lineForPointer(ChessGame game, ChessMovePointer pointer) {
    ChessLine? line = game.mainline;
    ChessMove? move;
    for (var i = 0; i < pointer.length; i++) {
      final index = pointer[i];
      if (i.isEven) {
        if (line == null || index >= line.length) return null;
        move = line[index];
      } else {
        final variations = move?.variations;
        if (variations == null || index >= variations.length) return null;
        line = variations[index];
      }
    }
    return line;
  }
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

    // Explorer slider range is absoluteMinRating–absoluteMaxRating. Clamp and null-out when at boundary.
    final clampedMin = minRating.clamp(
      GameFilter.absoluteMinRating,
      GameFilter.absoluteMaxRating,
    );
    final clampedMax = maxRating.clamp(
      GameFilter.absoluteMinRating,
      GameFilter.absoluteMaxRating,
    );

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
      minRating: clampedMin > GameFilter.absoluteMinRating ? clampedMin : null,
      maxRating: clampedMax < GameFilter.absoluteMaxRating ? clampedMax : null,
      playerColor: playerColor,
      gameResult: gameResult,
      yearFrom: minYear > GameFilter.absoluteMinYear ? minYear : null,
      yearTo: maxYear < DateTime.now().year ? maxYear : null,
    );
  }

  /// Whether this filter has any fields that map to explorer filters.
  bool get hasExplorerMappableFilters =>
      timeControl != GameTimeControlFilter.all ||
      color != GameColorFilter.all ||
      result != GameResultFilter.all ||
      minRating != GameFilter.defaultMinRating ||
      maxRating != GameFilter.absoluteMaxRating ||
      minYear != GameFilter.absoluteMinYear ||
      maxYear != DateTime.now().year;
}
