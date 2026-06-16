import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/group_event_games_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/group_event_match_card_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/match_expansion_provider.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';

class GroupEventMatchCard extends ConsumerWidget {
  final String roundTitle;
  final List<MatchWithComparison> games;
  final GamesScreenModel gamesData;
  final GamesListViewMode gamesListViewMode;
  final void Function(int)? onReturnFromChessboard;

  const GroupEventMatchCard({
    super.key,
    required this.roundTitle,
    required this.games,
    required this.gamesData,
    required this.gamesListViewMode,
    this.onReturnFromChessboard,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team1Name = roundTitle.split(' vs ').first;
    final country1 = ref
        .read(locationServiceProvider)
        .getValidCountryCodeFromName(team1Name);
    final team2Name = roundTitle.split(' vs ').last;
    final country2 = ref
        .read(locationServiceProvider)
        .getValidCountryCodeFromName(team2Name);

    final matchScore = ref
        .read(groupEventMatchCardProvider)
        .getMatchScore(matchList: games, team: team1Name);
    final team1ScoreStr =
        matchScore.first % 1 == 0
            ? matchScore.first.toStringAsFixed(0)
            : matchScore.first.toStringAsFixed(1);
    final team2ScoreStr =
        matchScore.last % 1 == 0
            ? matchScore.last.toStringAsFixed(0)
            : matchScore.last.toStringAsFixed(1);

    // Use match key from roundTitle (Team1 vs Team2)
    final matchKey = roundTitle;
    final isExpanded = ref.watch(matchExpansionStateProvider(matchKey));

    final radius = Radius.circular(12.br);
    final cardBorderRadius = BorderRadius.circular(12.br);
    final headerBorderRadius =
        isExpanded
            ? BorderRadius.only(topLeft: radius, topRight: radius)
            : cardBorderRadius;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: cardBorderRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () {
              ref.read(matchExpansionProvider.notifier).toggleMatch(matchKey);
            },
            child: Container(
              height: 60.h,
              padding: EdgeInsets.only(left: 12.sp, right: 12.sp),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: headerBorderRadius,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (country1.isNotEmpty) ...[
                          CountryFlag.fromCountryCode(
                            country1,
                            theme: ImageTheme(height: 12.h, width: 16.w),
                          ),
                          SizedBox(width: 4.w),
                        ],
                        Expanded(
                          child: Text(
                            team1Name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.textXsMedium.copyWith(
                              color: context.colors.textPrimary,
                            ),
                            textAlign: TextAlign.left,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(
                    width: 36.w,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        team1ScoreStr,
                        style: AppTypography.textXsMedium.copyWith(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(
                    width: 32.w,
                    child: Center(
                      child: Text(
                        'VS',
                        textAlign: TextAlign.center,
                        style: AppTypography.textXsMedium.copyWith(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(
                    width: 36.w,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        team2ScoreStr,
                        style: AppTypography.textXsMedium.copyWith(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            team2Name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.textXsMedium.copyWith(
                              color: context.colors.textPrimary,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        if (country2.isNotEmpty) ...[
                          SizedBox(width: 4.w),
                          CountryFlag.fromCountryCode(
                            country2,
                            theme: ImageTheme(height: 12.h, width: 16.w),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Expand/collapse icon
                  SizedBox(width: 8.w),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: context.colors.textPrimary.withValues(alpha: 0.5),
                    size: 20.sp,
                  ),
                ],
              ),
            ),
          ),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child:
                isExpanded
                    ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: 10.h,
                          color: context.colors.background,
                        ),
                        _buildGamesList(context, ref),
                      ],
                    )
                    : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildGamesList(BuildContext context, WidgetRef ref) {
    switch (gamesListViewMode) {
      case GamesListViewMode.gamesCard:
        return GroupEventGamesCard(
          games: games,
          gamesData: gamesData,
          onReturnFromChessboard: onReturnFromChessboard,
        );
      case GamesListViewMode.chessBoardGrid:
        return _buildChessBoardGridView(context, ref);
      case GamesListViewMode.chessBoard:
        return _buildChessBoardView(context, ref);
    }
  }

  Widget _buildChessBoardGridView(BuildContext context, WidgetRef ref) {
    final fullGamesList = gamesData.gamesTourModels;
    final gameIndexMap = {
      for (int i = 0; i < fullGamesList.length; i++) fullGamesList[i].gameId: i,
    };
    final liveBatchKeyByGameId = _groupEventLiveBatchKeys(fullGamesList);

    return ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: (games.length / 2).ceil(), // Each row contains up to 2 games
      itemBuilder: (context, index) {
        final matchWithComparison = games[index * 2];
        final game2 =
            (index * 2 + 1) < games.length ? games[index * 2 + 1] : null;

        return Padding(
          padding: EdgeInsets.only(bottom: 12.sp),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: _buildGridChessBoard(
                  context,
                  ref,
                  matchWithComparison,
                  gameIndexMap[matchWithComparison.game.gameId] ?? -1,
                  liveBatchKeyByGameId,
                ),
              ),
              if (game2 != null)
                Expanded(
                  child: _buildGridChessBoard(
                    context,
                    ref,
                    game2,
                    gameIndexMap[game2.game.gameId] ?? -1,
                    liveBatchKeyByGameId,
                  ),
                )
              else
                // Keep the lone card at half-row width; without this the
                // single Expanded stretches it across the whole row.
                const Expanded(child: SizedBox()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChessBoardView(BuildContext context, WidgetRef ref) {
    // Use the games list from widget data to maintain correct order for group events
    final fullGamesList = gamesData.gamesTourModels;
    final gameIndexMap = {
      for (int i = 0; i < fullGamesList.length; i++) fullGamesList[i].gameId: i,
    };
    // Share ONE batched realtime channel per chunk across all match cards in
    // this event instead of one channel per card (per-card channels blow
    // Supabase's per-client limit → ChannelRateLimitReached → updates die back
    // to the slow poll). Keys are content-stable, so cards dedupe to the same
    // channel.
    final liveBatchKeyByGameId = _groupEventLiveBatchKeys(fullGamesList);

    return ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: games.length,
      itemBuilder: (context, index) {
        final matchWithComparison = games[index];
        final gameIndex = gameIndexMap[matchWithComparison.game.gameId] ?? -1;

        return Padding(
          padding: EdgeInsets.only(bottom: 12.sp),
          child: GameCardWrapperWidget(
            game: matchWithComparison.game,
            liveBatchKey: liveBatchKeyByGameId[matchWithComparison.game.gameId],
            gamesData: GamesScreenModel(
              gamesTourModels: fullGamesList,
              pinnedGamedIs: gamesData.pinnedGamedIs,
            ),
            gameIndex: gameIndex,
            isChessBoardVisible: true,
            onReturnFromChessboard: onReturnFromChessboard,
          ),
        );
      },
    );
  }

  Widget _buildGridChessBoard(
    BuildContext context,
    WidgetRef ref,
    MatchWithComparison matchWithComparison,
    int gameIndex,
    Map<String, LiveGamesBatchKey> liveBatchKeyByGameId,
  ) {
    // Use the games list from widget data to maintain correct order for group events
    final fullGamesList = gamesData.gamesTourModels;

    return GridGameCardWrapperWidget(
      key: ValueKey('game_${matchWithComparison.game.gameId}'),
      game: matchWithComparison.game,
      liveBatchKey: liveBatchKeyByGameId[matchWithComparison.game.gameId],
      orderedGames: fullGamesList,
      gameIndex: gameIndex,
      onChangedWithLiveGames:
          (updatedGames) => ref
              .read(gameCardWrapperProvider)
              .navigateToChessBoard(
                context: context,
                orderedGames: updatedGames,
                gameIndex: gameIndex,
                onReturnFromChessboard: onReturnFromChessboard,
              ),
      pinnedIds: gamesData.pinnedGamedIs,
      onPinToggle:
          (_) async => await ref
              .read(gamesTourScreenProvider.notifier)
              .togglePinGame(
                matchWithComparison.game.gameId,
                sourceTourId: matchWithComparison.game.tourId,
              ),
    );
  }

  /// gameId → shared chunked [LiveGamesBatchKey] over the whole event game set.
  /// Content-stable (same scope + sorted ids → equal key), so every match card
  /// in the event resolves to the same batched realtime channels instead of
  /// opening one channel per card.
  static Map<String, LiveGamesBatchKey> _groupEventLiveBatchKeys(
    List<GamesTourModel> games,
  ) {
    const chunkSize = 25;
    final result = <String, LiveGamesBatchKey>{};
    if (games.isEmpty) return result;
    final chunkCount = (games.length / chunkSize).ceil();
    for (var chunk = 0; chunk < chunkCount; chunk++) {
      final start = chunk * chunkSize;
      final end = math.min(start + chunkSize, games.length);
      final chunkGames = games.sublist(start, end);
      final key = LiveGamesBatchKey(
        scopeId: 'group_event_match:$chunk',
        gameIds: chunkGames.map((game) => game.gameId),
      );
      for (final game in chunkGames) {
        result[game.gameId] = key;
      }
    }
    return result;
  }
}
