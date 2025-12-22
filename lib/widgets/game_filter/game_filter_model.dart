import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/material.dart';

/// Result filter options for chess games
enum GameResultFilter {
  all,
  whiteWins,
  blackWins,
  draw,
}

extension GameResultFilterX on GameResultFilter {
  String get displayText {
    switch (this) {
      case GameResultFilter.all:
        return 'All Results';
      case GameResultFilter.whiteWins:
        return '1-0';
      case GameResultFilter.blackWins:
        return '0-1';
      case GameResultFilter.draw:
        return '½-½';
    }
  }

  String? get statusValue {
    switch (this) {
      case GameResultFilter.all:
        return null;
      case GameResultFilter.whiteWins:
        return '1-0';
      case GameResultFilter.blackWins:
        return '0-1';
      case GameResultFilter.draw:
        return '1/2-1/2';
    }
  }

  bool matches(GameStatus status) {
    switch (this) {
      case GameResultFilter.all:
        return true;
      case GameResultFilter.whiteWins:
        return status == GameStatus.whiteWins;
      case GameResultFilter.blackWins:
        return status == GameStatus.blackWins;
      case GameResultFilter.draw:
        return status == GameStatus.draw;
    }
  }
}

/// Color filter options
enum GameColorFilter { all, white, black }

extension GameColorFilterX on GameColorFilter {
  String get displayText {
    switch (this) {
      case GameColorFilter.all:
        return 'All Colors';
      case GameColorFilter.white:
        return 'White';
      case GameColorFilter.black:
        return 'Black';
    }
  }
}

/// Time control filter options
enum GameTimeControlFilter { all, rapid, blitz, classical }

extension GameTimeControlFilterX on GameTimeControlFilter {
  String get displayText {
    switch (this) {
      case GameTimeControlFilter.all:
        return 'All Time Controls';
      case GameTimeControlFilter.rapid:
        return 'Rapid';
      case GameTimeControlFilter.blitz:
        return 'Blitz';
      case GameTimeControlFilter.classical:
        return 'Classical';
    }
  }

  /// Icon data for time control display
  IconData get icon {
    switch (this) {
      case GameTimeControlFilter.all:
        return Icons.timer_outlined;
      case GameTimeControlFilter.rapid:
        return Icons.speed_outlined;
      case GameTimeControlFilter.blitz:
        return Icons.bolt;
      case GameTimeControlFilter.classical:
        return Icons.psychology_outlined;
    }
  }
}

/// ECO opening filter - supports individual ECO codes (A00-E99)
class GameEcoFilter {
  const GameEcoFilter({this.code});

  /// The specific ECO code (e.g., "B90", "C89") or null for all openings
  final String? code;

  /// Factory for "all openings" filter
  static const GameEcoFilter all = GameEcoFilter();

  /// Create a filter for a specific ECO code
  factory GameEcoFilter.forCode(String code) => GameEcoFilter(code: code.toUpperCase());

  /// Whether this filter shows all openings
  bool get isAll => code == null;

  /// Get the category letter (A, B, C, D, E) or null
  String? get categoryLetter => code?.isNotEmpty == true ? code![0] : null;

  /// Display text for the filter
  String get displayText => code ?? 'All Openings';

  /// Check if a game's ECO code matches this filter
  bool matches(String? eco) {
    if (isAll) return true;
    if (eco == null || eco.isEmpty) return false;
    return eco.toUpperCase().startsWith(code!);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GameEcoFilter && other.code == code;
  }

  @override
  int get hashCode => code.hashCode;
}

/// Complete filter state for chess games
class GameFilter {
  const GameFilter({
    this.result = GameResultFilter.all,
    this.color = GameColorFilter.all,
    this.timeControl = GameTimeControlFilter.all,
    GameEcoFilter? eco,
    this.minYear = 1990,
    this.maxYear = 2025,
    this.minRating = 1000,
    this.maxRating = 3500,
  }) : eco = eco ?? GameEcoFilter.all;

  final GameResultFilter result;
  final GameColorFilter color;
  final GameTimeControlFilter timeControl;
  final GameEcoFilter eco;
  final int minYear;
  final int maxYear;
  final int minRating;
  final int maxRating;

  /// Check if any filter is active (not default)
  bool get hasActiveFilters =>
      result != GameResultFilter.all ||
      color != GameColorFilter.all ||
      timeControl != GameTimeControlFilter.all ||
      !eco.isAll ||
      minYear != 1990 ||
      maxYear != DateTime.now().year ||
      minRating != 1000 ||
      maxRating != 3500;

  /// Count of active filters
  int get activeFilterCount {
    int count = 0;
    if (result != GameResultFilter.all) count++;
    if (color != GameColorFilter.all) count++;
    if (timeControl != GameTimeControlFilter.all) count++;
    if (!eco.isAll) count++;
    if (minYear != 1990 || maxYear != DateTime.now().year) count++;
    if (minRating != 1000 || maxRating != 3500) count++;
    return count;
  }

  GameFilter copyWith({
    GameResultFilter? result,
    GameColorFilter? color,
    GameTimeControlFilter? timeControl,
    GameEcoFilter? eco,
    int? minYear,
    int? maxYear,
    int? minRating,
    int? maxRating,
  }) {
    return GameFilter(
      result: result ?? this.result,
      color: color ?? this.color,
      timeControl: timeControl ?? this.timeControl,
      eco: eco ?? this.eco,
      minYear: minYear ?? this.minYear,
      maxYear: maxYear ?? this.maxYear,
      minRating: minRating ?? this.minRating,
      maxRating: maxRating ?? this.maxRating,
    );
  }

  static GameFilter defaultFilter() => GameFilter(maxYear: DateTime.now().year);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GameFilter &&
        other.result == result &&
        other.color == color &&
        other.timeControl == timeControl &&
        other.eco == eco &&
        other.minYear == minYear &&
        other.maxYear == maxYear &&
        other.minRating == minRating &&
        other.maxRating == maxRating;
  }

  @override
  int get hashCode => Object.hash(
        result,
        color,
        timeControl,
        eco,
        minYear,
        maxYear,
        minRating,
        maxRating,
      );
}

/// Helper to filter games locally based on GameFilter
class GameFilterHelper {
  /// Apply filter to a list of games
  ///
  /// [targetFideId] - When provided, color filter checks if target player
  /// played as white/black using FIDE ID matching (most accurate)
  ///
  /// [playerNameQuery] - Fallback for color filter when targetFideId not
  /// available, uses name containment matching
  static List<GamesTourModel> applyFilter(
    List<GamesTourModel> games,
    GameFilter filter, {
    String? playerNameQuery,
    int? targetFideId,
  }) {
    return games.where((game) {
      // Result filter
      if (!filter.result.matches(game.gameStatus)) return false;

      // Time control filter
      if (filter.timeControl != GameTimeControlFilter.all) {
        final inferred = _inferTimeControl(game);
        if (inferred != filter.timeControl) return false;
      }

      // ECO filter - uses the new class-based filter
      if (!filter.eco.matches(game.eco)) return false;

      // Year filter
      final year = game.lastMoveTime?.year;
      if (year != null) {
        if (year < filter.minYear || year > filter.maxYear) return false;
      }

      // Rating filter - check both players
      final avgRating =
          (game.whitePlayer.rating + game.blackPlayer.rating) / 2;
      if (avgRating < filter.minRating || avgRating > filter.maxRating) {
        return false;
      }

      // Color filter - determine if target player is white or black
      if (filter.color != GameColorFilter.all) {
        bool isTargetWhite = false;
        bool isTargetBlack = false;

        // Use FIDE ID matching when available (most accurate)
        if (targetFideId != null) {
          isTargetWhite = game.whitePlayer.fideId == targetFideId;
          isTargetBlack = game.blackPlayer.fideId == targetFideId;
        } else if (playerNameQuery != null && playerNameQuery.isNotEmpty) {
          // Fallback to name matching
          final qLower = playerNameQuery.toLowerCase();
          isTargetWhite = game.whitePlayer.name.toLowerCase().contains(qLower);
          isTargetBlack = game.blackPlayer.name.toLowerCase().contains(qLower);
        }

        // Only apply filter if we could identify the target player
        if (targetFideId != null ||
            (playerNameQuery != null && playerNameQuery.isNotEmpty)) {
          if (filter.color == GameColorFilter.white && !isTargetWhite) {
            return false;
          }
          if (filter.color == GameColorFilter.black && !isTargetBlack) {
            return false;
          }
        }
      }

      return true;
    }).toList();
  }

  /// Infer time control from game clock data
  /// Uses whiteClockSeconds (from DB last_clock_white) as primary source,
  /// falls back to whiteClockCentiseconds (from players JSON)
  static GameTimeControlFilter _inferTimeControl(GamesTourModel game) {
    // Try whiteClockSeconds first (from last_clock_white DB column, more reliable)
    if (game.whiteClockSeconds != null && game.whiteClockSeconds! > 0) {
      final baseSeconds = game.whiteClockSeconds!;
      if (baseSeconds >= 1800) return GameTimeControlFilter.classical;
      if (baseSeconds >= 600) return GameTimeControlFilter.rapid;
      return GameTimeControlFilter.blitz;
    }

    // Fall back to whiteClockCentiseconds (from players JSON)
    if (game.whiteClockCentiseconds > 0) {
      final baseSeconds = (game.whiteClockCentiseconds / 100).round();
      if (baseSeconds >= 1800) return GameTimeControlFilter.classical;
      if (baseSeconds >= 600) return GameTimeControlFilter.rapid;
      return GameTimeControlFilter.blitz;
    }

    return GameTimeControlFilter.all;
  }
}
