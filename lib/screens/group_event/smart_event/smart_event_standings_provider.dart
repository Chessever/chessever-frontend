import 'package:chessever2/repository/supabase/supabase.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/standings_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Tours that belong to one event included in a smart event. Mirrors the
/// fallback used by the smart aggregate loader: events saved before the
/// group-broadcast split can carry a tour id instead of a broadcast id.
final _smartEventStandingsToursProvider = FutureProvider.autoDispose
    .family<List<Tour>, String>((ref, eventId) async {
      final tourRepository = ref.read(tourRepositoryProvider);
      final toursByEvent = await tourRepository.getToursByGroupBroadcastIds([
        eventId,
      ]);
      final tours = toursByEvent[eventId] ?? const <Tour>[];
      if (tours.isNotEmpty) return tours;

      final fallbackTours = await tourRepository.getToursByIds([eventId]);
      return fallbackTours
          .where(
            (tour) => tour.id == eventId || tour.groupBroadcastId == eventId,
          )
          .toList(growable: false);
    });

/// Live standings for one event inside the smart event Standings tab,
/// computed with [buildStandingsFromData] — the exact builder the regular
/// event view uses — so scores, rating diffs, and ordering match what the
/// user would see inside that event.
final smartEventStandingsProvider = FutureProvider.autoDispose
    .family<List<PlayerStandingModel>, String>((ref, eventId) async {
      final tours = await ref.watch(
        _smartEventStandingsToursProvider(eventId).future,
      );
      if (tours.isEmpty) return const <PlayerStandingModel>[];

      // Watch only the standings-relevant slice of live games so move/clock
      // ticks don't recompute standings, but results and new games do.
      final allGames = <GamesTourModel>[];
      for (final tour in tours) {
        ref.watch(gamesTourProvider(tour.id).select(standingsGamesSignature));
        final games = ref.read(gamesTourProvider(tour.id)).valueOrNull;
        if (games == null || games.isEmpty) continue;
        for (final game in games) {
          try {
            allGames.add(GamesTourModel.fromGame(game));
          } catch (_) {
            // Skip malformed rows to keep standings resilient during ingest.
          }
        }
      }

      final allPlayers = <TournamentPlayer>[
        for (final tour in tours) ...tour.players,
      ];

      final standings = await buildStandingsFromData(
        supabase: ref.read(supabaseProvider),
        tournamentPlayers: allPlayers,
        gamesTourModels: allGames,
        useExternalOrder:
            tours.length == 1 && tours.first.usesExternalStandings,
        singleTourScope: tours.length == 1,
      );
      return assignOverallRanks(standings);
    });
