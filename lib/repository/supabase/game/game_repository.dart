// repositories/game_repository.dart
import 'dart:convert';

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gameRepositoryProvider = AutoDisposeProvider<GameRepository>((ref) {
  return GameRepository();
});

class GameRepository extends BaseRepository {
  // Fetch games by round ID
  Future<List<Games>> getGamesByRoundId(String roundId) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('games')
          .select()
          .eq('round_id', roundId)
          .order('id', ascending: true);

      return (response as List).map((json) => Games.fromJson(json)).toList();
    });
  }

  // Fetch games by tour ID
  Future<List<Games>> getGamesByTourId(String tourId, {int? limit}) async {
    return handleApiCall(() async {
      var query = supabase
          .from('games')
          .select('''
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
        ''')
          .eq('tour_id', tourId)
          .order('id', ascending: true);

      if (limit != null) {
        query = query.limit(limit);
      }

      final response = await query;

      return (response as List).map((json) => Games.fromJson(json)).toList();
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

  // Fetch games by round and tour slug
  Future<List<Games>> getGamesBySlug(String roundSlug, String tourSlug) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('games')
          .select()
          .eq('round_slug', roundSlug)
          .eq('tour_slug', tourSlug)
          .order('id', ascending: true);

      return (response as List).map((json) => Games.fromJson(json)).toList();
    });
  }

  // Fetch ongoing games
  Future<List<Games>> getOngoingGames({String? tourId, String? roundId}) async {
    return handleApiCall(() async {
      var query = supabase
          .from('games')
          .select()
          .eq('status', '*'); // Assuming '*' means ongoing

      if (tourId != null) {
        query = query.eq('tour_id', tourId);
      }

      if (roundId != null) {
        query = query.eq('round_id', roundId);
      }

      final response = await query.order('id', ascending: true);

      return (response as List).map((json) => Games.fromJson(json)).toList();
    });
  }

  // Fetch games by status
  Future<List<Games>> getGamesByStatus(
    String status, {
    String? tourId,
    int? limit,
  }) async {
    return handleApiCall(() async {
      var query = supabase.from('games').select().eq('status', status);

      if (tourId != null) {
        query = query.eq('tour_id', tourId);
      }

      if (limit != null) {
        final response = await query.limit(limit).order('id', ascending: true);
        return (response as List).map((json) => Games.fromJson(json)).toList();
      } else {
        final response = await query.order('id', ascending: true);
        return (response as List).map((json) => Games.fromJson(json)).toList();
      }
    });
  }

  // Search games by player name (requires full-text search setup)
  Future<List<Games>> searchGamesByPlayer(String playerQuery) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('games')
          .select()
          .like('name', '%$playerQuery%')
          .order('id', ascending: false);

      return (response as List).map((json) => Games.fromJson(json)).toList();
    });
  }

  // Get all games for a specific player by fideId
  Future<List<Games>> getGamesByFideId(String fideId, {int? limit}) async {
    return handleApiCall(() async {
      print('===== GameRepository: Fetching games for fideId: $fideId =====');

      // Query games where the fideId appears in the players JSONB array
      var query = supabase
          .from('games')
          .select('''
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
          pgn,
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
        ''')
          .contains('players', [{'fideId': int.parse(fideId)}])
          .order('date_start', ascending: false)
          .order('time_start', ascending: false);

      if (limit != null) {
        query = query.limit(limit);
      }

      print('===== GameRepository: Executing query with limit: $limit =====');
      final response = await query;

      print('===== GameRepository: Received ${(response as List).length} games =====');
      return (response as List).map((json) => Games.fromJson(json)).toList();
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
          .select('''
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
          pgn,
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
        ''')
          .contains('players', [{'fideId': int.parse(fideId)}])
          .order('date_start', ascending: false)
          .order('time_start', ascending: false)
          .range(offset, offset + limit - 1);

      return (response as List).map((json) => Games.fromJson(json)).toList();
    });
  }

  // Get recent games across all tournaments
  Future<List<Games>> getRecentGames({int limit = 20}) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('games')
          .select()
          .order('id', ascending: false)
          .limit(limit);

      return (response as List).map((json) => Games.fromJson(json)).toList();
    });
  }

  // Get game with full context (tournament and round info)
  Future<Map<String, dynamic>> getGameWithContext(String gameId) async {
    return handleApiCall(() async {
      final response =
          await supabase
              .from('games')
              .select('''
            *,
            rounds!inner(
              id,
              name,
              slug,
              ongoing,
              starts_at,
              tours!inner(
                id,
                name,
                slug,
                tier,
                image
              )
            )
          ''')
              .eq('id', gameId)
              .single();

      return response;
    });
  }

  // Get games with moves (non-null last_move)
  Future<List<Games>> getGamesWithMoves({String? tourId, int? limit}) async {
    return handleApiCall(() async {
      var query = supabase.from('games').select().not('last_move', 'is', null);

      if (tourId != null) {
        query = query.eq('tour_id', tourId);
      }

      if (limit != null) {
        final response = await query.limit(limit).order('id', ascending: false);
        return (response as List).map((json) => Games.fromJson(json)).toList();
      } else {
        final response = await query.order('id', ascending: false);
        return (response as List).map((json) => Games.fromJson(json)).toList();
      }
    });
  }

  // Get games where any player has a specific country code
  Future<List<Games>> getGamesByCountryCode(String countryCode) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('games')
          .select()
          .contains('players', '[{"fed": "$countryCode"}]')
          .order('id', ascending: true);

      return (response as List).map((json) => Games.fromJson(json)).toList();
    });
  }
}

List<Games> decodeGamesInIsolate(List<String> gameJsonList) {
  return gameJsonList.map((e) {
    final decoded = json.decode(e) as Map<String, dynamic>;
    return Games.fromJson(decoded);
  }).toList();
}
