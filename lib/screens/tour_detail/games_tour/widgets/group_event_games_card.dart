import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
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

    return ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.games.length,
      separatorBuilder: (context, _) => SizedBox(height: 12.sp),
      itemBuilder: (context, index) {
        final game = widget.games[index];

        final gameIndex = fullGamesList.indexWhere(
          (g) => g.gameId == game.game.gameId,
        );
        return GameCard(
          // Use actual comparison to maintain team positions
          matchComparison: game,
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
                  orderedGames: fullGamesList,
                  gameIndex: gameIndex,
                  onReturnFromChessboard: widget.onReturnFromChessboard,
                );
          },
        );
      },
    );
  }
}
