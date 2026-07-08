import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/team_tour/widgets/team_round_group.dart';
import 'package:chessever2/screens/group_event/widget/empty_widget.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
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
        final data =
            query.isEmpty
                ? allTeams
                : allTeams
                    .where(
                      (t) => t.teamName.toLowerCase().contains(
                        query.toLowerCase(),
                      ),
                    )
                    .toList(growable: false);
        final isSearching = query.isNotEmpty;
        final expanded = ref.watch(expandedTeamsProvider);

        if (allTeams.isEmpty) {
          return const _TeamStandingsLoading();
        }

        return ListView.builder(
          key: const PageStorageKey<String>('team_standings_list'),
          controller: controller,
          primary: false,
          padding: EdgeInsets.only(
            top: 8.sp,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16.sp,
          ),
          itemCount: data.isEmpty ? 1 : data.length,
          itemBuilder: (context, index) {
            if (data.isEmpty) {
              return Padding(
                padding: EdgeInsets.only(top: 48.h),
                child: EmptyWidget(
                  title:
                      isSearching
                          ? "No teams found matching your search"
                          : "No data available",
                ),
              );
            }

            final team = data[index];
            final isExpanded = expanded.contains(team.teamName);
            return FigmaTeamCard(
              key: ValueKey('team_standing_${team.teamName}'),
              team: team,
              rank: team.rank,
              isExpanded: isExpanded,
              onTeamTap: () {
                ref.read(selectedTeamProvider.notifier).state = team;
                Navigator.of(context).pushNamed('/team_scorecard_screen');
              },
              onToggle: () {
                final next = Set<String>.from(
                  ref.read(expandedTeamsProvider),
                );
                if (!next.remove(team.teamName)) {
                  next.add(team.teamName);
                }
                ref.read(expandedTeamsProvider.notifier).state = next;
              },
              expandedChildren:
                  isExpanded
                      ? [_TeamExpansion(teamName: team.teamName)]
                      : const [],
            );
          },
        );
      },
      error: (e, _) => const _TeamStandingsLoading(),
      loading: () => const _TeamStandingsLoading(),
    );
  }
}

/// Round-by-round matchups revealed under an expanded team row.
class _TeamExpansion extends ConsumerWidget {
  const _TeamExpansion({required this.teamName});

  final String teamName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(teamMatchesFamilyProvider(teamName));
    if (matches.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 12.h),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'No matches played yet',
            style: AppTypography.textSmMedium.copyWith(
              color: Theme.of(context).hintColor,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 12.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < matches.length; i++)
            TeamRoundGroup(match: matches[i], index: i),
        ],
      ),
    );
  }
}

class _TeamStandingsLoading extends StatelessWidget {
  const _TeamStandingsLoading();

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
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16.sp,
      ),
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
