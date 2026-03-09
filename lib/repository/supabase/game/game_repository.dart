// repositories/game_repository.dart
import 'dart:convert';

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/base_repository.dart';
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
          tours!games_tour_id_fkey(group_broadcasts!tours_group_broadcast_id_fkey(time_control))
        ''';

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

      return (response as List).map((json) => Games.fromJson(json)).toList();
    });
  }

  // Fetch games by tour ID
  Future<List<Games>> getGamesByTourId(
    String tourId, {
    int? limit,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      var query = supabase
          .from('games')
          .select(_gameListSelectColumns)
          .eq('tour_id', tourId)
          .order('id', ascending: true);

      if (limit != null) {
        query = query.range(offset, offset + limit - 1);
      }

      final response = await query;

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

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

  // Fetch game by ID
  Future<Games> getGameById(String id) async {
    print('Fetching game by ID: $id');
    return handleApiCall(() async {
      final response =
          await supabase.from('games').select().eq('id', id).single();

      return Games.fromJson(response);
    });
  }

  // Get all games for a specific player by fideId
  Future<List<Games>> getGamesByFideId(String fideId, {int? limit}) async {
    return handleApiCall(() async {
      print('===== GameRepository: Fetching games for fideId: $fideId =====');

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

      print('===== GameRepository: Executing query with limit: $limit =====');
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
      return (response as List).map((json) => Games.fromJson(json)).toList();
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
          .or('player_white.eq.$normalizedName,player_black.eq.$normalizedName')
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
  Future<List<Games>> searchCountrymenGames({
    required String countryCode,
    String? query,
    int limit = 30,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      final normalizedCode = _normalizeCountryCode(countryCode);
      debugPrint(
        '[GameRepository] searchCountrymenGames: country=$normalizedCode, query=$query',
      );

      var dbQuery = supabase
          .from('games')
          .select(_gameListSelectColumns)
          .contains('player_feds', [normalizedCode]);

      // Add text search if query provided (searches player names, ECO code, and opening name)
      if (query != null && query.trim().isNotEmpty) {
        dbQuery = dbQuery.or(
          'name.ilike.%${query.trim()}%,eco.ilike.%${query.trim()}%,opening_name.ilike.%${query.trim()}%',
        );
      }

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
  Future<List<Games>> searchFavoritesGames({
    required List<String> fideIds,
    required List<String> playerNames,
    String? query,
    int limit = 30,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      debugPrint(
        '[GameRepository] searchFavoritesGames: fideIds=${fideIds.length}, query=$query, offset=$offset',
      );

      final fideIdInts = _parseFideIds(fideIds);
      if (fideIdInts.isEmpty) return <Games>[];

      var dbQuery = supabase
          .from('games')
          .select(_gameListSelectColumns)
          .overlaps('player_fide_ids', fideIdInts);

      // Add text search if query provided (searches player names, ECO code, and opening name)
      if (query != null && query.trim().isNotEmpty) {
        dbQuery = dbQuery.or(
          'name.ilike.%${query.trim()}%,eco.ilike.%${query.trim()}%,opening_name.ilike.%${query.trim()}%',
        );
      }

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

      // Handle null response gracefully
      if (response == null) {
        debugPrint(
          '[GameRepository] Warning: null response from getGamesFromTourIds query',
        );
        return <Games>[];
      }

      // Safely convert to List
      final List<dynamic> responseList;
      if (response is List) {
        responseList = response;
      } else {
        debugPrint(
          '[GameRepository] Warning: response is not a List, got ${response.runtimeType}',
        );
        return <Games>[];
      }

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

      if (liveResponse is List && liveResponse.isNotEmpty) {
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

        if (recentResponse is List && recentResponse.isNotEmpty) {
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

        if (roundResponse is List && roundResponse.isNotEmpty) {
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
      if (gamesResponse is List && gamesResponse.isNotEmpty) {
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

  static int _extractRoundNumberStatic(String? roundSlug) {
    if (roundSlug == null || roundSlug.isEmpty) return 0;
    final match =
        RegExp(r'round-?(\d+)', caseSensitive: false).firstMatch(roundSlug) ??
        RegExp(r'(\d+)').firstMatch(roundSlug);
    return int.tryParse(match?.group(1) ?? '0') ?? 0;
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
  Future<List<DateTime>> getDistinctDatesForFavorites({
    required List<String> fideIds,
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

      final filteredDates = _filterOutFutureDates(dates);
      debugPrint(
        '[GameRepository] getDistinctDatesForFavorites: found ${filteredDates.length} dates',
      );
      return filteredDates;
    });
  }

  /// Get ALL games by FIDE IDs for a specific date.
  /// No pagination - returns all games for the date.
  Future<List<Games>> getGamesByFideIdsAndDate({
    required List<String> fideIds,
    required DateTime date,
    String? eco,
  }) async {
    return handleApiCall(() async {
      final fideIdInts = _parseFideIds(fideIds);
      if (fideIdInts.isEmpty) return <Games>[];

      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final dayStartUtc = DateTime.utc(date.year, date.month, date.day);
      final nextDayUtc = dayStartUtc.add(const Duration(days: 1));
      final dayFilter =
          'game_day.eq.$dateStr,'
          'and(game_day.is.null,last_move_time.gte.${dayStartUtc.toIso8601String()},last_move_time.lt.${nextDayUtc.toIso8601String()}),'
          'and(game_day.is.null,last_move_time.is.null,date_start.eq.$dateStr)';
      debugPrint(
        '[GameRepository] getGamesByFideIdsAndDate: fideIds=${fideIdInts.length}, date=$dateStr, eco=$eco',
      );

      // Fetch ALL games for this date (no limit)
      var dbQuery = supabase
          .from('games')
          .select(_gameListSelectColumns)
          .overlaps('player_fide_ids', fideIdInts)
          .or(dayFilter);

      if (eco != null && eco.isNotEmpty) {
        dbQuery = dbQuery.eq('eco', eco);
      }

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
  Future<List<DateTime>> getDistinctDatesForCountry({
    required String countryCode,
    int minElo = 2000,
    int limit = 30,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      final normalizedCode = _normalizeCountryCode(countryCode);
      debugPrint(
        '[GameRepository] getDistinctDatesForCountry: countryCode=$normalizedCode',
      );

      final response = await supabase.rpc(
        'get_distinct_dates_for_country',
        params: {
          'country_code': normalizedCode,
          'min_elo': minElo,
          'limit_count': limit,
          'offset_count': offset,
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

      final filteredDates = _filterOutFutureDates(dates);
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
  Future<List<Games>> getGamesByCountryAndDate({
    required String countryCode,
    required DateTime date,
    int minElo = 2000,
    String? eco,
  }) async {
    return handleApiCall(() async {
      final normalizedCode = _normalizeCountryCode(countryCode);
      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final dayStartUtc = DateTime.utc(date.year, date.month, date.day);
      final nextDayUtc = dayStartUtc.add(const Duration(days: 1));
      final dayFilter =
          'game_day.eq.$dateStr,'
          'and(game_day.is.null,last_move_time.gte.${dayStartUtc.toIso8601String()},last_move_time.lt.${nextDayUtc.toIso8601String()}),'
          'and(game_day.is.null,last_move_time.is.null,date_start.eq.$dateStr)';
      debugPrint(
        '[GameRepository] getGamesByCountryAndDate: countryCode=$normalizedCode, date=$dateStr, eco=$eco',
      );

      // No limit - fetch ALL games for this date
      var dbQuery = supabase
          .from('games')
          .select(_gameListSelectColumns)
          .contains('player_feds', [normalizedCode])
          .or(dayFilter)
          .gte('player_max_rating', minElo);

      if (eco != null && eco.isNotEmpty) {
        dbQuery = dbQuery.eq('eco', eco);
      }

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
}

List<Games> _decodeGamesInIsolate(List<String> gameJsonList) {
  return gameJsonList.map((e) {
    final decoded = json.decode(e) as Map<String, dynamic>;
    return Games.fromJson(decoded);
  }).toList();
}
