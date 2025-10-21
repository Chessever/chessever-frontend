import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/chess_progress_bar.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GroupEventGamesCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: games.length,
      itemBuilder: (context, index) {
        final game = games[index];

        return Container(
          padding: EdgeInsets.symmetric(vertical: 8.sp),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: kDarkGreyColor,
                width: index == (games.length - 1) ? 0 : 0.5.h,
              ),
            ),
          ),
          child: _GameRow(
            gamesData: gamesData,
            game: game,
            onReturnFromChessboard: onReturnFromChessboard,
          ),
        );
      },
    );
  }
}

class _GameRow extends ConsumerWidget {
  const _GameRow({
    required this.gamesData,
    required this.game,
    required this.onReturnFromChessboard,
    super.key,
  });

  final GamesScreenModel gamesData;
  final MatchWithComparison game;
  final void Function(int)? onReturnFromChessboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameIndex = gamesData.gamesTourModels.indexOf(game.game);

    // Combine title + name + rating
    String formatPlayer(PlayerCard player) {
      final title = player.title.isNotEmpty == true ? '${player.title} ' : '';
      final rating = player.rating > 0 ? ' (${player.rating})' : '';
      return '$title${player.name}$rating';
    }

    final player1 =
        game.comparison == MatchComparison.sameOrder
            ? game.game.whitePlayer
            : game.game.blackPlayer;

    final player2 =
        game.comparison == MatchComparison.sameOrder
            ? game.game.blackPlayer
            : game.game.whitePlayer;

    return InkWell(
      onTap:
          () => ref
              .read(gameCardWrapperProvider)
              .navigateToChessBoard(
                context: context,
                orderedGames: gamesData.gamesTourModels,
                gameIndex: gameIndex,
                onReturnFromChessboard: onReturnFromChessboard,
              ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
        child: Row(
          children: [
            // Left player
            Expanded(
              flex: 4,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  formatPlayer(player1),
                  style: AppTypography.textXsMedium.copyWith(
                    color: kWhiteColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            // Middle progress bar
            Expanded(
              flex: 2,
              child: Center(
                child:
                    game.game.gameStatus == GameStatus.ongoing
                        ? game.comparison == MatchComparison.sameOrder
                            ? ChessProgressBar(gamesTourModel: game.game)
                            : ChessProgressBar.reversedMode(
                              gamesTourModel: game.game,
                            )
                        : StatusText(
                          status: _displayTextSupporter(game),
                          color: kWhiteColor,
                        ),
              ),
            ),

            // Right player
            Expanded(
              flex: 4,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  formatPlayer(player2),
                  style: AppTypography.textXsMedium.copyWith(
                    color: kWhiteColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _displayTextSupporter(MatchWithComparison game) {
  if (game.comparison == MatchComparison.sameOrder) {
    switch (game.game.gameStatus) {
      case GameStatus.whiteWins:
        return '1-0';
      case GameStatus.blackWins:
        return '0-1';
      case GameStatus.draw:
        return '½-½';
      case GameStatus.ongoing:
        return '*';
      case GameStatus.unknown:
        return '';
    }
  } else {
    switch (game.game.gameStatus) {
      case GameStatus.whiteWins:
        return '0-1';
      case GameStatus.blackWins:
        return '1-0';
      case GameStatus.draw:
        return '½-½';
      case GameStatus.ongoing:
        return '*';
      case GameStatus.unknown:
        return '';
    }
  }
}
