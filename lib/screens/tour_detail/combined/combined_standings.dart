import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/official_team_standings.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/standings_search_text.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_games_provider.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_round_sections.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart'
    show resolveIsTeamEvent;
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_tour_screen_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Standings and Players tabs while the event is shown in Combined.
///
/// Combined never adds standings up across categories. Group A's table says
/// nothing about Group B's, an Open and a Women's section are two
/// competitions, a knockout stage's points mean nothing next to the group
/// stage before it, and a rapid and a blitz leg are scored by rules the feed
/// does not carry. So Combined shows every category's own table in one list,
/// each exactly as its single-category tab shows it:
///
/// 1. One section per category, in the order the picker lists them.
/// 2. The pages of one tournament an organizer split by board ("Boards
///    1-100", "Boards 101-200") are one section, as they are one table in
///    the single-category tab.
/// 3. A team category shows its team table on Standings and its players on
///    Players; any other category shows its players on both.
/// 4. A category with nothing to rank yet is left out, and so is an
///    organizer's own combined section, which would repeat the others.

/// Which of the two tabs a Combined standings list is drawn for.
enum CombinedStandingsView {
  /// The Standings tab: team tables for team categories.
  standings,

  /// The Players tab of a team event: every category's players.
  players,
}

/// One section of the Combined standings list: a category's own table.
@immutable
class CombinedStandingsGroup {
  const CombinedStandingsGroup({
    required this.tourIds,
    required this.label,
    required this.isTeam,
  });

  /// The tours ranked together in this table: one, or every page of a
  /// board-paginated tournament. Never empty.
  final List<String> tourIds;

  /// The category as Combined names it ("Group Stage | A", "Women").
  final String label;

  /// Whether the category is a team event.
  final bool isTeam;

  /// Identifies the section, whichever of its pages is selected.
  String get id => tourIds.first;

  /// The tour whose providers hold this table. The selected category's own
  /// tour when it is one of the pages, so its table is computed once.
  String tourIdFor(String? selectedTourId) =>
      selectedTourId != null && tourIds.contains(selectedTourId)
      ? selectedTourId
      : tourIds.first;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CombinedStandingsGroup &&
          listEquals(other.tourIds, tourIds) &&
          other.label == label &&
          other.isTeam == isTeam;

  @override
  int get hashCode => Object.hash(Object.hashAll(tourIds), label, isTeam);
}

/// The sections of the Combined standings list. Value-equal, so a live move
/// that changes no section does not rebuild the list.
@immutable
class CombinedStandingsGroups {
  const CombinedStandingsGroups(this.items, {this.isLoading = false});

  static const loading = CombinedStandingsGroups(
    <CombinedStandingsGroup>[],
    isLoading: true,
  );

  final List<CombinedStandingsGroup> items;

  /// Some category's boards are still loading, so which categories are team
  /// events, or copies of another, is not known yet.
  final bool isLoading;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CombinedStandingsGroups &&
          other.isLoading == isLoading &&
          listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(isLoading, Object.hashAll(items));
}

final RegExp _trailingSeparators = RegExp(r'[\s|:\-–—]+$');

/// Splits an event's categories into standings sections, in picker order.
///
/// [categories] are the categories Combined merges, in picker order.
/// [tourNamesById] holds each tour's full name, which is what tells a page
/// of a board-paginated tournament from a category of its own.
@visibleForTesting
List<CombinedStandingsGroup> buildCombinedStandingsGroups({
  required List<CombinedCategory> categories,
  required Map<String, String> tourNamesById,
  Set<String> teamTourIds = const <String>{},
  Set<String> mirrorTourIds = const <String>{},
}) {
  final groups = <CombinedStandingsGroup>[];
  final groupIndexByPageKey = <String, int>{};
  for (final category in categories) {
    if (mirrorTourIds.contains(category.tourId)) continue;
    final name = tourNamesById[category.tourId] ?? '';
    final isTeam = teamTourIds.contains(category.tourId);

    if (isBoardPaginationCategory(name)) {
      final pageKey = boardPaginationBaseName(name);
      final existing = groupIndexByPageKey[pageKey];
      if (existing != null) {
        final group = groups[existing];
        groups[existing] = CombinedStandingsGroup(
          tourIds: List<String>.unmodifiable([
            ...group.tourIds,
            category.tourId,
          ]),
          label: group.label,
          isTeam: group.isTeam || isTeam,
        );
        continue;
      }
      groupIndexByPageKey[pageKey] = groups.length;
      // "Open | Boards 1-50" reads "Open". A tournament whose pages are its
      // only categories has nothing left to name, and keeps the event's.
      final shared = boardPaginationBaseName(
        category.label,
      ).replaceFirst(_trailingSeparators, '');
      groups.add(
        CombinedStandingsGroup(
          tourIds: List<String>.unmodifiable([category.tourId]),
          label: shared.isEmpty ? 'All boards' : shared,
          isTeam: isTeam,
        ),
      );
      continue;
    }

    groups.add(
      CombinedStandingsGroup(
        tourIds: List<String>.unmodifiable([category.tourId]),
        label: category.label,
        isTeam: isTeam,
      ),
    );
  }
  return groups;
}

/// The standings sections of the open event.
///
/// Once the sections are known they stay known: a category whose boards are
/// being refetched, or one that joins the event later, does not send the
/// whole tab back to its loading state.
final combinedStandingsGroupsProvider =
    NotifierProvider.autoDispose<
      CombinedStandingsGroupsNotifier,
      CombinedStandingsGroups
    >(CombinedStandingsGroupsNotifier.new);

class CombinedStandingsGroupsNotifier
    extends AutoDisposeNotifier<CombinedStandingsGroups> {
  CombinedStandingsGroups? _last;
  String? _lastEventId;

  @override
  bool updateShouldNotify(
    CombinedStandingsGroups previous,
    CombinedStandingsGroups next,
  ) => previous != next;

  @override
  CombinedStandingsGroups build() {
    final eventId = ref.watch(combinedCategoryGroupIdProvider);
    // Another event's sections are never a stand-in for this one's.
    if (eventId != _lastEventId) {
      _lastEventId = eventId;
      _last = null;
    }
    final categories = ref.watch(combinedCategoriesProvider);
    if (!categories.canCombine) {
      return const CombinedStandingsGroups(<CombinedStandingsGroup>[]);
    }
    final tours =
        ref.watch(
          tourDetailScreenProvider.select((state) => state.valueOrNull?.tours),
        ) ??
        const <TourModel>[];
    final toursById = <String, Tour>{
      for (final model in tours) model.tour.id: model.tour,
    };
    final tourIds = categories.tourIds;

    // The boards decide two things: whether a category is a team event, and
    // whether it only repeats the boards of the others. The same lists the
    // Combined Games tab reads, so nothing is fetched for this.
    final gamesByTourId = <String, List<GamesTourModel>>{};
    var pending = false;
    for (final tourId in tourIds) {
      final games = ref.watch(combinedTourGamesProvider(tourId));
      final value = games.valueOrNull;
      if (value != null) {
        gamesByTourId[tourId] = value;
      } else if (!games.hasError) {
        pending = true;
      }
    }
    // The schedule too, as the Games list waits for it: without start times
    // a side event that reuses the round names can pass for a copy.
    final roundsAsync = ref.watch(
      combinedRoundsProvider(combinedRoundsKey(tourIds)),
    );
    final roundsByTourId = roundsAsync.valueOrNull;
    if (pending || (roundsByTourId == null && roundsAsync.isLoading)) {
      return _last ?? CombinedStandingsGroups.loading;
    }

    final mirrorTourIds = findMirrorTourIds(
      tourIds: tourIds,
      gamesByTourId: gamesByTourId,
      roundsByTourId: roundsByTourId ?? const <String, List<Round>>{},
    );

    final teamTourIds = <String>{};
    for (final tourId in tourIds) {
      final tour = toursById[tourId];
      if (tour == null) continue;
      final isTeam = resolveIsTeamEvent(
        teamTable: tour.info.teamTable,
        formatString: tour.info.format,
        players: tour.players,
        games: gamesByTourId[tourId] ?? const <GamesTourModel>[],
        // The flag settles it alone; only an unflagged tour needs its
        // published table parsed to find out.
        hasOfficialTeamTable:
            tour.info.teamTable != true &&
            buildOfficialTeamStandings(
                  info: tour.info,
                  players: const <PlayerStandingModel>[],
                ) !=
                null,
      );
      if (isTeam) teamTourIds.add(tourId);
    }

    return _last = CombinedStandingsGroups(
      List<CombinedStandingsGroup>.unmodifiable(
        buildCombinedStandingsGroups(
          categories: categories.items,
          tourNamesById: {
            for (final entry in toursById.entries) entry.key: entry.value.name,
          },
          teamTourIds: teamTourIds,
          mirrorTourIds: mirrorTourIds,
        ),
      ),
    );
  }
}

/// One section as the list paints it.
@immutable
class CombinedStandingsSection {
  const CombinedStandingsSection({
    required this.group,
    required this.tourId,
    required this.isSelectedCategory,
    required this.showsTeams,
    required this.players,
    required this.teams,
    required this.total,
    required this.officialRound,
    required this.officialSections,
    required this.hasError,
  });

  final CombinedStandingsGroup group;

  /// The tour whose providers hold this table.
  final String tourId;

  /// Whether this is the category selected underneath Combined. Its rows
  /// open score cards the way the single-category tab does; any other
  /// section names its own category (see `StandingsCategoryScope`).
  final bool isSelectedCategory;

  /// A team table ([teams]) rather than a player one ([players]).
  final bool showsTeams;

  /// The rows on screen: every row, or the search's hits.
  final List<PlayerStandingModel> players;
  final List<TeamStandingModel> teams;

  /// Rows in the table before any search.
  final int total;

  /// Set when a team table is the organizer's own, published after a round.
  final int? officialRound;

  /// The organizer's own sub-tables of this category, when it publishes
  /// several (the picker for them sits under the header).
  final List<OfficialPlayerSection> officialSections;

  /// The table could not be loaded; the section says so under its header.
  final bool hasError;

  int get rowCount => showsTeams ? teams.length : players.length;

  /// Same section, same rows. The row lists are compared by identity: a
  /// table that was not recomputed is the same list, and that is the case
  /// this exists for (a reload that changed nothing repaints nothing).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CombinedStandingsSection &&
          other.group == group &&
          other.tourId == tourId &&
          other.isSelectedCategory == isSelectedCategory &&
          other.showsTeams == showsTeams &&
          identical(other.players, players) &&
          identical(other.teams, teams) &&
          other.total == total &&
          other.officialRound == officialRound &&
          identical(other.officialSections, officialSections) &&
          other.hasError == hasError;

  @override
  int get hashCode => Object.hash(
    group,
    tourId,
    isSelectedCategory,
    showsTeams,
    identityHashCode(players),
    identityHashCode(teams),
    total,
    officialRound,
    hasError,
  );
}

/// Everything a Combined standings list paints.
@immutable
class CombinedStandingsState {
  const CombinedStandingsState({
    required this.isLoading,
    required this.sections,
    required this.tableCount,
    required this.query,
  });

  static const loading = CombinedStandingsState(
    isLoading: true,
    sections: <CombinedStandingsSection>[],
    tableCount: 0,
    query: '',
  );

  final bool isLoading;
  final List<CombinedStandingsSection> sections;

  /// How many tables the event has, whatever the search leaves of them.
  /// With more than one, every section is headed by its category, including
  /// the only one a search has hits in: the header is what says which
  /// category the hit plays in.
  final int tableCount;

  /// The search in effect, trimmed. Empty when the tables are unfiltered.
  final String query;

  bool get isSearching => query.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CombinedStandingsState &&
          other.isLoading == isLoading &&
          other.tableCount == tableCount &&
          other.query == query &&
          listEquals(other.sections, sections);

  @override
  int get hashCode =>
      Object.hash(isLoading, tableCount, query, Object.hashAll(sections));
}

final combinedStandingsProvider = NotifierProvider.autoDispose
    .family<
      CombinedStandingsNotifier,
      CombinedStandingsState,
      CombinedStandingsView
    >(CombinedStandingsNotifier.new);

class CombinedStandingsNotifier
    extends
        AutoDisposeFamilyNotifier<
          CombinedStandingsState,
          CombinedStandingsView
        > {
  /// The tables last painted, by [CombinedStandingsGroup.id]. A table that
  /// goes back to loading (another page of its tournament was selected, its
  /// provider was rebuilt) keeps these rows until the new ones arrive.
  final Map<String, List<PlayerStandingModel>> _lastPlayers =
      <String, List<PlayerStandingModel>>{};
  final Map<String, List<TeamStandingModel>> _lastTeams =
      <String, List<TeamStandingModel>>{};
  bool _hasPainted = false;
  String? _paintedEventId;

  @override
  bool updateShouldNotify(
    CombinedStandingsState previous,
    CombinedStandingsState next,
  ) => previous != next;

  @override
  CombinedStandingsState build(CombinedStandingsView arg) {
    final view = arg;
    final eventId = ref.watch(combinedCategoryGroupIdProvider);
    if (eventId != _paintedEventId) {
      _paintedEventId = eventId;
      _hasPainted = false;
      _lastPlayers.clear();
      _lastTeams.clear();
    }

    final groups = ref.watch(combinedStandingsGroupsProvider);
    if (groups.isLoading) return CombinedStandingsState.loading;

    final selectedTourId = ref.watch(
      tourDetailScreenProvider.select(
        (state) => state.valueOrNull?.aboutTourModel.id,
      ),
    );
    final toursById = <String, Tour>{
      for (final model
          in ref.watch(
                tourDetailScreenProvider.select(
                  (state) => state.valueOrNull?.tours,
                ),
              ) ??
              const <TourModel>[])
        model.tour.id: model.tour,
    };
    final query = ref.watch(standingsSearchQueryProvider).trim();

    final sections = <CombinedStandingsSection>[];
    // First paint waits for every table, so the list is laid out once
    // instead of growing section by section under the reader's thumb. From
    // then on nothing sends the tab back to loading: a table keeps its rows
    // while it is recomputed, and a category that joins the event later
    // takes its place when its table is ready.
    var pending = false;
    var tableCount = 0;
    for (final group in groups.items) {
      final tourId = group.tourIdFor(selectedTourId);
      final showsTeams =
          view == CombinedStandingsView.standings && group.isTeam;
      final officialSections = group.tourIds.length == 1
          ? toursById[tourId]?.info.playerStandingSections ??
                const <OfficialPlayerSection>[]
          : const <OfficialPlayerSection>[];

      var players = const <PlayerStandingModel>[];
      var teams = const <TeamStandingModel>[];
      var total = 0;
      int? officialRound;
      final bool hasValue;
      final bool hasError;
      if (showsTeams) {
        final table = ref.watch(categoryTeamStandingsProvider(tourId));
        final fresh = table.valueOrNull;
        if (fresh != null) _lastTeams[group.id] = fresh;
        final all = fresh ?? (_hasPainted ? _lastTeams[group.id] : null);
        hasValue = all != null;
        hasError = !hasValue && table.hasError;
        if (all != null) {
          total = all.length;
          officialRound = all.isEmpty ? null : all.first.officialRound;
          teams = query.isEmpty
              ? all
              : [
                  for (final team in all)
                    if (matchesStandingsSearch(team.teamName, query)) team,
                ];
        }
      } else {
        final table = ref.watch(categoryStandingsProvider(tourId));
        final fresh = table.valueOrNull;
        if (fresh != null) _lastPlayers[group.id] = fresh;
        final all = fresh ?? (_hasPainted ? _lastPlayers[group.id] : null);
        hasValue = all != null;
        hasError = !hasValue && table.hasError;
        if (all != null) {
          total = all.length;
          players = filterStandingsByQuery(all, query);
        }
      }

      if (!hasValue && !hasError) {
        pending = true;
        continue;
      }
      if (hasError || total > 0) tableCount++;
      // Nothing to rank yet (a stage that has not been drawn), or no hit
      // for the search: the section would be a header over nothing.
      final isEmpty = showsTeams ? teams.isEmpty : players.isEmpty;
      if (isEmpty && (!hasError || query.isNotEmpty)) continue;

      sections.add(
        CombinedStandingsSection(
          group: group,
          tourId: tourId,
          isSelectedCategory: tourId == selectedTourId,
          showsTeams: showsTeams,
          players: players,
          teams: teams,
          total: total,
          officialRound: officialRound,
          officialSections: officialSections,
          hasError: hasError,
        ),
      );
    }

    if (pending && !_hasPainted) return CombinedStandingsState.loading;
    _hasPainted = true;
    return CombinedStandingsState(
      isLoading: false,
      sections: List<CombinedStandingsSection>.unmodifiable(sections),
      tableCount: tableCount,
      query: query,
    );
  }
}

/// Sections the reader folded, by [CombinedStandingsGroup.id]. Every section
/// starts open; the choice lasts while the event stays open in Combined.
final combinedStandingsCollapsedProvider =
    StateProvider.autoDispose<Set<String>>((ref) => const <String>{});
