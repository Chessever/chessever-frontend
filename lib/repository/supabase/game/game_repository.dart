// repositories/game_repository.dart
import 'package:chessever2/repository/supabase/game/game.dart';
import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gameRepositoryProvider = AutoDisposeProvider<GameRepository>((ref) {
  return GameRepository();
});

class GameRepository extends BaseRepository {
  // Fetch games by round ID
  Future<List<Game>> getGamesByRoundId(String roundId) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('games')
          .select()
          .eq('round_id', roundId)
          .order('id', ascending: true);

      return (response as List).map((json) => Game.fromJson(json)).toList();
    });
  }

  // Fetch games by tour ID
  Future<List<Game>> getGamesByTourId(String tourId, {int? limit}) async {
    return handleApiCall(() async {
      var query = supabase
          .from('games')
          .select()
          .eq('tour_id', tourId)
          .order('id', ascending: true);

      if (limit != null) {
        query = query.limit(limit);
      }

      final response = await query;

      return (response as List).map((json) => Game.fromJson(json)).toList();
    });
  }

  // Fetch game by ID
  Future<Game> getGameById(String id) async {
    return handleApiCall(() async {
      final response =
          await supabase.from('games').select().eq('id', id).single();

      return Game.fromJson(response);
    });
  }

  // Fetch games by round and tour slug
  Future<List<Game>> getGamesBySlug(String roundSlug, String tourSlug) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('games')
          .select()
          .eq('round_slug', roundSlug)
          .eq('tour_slug', tourSlug)
          .order('id', ascending: true);

      return (response as List).map((json) => Game.fromJson(json)).toList();
    });
  }

  // Fetch ongoing games
  Future<List<Game>> getOngoingGames({String? tourId, String? roundId}) async {
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

      return (response as List).map((json) => Game.fromJson(json)).toList();
    });
  }

  // Fetch games by status
  Future<List<Game>> getGamesByStatus(
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
        return (response as List).map((json) => Game.fromJson(json)).toList();
      } else {
        final response = await query.order('id', ascending: true);
        return (response as List).map((json) => Game.fromJson(json)).toList();
      }
    });
  }

  // Search games by player name (requires full-text search setup)
  Future<List<Game>> searchGamesByPlayer(String playerQuery) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('games')
          .select()
          .like('name', '%$playerQuery%')
          .order('id', ascending: false);

      return (response as List).map((json) => Game.fromJson(json)).toList();
    });
  }

  // Get recent games across all tournaments
  Future<List<Game>> getRecentGames({int limit = 20}) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('games')
          .select()
          .order('id', ascending: false)
          .limit(limit);

      return (response as List).map((json) => Game.fromJson(json)).toList();
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
  Future<List<Game>> getGamesWithMoves({String? tourId, int? limit}) async {
    return handleApiCall(() async {
      var query = supabase.from('games').select().not('last_move', 'is', null);

      if (tourId != null) {
        query = query.eq('tour_id', tourId);
      }

      if (limit != null) {
        final response = await query.limit(limit).order('id', ascending: false);
        return (response as List).map((json) => Game.fromJson(json)).toList();
      } else {
        final response = await query.order('id', ascending: false);
        return (response as List).map((json) => Game.fromJson(json)).toList();
      }
    });
  }
}
