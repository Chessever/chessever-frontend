import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/responsive_helper.dart';

class GroupEventGamesCard extends ConsumerStatefulWidget {
  const GroupEventGamesCard({
    required this.games,
    required this.gamesData,
    required this.onReturnFromChessboard,
    super.key,
  });

  final List<MatchWithComparison> games;
  final GamesScreenModel gamesData;
  final void Function(int)? onReturnFromChessboard;

  @override
  ConsumerState<GroupEventGamesCard> createState() =>
      _GroupEventGamesCardState();
}

class _GroupEventGamesCardState extends ConsumerState<GroupEventGamesCard> {
  @override
  Widget build(BuildContext buildCxt) {
    // Use the games list from widget data to maintain correct order for group events
    final fullGamesList = widget.gamesData.gamesTourModels;

    // Audit optimization: Precompute indices to avoid O(N^2) indexWhere lookups
    final gameIndexMap = {
      for (int i = 0; i < fullGamesList.length; i++) fullGamesList[i].gameId: i,
    };

    return ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.games.length,
      separatorBuilder: (context, _) => SizedBox(height: 12.sp),
      itemBuilder: (context, index) {
        final match = widget.games[index];
        final liveGame = watchLiveGame(ref, match.game);
        final liveMatch = MatchWithComparison(
          game: liveGame,
          comparison: match.comparison,
        );
        final gameIndex = gameIndexMap[liveGame.gameId] ?? -1;
        final updatedGames = List<GamesTourModel>.from(fullGamesList);
        if (gameIndex >= 0 && gameIndex < updatedGames.length) {
          updatedGames[gameIndex] = liveGame;
        }

        return GameCard(
          // Use actual comparison to maintain team positions
          matchComparison: liveMatch,
          onPinToggle: (game) async {
            await ref
                .read(gamesTourScreenProvider.notifier)
                .togglePinGame(game.gameId, sourceTourId: game.tourId);
          },
          pinnedIds: widget.gamesData.pinnedGamedIs,
          onTap: () {
            ref
                .read(gameCardWrapperProvider)
                .navigateToChessBoard(
                  context: context,
                  orderedGames: updatedGames,
                  gameIndex: gameIndex,
                  onReturnFromChessboard: widget.onReturnFromChessboard,
                );
          },
        );
      },
    );
  }
}
