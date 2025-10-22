import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
    // Get the full games list from the provider to ensure we have all games
    final fullGamesData = ref.watch(gamesTourScreenProvider).valueOrNull;
    final fullGamesList = fullGamesData?.gamesTourModels ?? widget.gamesData.gamesTourModels;

    return ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.games.length,
      itemBuilder: (context, index) {
        final game = widget.games[index];

        final gameIndex = fullGamesList.indexOf(game.game);
        return GameCard(
          matchComparison: game,
          onPinToggle: (game) async {
            await ref
                .read(gamesTourScreenProvider.notifier)
                .togglePinGame(game.gameId);
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
