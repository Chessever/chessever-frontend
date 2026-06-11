// repositories/game_repository.dart
import 'dart:convert';

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gameRepositoryProvider = AutoDisposeProvider<GameRepository>((ref) {
  return GameRepository();
});

/// Chess title prefixes that may appear before player names
const _chessTitlePrefixes = [
  'GM ',
  'IM ',
  'FM ',
  'CM ',
  'NM ',
  'WGM ',
  'WIM ',
  'WFM ',
  'WCM ',
  'WNM ',
];

/// Strips chess title prefix from a player name if present.
/// e.g., "GM Nakamura, Hikaru" -> "Nakamura, Hikaru"
String _stripTitlePrefix(String playerName) {
  final trimmed = playerName.trim();
  for (final prefix in _chessTitlePrefixes) {
    if (trimmed.startsWith(prefix)) {
      return trimmed.substring(prefix.length).trim();
    }
  }
  return trimmed;
}

const String _gameListSelectColumns = '''
          id,
          round_id,
          round_slug,
          tour_id,
          tour_slug,
          name,
          fen,
          pgn,
          players,
          last_move,
          think_time,
          status,
          search,
          lichess_id,
          player_white,
          player_black,
          date_start,
          time_start,
          board_nr,
          last_move_time,
          game_day,
          last_clock_white,
          last_clock_black,
          eco,
          opening_name,
          tours!games_tour_id_fkey(
            avg_elo,
            group_broadcasts!tours_group_broadcast_id_fkey(time_control)
          )
        ''';

/// Same column list as [_gameListSelectColumns], but forces an INNER join on
/// `tours` + `group_broadcasts` so that filtering by `tours.group_broadcasts.time_control`
/// narrows rows instead of just narrowing the embedded payload.
const String _gameListSelectColumnsInnerTc = '''
          id,
          round_id,
          round_slug,
          tour_id,
          tour_slug,
          name,
          fen,
          pgn,
          players,
          last_move,
          think_time,
          status,
          search,
          lichess_id,
          player_white,
          player_black,
          date_start,
          time_start,
          board_nr,
          last_move_time,
          game_day,
          last_clock_white,
          last_clock_black,
          eco,
          opening_name,
          tours!games_tour_id_fkey!inner(
            avg_elo,
            group_broadcasts!tours_group_broadcast_id_fkey!inner(time_control)
          )
        ''';

const int _tourGamesFetchPageSize = 1000;

@visibleForTesting
bool shouldFetchAnotherTourGamesPage(
  int fetchedCount, {
  int pageSize = _tourGamesFetchPageSize,
}) {
  return fetchedCount == pageSize;
}

/// Maps a `GameFilter` to the named-parameter map consumed by the Supabase
/// RPCs (`get_distinct_dates_for_*`, etc). Keeps the mapping in one place so
/// every server-side query layers in the same filters.
Map<String, dynamic> _gameFilterRpcParams(GameFilter? filter) {
  final params = <String, dynamic>{};
  if (filter == null) return params;

  // Live / completed
  switch (filter.live) {
    case GameLiveFilter.live:
      params['p_status'] = 'live';
      break;
    case GameLiveFilter.completed:
      params['p_status'] = 'completed';
      break;
    case GameLiveFilter.all:
      break;
  }

  // Result
  switch (filter.result) {
    case GameResultFilter.whiteWins:
      params['p_result'] = '1-0';
      break;
    case GameResultFilter.blackWins:
      params['p_result'] = '0-1';
      break;
    case GameResultFilter.draw:
      params['p_result'] = '1/2';
      break;
    case GameResultFilter.all:
      break;
  }

  // Time control → DB tag on group_broadcasts
  final tc = _timeControlDbValue(filter.timeControl);
  if (tc != null) params['p_time_control'] = tc;

  // Year range — only send when narrowed
  if (filter.minYear != GameFilter.defaultMinYear) {
    params['p_min_year'] = filter.minYear;
  }
  if (filter.maxYear < DateTime.now().year) {
    params['p_max_year'] = filter.maxYear;
  }

  // Rating range — only send when narrowed
  if (filter.minRating > GameFilter.defaultMinRating) {
    params['p_min_rating'] = filter.minRating;
  }
  if (filter.maxRating < GameFilter.absoluteMaxRating) {
    params['p_max_rating'] = filter.maxRating;
  }

  // ECO prefix
  if (!filter.eco.isAll && (filter.eco.code?.isNotEmpty ?? false)) {
    params['p_eco'] = filter.eco.code;
  }

  // Color (white / black side)
  switch (filter.color) {
    case GameColorFilter.white:
      params['p_color'] = 'white';
      break;
    case GameColorFilter.black:
      params['p_color'] = 'black';
      break;
    case GameColorFilter.all:
      break;
  }
  return params;
}

String? _timeControlDbValue(GameTimeControlFilter tc) {
  switch (tc) {
    case GameTimeControlFilter.classical:
      return 'standard';
    case GameTimeControlFilter.rapid:
      return 'rapid';
    case GameTimeControlFilter.blitz:
      return 'blitz';
    case GameTimeControlFilter.all:
      return null;
  }
}

/// Status values that map to GameResultFilter.draw on the games table. The
/// table is denormalized and historic rows use any of these three encodings.
const List<String> _drawStatusValues = ['1/2', '1/2-1/2', '½-½'];

DateTime _todayUtc([DateTime? now]) {
  final nowUtc = (now ?? DateTime.now()).toUtc();
  return DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
}

String _dateKey(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String _currentLiveDayFilter() {
  final todayUtc = _todayUtc();
  final nextDayUtc = todayUtc.add(const Duration(days: 1));
  final dateStr = _dateKey(todayUtc);

  return 'and(last_move_time.gte.${todayUtc.toIso8601String()},last_move_time.lt.${nextDayUtc.toIso8601String()}),'
      'and(last_move_time.is.null,game_day.eq.$dateStr),'
      'and(last_move_time.is.null,game_day.is.null,date_start.eq.$dateStr)';
}

String _yearLowerBoundFilter(int year) {
  final startUtc = DateTime.utc(year).toIso8601String();
  final dateStr = '$year-01-01';
  return 'game_day.gte.$dateStr,'
      'and(game_day.is.null,last_move_time.gte.$startUtc),'
      'and(game_day.is.null,last_move_time.is.null,date_start.gte.$dateStr)';
}

String _yearUpperBoundFilter(int year) {
  final nextYearUtc = DateTime.utc(year + 1).toIso8601String();
  final nextYearDateStr = '${year + 1}-01-01';
  return 'game_day.lt.$nextYearDateStr,'
      'and(game_day.is.null,last_move_time.lt.$nextYearUtc),'
      'and(game_day.is.null,last_move_time.is.null,date_start.lt.$nextYearDateStr)';
}

bool _isSameCalendarDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

List<DateTime> _filterDatesForLiveFilter(
  List<DateTime> dates,
  GameFilter? filter,
) {
  if (filter?.live != GameLiveFilter.live) return dates;
  final todayUtc = _todayUtc();
  return dates.where((date) => _isSameCalendarDay(date, todayUtc)).toList();
}

class GameRepository extends BaseRepository {
  List<int> _parseFideIds(List<String> fideIds) {
    return fideIds.map((id) => int.tryParse(id)).whereType<int>().toList();
  }

  int? _parseFideId(String fideId) => int.tryParse(fideId);

  String _normalizeCountryCode(String countryCode) {
    return countryCode.trim().toUpperCase();
  }

  // Fetch games by round ID
  Future<List<Games>> getGamesByRoundId(String roundId) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .eq('round_id', roundId)
          .order('id', ascending: true);

      final games =
          (response as List).map((json) => Games.fromJson(json)).toList();
      return _deduplicateGames(games);
    });
  }

  // Fetch games by tour ID
  Future<List<Games>> getGamesByTourId(
    String tourId, {
    int? limit,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      final jsonList = <String>[];
      var pageOffset = offset;
      var remaining = limit;

      while (true) {
        final pageSize =
            remaining == null || remaining > _tourGamesFetchPageSize
                ? _tourGamesFetchPageSize
                : remaining;
        if (pageSize <= 0) {
          break;
        }

        final response = await supabase
            .from('games')
            .select(_gameListSelectColumns)
            .eq('tour_id', tourId)
            .order('id', ascending: true)
            .range(pageOffset, pageOffset + pageSize - 1);

        final responseList = response as List;
        jsonList.addAll(responseList.map((item) => json.encode(item)));

        if (!shouldFetchAnotherTourGamesPage(
          responseList.length,
          pageSize: pageSize,
        )) {
          break;
        }

        if (remaining != null) {
          remaining -= responseList.length;
          if (remaining <= 0) {
            break;
          }
        }

        pageOffset += responseList.length;
      }

      final games = await compute(_decodeGamesInIsolate, jsonList);

      return games;
    });
  }

  Future<Games> getGameWithPGN(String gameId) async {
    return handleApiCall(() async {
      final response =
          await supabase.from('games').select().eq('id', gameId).single();

      return Games.fromJson(response);
    });
  }

  // Fetch game by its Supabase UUID (games.id column).
  Future<Games> getGameById(String id) async {
    debugPrint('Fetching game by ID: $id');
    return handleApiCall(() async {
      final response =
          await supabase
              .from('games')
              .select(_gameListSelectColumns)
              .eq('id', id)
              .single();

      return Games.fromJson(response);
    });
  }

  // Fetch game by Lichess short ID (games.lichess_id column).
  Future<Games> getGameByLichessId(String lichessId) async {
    debugPrint('Fetching game by Lichess ID: $lichessId');
    return handleApiCall(() async {
      final response =
          await supabase
              .from('games')
              .select(_gameListSelectColumns)
              .eq('lichess_id', lichessId)
              .single();

      return Games.fromJson(response);
    });
  }

  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  /// Resolves a game from either a Supabase UUID or a Lichess short ID.
  /// UUID  → queries games.id
  /// Other → queries games.lichess_id (e.g. "4uVwSr9q")
  Future<Games> getGameByAnyId(String id) async {
    final trimmed = id.trim();
    if (_uuidPattern.hasMatch(trimmed)) {
      return getGameById(trimmed);
    }
    return getGameByLichessId(trimmed);
  }

  // Get all games for a specific player by fideId
  Future<List<Games>> getGamesByFideId(String fideId, {int? limit}) async {
    return handleApiCall(() async {
      debugPrint(
        '===== GameRepository: Fetching games for fideId: $fideId =====',
      );

      final fideIdInt = _parseFideId(fideId);
      if (fideIdInt == null) return <Games>[];

      // Query games where the fideId appears in the generated array column
      var query = supabase
          .from('games')
          .select(_gameListSelectColumns)
          .contains('player_fide_ids', [fideIdInt])
          .order('date_start', ascending: false)
          .order('time_start', ascending: false);

      if (limit != null) {
        query = query.limit(limit);
      }

      debugPrint(
        '===== GameRepository: Executing query with limit: $limit =====',
      );
      final response = await query;

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      return games;
    });
  }

  // Get games for a specific player by fideId with pagination
  Future<List<Games>> getGamesByFideIdPaginated(
    String fideId, {
    required int limit,
    required int offset,
  }) async {
    return handleApiCall(() async {
      final fideIdInt = _parseFideId(fideId);
      if (fideIdInt == null) return <Games>[];

      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .contains('player_fide_ids', [fideIdInt])
          .order('date_start', ascending: false)
          .order('time_start', ascending: false)
          .range(offset, offset + limit - 1);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      return games;
    });
  }

  // Get all games for a specific player by player name (for players without fideId)
  Future<List<Games>> getGamesByPlayerName(
    String playerName, {
    int? limit,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      // Strip title prefix if present (e.g., "GM Nakamura, Hikaru" -> "Nakamura, Hikaru")
      final normalizedName = _stripTitlePrefix(playerName);

      debugPrint(
        '===== GameRepository: Fetching games for player name: $playerName (normalized: $normalizedName) =====',
      );

      // Query games where player_white or player_black matches the name
      var query = supabase
          .from('games')
          .select(_gameListSelectColumns)
          .or(
            'player_white.eq."$normalizedName",player_black.eq."$normalizedName"',
          )
          .order('date_start', ascending: false)
          .order('time_start', ascending: false);

      if (limit != null) {
        query = query.range(offset, offset + limit - 1);
      }

      debugPrint(
        '===== GameRepository: Executing name query with limit: $limit =====',
      );
      final response = await query;

      debugPrint(
        '===== GameRepository: Received ${(response as List).length} games =====',
      );
      final games =
          (response as List).map((json) => Games.fromJson(json)).toList();
      return _deduplicateGames(games);
    });
  }

  // Get games for a specific player by name with pagination (for players without fideId)
  Future<List<Games>> getGamesByPlayerNamePaginated(
    String playerName, {
    required int limit,
    required int offset,
  }) async {
    return handleApiCall(() async {
      // Strip title prefix if present (e.g., "GM Nakamura, Hikaru" -> "Nakamura, Hikaru")
      final normalizedName = _stripTitlePrefix(playerName);

      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .or(
            'player_white.eq."$normalizedName",player_black.eq."$normalizedName"',
          )
          .order('date_start', ascending: false)
          .order('time_start', ascending: false)
          .range(offset, offset + limit - 1);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      return games;
    });
  }

  Future<String?> getGamePgn(String gameId) async {
    return handleApiCall(() async {
      final response =
          await supabase.from('games').select('pgn').eq('id', gameId).single();

      return response['pgn'] as String?;
    });
  }

  // Get games where any player has a specific country code
  Future<List<Games>> getGamesByCountryCode(String countryCode) async {
    return handleApiCall(() async {
      final normalizedCode = _normalizeCountryCode(countryCode);
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .contains('player_feds', [normalizedCode])
          .order('id', ascending: true);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      return games;
    });
  }

  // Get "For You" games - personalized feed based on favorited players, country, and high ELO
  // This fetches ALL matching games and sorting/pagination is done in the provider
  Future<List<Games>> getForYouGames({
    List<String>? favoritedFideIds,
    String? countryCode,
    int limit = 50,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      debugPrint('===== GameRepository: Fetching For You games =====');
      debugPrint('Favorited FIDE IDs: $favoritedFideIds');
      debugPrint('Country code: $countryCode');
      debugPrint('Limit: $limit, Offset: $offset');

      // Build the query based on what filters we have
      // If we have favorited players or country code, filter for them
      // Otherwise, just get high ELO games as fallback
      // Order by date_start first to group games by day, then by last_move_time
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .range(offset, offset + limit - 1);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      debugPrint('===== GameRepository: Fetched ${games.length} games =====');

      return games;
    });
  }

  // Get games by multiple FIDE IDs (for favorited players) with pagination
  Future<List<Games>> getGamesByMultipleFideIds({
    required List<String> fideIds,
    int limit = 50,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      final fideIdInts = _parseFideIds(fideIds);
      if (fideIdInts.isEmpty) {
        return <Games>[];
      }

      debugPrint(
        '===== GameRepository: Fetching games for ${fideIdInts.length} FIDE IDs =====',
      );

      // Order by date_start first to group games by day, then by last_move_time
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .overlaps('player_fide_ids', fideIdInts)
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .range(offset, offset + limit - 1);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      debugPrint(
        '===== GameRepository: Fetched ${games.length} games for favorited players =====',
      );

      return games;
    });
  }

  // Get games by country code with pagination
  Future<List<Games>> getGamesByCountryCodePaginated({
    required String countryCode,
    int limit = 50,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      final normalizedCode = _normalizeCountryCode(countryCode);
      debugPrint(
        '===== GameRepository: Fetching games for country $normalizedCode =====',
      );

      // Order by date_start first to group games by day, then by last_move_time
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .contains('player_feds', [normalizedCode])
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .range(offset, offset + limit - 1);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      debugPrint(
        '===== GameRepository: Fetched ${games.length} games for country =====',
      );

      return games;
    });
  }

  /// Get highest ELO games (fallback when no favorites/country)
  /// Only returns games where at least one player has ELO >= minElo (default 2500)
  Future<List<Games>> getHighEloGames({
    int minElo = 2500,
    int limit = 50,
    int offset = 0,
    bool onlyLive = false,
  }) async {
    return handleApiCall(() async {
      debugPrint(
        '===== GameRepository: Fetching high ELO games (>= $minElo) =====',
      );

      // Fetch more games than needed since we filter by ELO in Dart
      // (JSONB nested field filtering is complex in Supabase)
      dynamic query = supabase.from('games').select(_gameListSelectColumns);

      if (onlyLive) {
        query = query.eq('status', '*');
      }

      // Order by date_start first to group games by day, then by last_move_time
      query = query
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .range(
            offset,
            offset +
                limit * (onlyLive ? 2 : 3) -
                1, // Fetch extra to compensate for ELO filter
          );

      final response = await query;

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      var games = await compute(_decodeGamesInIsolate, jsonList);

      // Filter games where at least one player has ELO >= minElo
      games =
          games
              .where((game) {
                if (game.players == null || game.players!.isEmpty) return false;
                return game.players!.any((player) => player.rating >= minElo);
              })
              .take(limit)
              .toList();

      debugPrint(
        '===== GameRepository: Fetched ${games.length} high ELO games (>= $minElo) =====',
      );

      return games;
    });
  }

  /// Get LIVE games (status = '*') - highest priority in For You
  /// These are ongoing games with recent activity
  Future<List<Games>> getLiveGames({int limit = 30, int offset = 0}) async {
    return handleApiCall(() async {
      debugPrint('===== GameRepository: Fetching LIVE games =====');

      // Order by date_start first to group games by day, then by last_move_time
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .eq('status', '*')
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .range(offset, offset + limit - 1);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      debugPrint(
        '===== GameRepository: Fetched ${games.length} LIVE games =====',
      );

      return games;
    });
  }

  /// Get countryman games with minimum ELO filter.
  /// Shows games where at least one player from the country has rating >= minElo.
  ///
  /// The caller is responsible for pagination. This method fetches exactly
  /// `limit` games starting at `offset` with server-side ELO filtering.
  /// Returns: (filteredGames, rawGamesFetched).
  Future<({List<Games> games, int rawFetched})>
  getCountrymanGamesWithMinEloAndRawCount({
    required String countryCode,
    int minElo = 2300,
    int limit = 20,
    int rawOffset = 0,
  }) async {
    return handleApiCall(() async {
      final normalizedCode = _normalizeCountryCode(countryCode);
      debugPrint(
        '===== GameRepository: Fetching countryman games (ELO >= $minElo) for countryCode="$normalizedCode", limit=$limit, rawOffset=$rawOffset =====',
      );

      // Order by date_start first to group games by day, then by last_move_time
      // This ensures all games from today appear together, even if some have NULL last_move_time
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .contains('player_feds', [normalizedCode])
          .gte('player_max_rating', minElo)
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .range(rawOffset, rawOffset + limit - 1);

      final rawCount = (response as List).length;
      debugPrint('===== GameRepository: Raw response count: $rawCount =====');

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      debugPrint('===== GameRepository: Decoded ${games.length} games =====');

      return (games: games, rawFetched: rawCount);
    });
  }

  /// Get countryman games with minimum ELO filter (simple version).
  /// For backwards compatibility - just returns filtered games.
  Future<List<Games>> getCountrymanGamesWithMinElo({
    required String countryCode,
    int minElo = 2300,
    int limit = 50,
    int offset = 0,
  }) async {
    final result = await getCountrymanGamesWithMinEloAndRawCount(
      countryCode: countryCode,
      minElo: minElo,
      limit: limit,
      rawOffset: offset,
    );
    return result.games;
  }

  /// Get live games for specific players (favorited players who are currently playing)
  Future<List<Games>> getLiveGamesForPlayers({
    required List<String> fideIds,
    int limit = 20,
  }) async {
    return handleApiCall(() async {
      final fideIdInts = _parseFideIds(fideIds);
      if (fideIdInts.isEmpty) return <Games>[];

      debugPrint(
        '===== GameRepository: Fetching LIVE games for ${fideIdInts.length} players =====',
      );

      // Order by date_start first to group games by day, then by last_move_time
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .eq('status', '*')
          .overlaps('player_fide_ids', fideIdInts)
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .limit(limit);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      debugPrint(
        '===== GameRepository: Fetched ${games.length} LIVE games for players =====',
      );

      return games;
    });
  }

  /// Get live games for favorited events
  Future<List<Games>> getLiveGamesForEvents({
    required List<String> eventIds,
    int limit = 20,
  }) async {
    return handleApiCall(() async {
      if (eventIds.isEmpty) return <Games>[];

      debugPrint(
        '===== GameRepository: Fetching LIVE games for ${eventIds.length} events =====',
      );

      // Order by date_start first to group games by day, then by last_move_time
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .eq('status', '*')
          .inFilter('tour_id', eventIds)
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .limit(limit);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      debugPrint(
        '===== GameRepository: Fetched ${games.length} LIVE games for events =====',
      );

      return games;
    });
  }

  /// Get top board games from a specific tournament (highest ELO players)
  /// Used to fill up the "For You" feed when there aren't enough personalized games
  Future<List<Games>> getTopBoardGamesByTourId({
    required String tourId,
    int limit = 4,
    Set<String>? excludeGameIds,
  }) async {
    return handleApiCall(() async {
      debugPrint(
        '===== GameRepository: Fetching top $limit board games for tour $tourId =====',
      );

      // Fetch more games than needed since we sort by ELO in Dart
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .eq('tour_id', tourId)
          .order(
            'board_nr',
            ascending: true,
          ) // Lower board number = higher boards
          .limit(limit * 3); // Fetch extra for filtering

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      var games = await compute(_decodeGamesInIsolate, jsonList);

      // Exclude games already in the feed
      if (excludeGameIds != null && excludeGameIds.isNotEmpty) {
        games = games.where((g) => !excludeGameIds.contains(g.id)).toList();
      }

      // Sort by max ELO (highest first) - top boards have highest rated players
      games.sort((a, b) {
        final maxEloA =
            a.players
                ?.map((p) => p.rating)
                .fold<int>(0, (max, r) => r > max ? r : max) ??
            0;
        final maxEloB =
            b.players
                ?.map((p) => p.rating)
                .fold<int>(0, (max, r) => r > max ? r : max) ??
            0;
        return maxEloB.compareTo(maxEloA);
      });

      final result = games.take(limit).toList();

      debugPrint(
        '===== GameRepository: Fetched ${result.length} top board games for tour $tourId =====',
      );

      return result;
    });
  }

  /// Search games using the precomputed `search` tokens column.
  ///
  /// The `games.search` column contains normalized tokens (players, events,
  /// openings, ECO codes, countries, common move strings, etc). This query
  /// matches games that contain all provided tokens.
  Future<List<Games>> searchGamesBySearchTermsPaginated({
    required List<String> terms,
    int limit = 30,
    int offset = 0,
    String? status,
  }) async {
    return handleApiCall(() async {
      final normalizedTerms =
          terms
              .map((t) => t.trim().toLowerCase())
              .where((t) => t.isNotEmpty)
              .toList();

      if (normalizedTerms.isEmpty) return <Games>[];

      // Build filter chain first (must come before transform operations)
      var query = supabase
          .from('games')
          .select(_gameListSelectColumns)
          .contains('search', normalizedTerms);

      if (status != null && status.isNotEmpty) {
        query = query.eq('status', status);
      }

      // Transform operations (order, range) come after filters
      // Order by date_start first to group games by day, then by last_move_time
      final response = await query
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .range(offset, offset + limit - 1);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);
      return games;
    });
  }

  /// Search games using flexible text matching on the `name` column.
  /// The `name` column contains "WhitePlayer - BlackPlayer" format.
  /// This uses ILIKE for partial matching (e.g., "carlsen" matches "Carlsen, Magnus").
  ///
  /// Optionally filter by country using the `players` JSONB column.
  Future<List<Games>> searchGamesFlexible({
    required String query,
    String? countryCode,
    int limit = 30,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      final trimmedQuery = query.trim();
      if (trimmedQuery.isEmpty && countryCode == null) return <Games>[];

      debugPrint(
        '[GameRepository] searchGamesFlexible: query="$trimmedQuery", countryCode=$countryCode, limit=$limit, offset=$offset',
      );

      // Build the query with ILIKE on the name column
      var dbQuery = supabase.from('games').select(_gameListSelectColumns);

      // If we have a text query, use ILIKE on the name column
      if (trimmedQuery.isNotEmpty) {
        dbQuery = dbQuery.ilike('name', '%$trimmedQuery%');
      }

      // If we have a country filter, add it
      if (countryCode != null && countryCode.isNotEmpty) {
        dbQuery = dbQuery.contains('player_feds', [
          _normalizeCountryCode(countryCode),
        ]);
      }

      // Order by date_start first to group games by day, then by last_move_time
      final response = await dbQuery
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .range(offset, offset + limit - 1);

      final rawCount = (response as List).length;
      debugPrint('[GameRepository] searchGamesFlexible: got $rawCount results');

      final jsonList = response.map((item) => json.encode(item)).toList();
      final games = await compute(_decodeGamesInIsolate, jsonList);
      return games;
    });
  }

  /// Search games for a specific country with optional text query.
  /// Returns games where at least one player is from the country AND
  /// optionally matches the search query.
  /// When [filter] is supplied, the active GameFilter is layered onto the
  /// PostgREST query so the search respects the user's current filter set.
  Future<List<Games>> searchCountrymenGames({
    required String countryCode,
    String? query,
    GameFilter? filter,
    int limit = 30,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      final normalizedCode = _normalizeCountryCode(countryCode);
      final tcDb = _timeControlDbValue(
        filter?.timeControl ?? GameTimeControlFilter.all,
      );
      debugPrint(
        '[GameRepository] searchCountrymenGames: country=$normalizedCode, query=$query, filter=${filter?.hasActiveFilters == true}',
      );

      final selectCols =
          tcDb != null ? _gameListSelectColumnsInnerTc : _gameListSelectColumns;

      var dbQuery = supabase.from('games').select(selectCols).contains(
        'player_feds',
        [normalizedCode],
      );

      if (filter != null && filter.minRating > GameFilter.defaultMinRating) {
        dbQuery = dbQuery.gte('player_max_rating', filter.minRating);
      }

      // Add text search if query provided (searches player names, ECO code, and opening name)
      if (query != null && query.trim().isNotEmpty) {
        dbQuery = dbQuery.or(
          'name.ilike.%${query.trim()}%,eco.ilike.%${query.trim()}%,opening_name.ilike.%${query.trim()}%',
        );
      }

      dbQuery = _applyCountryFilterChain(
        query: dbQuery,
        filter: filter,
        countryCode: normalizedCode,
        tcDb: tcDb,
      );

      // Order by date_start first to group games by day, then by last_move_time
      final response = await dbQuery
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .range(offset, offset + limit - 1);

      debugPrint(
        '[GameRepository] searchCountrymenGames: raw results = ${(response as List).length}',
      );

      final jsonList = response.map((item) => json.encode(item)).toList();
      final games = await compute(_decodeGamesInIsolate, jsonList);

      return games;
    });
  }

  /// Search games for favorite players with optional text query.
  /// First filters by FIDE IDs (indexed), then applies text search.
  /// When [filter] is supplied, the active GameFilter is layered onto the
  /// PostgREST query so the search respects the user's current filter set.
  Future<List<Games>> searchFavoritesGames({
    required List<String> fideIds,
    required List<String> playerNames,
    String? query,
    GameFilter? filter,
    int limit = 30,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      debugPrint(
        '[GameRepository] searchFavoritesGames: fideIds=${fideIds.length}, query=$query, offset=$offset, filter=${filter?.hasActiveFilters == true}',
      );

      final fideIdInts = _parseFideIds(fideIds);
      if (fideIdInts.isEmpty) return <Games>[];

      final tcDb = _timeControlDbValue(
        filter?.timeControl ?? GameTimeControlFilter.all,
      );
      final selectCols =
          tcDb != null ? _gameListSelectColumnsInnerTc : _gameListSelectColumns;

      var dbQuery = supabase
          .from('games')
          .select(selectCols)
          .overlaps('player_fide_ids', fideIdInts);

      // Add text search if query provided (searches player names, ECO code, and opening name)
      if (query != null && query.trim().isNotEmpty) {
        dbQuery = dbQuery.or(
          'name.ilike.%${query.trim()}%,eco.ilike.%${query.trim()}%,opening_name.ilike.%${query.trim()}%',
        );
      }

      dbQuery = _applyFavoritesFilterChain(
        query: dbQuery,
        filter: filter,
        fideIds: fideIdInts,
        tcDb: tcDb,
      );

      // Order and paginate
      final response = await dbQuery
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .range(offset, offset + limit - 1);

      debugPrint(
        '[GameRepository] searchFavoritesGames: results = ${(response as List).length}',
      );

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();
      final games = await compute(_decodeGamesInIsolate, jsonList);

      return games;
    });
  }

  /// Get games from multiple tour IDs (for fetching all current events' games)
  /// Returns games ordered by last_move_time descending
  Future<List<Games>> getGamesFromTourIds({
    required List<String> tourIds,
    int limit = 500,
    int offset = 0,
  }) async {
    if (tourIds.isEmpty) {
      return <Games>[];
    }

    debugPrint(
      '[GameRepository] Fetching games from ${tourIds.length} tour IDs (limit: $limit, offset: $offset)',
    );

    try {
      // Use inFilter for multiple tour IDs
      // Order by date_start first to group games by day, then by last_move_time
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .inFilter('tour_id', tourIds)
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .range(offset, offset + limit - 1);

      final responseList = response as List<dynamic>;

      if (responseList.isEmpty) {
        debugPrint(
          '[GameRepository] Empty response from getGamesFromTourIds query',
        );
        return <Games>[];
      }

      final jsonList = responseList.map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      debugPrint(
        '[GameRepository] Fetched ${games.length} games from current events',
      );

      return games;
    } catch (e) {
      debugPrint('[GameRepository] Error in getGamesFromTourIds: $e');
      return <Games>[];
    }
  }

  /// Get smart-event games from multiple tour IDs.
  ///
  /// This is the direct database-backed path for synthetic smart events. It
  /// pushes every filter the schema can represent down to PostgREST. The smart
  /// event's exact rating semantics are game-average based, while the DB stores
  /// `player_max_rating`; [minAverageEloForPrefilter] is therefore only used as
  /// a safe lower-bound prefilter and the exact average range is checked after
  /// decoding by the provider.
  ///
  /// Pages through every matching row ([_tourGamesFetchPageSize] per request,
  /// like [getGamesByTourId]) up to [limit] TOTAL rows. A single-page fetch
  /// silently truncated broad filters to a shorter day span than narrow ones,
  /// making "Classical" show fewer games than "Classical + GM" on older days.
  Future<List<Games>> getSmartEventGamesFromTourIds({
    required List<String> tourIds,
    GameFilter? filter,
    String? query,
    int? minAverageEloForPrefilter,
    int limit = 6000,
    int offset = 0,
  }) async {
    if (tourIds.isEmpty) return <Games>[];

    return handleApiCall(() async {
      final tcDb = _timeControlDbValue(
        filter?.timeControl ?? GameTimeControlFilter.all,
      );
      final selectCols =
          tcDb != null ? _gameListSelectColumnsInnerTc : _gameListSelectColumns;
      final trimmedQuery = query?.trim();

      final jsonList = <String>[];
      var pageOffset = offset;
      var remaining = limit;

      while (remaining > 0) {
        final pageSize =
            remaining > _tourGamesFetchPageSize
                ? _tourGamesFetchPageSize
                : remaining;

        dynamic dbQuery = supabase
            .from('games')
            .select(selectCols)
            .inFilter('tour_id', tourIds);

        if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
          dbQuery = dbQuery.or(
            'name.ilike.%$trimmedQuery%,'
            'player_white.ilike.%$trimmedQuery%,'
            'player_black.ilike.%$trimmedQuery%,'
            'eco.ilike.%$trimmedQuery%,'
            'opening_name.ilike.%$trimmedQuery%',
          );
        }

        dbQuery = _applySmartEventFilterChain(
          query: dbQuery,
          filter: filter,
          tcDb: tcDb,
          minAverageEloForPrefilter: minAverageEloForPrefilter,
        );

        final response = await dbQuery
            .order('last_move_time', ascending: false, nullsFirst: false)
            .order('game_day', ascending: false, nullsFirst: false)
            .order('date_start', ascending: false, nullsFirst: false)
            .order('player_max_rating', ascending: false, nullsFirst: false)
            .range(pageOffset, pageOffset + pageSize - 1);

        final responseList = response as List;
        jsonList.addAll(responseList.map((item) => json.encode(item)));

        if (!shouldFetchAnotherTourGamesPage(
          responseList.length,
          pageSize: pageSize,
        )) {
          break;
        }
        pageOffset += responseList.length;
        remaining -= responseList.length;
      }

      return compute(_decodeGamesInIsolate, jsonList);
    });
  }

  /// Resolve the best tour to open for an event group.
  ///
  /// Priority:
  /// 1) live games with moves
  /// 2) most recently moved game
  /// 3) most recently started round
  /// 4) nearest upcoming round when nothing started yet
  Future<String?> getMostRelevantTourId({required List<String> tourIds}) async {
    if (tourIds.isEmpty) return null;

    try {
      final liveResponse = await supabase
          .from('games')
          .select('tour_id,last_move_time,date_start')
          .inFilter('tour_id', tourIds)
          .inFilter('status', ['*', 'ongoing'])
          .not('last_move_time', 'is', null)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .order('date_start', ascending: false, nullsFirst: false)
          .limit(1);

      if (liveResponse.isNotEmpty) {
        final id = liveResponse.first['tour_id'];
        if (id is String && id.isNotEmpty) {
          return id;
        }
      }

      final recentResponse = await supabase
          .from('games')
          .select('tour_id,last_move_time,date_start')
          .inFilter('tour_id', tourIds)
          .not('last_move_time', 'is', null)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .limit(1);

      if (recentResponse.isNotEmpty) {
        final id = recentResponse.first['tour_id'];
        if (id is String && id.isNotEmpty) {
          return id;
        }
      }

      final nowIso = DateTime.now().toUtc().toIso8601String();
      final startedRounds = await supabase
          .from('rounds')
          .select('tour_id,starts_at')
          .inFilter('tour_id', tourIds)
          .not('starts_at', 'is', null)
          .lte('starts_at', nowIso)
          .order('starts_at', ascending: false)
          .limit(1);

      if (startedRounds.isNotEmpty) {
        final id = startedRounds.first['tour_id'];
        if (id is String && id.isNotEmpty) {
          return id;
        }
      }

      final upcomingRounds = await supabase
          .from('rounds')
          .select('tour_id,starts_at')
          .inFilter('tour_id', tourIds)
          .not('starts_at', 'is', null)
          .gte('starts_at', nowIso)
          .order('starts_at', ascending: true)
          .limit(1);

      if (upcomingRounds.isNotEmpty) {
        final id = upcomingRounds.first['tour_id'];
        if (id is String && id.isNotEmpty) {
          return id;
        }
      }

      return null;
    } catch (e) {
      debugPrint('[GameRepository] Error in getMostRelevantTourId: $e');
      return null;
    }
  }

  Future<Map<String, DateTime>> getLatestLastMoveTimesByRoundIds(
    List<String> roundIds,
  ) async {
    if (roundIds.isEmpty) return <String, DateTime>{};

    return handleApiCall(() async {
      final response = await supabase
          .from('games')
          .select('round_id,last_move_time')
          .inFilter('round_id', roundIds)
          .not('last_move_time', 'is', null)
          .order('last_move_time', ascending: false, nullsFirst: false);

      final latestByRoundId = <String, DateTime>{};
      for (final row in response as List) {
        final roundId = row['round_id'] as String?;
        final lastMoveTimeRaw = row['last_move_time'] as String?;
        if (roundId == null || roundId.isEmpty || lastMoveTimeRaw == null) {
          continue;
        }
        latestByRoundId.putIfAbsent(
          roundId,
          () => DateTime.parse(lastMoveTimeRaw),
        );
      }

      return latestByRoundId;
    });
  }

  /// Get games for "For You" event cards
  /// Current round = live games with moves, else most recently played,
  /// else earliest upcoming round when nothing has started yet.
  Future<List<Games>> getForYouEventGames({
    required List<String> tourIds,
    int neededCount = 4,
  }) async {
    if (tourIds.isEmpty) return <Games>[];

    try {
      // Step 1: Check for live games first - their round is the "current" round
      final liveResponse = await supabase
          .from('games')
          .select('round_id, last_move_time, date_start')
          .inFilter('tour_id', tourIds)
          .inFilter('status', ['*', 'ongoing'])
          .not('last_move_time', 'is', null)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .order('date_start', ascending: false, nullsFirst: false)
          .limit(1);

      Set<String> currentRoundIds = {};

      if (liveResponse.isNotEmpty) {
        // Live games exist - use the most recently active live round
        final liveRoundId = liveResponse.first['round_id'];
        if (liveRoundId is String && liveRoundId.isNotEmpty) {
          currentRoundIds = {liveRoundId};
          debugPrint(
            '[GameRepository] ForYou: Found live round: $currentRoundIds',
          );
        }
      }

      if (currentRoundIds.isEmpty) {
        // No live games - find most recently played round (by last_move_time)
        final recentResponse = await supabase
            .from('games')
            .select('round_id')
            .inFilter('tour_id', tourIds)
            .not('last_move_time', 'is', null)
            .order('last_move_time', ascending: false)
            .limit(1);

        if (recentResponse.isNotEmpty) {
          currentRoundIds.add(recentResponse.first['round_id'] as String);
          debugPrint(
            '[GameRepository] ForYou: Most recent round: $currentRoundIds',
          );
        }
      }

      if (currentRoundIds.isEmpty) {
        // No games played yet - use the earliest upcoming round (by starts_at)
        final nowIso = DateTime.now().toUtc().toIso8601String();
        List<dynamic>? roundResponse;
        try {
          roundResponse = await supabase
              .from('rounds')
              .select('id, starts_at')
              .inFilter('tour_id', tourIds)
              .not('starts_at', 'is', null)
              .gte('starts_at', nowIso)
              .order('starts_at', ascending: true)
              .limit(1);
        } catch (e) {
          debugPrint(
            '[GameRepository] ForYou: Failed to load upcoming rounds ($e)',
          );
        }

        if (roundResponse != null && roundResponse.isNotEmpty) {
          final roundId = roundResponse.first['id'];
          if (roundId is String && roundId.isNotEmpty) {
            currentRoundIds.add(roundId);
            debugPrint(
              '[GameRepository] ForYou: Earliest upcoming round: $currentRoundIds',
            );
          }
        }
      }

      if (currentRoundIds.isEmpty) return <Games>[];

      // Step 2: Fetch games from current round(s), ordered by ELO
      final gamesResponse = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .inFilter('round_id', currentRoundIds.toList())
          .order('player_max_rating', ascending: false, nullsFirst: false)
          .limit(neededCount + 4);

      final games = <Games>[];
      if (gamesResponse.isNotEmpty) {
        final jsonList =
            gamesResponse.map((item) => json.encode(item)).toList();
        games.addAll(await compute(_decodeGamesInIsolate, jsonList));
      }

      return games;
    } catch (e) {
      debugPrint('[GameRepository] Error in getForYouEventGames: $e');
      return <Games>[];
    }
  }

  /// Get top live games globally, ordered by recency.
  Future<List<Games>> getTopLiveGames({int limit = 200}) async {
    return handleApiCall(() async {
      // Order by date_start first to group games by day, then by last_move_time
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .eq('status', '*')
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .limit(limit);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);
      return games;
    });
  }

  /// Get distinct game dates for favorited players.
  /// Returns dates in descending order (most recent first).
  /// When [filter] is supplied, the same predicates that constrain the games
  /// fetch are applied to the date pagination so users don't page through
  /// empty days when, e.g. they've selected "Live + 1-0 + Classical".
  Future<List<DateTime>> getDistinctDatesForFavorites({
    required List<String> fideIds,
    GameFilter? filter,
    int limit = 30,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      final fideIdInts = _parseFideIds(fideIds);
      if (fideIdInts.isEmpty) return <DateTime>[];

      debugPrint(
        '[GameRepository] getDistinctDatesForFavorites: fideIds=${fideIdInts.length}',
      );

      final response = await supabase.rpc(
        'get_distinct_dates_for_favorites',
        params: {
          'fide_ids': fideIdInts,
          'limit_count': limit,
          'offset_count': offset,
          ..._gameFilterRpcParams(filter),
        },
      );

      final dates = <DateTime>[];

      for (final row in (response as List)) {
        final dateStr = row['date_start']?.toString();
        if (dateStr == null) continue;
        try {
          dates.add(DateTime.parse(dateStr));
        } catch (e) {
          debugPrint('[GameRepository] Error parsing date: $dateStr');
        }
      }

      final filteredDates = _filterDatesForLiveFilter(
        _filterOutFutureDates(dates),
        filter,
      );
      debugPrint(
        '[GameRepository] getDistinctDatesForFavorites: found ${filteredDates.length} dates',
      );
      return filteredDates;
    });
  }

  /// Get ALL games by FIDE IDs for a specific date.
  /// No pagination - returns all games for the date.
  /// Server-side filters from [filter] are applied so the result already
  /// matches the active GameFilter without a client-side second pass.
  Future<List<Games>> getGamesByFideIdsAndDate({
    required List<String> fideIds,
    required DateTime date,
    GameFilter? filter,
  }) async {
    return handleApiCall(() async {
      final fideIdInts = _parseFideIds(fideIds);
      if (fideIdInts.isEmpty) return <Games>[];

      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final dayStartUtc = DateTime.utc(date.year, date.month, date.day);
      final nextDayUtc = dayStartUtc.add(const Duration(days: 1));
      // Match game_day first (PGN [Date], stable per round), then fall back
      // to last_move_time, then date_start. date_start is the broadcast
      // pairing-upload day and can drift several days from the round day on
      // pre-created multi-round broadcasts (e.g. GCT), so it is only used
      // when game_day and last_move_time are both null on the row.
      final dayFilter =
          'game_day.eq.$dateStr,'
          'and(game_day.is.null,last_move_time.gte.${dayStartUtc.toIso8601String()},last_move_time.lt.${nextDayUtc.toIso8601String()}),'
          'and(game_day.is.null,last_move_time.is.null,date_start.eq.$dateStr)';
      final tcDb = _timeControlDbValue(
        filter?.timeControl ?? GameTimeControlFilter.all,
      );
      debugPrint(
        '[GameRepository] getGamesByFideIdsAndDate: fideIds=${fideIdInts.length}, date=$dateStr, filter=${filter?.hasActiveFilters == true}',
      );

      // Switch to !inner embedding when filtering by time control so the
      // PostgREST query narrows on tours.group_broadcasts.time_control.
      final selectCols =
          tcDb != null ? _gameListSelectColumnsInnerTc : _gameListSelectColumns;

      var dbQuery = supabase
          .from('games')
          .select(selectCols)
          .overlaps('player_fide_ids', fideIdInts)
          .or(dayFilter);

      dbQuery = _applyFavoritesFilterChain(
        query: dbQuery,
        filter: filter,
        fideIds: fideIdInts,
        tcDb: tcDb,
      );

      final response = await dbQuery.order(
        'last_move_time',
        ascending: false,
        nullsFirst: false,
      );

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      debugPrint(
        '[GameRepository] getGamesByFideIdsAndDate: found ${games.length} games for $dateStr',
      );
      return games;
    });
  }

  /// Get distinct game dates for a country.
  /// Returns dates in descending order (most recent first).
  /// When [filter] is supplied, all filter predicates are applied to the
  /// date pagination on the server so pages are dense with matching games.
  /// `filter.minRating` is folded into `minElo` (max of both) because the
  /// RPC already exposes a single rating-floor parameter for this code path.
  Future<List<DateTime>> getDistinctDatesForCountry({
    required String countryCode,
    int minElo = 0,
    GameFilter? filter,
    int limit = 30,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      final normalizedCode = _normalizeCountryCode(countryCode);
      debugPrint(
        '[GameRepository] getDistinctDatesForCountry: countryCode=$normalizedCode',
      );

      final mergedParams = _gameFilterRpcParams(filter)
        ..remove('p_min_rating'); // folded into min_elo for country RPC
      final effectiveMinElo =
          (filter == null)
              ? minElo
              : (minElo > filter.minRating ? minElo : filter.minRating);

      final response = await supabase.rpc(
        'get_distinct_dates_for_country',
        params: {
          'country_code': normalizedCode,
          'min_elo': effectiveMinElo,
          'limit_count': limit,
          'offset_count': offset,
          ...mergedParams,
        },
      );

      final dates = <DateTime>[];

      for (final row in (response as List)) {
        final dateStr = row['date_start']?.toString();
        if (dateStr == null) continue;
        try {
          dates.add(DateTime.parse(dateStr));
        } catch (e) {
          debugPrint('[GameRepository] Error parsing date: $dateStr');
        }
      }

      final filteredDates = _filterDatesForLiveFilter(
        _filterOutFutureDates(dates),
        filter,
      );
      debugPrint(
        '[GameRepository] getDistinctDatesForCountry: found ${filteredDates.length} dates',
      );
      return filteredDates;
    });
  }

  List<DateTime> _filterOutFutureDates(List<DateTime> dates) {
    if (dates.isEmpty) return dates;
    final nowUtc = DateTime.now().toUtc();
    final todayUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    return dates.where((date) {
      final dateUtc = DateTime.utc(date.year, date.month, date.day);
      return !dateUtc.isAfter(todayUtc);
    }).toList();
  }

  /// Get games by country for a specific date.
  /// Returns ALL games for the date (no limit) - the countrymen tab should display
  /// everything your countrymen played on that date.
  /// Server-side filters from [filter] are applied to the PostgREST query.
  Future<List<Games>> getGamesByCountryAndDate({
    required String countryCode,
    required DateTime date,
    int minElo = 0,
    GameFilter? filter,
  }) async {
    return handleApiCall(() async {
      final normalizedCode = _normalizeCountryCode(countryCode);
      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final dayStartUtc = DateTime.utc(date.year, date.month, date.day);
      final nextDayUtc = dayStartUtc.add(const Duration(days: 1));
      // Match game_day first (PGN [Date], stable per round), then fall back
      // to last_move_time, then date_start. date_start is the broadcast
      // pairing-upload day and can drift several days from the round day on
      // pre-created multi-round broadcasts (e.g. GCT), so it is only used
      // when game_day and last_move_time are both null on the row.
      final dayFilter =
          'game_day.eq.$dateStr,'
          'and(game_day.is.null,last_move_time.gte.${dayStartUtc.toIso8601String()},last_move_time.lt.${nextDayUtc.toIso8601String()}),'
          'and(game_day.is.null,last_move_time.is.null,date_start.eq.$dateStr)';
      final tcDb = _timeControlDbValue(
        filter?.timeControl ?? GameTimeControlFilter.all,
      );
      final effectiveMinElo =
          filter == null
              ? minElo
              : (minElo > filter.minRating ? minElo : filter.minRating);
      debugPrint(
        '[GameRepository] getGamesByCountryAndDate: countryCode=$normalizedCode, date=$dateStr, filter=${filter?.hasActiveFilters == true}',
      );

      final selectCols =
          tcDb != null ? _gameListSelectColumnsInnerTc : _gameListSelectColumns;

      var dbQuery = supabase
          .from('games')
          .select(selectCols)
          .contains('player_feds', [normalizedCode])
          .or(dayFilter)
          .gte('player_max_rating', effectiveMinElo);

      dbQuery = _applyCountryFilterChain(
        query: dbQuery,
        filter: filter,
        countryCode: normalizedCode,
        tcDb: tcDb,
      );

      final response = await dbQuery.order(
        'last_move_time',
        ascending: false,
        nullsFirst: false,
      );

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      debugPrint(
        '[GameRepository] getGamesByCountryAndDate: found ${games.length} games',
      );
      return games;
    });
  }

  /// Adds the server-side filter chain for the favorites-games path.
  /// Returned builder type is the same as the input so it can keep chaining
  /// (e.g. `.order(...)` after this call).
  dynamic _applyFavoritesFilterChain({
    required dynamic query,
    required GameFilter? filter,
    required List<int> fideIds,
    required String? tcDb,
  }) {
    if (filter == null || !filter.hasActiveFilters) return query;

    // Live / completed
    switch (filter.live) {
      case GameLiveFilter.live:
        query = query.or('status.is.null,status.eq.*');
        query = query.or(_currentLiveDayFilter());
        break;
      case GameLiveFilter.completed:
        query = query.not('status', 'is', null).neq('status', '*');
        break;
      case GameLiveFilter.all:
        break;
    }

    // Result
    switch (filter.result) {
      case GameResultFilter.whiteWins:
        query = query.eq('status', '1-0');
        break;
      case GameResultFilter.blackWins:
        query = query.eq('status', '0-1');
        break;
      case GameResultFilter.draw:
        query = query.inFilter('status', _drawStatusValues);
        break;
      case GameResultFilter.all:
        break;
    }

    // Time control via embedded join
    if (tcDb != null) {
      query = query.eq('tours.group_broadcasts.time_control', tcDb);
    }

    // Rating range — date pagination handles year range and ECO already, but
    // we re-apply rating here so per-day results are also narrowed.
    if (filter.minRating > GameFilter.defaultMinRating) {
      query = query.gte('player_max_rating', filter.minRating);
    }
    if (filter.maxRating < GameFilter.absoluteMaxRating) {
      query = query.lte('player_max_rating', filter.maxRating);
    }

    // ECO prefix
    if (!filter.eco.isAll && (filter.eco.code?.isNotEmpty ?? false)) {
      query = query.ilike('eco', '${filter.eco.code}%');
    }

    // Color — which side the favourited player is on
    if (filter.color != GameColorFilter.all && fideIds.isNotEmpty) {
      final idx = filter.color == GameColorFilter.white ? 0 : 1;
      final ids = fideIds.join(',');
      query = query.filter('players->$idx->>fideId', 'in', '($ids)');
    }
    return query;
  }

  /// Adds the server-side filter chain for the countrymen-games path.
  dynamic _applyCountryFilterChain({
    required dynamic query,
    required GameFilter? filter,
    required String countryCode,
    required String? tcDb,
  }) {
    if (filter == null || !filter.hasActiveFilters) return query;

    switch (filter.live) {
      case GameLiveFilter.live:
        query = query.or('status.is.null,status.eq.*');
        query = query.or(_currentLiveDayFilter());
        break;
      case GameLiveFilter.completed:
        query = query.not('status', 'is', null).neq('status', '*');
        break;
      case GameLiveFilter.all:
        break;
    }

    switch (filter.result) {
      case GameResultFilter.whiteWins:
        query = query.eq('status', '1-0');
        break;
      case GameResultFilter.blackWins:
        query = query.eq('status', '0-1');
        break;
      case GameResultFilter.draw:
        query = query.inFilter('status', _drawStatusValues);
        break;
      case GameResultFilter.all:
        break;
    }

    if (tcDb != null) {
      query = query.eq('tours.group_broadcasts.time_control', tcDb);
    }

    if (filter.maxRating < GameFilter.absoluteMaxRating) {
      query = query.lte('player_max_rating', filter.maxRating);
    }

    if (!filter.eco.isAll && (filter.eco.code?.isNotEmpty ?? false)) {
      query = query.ilike('eco', '${filter.eco.code}%');
    }

    // Color — which side the player from `countryCode` is on
    if (filter.color != GameColorFilter.all) {
      final idx = filter.color == GameColorFilter.white ? 0 : 1;
      query = query.eq('players->$idx->>fed', countryCode);
    }
    return query;
  }

  dynamic _applySmartEventFilterChain({
    required dynamic query,
    required GameFilter? filter,
    required String? tcDb,
    required int? minAverageEloForPrefilter,
  }) {
    if (filter == null && minAverageEloForPrefilter == null) return query;

    if (filter != null && filter.hasActiveFilters) {
      switch (filter.live) {
        case GameLiveFilter.live:
          query = query.or('status.is.null,status.eq.*');
          query = query.or(_currentLiveDayFilter());
          break;
        case GameLiveFilter.completed:
          query = query.not('status', 'is', null).neq('status', '*');
          break;
        case GameLiveFilter.all:
          break;
      }

      switch (filter.result) {
        case GameResultFilter.whiteWins:
          query = query.eq('status', '1-0');
          break;
        case GameResultFilter.blackWins:
          query = query.eq('status', '0-1');
          break;
        case GameResultFilter.draw:
          query = query.inFilter('status', _drawStatusValues);
          break;
        case GameResultFilter.all:
          break;
      }

      if (tcDb != null) {
        query = query.eq('tours.group_broadcasts.time_control', tcDb);
      }

      if (!filter.eco.isAll && (filter.eco.code?.isNotEmpty ?? false)) {
        query = query.ilike('eco', '${filter.eco.code}%');
      }

      if (filter.minYear != GameFilter.defaultMinYear) {
        query = query.or(_yearLowerBoundFilter(filter.minYear));
      }
      if (filter.maxYear < DateTime.now().year) {
        query = query.or(_yearUpperBoundFilter(filter.maxYear));
      }

      switch (filter.online) {
        case GameOnlineFilter.online:
          query = query.not('lichess_id', 'is', null);
          break;
        case GameOnlineFilter.otb:
          query = query.filter('lichess_id', 'is', 'null');
          break;
        case GameOnlineFilter.all:
          break;
      }
    }

    final filterMinRating = filter?.minRating ?? GameFilter.defaultMinRating;
    final safeMinRating =
        minAverageEloForPrefilter != null &&
                minAverageEloForPrefilter > filterMinRating
            ? minAverageEloForPrefilter
            : filterMinRating;
    if (safeMinRating > GameFilter.defaultMinRating) {
      query = query.gte('player_max_rating', safeMinRating);
    }

    return query;
  }
}

List<Games> _decodeGamesInIsolate(List<String> gameJsonList) {
  final games =
      gameJsonList.map((e) {
        final decoded = json.decode(e) as Map<String, dynamic>;
        return Games.fromJson(decoded);
      }).toList();
  return _deduplicateGames(games);
}

/// Removes duplicate games by ID, keeping the first occurrence.
List<Games> _deduplicateGames(List<Games> games) {
  final seen = <String>{};
  return games.where((game) => seen.add(game.id)).toList();
}
