import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';

/// Result filter options for chess games
enum GameResultFilter { all, whiteWins, blackWins, draw }

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

/// Finish-length filter for miniature-style game collections.
enum GameFinishFilter { all, byMove25, byMove20, byMove15 }

extension GameFinishFilterX on GameFinishFilter {
  String get displayText {
    switch (this) {
      case GameFinishFilter.all:
        return 'All';
      case GameFinishFilter.byMove25:
        return '≤25';
      case GameFinishFilter.byMove20:
        return '≤20';
      case GameFinishFilter.byMove15:
        return '≤15';
    }
  }

  int? get maxMoveNumber {
    switch (this) {
      case GameFinishFilter.all:
        return null;
      case GameFinishFilter.byMove25:
        return 25;
      case GameFinishFilter.byMove20:
        return 20;
      case GameFinishFilter.byMove15:
        return 15;
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

/// Live/completed filter — filters games by ongoing vs finished state.
/// Mirrors the EventStatus filter from the event view, but applied to games.
enum GameLiveFilter { all, live, completed }

extension GameLiveFilterX on GameLiveFilter {
  String get displayText {
    switch (this) {
      case GameLiveFilter.all:
        return 'All Games';
      case GameLiveFilter.live:
        return 'Live';
      case GameLiveFilter.completed:
        return 'Completed';
    }
  }
}

/// Online vs OTB filter options
enum GameOnlineFilter { all, online, otb }

extension GameOnlineFilterX on GameOnlineFilter {
  String get displayText {
    switch (this) {
      case GameOnlineFilter.all:
        return 'All Formats';
      case GameOnlineFilter.online:
        return 'Online Only';
      case GameOnlineFilter.otb:
        return 'OTB Only';
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

  /// Asset path for time control icon (matches event card icons)
  String? get assetPath {
    switch (this) {
      case GameTimeControlFilter.all:
        return null; // No icon for "all"
      case GameTimeControlFilter.rapid:
        return 'assets/pngs/rapid.png';
      case GameTimeControlFilter.blitz:
        return 'assets/pngs/blitz.png';
      case GameTimeControlFilter.classical:
        return 'assets/pngs/classical.png';
    }
  }
}

/// Tournament type filter options
enum GameTournamentTypeFilter { all, roundRobin, swiss, knockout, team }

extension GameTournamentTypeFilterX on GameTournamentTypeFilter {
  String get displayText {
    switch (this) {
      case GameTournamentTypeFilter.all:
        return 'All Types';
      case GameTournamentTypeFilter.roundRobin:
        return 'Round Robin';
      case GameTournamentTypeFilter.swiss:
        return 'Swiss';
      case GameTournamentTypeFilter.knockout:
        return 'Knockout';
      case GameTournamentTypeFilter.team:
        return 'Team';
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
  factory GameEcoFilter.forCode(String code) =>
      GameEcoFilter(code: code.toUpperCase());

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

/// A single ordered sort key: a field plus its direction. Multiple criteria
/// combine into a multi-key sort (applied in list order — index 0 is the
/// primary key, index 1 the tie-breaker, and so on).
class GameSortCriterion {
  const GameSortCriterion({
    required this.field,
    this.direction = GamebaseSortDirection.desc,
  });

  final GamebaseSortField field;
  final GamebaseSortDirection direction;

  GameSortCriterion copyWith({
    GamebaseSortField? field,
    GamebaseSortDirection? direction,
  }) {
    return GameSortCriterion(
      field: field ?? this.field,
      direction: direction ?? this.direction,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GameSortCriterion &&
          other.field == field &&
          other.direction == direction;

  @override
  int get hashCode => Object.hash(field, direction);
}

/// Complete filter state for chess games
class GameFilter {
  static const int defaultMinYear = 1800;
  static const int absoluteMinYear = 1800;
  static const int defaultMinRating = 0;
  static const int absoluteMinRating = 0;
  static const int absoluteMaxRating = 3500;

  GameFilter({
    this.result = GameResultFilter.all,
    this.color = GameColorFilter.all,
    this.finish = GameFinishFilter.all,
    this.timeControl = GameTimeControlFilter.all,
    this.online = GameOnlineFilter.all,
    this.live = GameLiveFilter.all,
    GameEcoFilter? eco,
    this.minYear = defaultMinYear,
    int? maxYear,
    this.minRating = defaultMinRating,
    this.maxRating = absoluteMaxRating,
    List<GameSortCriterion>? sorts,
  }) : eco = eco ?? GameEcoFilter.all,
       maxYear = maxYear ?? DateTime.now().year,
       sorts = sorts ?? const [];

  final GameResultFilter result;
  final GameColorFilter color;
  final GameFinishFilter finish;
  final GameTimeControlFilter timeControl;
  final GameOnlineFilter online;
  final GameLiveFilter live;
  final GameEcoFilter eco;
  final int minYear;
  final int maxYear;
  final int minRating;
  final int maxRating;

  /// Ordered multi-key presentation sort, surfaced when the caller's dialog
  /// enables the Sort section (database/My-Likes contexts). Empty means the
  /// consumer falls back to its own default ordering. Sort is *not* counted as
  /// an "active filter" ([activeFilterCount]) — it shapes presentation, not the
  /// result set — but it is surfaced in the filter-bar badge via
  /// [activeSortCount] so users can tell a sort is applied.
  final List<GameSortCriterion> sorts;

  /// Whether any sort criterion is applied.
  bool get hasActiveSorts => sorts.isNotEmpty;

  /// Number of applied sort criteria (folded into the filter-bar badge count).
  int get activeSortCount => sorts.length;

  /// Check if any filter is active (not default)
  bool get hasActiveFilters =>
      result != GameResultFilter.all ||
      color != GameColorFilter.all ||
      finish != GameFinishFilter.all ||
      timeControl != GameTimeControlFilter.all ||
      online != GameOnlineFilter.all ||
      live != GameLiveFilter.all ||
      !eco.isAll ||
      minYear != defaultMinYear ||
      maxYear != DateTime.now().year ||
      minRating != defaultMinRating ||
      maxRating != absoluteMaxRating;

  /// Count of active filters
  int get activeFilterCount {
    int count = 0;
    if (result != GameResultFilter.all) count++;
    if (color != GameColorFilter.all) count++;
    if (finish != GameFinishFilter.all) count++;
    if (timeControl != GameTimeControlFilter.all) count++;
    if (online != GameOnlineFilter.all) count++;
    if (live != GameLiveFilter.all) count++;
    if (!eco.isAll) count++;
    if (minYear != defaultMinYear || maxYear != DateTime.now().year) count++;
    if (minRating != defaultMinRating ||
        maxRating != GameFilter.absoluteMaxRating) {
      count++;
    }
    return count;
  }

  GameFilter copyWith({
    GameResultFilter? result,
    GameColorFilter? color,
    GameFinishFilter? finish,
    GameTimeControlFilter? timeControl,
    GameOnlineFilter? online,
    GameLiveFilter? live,
    GameEcoFilter? eco,
    int? minYear,
    int? maxYear,
    int? minRating,
    int? maxRating,
    List<GameSortCriterion>? sorts,
  }) {
    return GameFilter(
      result: result ?? this.result,
      color: color ?? this.color,
      finish: finish ?? this.finish,
      timeControl: timeControl ?? this.timeControl,
      online: online ?? this.online,
      live: live ?? this.live,
      eco: eco ?? this.eco,
      minYear: minYear ?? this.minYear,
      maxYear: maxYear ?? this.maxYear,
      minRating: minRating ?? this.minRating,
      maxRating: maxRating ?? this.maxRating,
      sorts: sorts ?? this.sorts,
    );
  }

  static GameFilter defaultFilter() => GameFilter(maxYear: DateTime.now().year);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GameFilter &&
        other.result == result &&
        other.color == color &&
        other.finish == finish &&
        other.timeControl == timeControl &&
        other.online == online &&
        other.live == live &&
        other.eco == eco &&
        other.minYear == minYear &&
        other.maxYear == maxYear &&
        other.minRating == minRating &&
        other.maxRating == maxRating &&
        listEquals(other.sorts, sorts);
  }

  @override
  int get hashCode => Object.hash(
    result,
    color,
    finish,
    timeControl,
    online,
    live,
    eco,
    minYear,
    maxYear,
    minRating,
    maxRating,
    Object.hashAll(sorts),
  );
}

/// Helper to filter games locally based on GameFilter
class GameFilterHelper {
  /// A game is live only while it is marked ongoing and belongs to today.
  ///
  /// Prefer `lastMoveTime` because it proves active play. For not-yet-moved
  /// same-day games, fall back to the scheduled game day/date.
  static bool isLiveNow(GamesTourModel game, {DateTime? now}) {
    if (!game.effectiveGameStatus.isOngoing) return false;

    final comparisonTime = now ?? DateTime.now();
    if (game.lastMoveTime != null) {
      return _isSameUtcDay(game.lastMoveTime!, comparisonTime);
    }

    final liveDate = game.gameDay ?? game.dateStart;
    if (liveDate == null) return false;

    return _isSameCalendarDay(liveDate, _todayUtc(comparisonTime));
  }

  static bool _isSameUtcDay(DateTime left, DateTime right) {
    final leftUtc = left.toUtc();
    final rightUtc = right.toUtc();
    return leftUtc.year == rightUtc.year &&
        leftUtc.month == rightUtc.month &&
        leftUtc.day == rightUtc.day;
  }

  static DateTime _todayUtc(DateTime now) {
    final nowUtc = now.toUtc();
    return DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
  }

  static bool _isSameCalendarDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

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
      // Live/completed filter — use effectiveGameStatus so games whose clock
      // hit 00:00 but DB hasn't caught up still count as completed. A stale
      // ongoing marker from an old day is neither live nor completed.
      if (filter.live != GameLiveFilter.all) {
        final isLive = isLiveNow(game);
        final isCompleted = game.effectiveGameStatus.isFinished;
        if (filter.live == GameLiveFilter.live && !isLive) return false;
        if (filter.live == GameLiveFilter.completed && !isCompleted) {
          return false;
        }
      }

      // Result filter
      if (!filter.result.matches(game.gameStatus)) return false;

      // Finish filter
      if (filter.finish != GameFinishFilter.all) {
        final moveNumber = _estimateFinalMoveNumber(game);
        final maxMoveNumber = filter.finish.maxMoveNumber;
        if (moveNumber == null ||
            maxMoveNumber == null ||
            moveNumber > maxMoveNumber) {
          return false;
        }
      }

      // Time control filter
      if (filter.timeControl != GameTimeControlFilter.all) {
        final inferred = _inferTimeControl(game);
        // If we can't determine the time control (returns 'all'), don't filter out the game
        // This prevents games with missing time_control data from being excluded
        if (inferred != GameTimeControlFilter.all &&
            inferred != filter.timeControl) {
          return false;
        }
      }

      // Online vs OTB filter
      if (filter.online != GameOnlineFilter.all) {
        final isOnline = game.isOnline;
        if (filter.online == GameOnlineFilter.online && !isOnline) return false;
        if (filter.online == GameOnlineFilter.otb && isOnline) return false;
      }

      // ECO filter - uses the new class-based filter
      if (!filter.eco.matches(game.eco)) return false;

      // Year filter
      final year = game.lastMoveTime?.year;
      if (year != null) {
        if (year < filter.minYear || year > filter.maxYear) return false;
      }

      // Rating filter - use the game's top rating
      final cardElo = game.cardElo;
      if (cardElo < filter.minRating || cardElo > filter.maxRating) {
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

  /// Get time control from game data
  /// Primary source: timeControl field from group_broadcasts table
  /// No fallback - we only use the authoritative time_control from the database
  /// Using remaining clock time is unreliable (a classical game with 5min left
  /// would be wrongly classified as blitz)
  static GameTimeControlFilter _inferTimeControl(GamesTourModel game) {
    // Use the actual time_control from group_broadcasts (via tours join)
    if (game.timeControl != null && game.timeControl!.isNotEmpty) {
      switch (game.timeControl!.toLowerCase()) {
        case 'standard':
        case 'classical':
          return GameTimeControlFilter.classical;
        case 'rapid':
          return GameTimeControlFilter.rapid;
        case 'blitz':
          return GameTimeControlFilter.blitz;
        case 'bullet':
          return GameTimeControlFilter.blitz; // Treat bullet as blitz
      }
    }

    // No fallback - if timeControl is not set in the database, we can't reliably
    // determine it. Return 'all' which means "unknown" and won't filter out the game.
    return GameTimeControlFilter.all;
  }

  static int? _estimateFinalMoveNumber(GamesTourModel game) {
    final pgn = game.pgn;
    if (pgn != null && pgn.isNotEmpty) {
      return _estimateMoveNumberFromPgn(pgn);
    }

    final lastMove = game.lastMove;
    if (lastMove == null || lastMove.isEmpty) return null;
    return _estimateMoveNumberFromPgn(lastMove);
  }

  static int? _estimateMoveNumberFromPgn(String text) {
    final cleaned = text
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'\{[^}]*\}'), ' ')
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'\$\d+'), ' ');
    final matches = RegExp(r'\b(\d{1,3})\s*\.{1,3}').allMatches(cleaned);
    int? maxMove;
    for (final match in matches) {
      final value = int.tryParse(match.group(1) ?? '');
      if (value == null) continue;
      if (maxMove == null || value > maxMove) maxMove = value;
    }
    return maxMove;
  }
}
