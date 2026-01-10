import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/group_event/widget/empty_widget.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/standing_score_card.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';

class PlayerTourScreen extends ConsumerWidget {
  const PlayerTourScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Tablet-specific padding
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 24.sp,
    );

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ResponsiveHelper.contentMaxWidth,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: 16.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.sp),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left padding before rank
                SizedBox(width: 8.w),
                // Rank column header - matches card's 28.w minus extra left padding
                SizedBox(
                  width: 20.w,
                  child: Text(
                    '#',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
                // Player column - starts where flag starts in the card
                Expanded(
                  child: Text(
                    'Player',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Elo column - LEFT aligned, matches card's 80.w
                SizedBox(
                  width: 80.w,
                  child: Text(
                    'Elo',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),

                // Score column - LEFT aligned, matches card's 52.w
                SizedBox(
                  width: 52.w,
                  child: Text(
                    'Score',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),

                // Favorite icon column - matches card's 36.w
                SizedBox(width: 36.w),
              ],
            ),
          ),
          SizedBox(height: 4.h),
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
                                  favData.players.map((e) => e.fideId).toSet();

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
                                    final isFav = favIds.contains(player.fideId);
                                    return StandingScoreCard(
                                      countryCode: player.countryCode,
                                      title: player.title,
                                      name: player.name,
                                      score: player.score,
                                      scoreChange: player.scoreChange,
                                      matchScore: player.matchScore,
                                      index: index,
                                      rank: index + 1,
                                      isFirst: index == 0,
                                      isLast: index == data.length - 1,
                                      onTap: () {
                                        ref
                                            .read(
                                              selectedPlayerProvider.notifier,
                                            )
                                            .state = player;
                                        // Clear games context - tournament games come from gamesTourScreenProvider
                                        ref
                                            .read(
                                              scoreCardGamesContextProvider.notifier,
                                            )
                                            .state = null;
                                        Navigator.of(
                                          context,
                                        ).pushNamed('/scorecard_screen');
                                      },
                                      onToggleFavorite: () async {
                                        final allowed = await requireFullAuthGuard(context);
                                        if (!allowed) return;

                                        ref
                                            .read(
                                              favoritePlayersNotifierProvider
                                                  .notifier,
                                            )
                                            .toggleFavorite(player);
                                      },
                                      isFav: isFav,
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
        matchScore: '5.0 / 9',
      ),
      PlayerStandingModel(
        countryCode: 'AZE',
        title: 'GM',
        name: 'Mamedyarov, Shakhriyar',
        score: 2704,
        scoreChange: 6,
        matchScore: '5.0 / 9',
      ),
      PlayerStandingModel(
        countryCode: 'USA',
        title: 'GM',
        name: 'Nakamura, Hikaru',
        score: 2698,
        scoreChange: -5,
        matchScore: '4.5 / 9',
      ),
      PlayerStandingModel(
        countryCode: 'ARM',
        title: 'GM',
        name: 'Nakamura, Hikaru',
        score: 2698,
        scoreChange: -5,
        matchScore: '4.5 / 9',
      ),
      PlayerStandingModel(
        countryCode: 'ARM',
        title: 'GM',
        name: 'Nakamura, Hikaru',
        score: 2698,
        scoreChange: -5,
        matchScore: '4.5 / 9',
      ),
      PlayerStandingModel(
        countryCode: 'ARM',
        title: 'GM',
        name: 'Nakamura, Hikaru',
        score: 2698,
        scoreChange: -5,
        matchScore: '4.5 / 9',
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
          child: Padding(
            padding: EdgeInsets.only(
              bottom: 16.sp,
              top: index == 0 ? 16.sp : 0,
            ),
            child: StandingScoreCard(
              countryCode: player.countryCode,
              title: player.title,
              name: player.name,
              score: player.score,
              scoreChange: player.scoreChange,
              matchScore: player.matchScore,
              index: index,
              isFirst: index == 0,
              isLast: index == data.length - 1,
              onTap: () {},
              onToggleFavorite: () {},
              isFav: index.isEven,
            ),
          ),
        );
      },
    );
  }
}
