import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/group_event/widget/empty_widget.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PlayerTourScreen extends ConsumerWidget {
  const PlayerTourScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              SizedBox(height: 8.h),
              // Header row
              const FigmaStandingsHeader(showScore: true),
              ref
                  .watch(playerTourScreenProvider)
                  .when(
                    data: (data) {
                      return data.isEmpty
                          ? Center(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(height: 64.h),
                                EmptyWidget(title: "No data available"),
                              ],
                            ),
                          )
                          : ref
                              .watch(favoritePlayersNotifierProvider)
                              .when(
                                data: (favData) {
                                  final favIds =
                                      favData.players
                                          .map((e) => e.fideId)
                                          .toSet();

                                  // Keep players in their original ranking order (by score)
                                  // Do NOT reorder based on favorite status

                                  return Expanded(
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      padding: EdgeInsets.only(
                                        bottom:
                                            MediaQuery.of(
                                              context,
                                            ).viewInsets.bottom +
                                            16.sp,
                                      ),
                                      itemCount: data.length,
                                      itemBuilder: (context, index) {
                                        final player = data[index];
                                        final isFav = favIds.contains(
                                          player.fideId,
                                        );
                                        return FigmaPlayerCard(
                                          player: player,
                                          rank: index + 1,
                                          isFavorite: isFav,
                                          showFavoriteButton: false,
                                          onTap: () {
                                            ref
                                                .read(
                                                  selectedPlayerProvider
                                                      .notifier,
                                                )
                                                .state = player;
                                            // Clear games context - tournament games come from gamesTourScreenProvider
                                            ref
                                                .read(
                                                  scoreCardGamesContextProvider
                                                      .notifier,
                                                )
                                                .state = null;
                                            ref
                                                .read(
                                                  scoreCardPlayerProfileDataSourceProvider
                                                      .notifier,
                                                )
                                                .state = PlayerProfileDataSource
                                                    .supabase;
                                            Navigator.of(
                                              context,
                                            ).pushNamed('/scorecard_screen');
                                          },
                                        );
                                      },
                                    ),
                                  );
                                },
                                loading: () {
                                  return _StandingScreenLoading();
                                },
                                error: (error, stackTrace) {
                                  return _StandingScreenLoading();
                                },
                                skipLoadingOnRefresh: true,
                                skipLoadingOnReload: true,
                              );
                    },
                    error: (e, _) {
                      return _StandingScreenLoading();
                    },
                    loading: () {
                      return _StandingScreenLoading();
                    },
                  ),
            ],
          ),
        ),
      ),
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

    return Expanded(
      child: ListView.builder(
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
      ),
    );
  }
}
