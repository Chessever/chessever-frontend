// repositories/game_repository.dart
import 'dart:convert';

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gameRepositoryProvider = AutoDisposeProvider<GameRepository>((ref) {
  return GameRepository();
});

const String _gameListSelectColumns = '''
          id,
          round_id,
          round_slug,
          tour_id,
          tour_slug,
          name,
          fen,
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
          last_clock_black
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
      var query = supabase
          .from('games')
          .select(_gameListSelectColumns)
          .contains('players', [
            {'fideId': int.parse(fideId)},
          ])
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
          .contains('players', [
            {'fideId': int.parse(fideId)},
          ])
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
      debugPrint(
        '===== GameRepository: Fetching games for player name: $playerName =====',
      );

      // Query games where player_white or player_black matches the name
      var query = supabase
          .from('games')
          .select(_gameListSelectColumns)
          .or('player_white.eq."$playerName",player_black.eq."$playerName"')
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
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .or('player_white.eq.$playerName,player_black.eq.$playerName')
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
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .order('last_move_time', ascending: false)
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

      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .or(orConditions)
          .order('last_move_time', ascending: false)
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

      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .contains('players', '[{"fed": "$countryCode"}]')
          .order('last_move_time', ascending: false)
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

      query = query
          .order('last_move_time', ascending: false)
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

      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .eq('status', '*')
          .order('last_move_time', ascending: false)
          .range(offset, offset + limit - 1);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);

      debugPrint('===== GameRepository: Fetched ${games.length} LIVE games =====');

      return games;
    });
  }

  /// Get countryman games with minimum ELO filter
  /// Only shows games where at least one player from the country has rating > minElo
  Future<List<Games>> getCountrymanGamesWithMinElo({
    required String countryCode,
    int minElo = 2300,
    int limit = 50,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      debugPrint('===== GameRepository: Fetching countryman games (ELO > $minElo) for $countryCode =====');

      // First fetch all country games, then filter by ELO in Dart
      // (JSONB filtering by nested rating is complex in Supabase)
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .contains('players', '[{"fed": "$countryCode"}]')
          .order('last_move_time', ascending: false)
          .range(offset, offset + limit * 2 - 1); // Fetch extra to compensate for ELO filter

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      var games = await compute(_decodeGamesInIsolate, jsonList);

      // Filter games where at least one player from the country has rating > minElo
      games = games.where((game) {
        if (game.players == null) return false;
        return game.players!.any((player) =>
            player.fed.toUpperCase() == countryCode.toUpperCase() &&
            player.rating >= minElo);
      }).take(limit).toList();

      debugPrint('===== GameRepository: Fetched ${games.length} countryman games (ELO > $minElo) =====');

      return games;
    });
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

      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .eq('status', '*')
          .or(orConditions)
          .order('last_move_time', ascending: false)
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

      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .eq('status', '*')
          .inFilter('tour_id', eventIds)
          .order('last_move_time', ascending: false)
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

  /// Get top live games globally, ordered by recency.
  Future<List<Games>> getTopLiveGames({int limit = 200}) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('games')
          .select(_gameListSelectColumns)
          .eq('status', '*')
          .order('last_move_time', ascending: false)
          .limit(limit);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();

      final games = await compute(_decodeGamesInIsolate, jsonList);
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
