import 'package:chessever2/screens/standings/player_standing_sections_provider.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/standings_builder.dart';
import 'package:chessever2/screens/standings/official_team_standings.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
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

/// The category a team was opened from when it is not the selected one: a
/// row of the Combined Standings tab. Set together with [selectedTeamProvider].
///
/// It holds the very team it was set for, and applies to nothing else. A
/// team opened any other way (the Games tab, a link, the selected category's
/// own table) therefore describes the selected category as before, even when
/// both categories have a team of that name (Olympiad Open and Women both
/// field "India").
final selectedTeamCategoryProvider =
    StateProvider<({TeamStandingModel team, String tourId})?>((ref) => null);

/// The tour the open team score card reads, or null for the selected one.
String? _selectedTeamTourId(Ref ref) {
  final scope = ref.watch(selectedTeamCategoryProvider);
  if (scope == null) return null;
  if (!identical(scope.team, ref.watch(selectedTeamProvider))) return null;
  // Only while that tour is still another category of the open Combined
  // event. Once the reader leaves the event, or Combined, this falls back to
  // the selected category, so nothing here keeps a foreign category's games
  // loaded and polling.
  return ref.watch(combinedOtherCategoryProvider(scope.tourId))
      ? scope.tourId
      : null;
}

/// The category the open team score card describes when it is not the
/// selected one, so the card's name, link and player chips are that
/// category's too.
final selectedTeamTourIdProvider = AutoDisposeProvider<String?>(
  _selectedTeamTourId,
);

/// Team standings of the category the open team score card describes.
final selectedTeamStandingsProvider =
    AutoDisposeProvider<AsyncValue<List<TeamStandingModel>>>((ref) {
      final tourId = _selectedTeamTourId(ref);
      return tourId == null
          ? ref.watch(teamStandingsProvider)
          : ref.watch(categoryTeamStandingsProvider(tourId));
    });

final selectedTeamStandingProvider = Provider<TeamStandingModel?>((ref) {
  return resolveSelectedTeamStanding(
    selected: ref.watch(selectedTeamProvider),
    standings: ref.watch(selectedTeamStandingsProvider).valueOrNull,
  );
});

String _selectedTourId(Ref ref) =>
    ref.watch(tourDetailScreenProvider).valueOrNull?.aboutTourModel.id ?? '';

/// Reads [tourId]'s live games as [GamesTourModel]s, subscribing only to
/// result-affecting changes.
List<GamesTourModel> _watchTeamGames(Ref ref, String tourId) {
  final games = <GamesTourModel>[];
  if (tourId.isEmpty) return games;
  ref.watch(completeGamesTourProvider(tourId).select(standingsGamesSignature));
  final raw =
      ref.watch(completeGamesTourProvider(tourId)).valueOrNull ?? const [];
  for (final g in raw) {
    try {
      games.add(GamesTourModel.fromGameIndex(g));
    } catch (_) {}
  }
  final info = _tourInfo(ref, tourId);
  final section = selectedOfficialPlayerSection(
    info?.playerStandingSections ?? const [],
    ref.watch(selectedPlayerStandingSectionProvider(tourId)),
  );
  return section == null ? games : scopeOfficialSectionGames(section, games);
}

TourInfo? _tourInfo(Ref ref, String tourId) {
  final vm = ref.watch(tourDetailScreenProvider).valueOrNull;
  if (vm == null) return null;
  for (final t in vm.tours) {
    if (t.tour.id == tourId) return t.tour.info;
  }
  return null;
}

List<TeamMatch> _buildTeamMatches(
  Ref ref, {
  required String tourId,
  required String teamName,
  required List<TeamStandingModel>? standings,
}) {
  final games = _watchTeamGames(ref, tourId);
  // Official rows can be spelled differently from the broadcast labels.
  final key = teamName.trim().toLowerCase();
  final link = standings
      ?.where((t) => t.teamName.trim().toLowerCase() == key)
      .firstOrNull
      ?.feedLink;
  return buildTeamMatches(
    games: games,
    teamName: teamName,
    scoring: TeamScoringRules.fromTourInfo(_tourInfo(ref, tourId)),
    link: link,
    opponentName: officialTeamOpponentNamer(standings),
  );
}

/// Round-by-round matches for a given team (by name) of the selected
/// category. Powers both the expandable team standings row and the team
/// score card.
final teamMatchesFamilyProvider =
    AutoDisposeProvider.family<List<TeamMatch>, String>((ref, teamName) {
      return _buildTeamMatches(
        ref,
        tourId: _selectedTourId(ref),
        teamName: teamName,
        standings: ref.watch(teamStandingsProvider).valueOrNull,
      );
    });

/// The same matches for a team of any category of the open event: what a
/// Combined standings row expands to.
final categoryTeamMatchesProvider =
    AutoDisposeProvider.family<
      List<TeamMatch>,
      ({String tourId, String teamName})
    >((ref, team) {
      return _buildTeamMatches(
        ref,
        tourId: team.tourId,
        teamName: team.teamName,
        standings: ref
            .watch(categoryTeamStandingsProvider(team.tourId))
            .valueOrNull,
      );
    });

/// Round-by-round matches for the currently selected team (team score card).
final teamMatchesProvider = AutoDisposeProvider<List<TeamMatch>>((ref) {
  final team = ref.watch(selectedTeamStandingProvider);
  if (team == null) return const [];
  final tourId = _selectedTeamTourId(ref);
  return tourId == null
      ? ref.watch(teamMatchesFamilyProvider(team.teamName))
      : ref.watch(
          categoryTeamMatchesProvider((
            tourId: tourId,
            teamName: team.teamName,
          )),
        );
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
      return playersAsync.whenData(
        (players) => _buildTeamTable(ref, _selectedTourId(ref), players),
      );
    });

/// Team standings of one category of the open event, whichever category is
/// selected: a section of the Combined Standings tab. Built exactly like
/// [teamStandingsProvider], from that category's own players and games.
///
/// A table already on screen stays through a recompute. That covers two
/// things the selected category's provider handles by dropping to its
/// loading state instead: the players being re-ranked, and the boards being
/// refetched. The second matters most: a table computed from the boards
/// while the catalog is reloading would rank every team on zero games.
final categoryTeamStandingsProvider = NotifierProvider.autoDispose
    .family<
      CategoryTeamStandingsNotifier,
      AsyncValue<List<TeamStandingModel>>,
      String
    >(CategoryTeamStandingsNotifier.new);

class CategoryTeamStandingsNotifier
    extends
        AutoDisposeFamilyNotifier<AsyncValue<List<TeamStandingModel>>, String> {
  List<TeamStandingModel>? _lastTable;

  AsyncValue<List<TeamStandingModel>> _keep(AsyncValue<Object?> source) {
    final last = _lastTable;
    if (last != null) return AsyncValue.data(last);
    if (source.hasError) {
      return AsyncValue.error(
        source.error!,
        source.stackTrace ?? StackTrace.current,
      );
    }
    return const AsyncValue.loading();
  }

  @override
  AsyncValue<List<TeamStandingModel>> build(String arg) {
    final tourId = arg;
    final playersAsync = ref.watch(categoryStandingsProvider(tourId));
    final players = playersAsync.valueOrNull;
    if (players == null) return _keep(playersAsync);

    final info = _tourInfo(ref, tourId);
    final official = buildOfficialTeamStandings(
      info: info,
      players: players,
      selectedSectionId: ref.watch(
        selectedPlayerStandingSectionProvider(tourId),
      ),
    );
    if (official != null) return AsyncValue.data(_lastTable = official);

    // Without the organizer's table the boards are the table, and only the
    // complete catalog will do.
    final catalog = ref.watch(completeGamesTourProvider(tourId));
    if (!catalog.hasValue) return _keep(catalog);
    return AsyncValue.data(
      _lastTable = buildTeamStandings(
        games: _watchTeamGames(ref, tourId),
        playerStandings: players,
        scoring: TeamScoringRules.fromTourInfo(info),
      ),
    );
  }
}

List<TeamStandingModel> _buildTeamTable(
  Ref ref,
  String tourId,
  List<PlayerStandingModel> players,
) {
  final info = _tourInfo(ref, tourId);
  final official = buildOfficialTeamStandings(
    info: info,
    players: players,
    selectedSectionId: ref.watch(selectedPlayerStandingSectionProvider(tourId)),
  );
  if (official != null) return official;
  return buildTeamStandings(
    games: _watchTeamGames(ref, tourId),
    playerStandings: players,
    scoring: TeamScoringRules.fromTourInfo(info),
  );
}
