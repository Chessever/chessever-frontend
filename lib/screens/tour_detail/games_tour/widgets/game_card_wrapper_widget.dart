import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_widget_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../chessboard/chess_board_screen_new.dart';

class GameCardWrapperWidget extends ConsumerWidget {
  final GamesTourModel game;
  final GamesScreenModel gamesData;
  final int gameIndex;
  final bool isChessBoardVisible;

  const GameCardWrapperWidget({
    super.key,
    required this.game,
    required this.gamesData,
    required this.gameIndex,
    required this.isChessBoardVisible,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keyValue =
        'game_${game.gameId}_${gameIndex}_${isChessBoardVisible ? 'chess' : 'card'}';

    return isChessBoardVisible
        ? ChessBoardFromFENNew(
          key: ValueKey(keyValue),
          gamesTourModel: game,
          onChanged: () => _navigateToChessBoard(context, ref),
        )
        : GameCard(
          key: ValueKey(keyValue),
          gamesTourModel: game,
          pinnedIds: gamesData.pinnedGamedIs,
          onPinToggle: (_) => _handlePinToggle(ref),
          onTap: () => _navigateToChessBoard(context, ref),
        );
  }

  void _navigateToChessBoard(BuildContext context, WidgetRef ref) async {
    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;

    final lastViewedIndex = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder:
            (_) => ChessBoardScreenNew(
              games: gamesData.gamesTourModels,
              currentIndex: gameIndex,
            ),
      ),
    );

    if (lastViewedIndex != null && context.mounted) {
      ref
          .read(gamesTourScreenProvider.notifier)
          .setLastViewedGameIndex(lastViewedIndex);
    } else {
      ref.read(scrollToGameIndexProvider.notifier).state = null;
    }
  }

  Future<void> _handlePinToggle(WidgetRef ref) async {
    await ref.read(gamesTourScreenProvider.notifier).togglePinGame(game.gameId);
  }
}
