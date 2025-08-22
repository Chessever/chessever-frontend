import 'package:chessever2/screens/chessboard/chess_board_screen.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_widget.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tournaments/widget/game_card.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
    // Use consistent keys based on game ID to help with position tracking
    final keyValue =
        'game_${game.gameId}_${isChessBoardVisible ? 'chess' : 'card'}';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child:
          isChessBoardVisible
              ? ChessBoardFromFEN(
                key: ValueKey('${keyValue}_board'),
                gamesTourModel: game,
                onChanged: () => _navigateToChessBoard(context, ref),
              )
              : GameCard(
                key: ValueKey('${keyValue}_card'),
                gamesTourModel: game,
                pinnedIds: gamesData.pinnedGamedIs,
                onPinToggle: (_) => _handlePinToggle(ref),
                onTap: () => _navigateToChessBoard(context, ref),
              ),
    );
  }

  void _navigateToChessBoard(BuildContext context, WidgetRef ref) {
    ref.read(chessboardViewFromProvider.notifier).state = ChessboardView.tour;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ChessBoardScreen(
              games: gamesData.gamesTourModels,
              currentIndex: gameIndex,
            ),
      ),
    );
  }

  Future<void> _handlePinToggle(WidgetRef ref) async {
    await ref.read(gamesTourScreenProvider.notifier).togglePinGame(game.gameId);
  }
}
