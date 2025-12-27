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
          last_clock_white,
          last_clock_black,
          eco,
          opening_name
        ''';

class GameRepository extends BaseRepository {
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

      // Query games where the fideId appears in the players JSONB array
      // Use JSON string format for JSONB contains query (consistent with other methods)
      var query = supabase
          .from('games')
          .select(_gameListSelectColumns)
          .contains('players', '[{"fideId": $fideId}]')
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
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .contains('players', '[{"fideId": $fideId}]')
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
          .or('player_white.eq."$normalizedName",player_black.eq."$normalizedName"')
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
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .contains('players', '[{"fed": "$countryCode"}]')
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
      if (fideIds.isEmpty) {
        return <Games>[];
      }

      debugPrint('===== GameRepository: Fetching games for ${fideIds.length} FIDE IDs =====');

      // Build OR query for multiple FIDE IDs
      final orConditions = fideIds.map((fideId) {
        return 'players.cs.[{"fideId":${int.parse(fideId)}}]';
      }).join(',');

      // Order by date_start first to group games by day, then by last_move_time
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .or(orConditions)
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .range(offset, offset + limit - 1);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      debugPrint('===== GameRepository: Fetched ${games.length} games for favorited players =====');

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
      debugPrint('===== GameRepository: Fetching games for country $countryCode =====');

      // Order by date_start first to group games by day, then by last_move_time
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .contains('players', '[{"fed": "$countryCode"}]')
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .range(offset, offset + limit - 1);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      debugPrint('===== GameRepository: Fetched ${games.length} games for country =====');

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
      debugPrint('===== GameRepository: Fetching high ELO games (>= $minElo) =====');

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
            offset + limit * (onlyLive ? 2 : 3) - 1, // Fetch extra to compensate for ELO filter
          );

      final response = await query;

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      var games = await compute(_decodeGamesInIsolate, jsonList);

      // Filter games where at least one player has ELO >= minElo
      games = games.where((game) {
        if (game.players == null || game.players!.isEmpty) return false;
        return game.players!.any((player) => player.rating >= minElo);
      }).take(limit).toList();

      debugPrint('===== GameRepository: Fetched ${games.length} high ELO games (>= $minElo) =====');

      return games;
    });
  }

  /// Get LIVE games (status = '*') - highest priority in For You
  /// These are ongoing games with recent activity
  Future<List<Games>> getLiveGames({
    int limit = 30,
    int offset = 0,
  }) async {
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

      debugPrint('===== GameRepository: Fetched ${games.length} LIVE games =====');

      return games;
    });
  }

  /// Get countryman games with minimum ELO filter.
  /// Shows games where at least one player from the country has rating >= minElo.
  ///
  /// The caller is responsible for pagination. This method fetches exactly
  /// `limit` games starting at `offset` (after ELO filtering is applied in-memory).
  ///
  /// To handle ELO filtering, we fetch extra records and filter in Dart.
  /// Returns: (filteredGames, rawGamesFetched) so caller can track raw offset.
  Future<({List<Games> games, int rawFetched})> getCountrymanGamesWithMinEloAndRawCount({
    required String countryCode,
    int minElo = 2300,
    int limit = 20,
    int rawOffset = 0,
  }) async {
    return handleApiCall(() async {
      debugPrint('===== GameRepository: Fetching countryman games (ELO >= $minElo) for countryCode="$countryCode", limit=$limit, rawOffset=$rawOffset =====');

      // Fetch more than needed since we filter by ELO in Dart
      // Fetch limit * 10 to have enough buffer for ELO filtering
      final fetchLimit = limit * 10;

      final containsFilter = '[{"fed": "$countryCode"}]';
      debugPrint('===== GameRepository: Using contains filter: $containsFilter, fetching up to $fetchLimit raw games =====');

      // Order by date_start first to group games by day, then by last_move_time
      // This ensures all games from today appear together, even if some have NULL last_move_time
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .contains('players', containsFilter)
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .range(rawOffset, rawOffset + fetchLimit - 1);

      final rawCount = (response as List).length;
      debugPrint('===== GameRepository: Raw response count: $rawCount =====');

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      var games = await compute(_decodeGamesInIsolate, jsonList);

      debugPrint('===== GameRepository: Decoded ${games.length} games, now filtering by ELO >= $minElo =====');

      // Filter games where at least one player has rating >= minElo
      // (shows countrymen games against strong opponents too)
      final filtered = games.where((game) {
        if (game.players == null) return false;
        return game.players!.any((player) => player.rating >= minElo);
      }).take(limit).toList();

      debugPrint('===== GameRepository: After ELO filter: ${filtered.length} countryman games (from $rawCount raw) =====');

      return (games: filtered, rawFetched: rawCount);
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
      if (fideIds.isEmpty) return <Games>[];

      debugPrint('===== GameRepository: Fetching LIVE games for ${fideIds.length} players =====');

      final orConditions = fideIds.map((fideId) {
        return 'players.cs.[{"fideId":${int.parse(fideId)}}]';
      }).join(',');

      // Order by date_start first to group games by day, then by last_move_time
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .eq('status', '*')
          .or(orConditions)
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .limit(limit);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      debugPrint('===== GameRepository: Fetched ${games.length} LIVE games for players =====');

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

      debugPrint('===== GameRepository: Fetching LIVE games for ${eventIds.length} events =====');

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

      debugPrint('===== GameRepository: Fetched ${games.length} LIVE games for events =====');

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
          .order('board_nr', ascending: true) // Lower board number = higher boards
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
        final maxEloA = a.players?.map((p) => p.rating).fold<int>(0, (max, r) => r > max ? r : max) ?? 0;
        final maxEloB = b.players?.map((p) => p.rating).fold<int>(0, (max, r) => r > max ? r : max) ?? 0;
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
      final normalizedTerms = terms
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

      debugPrint('[GameRepository] searchGamesFlexible: query="$trimmedQuery", countryCode=$countryCode, limit=$limit, offset=$offset');

      // Build the query with ILIKE on the name column
      var dbQuery = supabase.from('games').select(_gameListSelectColumns);

      // If we have a text query, use ILIKE on the name column
      if (trimmedQuery.isNotEmpty) {
        dbQuery = dbQuery.ilike('name', '%$trimmedQuery%');
      }

      // If we have a country filter, add it
      if (countryCode != null && countryCode.isNotEmpty) {
        dbQuery = dbQuery.contains('players', '[{"fed": "$countryCode"}]');
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
      debugPrint('[GameRepository] searchCountrymenGames: country=$countryCode, query=$query');

      var dbQuery = supabase
          .from('games')
          .select(_gameListSelectColumns)
          .contains('players', '[{"fed": "$countryCode"}]');

      // Add text search if query provided
      if (query != null && query.trim().isNotEmpty) {
        dbQuery = dbQuery.ilike('name', '%${query.trim()}%');
      }

      // Order by date_start first to group games by day, then by last_move_time
      final response = await dbQuery
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .range(offset, offset + limit - 1);

      debugPrint('[GameRepository] searchCountrymenGames: raw results = ${(response as List).length}');

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
      debugPrint('[GameRepository] searchFavoritesGames: fideIds=${fideIds.length}, query=$query, offset=$offset');

      if (fideIds.isEmpty) return <Games>[];

      // Build OR conditions for FIDE IDs (uses indexed JSONB query)
      final fideConditions = fideIds.map((fideId) {
        return 'players.cs.[{"fideId":${int.parse(fideId)}}]';
      }).join(',');

      var dbQuery = supabase
          .from('games')
          .select(_gameListSelectColumns)
          .or(fideConditions);

      // Add text search on name column if query provided
      if (query != null && query.trim().isNotEmpty) {
        dbQuery = dbQuery.ilike('name', '%${query.trim()}%');
      }

      // Order and paginate
      final response = await dbQuery
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .range(offset, offset + limit - 1);

      debugPrint('[GameRepository] searchFavoritesGames: results = ${(response as List).length}');

      final jsonList = (response as List).map((item) => json.encode(item)).toList();
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
    return handleApiCall(() async {
      if (tourIds.isEmpty) {
        return <Games>[];
      }

      debugPrint(
        '[GameRepository] Fetching games from ${tourIds.length} tour IDs (limit: $limit, offset: $offset)',
      );

      // Use inFilter for multiple tour IDs
      // Order by date_start first to group games by day, then by last_move_time
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .inFilter('tour_id', tourIds)
          .order('date_start', ascending: false, nullsFirst: false)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .range(offset, offset + limit - 1);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      debugPrint(
        '[GameRepository] Fetched ${games.length} games from current events',
      );

      return games;
    });
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
      if (fideIds.isEmpty) return <DateTime>[];

      debugPrint('[GameRepository] getDistinctDatesForFavorites: fideIds=${fideIds.length}');

      // Build OR query for multiple FIDE IDs
      final orConditions = fideIds.map((fideId) {
        return 'players.cs.[{"fideId":${int.parse(fideId)}}]';
      }).join(',');

      // Use raw query to get distinct dates
      final response = await supabase
          .from('games')
          .select('date_start')
          .or(orConditions)
          .not('date_start', 'is', null)
          .order('date_start', ascending: false);

      // Extract unique dates from response
      final seenDates = <String>{};
      final dates = <DateTime>[];

      for (final row in (response as List)) {
        final dateStr = row['date_start'] as String?;
        if (dateStr != null && !seenDates.contains(dateStr)) {
          seenDates.add(dateStr);
          try {
            dates.add(DateTime.parse(dateStr));
          } catch (e) {
            debugPrint('[GameRepository] Error parsing date: $dateStr');
          }
        }
      }

      // Apply pagination
      final start = offset.clamp(0, dates.length);
      final end = (offset + limit).clamp(0, dates.length);
      final paginatedDates = dates.sublist(start, end);

      debugPrint('[GameRepository] getDistinctDatesForFavorites: found ${paginatedDates.length} dates');
      return paginatedDates;
    });
  }

  /// Get games by FIDE IDs for a specific date.
  Future<List<Games>> getGamesByFideIdsAndDate({
    required List<String> fideIds,
    required DateTime date,
    int limit = 50,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      if (fideIds.isEmpty) return <Games>[];

      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      debugPrint('[GameRepository] getGamesByFideIdsAndDate: fideIds=${fideIds.length}, date=$dateStr');

      // Build OR query for multiple FIDE IDs
      final orConditions = fideIds.map((fideId) {
        return 'players.cs.[{"fideId":${int.parse(fideId)}}]';
      }).join(',');

      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .or(orConditions)
          .eq('date_start', dateStr)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .range(offset, offset + limit - 1);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      debugPrint('[GameRepository] getGamesByFideIdsAndDate: found ${games.length} games');
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
      debugPrint('[GameRepository] getDistinctDatesForCountry: countryCode=$countryCode');

      final containsFilter = '[{"fed": "$countryCode"}]';

      // Get dates from games with country filter
      final response = await supabase
          .from('games')
          .select('date_start, players')
          .contains('players', containsFilter)
          .not('date_start', 'is', null)
          .order('date_start', ascending: false);

      // Extract unique dates with ELO filtering
      final seenDates = <String>{};
      final dates = <DateTime>[];

      for (final row in (response as List)) {
        final dateStr = row['date_start'] as String?;
        if (dateStr == null || seenDates.contains(dateStr)) continue;

        // Check if at least one player has rating >= minElo
        final players = row['players'] as List?;
        if (players != null) {
          final hasHighElo = players.any((p) {
            final rating = p['rating'] as int?;
            return rating != null && rating >= minElo;
          });
          if (!hasHighElo) continue;
        }

        seenDates.add(dateStr);
        try {
          dates.add(DateTime.parse(dateStr));
        } catch (e) {
          debugPrint('[GameRepository] Error parsing date: $dateStr');
        }
      }

      // Apply pagination
      final start = offset.clamp(0, dates.length);
      final end = (offset + limit).clamp(0, dates.length);
      final paginatedDates = dates.sublist(start, end);

      debugPrint('[GameRepository] getDistinctDatesForCountry: found ${paginatedDates.length} dates');
      return paginatedDates;
    });
  }

  /// Get games by country for a specific date.
  Future<List<Games>> getGamesByCountryAndDate({
    required String countryCode,
    required DateTime date,
    int minElo = 2000,
    int limit = 50,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      debugPrint('[GameRepository] getGamesByCountryAndDate: countryCode=$countryCode, date=$dateStr');

      final containsFilter = '[{"fed": "$countryCode"}]';

      // Fetch more for ELO filtering
      final fetchLimit = limit * 5;

      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .contains('players', containsFilter)
          .eq('date_start', dateStr)
          .order('last_move_time', ascending: false, nullsFirst: false)
          .range(offset, offset + fetchLimit - 1);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      var games = await compute(_decodeGamesInIsolate, jsonList);

      // Filter by minimum ELO
      final filtered = games.where((game) {
        if (game.players == null) return false;
        return game.players!.any((p) => p.rating >= minElo);
      }).take(limit).toList();

      debugPrint('[GameRepository] getGamesByCountryAndDate: found ${filtered.length} games');
      return filtered;
    });
  }
}

List<Games> _decodeGamesInIsolate(List<String> gameJsonList) {
  return gameJsonList.map((e) {
    final decoded = json.decode(e) as Map<String, dynamic>;
    return Games.fromJson(decoded);
  }).toList();
}
