import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_fen_model.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_second_row_detail_widget.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:squares/squares.dart';
import 'package:square_bishop/square_bishop.dart';
import 'package:square_bishop/square_bishop.dart' as square_bishop;
import 'package:bishop/bishop.dart' as bishop;

import '../../../providers/board_settings_provider.dart';

class ChessBoardFromFEN extends ConsumerStatefulWidget {
  const ChessBoardFromFEN({super.key, required this.games});

  final List<GamesTourModel> games;

  @override
  ConsumerState<ChessBoardFromFEN> createState() => _ChessBoardFromFENState();
}

class _ChessBoardFromFENState extends ConsumerState<ChessBoardFromFEN> {
  late BoardState boardState;
  final int currentIndex = 0;
  final ChessBoardScreenNotifier boardNotifier = ChessBoardScreenNotifier(
    games: [],
    index: 0,
  );
  final List<double> evaluations = [0.4];
  @override
  void initState() {
    final game = bishop.Game.fromPgn(
      widget.games.isNotEmpty ? widget.games[0].fen ?? "" : "",
    );

    final squaresState = game.squaresState(Squares.white);

    boardState = squaresState.board;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final boardSettingsValue = ref.watch(boardSettingsProvider);
    final boardTheme = ref
        .read(boardSettingsRepository)
        .getBoardColorEnum(boardSettingsValue.boardColor);
    final sideBarWidth = 20.w;
    final horizontalPadding = 48.sp * 2;
    final screenWidth = MediaQuery.of(context).size.width;
    final boardSize = screenWidth - sideBarWidth - horizontalPadding;

    // final isFlipped = state.isBoardFlipped[index];
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 23.sp, vertical: 8.sp),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => ChessBoardScreen(games: widget.games, currentIndex: 0),
            ),
          );
          // if (widget.games[0].gameStatus.displayText != '*') {
          //   Navigator.push(
          //     context,
          //     MaterialPageRoute(
          //       builder:
          //           (_) =>
          //               ChessBoardScreen(games: widget.games, currentIndex: 0),
          //     ),
          //   );
          // } else {
          //   showDialog(
          //     context: context,
          //     builder:
          //         (_) => AlertDialog(
          //           title: const Text("No PGN Data"),
          //           content: const Text("This game has no PGN data available."),
          //           actions: [
          //             TextButton(
          //               onPressed: () => Navigator.pop(context),
          //               child: const Text("OK"),
          //             ),
          //           ],
          //         ),
          //   );
          // }
        },
        child: Column(
          children: [
            PlayerFirstRowDetailWidget(
              name: widget.games[0].whitePlayer.displayName,
              firstGmRank: widget.games[0].whitePlayer.displayTitle,
              countryCode: widget.games[0].whitePlayer.countryCode,
              // flagAsset: 'assets/usa_flag.png',
              time: widget.games[0].whiteTimeDisplay,
            ),
            SizedBox(height: 4.h),
            Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.5),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  EvaluationBar(
                    width: sideBarWidth,
                    height: boardSize,
                    index: currentIndex,
                    state: ChessBoardState(
                      evaluations: evaluations,
                      games: [],
                      allMoves: [],
                      sanMoves: [],
                      currentMoveIndex: [],
                      isPlaying: [],
                      isBoardFlipped: [],
                      isConnected: false,
                    ),
                    notifier: boardNotifier,
                    isFlipped: false,
                  ),

                  SizedBox(
                    height: boardSize,
                    child: Board(
                      theme: BoardTheme.blueGrey,
                      size: BoardSize.standard,
                      pieceSet: PieceSet.fromImageAssets(
                        folder: 'assets/pngs/pieces/',
                        symbols: [
                          'P',
                          'R',
                          'N',
                          'B',
                          'Q',
                          'K',
                          'P',
                          'R',
                          'N',
                          'B',
                          'Q',
                          'K',
                        ],
                        format: 'png',
                      ),
                      playState: PlayState.observing,
                      state: boardState,
                    ),
                  ),
                ],
              ),
            ),

            // Container(
            //   decoration: BoxDecoration(
            //     boxShadow: [
            //       BoxShadow(
            //         color: Colors.grey.withOpacity(0.5),
            //         blurRadius: 8,
            //         offset: const Offset(0, 4),
            //       ),
            //     ],
            //   ),
            //   child: Row(
            //     children: [
            //       // Main Board area
            //       Column(children: [

            //       ]),
            //       Expanded(
            //         child: Container(
            //           child: AbsorbPointer(
            //             child: Board(
            //               theme: BoardTheme.blueGrey,
            //               size: BoardSize.standard,
            //               pieceSet: PieceSet.fromImageAssets(
            //                 folder: 'assets/pngs/pieces/',
            //                 symbols: [
            //                   'P',
            //                   'R',
            //                   'N',
            //                   'B',
            //                   'Q',
            //                   'K',
            //                   'P',
            //                   'R',
            //                   'N',
            //                   'B',
            //                   'Q',
            //                   'K',
            //                 ],
            //                 format: 'png',
            //               ),
            //               playState: PlayState.observing,
            //               state: boardState,
            //             ),
            //           ),
            //         ),
            //       ),
            //     ],
            //   ),
            // ),
            SizedBox(height: 4.h),
            PlayerSecondRowDetailWidget(
              name: widget.games[0].blackPlayer.displayName,
              countryCode: widget.games[0].blackPlayer.displayTitle,
              time: widget.games[0].blackTimeDisplay,
              secondGmRank: widget.games[0].blackPlayer.displayTitle,
            ),
          ],
        ),
      ),
    );
  }
}
