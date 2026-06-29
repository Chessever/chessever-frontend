import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/group_event/widget/empty_widget.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

String _standingsScrollBucket(String query) {
  final normalized = query.toLowerCase().trim();
  return normalized.isEmpty ? 'standings:all' : 'standings:search:$normalized';
}

/// The outer PlayerTourScreen intentionally does NOT watch the search query.
/// Only the inner [_StandingsList] subscribes to it, which keeps the outer
/// page stable across keystrokes and live-round rebuilds.
class PlayerTourScreen extends ConsumerStatefulWidget {
  const PlayerTourScreen({super.key});

  @override
  ConsumerState<PlayerTourScreen> createState() => _PlayerTourScreenState();
}

class _PlayerTourScreenState extends ConsumerState<PlayerTourScreen>
    with AutomaticKeepAliveClientMixin, ScrollToTopListenerMixin {
  late final ScrollController _scrollController;
  late String _scrollBucket;
  final Map<String, double> _scrollOffsets = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void onScrollToTopRequested() {
    animateScrollControllerToTop(_scrollController);
  }

  @override
  void initState() {
    super.initState();
    _scrollBucket = _standingsScrollBucket(
      ref.read(standingsSearchQueryProvider),
    );
    _scrollController = ScrollController()..addListener(_rememberScrollOffset);
  }

  @override
  void dispose() {
    _rememberScrollOffset();
    _scrollController
      ..removeListener(_rememberScrollOffset)
      ..dispose();
    super.dispose();
  }

  void _rememberScrollOffset() {
    if (!_scrollController.hasClients) return;
    _scrollOffsets[_scrollBucket] = _scrollController.offset;
  }

  void _restoreScrollOffset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final target =
          (_scrollOffsets[_scrollBucket] ?? 0)
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble();
      if ((position.pixels - target).abs() > 0.5) {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _handleSearchQueryChanged(String query) {
    final nextBucket = _standingsScrollBucket(query);
    if (nextBucket == _scrollBucket) return;

    _rememberScrollOffset();
    _scrollBucket = nextBucket;
    _restoreScrollOffset();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen<String>(standingsSearchQueryProvider, (_, next) {
      _handleSearchQueryChanged(next);
    });

    // Tablet-specific padding
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.sp,
      tablet: 24.sp,
    );

    return Center(
      key: e2eKey(E2eIds.standingsRoot),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ResponsiveHelper.contentMaxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _StandingsList(controller: _scrollController)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Only this subtree re-runs when the search query changes. The search bar
/// itself is rendered above the tab switcher in TournamentDetailScreen.
class _StandingsList extends ConsumerWidget {
  const _StandingsList({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(playerTourScreenProvider)
        .when(
          // Keep the last-rendered list on screen while the provider
          // re-fires (live rounds tick games in steadily) — prevents a
          // flash-of-skeleton and the rank flicker that showed Mamedyarov as
          // #1 for one frame between #37 emissions.
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          data: (allRanked) {
            final query = ref.watch(standingsSearchQueryProvider);
            final data = filterStandingsByQuery(allRanked, query);
            final isSearching = query.trim().isNotEmpty;
            final favIds = ref
                .watch(favoritePlayersNotifierProvider)
                .maybeWhen(
                  data:
                      (favData) => favData.players.map((e) => e.fideId).toSet(),
                  orElse: () => <int?>{},
                  skipLoadingOnRefresh: true,
                  skipLoadingOnReload: true,
                );
            // `playerTourScreenProvider.build` synchronously returns `[]`
            // while `tourDetailScreenProvider` is still loading OR has only
            // emitted a transient empty `aboutTourModel.id` (e.g. on a
            // deep-linked cold-start into the Standings tab), which would
            // otherwise paint "No data available" for the few hundred ms
            // before the tour detail resolves. Treat that window as still
            // loading and render the skeleton instead.
            final tourDetailAsync = ref.watch(tourDetailScreenProvider);
            final tourDetailReady =
                tourDetailAsync.valueOrNull?.aboutTourModel.id.isNotEmpty ==
                true;
            final standingsHaventResolvedYet =
                data.isEmpty &&
                !isSearching &&
                !tourDetailAsync.hasError &&
                !tourDetailReady;
            if (standingsHaventResolvedYet) {
              return const _StandingScreenLoading();
            }
            return ListView.builder(
              key: const PageStorageKey<String>('standings_list'),
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
                              ? "No players found matching your search"
                              : "No data available",
                    ),
                  );
                }

                final player = data[index];
                final isFav = favIds.contains(player.fideId);
                return FigmaPlayerCard(
                  key: ValueKey(
                    'standing_${player.fideId ?? player.gamebasePlayerId ?? player.name}',
                  ),
                  player: player,
                  rank: player.overallRank,
                  isFavorite: isFav,
                  showFavoriteButton: false,
                  onTap: () {
                    ref.read(selectedPlayerProvider.notifier).state = player;
                    // Clear games context - tournament games come
                    // from gamesTourScreenProvider.
                    ref.read(scoreCardGamesContextProvider.notifier).state =
                        null;
                    ref
                        .read(scoreCardPlayerProfileDataSourceProvider.notifier)
                        .state = PlayerProfileDataSource.supabase;
                    ref.read(chessboardViewFromProviderNew.notifier).state =
                        ChessboardView.tour;
                    Navigator.of(context).pushNamed('/scorecard_screen');
                  },
                );
              },
            );
          },
          error: (e, _) => const _StandingScreenLoading(),
          loading: () => const _StandingScreenLoading(),
        );
  }
}

class _StandingScreenLoading extends StatelessWidget {
  const _StandingScreenLoading();

  @override
  Widget build(BuildContext context) {
    final List<PlayerStandingModel> data = [
      PlayerStandingModel(
        countryCode: 'ARM',
        title: 'GM',
        name: 'Aronian, Levon',
        score: 2712,
        scoreChange: -12,
        matchScore: '5.0/9',
      ),
      PlayerStandingModel(
        countryCode: 'AZE',
        title: 'GM',
        name: 'Mamedyarov, Shakhriyar',
        score: 2704,
        scoreChange: 6,
        matchScore: '5.0/9',
      ),
      PlayerStandingModel(
        countryCode: 'USA',
        title: 'GM',
        name: 'Nakamura, Hikaru',
        score: 2698,
        scoreChange: -5,
        matchScore: '4.5/9',
      ),
      PlayerStandingModel(
        countryCode: 'ARM',
        title: 'GM',
        name: 'Nakamura, Hikaru',
        score: 2698,
        scoreChange: -5,
        matchScore: '4.5/9',
      ),
      PlayerStandingModel(
        countryCode: 'ARM',
        title: 'GM',
        name: 'Nakamura, Hikaru',
        score: 2698,
        scoreChange: -5,
        matchScore: '4.5/9',
      ),
      PlayerStandingModel(
        countryCode: 'ARM',
        title: 'GM',
        name: 'Nakamura, Hikaru',
        score: 2698,
        scoreChange: -5,
        matchScore: '4.5/9',
      ),
    ];

    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16.sp,
      ),
      itemCount: data.length,
      itemBuilder: (context, index) {
        final player = data[index];
        return SkeletonWidget(
          child: FigmaPlayerCard(
            player: player,
            rank: index + 1,
            showFavoriteButton: false,
            onTap: () {},
          ),
        );
      },
    );
  }
}
