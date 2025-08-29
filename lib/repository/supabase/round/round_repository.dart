// repositories/round_repository.dart
import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final roundRepositoryProvider = AutoDisposeProvider<RoundRepository>((ref) {
  return RoundRepository();
});

class RoundRepository extends BaseRepository {
  // Fetch rounds by tour ID
  Future<List<Round>> getRoundsByTourId(String tourId) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('rounds')
          .select()
          .eq('tour_id', tourId)
          .order('created_at', ascending: true);

      return (response as List).map((json) => Round.fromJson(json)).toList();
    });
  }

  // Fetch rounds by tour slug
  Future<List<Round>> getRoundsByTourSlug(String tourSlug) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('rounds')
          .select()
          .eq('tour_slug', tourSlug)
          .order('created_at', ascending: true);

      return (response as List).map((json) => Round.fromJson(json)).toList();
    });
  }

  // Fetch round by ID
  Future<Round> getRoundById(String id) async {
    return handleApiCall(() async {
      final response =
          await supabase.from('rounds').select().eq('id', id).single();

      return Round.fromJson(response);
    });
  }

  // Fetch round by slug within a tour
  Future<Round> getRoundBySlug(String roundSlug, String tourSlug) async {
    return handleApiCall(() async {
      final response =
          await supabase
              .from('rounds')
              .select()
              .eq('slug', roundSlug)
              .eq('tour_slug', tourSlug)
              .single();

      return Round.fromJson(response);
    });
  }

  // Fetch ongoing rounds
  Future<List<Round>> getOngoingRounds({String? tourId}) async {
    return handleApiCall(() async {
      var query = supabase.from('rounds').select().eq('ongoing', true);

      if (tourId != null) {
        query = query.eq('tour_id', tourId);
      }

      final response = await query.order('starts_at', ascending: true);

      return (response as List).map((json) => Round.fromJson(json)).toList();
    });
  }

  // Fetch upcoming rounds
  Future<List<Round>> getUpcomingRounds({String? tourId, int? limit}) async {
    return handleApiCall(() async {
      final now = DateTime.now().toIso8601String();
      var query = supabase
          .from('rounds')
          .select()
          .eq('ongoing', false)
          .gte('starts_at', now);

      if (tourId != null) {
        query = query.eq('tour_id', tourId);
      }

      // Only call .limit() and .order() at the end, without reassigning
      if (limit != null) {
        final response = await query
            .limit(limit)
            .order('starts_at', ascending: true);
        return (response as List).map((json) => Round.fromJson(json)).toList();
      } else {
        final response = await query.order('starts_at', ascending: true);
        return (response as List).map((json) => Round.fromJson(json)).toList();
      }
    });
  }

  Future<List<Round>> getCompletedRounds({String? tourId, int? limit}) async {
    return handleApiCall(() async {
      var query = supabase
          .from('rounds')
          .select()
          .eq('ongoing', false)
          .lt('starts_at', DateTime.now().toIso8601String());

      if (tourId != null) {
        query = query.eq('tour_id', tourId);
      }

      if (limit != null) {
        final response = await query
            .limit(limit)
            .order('starts_at', ascending: false);
        return (response as List).map((json) => Round.fromJson(json)).toList();
      } else {
        final response = await query.order('starts_at', ascending: false);
        return (response as List).map((json) => Round.fromJson(json)).toList();
      }
    });
  }

  // Get round with game count
  Future<Map<String, dynamic>> getRoundWithStats(String roundId) async {
    return handleApiCall(() async {
      final round = await getRoundById(roundId);

      final gamesResponse = await supabase
          .from('games')
          .select('id, status')
          .eq('round_id', roundId);

      final games = gamesResponse as List;
      final totalGames = games.length;
      final ongoingGames = games.where((game) => game['status'] == '*').length;
      final completedGames = totalGames - ongoingGames;

      return {
        'round': round,
        'totalGames': totalGames,
        'ongoingGames': ongoingGames,
        'completedGames': completedGames,
      };
    });
  }

  Future<Round?> getLatestRoundByLastMove(String tourId) async {
    return handleApiCall(() async {
      final rounds = await getRoundsByTourId(tourId);

      if (rounds.isEmpty) {
        return null;
      }
      print(
        "🔹 Total rounds for tour $tourId: ${rounds.map((r) => r.id).toList()}",
      );

      Round? latestRoundWithMove;

      for (final round in rounds) {
        final gamesResponse = await supabase
            .from('games')
            .select('id, last_move')
            .eq('round_id', round.id)
            .not('last_move', 'is', null)
            .limit(1);

        final nonNullMoveCount = (gamesResponse as List).length;
        print(
          "Checking round ${round.id} → games with non-null last_move: $nonNullMoveCount",
        );

        if (nonNullMoveCount > 0) {
          latestRoundWithMove = round;
          print("Found round with non-null last_move: ${round.id}");
          break;
        }
      }

      if (latestRoundWithMove == null) {
        latestRoundWithMove = rounds.last;
        print(
          " No round with last_move (non-null) found, fallback to newest: ${rounds.last.id}",
        );
      } else {
        print(
          " Final selected round : ${latestRoundWithMove.id}",
        );
      }

      return latestRoundWithMove;
    });
  }
}
