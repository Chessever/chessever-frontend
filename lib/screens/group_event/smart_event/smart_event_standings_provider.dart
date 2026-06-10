import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/supabase.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/standings_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
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

      // Read games per tour from local cache (with one-shot network fallback)
      // instead of subscribing to gamesTourProvider. The standings tab does
      // not need every included event's 10s polling timer running on top of
      // the regular event view's own polling — that path was producing log
      // spam and post-dispose state mutations when the smart event surface
      // unmounted. Standings recompute on screen rebuild and on explicit
      // pull-to-refresh of the smart aggregate, which is sufficient for the
      // results / new-game cadence the standings table actually reflects.
      final storage = ref.read(gamesLocalStorage);
      final allGames = <GamesTourModel>[];
      for (final tour in tours) {
        final games = await storage.getGames(tour.id);
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
