import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_tour_screen_provider.dart';
import 'package:chessever2/screens/group_event/widget/empty_widget.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/widgets/figma_team_card.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Team-event "Standings" tab: one expandable row per team (match points +
/// board points), revealing that team's individual [FigmaPlayerCard] rows.
/// Structurally mirrors [PlayerTourScreen].
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
              onToggle: () {
                final next = Set<String>.from(
                  ref.read(expandedTeamsProvider),
                );
                if (!next.remove(team.teamName)) {
                  next.add(team.teamName);
                }
                ref.read(expandedTeamsProvider.notifier).state = next;
              },
              playerRows: [
                for (final player in team.players)
                  Padding(
                    padding: EdgeInsets.only(left: 12.w),
                    child: FigmaPlayerCard(
                      key: ValueKey(
                        'team_player_${player.fideId ?? player.gamebasePlayerId ?? player.name}',
                      ),
                      player: player,
                      rank: player.overallRank,
                      showFavoriteButton: false,
                      onTap: () => _openScorecard(context, ref, player),
                    ),
                  ),
              ],
            );
          },
        );
      },
      error: (e, _) => const _TeamStandingsLoading(),
      loading: () => const _TeamStandingsLoading(),
    );
  }

  void _openScorecard(
    BuildContext context,
    WidgetRef ref,
    PlayerStandingModel player,
  ) {
    ref.read(selectedPlayerProvider.notifier).state = player;
    // Clear games context — tournament games come from gamesTourScreenProvider.
    ref.read(scoreCardGamesContextProvider.notifier).state = null;
    ref.read(scoreCardPlayerProfileDataSourceProvider.notifier).state =
        PlayerProfileDataSource.supabase;
    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;
    Navigator.of(context).pushNamed('/scorecard_screen');
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
            playerRows: const [],
          ),
        );
      },
    );
  }
}
