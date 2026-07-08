import 'package:chessever2/screens/standings/standings_builder.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Team rows currently expanded to reveal their players. Multiple may be open.
final expandedTeamsProvider = StateProvider.autoDispose<Set<String>>(
  (ref) => <String>{},
);

/// Team standings for the team-event "Standings" tab. Reuses the already-ranked
/// individual standings ([playerTourScreenProvider]) for the per-team player
/// rows and the same games source for the match/board score computation.
///
/// Recomputes only when the individual standings re-emit or a game result
/// changes (via [standingsGamesSignature]) — not on clock/move ticks.
final teamStandingsProvider =
    AutoDisposeProvider<AsyncValue<List<TeamStandingModel>>>((ref) {
      final playersAsync = ref.watch(playerTourScreenProvider);
      return playersAsync.whenData((players) {
        final tourId =
            ref
                .watch(tourDetailScreenProvider)
                .valueOrNull
                ?.aboutTourModel
                .id ??
            '';

        final games = <GamesTourModel>[];
        if (tourId.isNotEmpty) {
          // Subscribe to result-affecting changes only.
          ref.watch(gamesTourProvider(tourId).select(standingsGamesSignature));
          final raw =
              ref.read(gamesTourProvider(tourId)).valueOrNull ?? const [];
          for (final g in raw) {
            try {
              games.add(GamesTourModel.fromGame(g));
            } catch (_) {
              // Skip malformed rows to stay resilient during live ingest.
            }
          }
        }

        return buildTeamStandings(games: games, playerStandings: players);
      });
    });
