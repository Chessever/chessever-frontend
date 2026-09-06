import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/standings_builder.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/utils/team_scoring_rules.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Team rows currently expanded to reveal their players. Multiple may be open.
final expandedTeamsProvider = StateProvider.autoDispose<Set<String>>(
  (ref) => <String>{},
);

/// The team whose score card is currently open (set on card tap, read by the
/// team score card screen). Mirrors `selectedPlayerProvider`.
final selectedTeamProvider = StateProvider<TeamStandingModel?>((ref) => null);

/// Replaces an early scorecard placeholder with the fully computed standing
/// as soon as standings finish loading. Games-tab navigation intentionally
/// opens immediately, so the selected value can initially have no players.
TeamStandingModel? resolveSelectedTeamStanding({
  required TeamStandingModel? selected,
  required List<TeamStandingModel>? standings,
}) {
  if (selected == null) return null;
  final selectedKey = selected.teamName.trim().toLowerCase();
  if (selectedKey.isEmpty || standings == null) return selected;
  for (final team in standings) {
    if (team.teamName.trim().toLowerCase() == selectedKey) return team;
  }
  return selected;
}

final selectedTeamStandingProvider = Provider<TeamStandingModel?>((ref) {
  return resolveSelectedTeamStanding(
    selected: ref.watch(selectedTeamProvider),
    standings: ref.watch(teamStandingsProvider).valueOrNull,
  );
});

/// Reads the current tour's live games as [GamesTourModel]s, subscribing only
/// to result-affecting changes.
List<GamesTourModel> _watchTeamGames(Ref ref) {
  final tourId =
      ref.watch(tourDetailScreenProvider).valueOrNull?.aboutTourModel.id ?? '';
  final games = <GamesTourModel>[];
  if (tourId.isEmpty) return games;
  ref.watch(gamesTourProvider(tourId).select(standingsGamesSignature));
  final raw = ref.watch(gamesTourProvider(tourId)).valueOrNull ?? const [];
  for (final g in raw) {
    try {
      games.add(GamesTourModel.fromGame(g));
    } catch (_) {}
  }
  return games;
}

/// Round-by-round matches for a given team (by name). Powers both the
/// expandable team standings row and the team score card.
TourInfo? _selectedTourInfo(Ref ref) {
  final vm = ref.watch(tourDetailScreenProvider).valueOrNull;
  if (vm == null) return null;
  for (final t in vm.tours) {
    if (t.tour.id == vm.aboutTourModel.id) return t.tour.info;
  }
  return null;
}

final teamMatchesFamilyProvider =
    AutoDisposeProvider.family<List<TeamMatch>, String>((ref, teamName) {
      final games = _watchTeamGames(ref);
      return buildTeamMatches(
        games: games,
        teamName: teamName,
        scoring: TeamScoringRules.fromTourInfo(_selectedTourInfo(ref)),
      );
    });

/// Round-by-round matches for the currently selected team (team score card).
final teamMatchesProvider = AutoDisposeProvider<List<TeamMatch>>((ref) {
  final team = ref.watch(selectedTeamStandingProvider);
  if (team == null) return const [];
  return ref.watch(teamMatchesFamilyProvider(team.teamName));
});

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
        final games = _watchTeamGames(ref);
        return buildTeamStandings(
          games: games,
          playerStandings: players,
          scoring: TeamScoringRules.fromTourInfo(_selectedTourInfo(ref)),
        );
      });
    });
