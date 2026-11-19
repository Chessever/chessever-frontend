import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/player_standing_section_select.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_games_list_end.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/standings/standings_search_text.dart';
import 'package:chessever2/screens/tour_detail/combined/standings_category_scope.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_space_shortcut.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/team_tour/widgets/team_player_chip.dart';
import 'package:chessever2/screens/tour_detail/team_tour/widgets/team_round_group.dart';
import 'package:chessever2/screens/group_event/widget/empty_widget.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/figma_team_card.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Team-event "Standings" tab: one expandable row per team (match points +
/// board points). Tapping the row opens the team score card; the chevron
/// expands the team's round-by-round matchups. Structurally mirrors
/// [PlayerTourScreen].
class TeamStandingsScreen extends ConsumerStatefulWidget {
  const TeamStandingsScreen({super.key});

  @override
  ConsumerState<TeamStandingsScreen> createState() =>
      _TeamStandingsScreenState();
}

class _TeamStandingsScreenState extends ConsumerState<TeamStandingsScreen>
    with AutomaticKeepAliveClientMixin, ScrollToTopListenerMixin {
  late final ScrollController _scrollController;

  @override
  bool get wantKeepAlive => true;

  @override
  void onScrollToTopRequested() {
    animateScrollControllerToTop(_scrollController);
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final vm = ref.watch(tourDetailScreenProvider).valueOrNull;
    final tourId = vm?.aboutTourModel.id ?? '';
    final tours = vm?.tours.where((t) => t.tour.id == tourId).toList();
    final sections = tours == null || tours.isEmpty
        ? const <OfficialPlayerSection>[]
        : tours.first.tour.info.playerStandingSections;
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.sp,
      tablet: 24.sp,
    );

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ResponsiveHelper.contentMaxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (sections.isNotEmpty)
                PlayerStandingSectionSelect(tourId: tourId, sections: sections),
              Expanded(child: _TeamList(controller: _scrollController)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamList extends ConsumerWidget {
  const _TeamList({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamsAsync = ref.watch(teamStandingsProvider);
    return teamsAsync.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: (allTeams) {
        final query = ref.watch(standingsSearchQueryProvider).trim();
        final data = query.isEmpty
            ? allTeams
            : allTeams
                  .where((t) => matchesStandingsSearch(t.teamName, query))
                  .toList(growable: false);
        final isSearching = query.isNotEmpty;
        final officialRound = allTeams.isEmpty
            ? null
            : allTeams.first.officialRound;

        // Empty finished compute must not look like "still loading".
        if (allTeams.isEmpty && !isSearching) {
          return Padding(
            padding: EdgeInsets.only(top: 48.h),
            child: const EmptyWidget(title: "No data available"),
          );
        }

        return ListView.builder(
          key: const PageStorageKey<String>('team_standings_list'),
          controller: controller,
          primary: false,
          padding: EdgeInsets.only(
            top: 8.sp,
            bottom: EventGamesListEnd.tableEnd(context),
          ),
          itemCount:
              (data.isEmpty ? 1 : data.length) +
              (officialRound == null ? 0 : 1),
          itemBuilder: (context, index) {
            if (officialRound != null && index == 0) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 12.sp),
                child: Text(
                  'Official standings · after round $officialRound',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            }
            if (data.isEmpty) {
              return Padding(
                padding: EdgeInsets.only(top: 48.h),
                child: EmptyWidget(
                  title: isSearching
                      ? "No teams found matching your search"
                      : "No data available",
                ),
              );
            }

            final team = data[index - (officialRound == null ? 0 : 1)];
            return TeamStandingRow(
              key: ValueKey('team_standing_${team.teamName}'),
              team: team,
            );
          },
        );
      },
      error: (e, _) => Padding(
        padding: EdgeInsets.only(top: 48.h),
        child: const EmptyWidget(
          title: "Couldn't load team standings. Pull away and try again.",
        ),
      ),
      loading: () => const TeamStandingsLoadingList(),
    );
  }
}

/// One team of a team standings table: the row, its long-press menu, and
/// the players and matches it expands to.
///
/// Shared by the selected category's table and by the team sections of the
/// Combined Standings tab. A section of another category sits under a
/// [StandingsCategoryScope], which this row reads so the score card, the
/// matches and the share link are that category's, not the selected one's.
class TeamStandingRow extends ConsumerWidget {
  const TeamStandingRow({super.key, required this.team});

  final TeamStandingModel team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tourId = StandingsCategoryScope.tourIdOf(context);
    // Two categories can field a team of the same name (Open and Women both
    // have "India"); each folds on its own.
    final expansionKey = tourId == null
        ? team.teamName
        : '$tourId\n${team.teamName}';
    // Per-row selector: toggling one team only rebuilds that row, not the
    // whole (crest-heavy) list.
    final isExpanded = ref.watch(
      expandedTeamsProvider.select((s) => s.contains(expansionKey)),
    );
    void openScorecard() {
      ref.read(selectedTeamProvider.notifier).state = team;
      ref.read(selectedTeamCategoryProvider.notifier).state = tourId == null
          ? null
          : (team: team, tourId: tourId);
      Navigator.of(context).pushNamed('/team_scorecard_screen');
    }

    return FigmaTeamCard(
      team: team,
      rank: team.rank,
      isExpanded: isExpanded,
      onTeamTap: openScorecard,
      onToggle: () {
        final next = Set<String>.from(ref.read(expandedTeamsProvider));
        if (!next.remove(expansionKey)) {
          next.add(expansionKey);
        }
        ref.read(expandedTeamsProvider.notifier).state = next;
      },
      // Header only: the menu measures and lifts the same box, and the
      // players and matchups below keep their gestures.
      wrapHeader: (header) => _TeamRowMenu(
        team: team,
        tourId: tourId,
        onOpen: openScorecard,
        child: header,
      ),
      expandedChildren: isExpanded
          ? [_TeamExpansion(team: team, tourId: tourId)]
          : const [],
    );
  }
}

/// Long-press on a team standings row header: the header lifts into the
/// shared focus menu (open its scorecard, share its page, pin it into My
/// Space).
///
/// Wraps only the collapsed header (via [FigmaTeamCard.wrapHeader]), so the
/// lifted copy and the anchor the menu is placed from are the same box even
/// while the team is expanded, and a press on the players or matchups below
/// never opens the team menu.
class _TeamRowMenu extends ConsumerWidget {
  const _TeamRowMenu({
    required this.team,
    required this.tourId,
    required this.onOpen,
    required this.child,
  });

  final TeamStandingModel team;
  final String? tourId;
  final VoidCallback onOpen;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CardContextMenu(
      actions: (menuContext) => teamMenuActions(
        context: menuContext,
        ref: ref,
        teamName: team.teamName,
        tourId: tourId,
        onOpen: onOpen,
      ),
      onPreviewTap: onOpen,
      child: child,
    );
  }
}

/// Revealed under an expanded team row: the team's players as tappable chips,
/// then its round-by-round matchups (each round collapsible, collapsed by
/// default).
class _TeamExpansion extends ConsumerWidget {
  const _TeamExpansion({required this.team, required this.tourId});

  final TeamStandingModel team;
  final String? tourId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryTourId = tourId;
    final matches = categoryTourId == null
        ? ref.watch(teamMatchesFamilyProvider(team.teamName))
        : ref.watch(
            categoryTeamMatchesProvider((
              tourId: categoryTourId,
              teamName: team.teamName,
            )),
          );
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 6.h, 12.w, 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (team.players.isNotEmpty) ...[
            TeamPlayerChipsGrid(players: team.players),
            SizedBox(height: 8.h),
          ],
          if (matches.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'No matches played yet',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textTertiary,
                ),
              ),
            )
          else
            for (var i = 0; i < matches.length; i++)
              TeamRoundGroup(
                match: matches[i],
                teamName: team.teamName,
                index: i,
              ),
        ],
      ),
    );
  }
}

/// Placeholder rows while a team table loads.
class TeamStandingsLoadingList extends StatelessWidget {
  const TeamStandingsLoadingList({super.key});

  @override
  Widget build(BuildContext context) {
    final List<TeamStandingModel> data = [
      for (var i = 0; i < 6; i++)
        TeamStandingModel(
          teamName: 'Team Name',
          rank: i + 1,
          matchPoints: 9,
          gamePoints: 26.5,
          matchesWon: 4,
          matchesDrawn: 1,
          matchesLost: 0,
          boardsPlayed: 40,
          players: const [],
        ),
    ];

    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.only(bottom: EventGamesListEnd.tableEnd(context)),
      itemCount: data.length,
      itemBuilder: (context, index) {
        return SkeletonWidget(
          child: FigmaTeamCard(
            team: data[index],
            rank: index + 1,
            isExpanded: false,
            onToggle: () {},
            onTeamTap: () {},
            expandedChildren: const [],
          ),
        );
      },
    );
  }
}
