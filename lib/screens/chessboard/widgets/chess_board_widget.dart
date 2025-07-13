import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/screens/chessboard/ChessBoardScreen.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_fen_model.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_second_row_detail_widget.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:squares/squares.dart';
import 'package:square_bishop/square_bishop.dart';
import 'package:square_bishop/square_bishop.dart' as square_bishop;
import 'package:bishop/bishop.dart' as bishop;

import '../../../providers/board_settings_provider.dart';

class ChessBoardFromFEN extends ConsumerStatefulWidget {
  const ChessBoardFromFEN({super.key, required this.chessBoardFenModel});

  final ChessBoardFenModel chessBoardFenModel;

  @override
  ConsumerState<ChessBoardFromFEN> createState() => _ChessBoardFromFENState();
}

class _ChessBoardFromFENState extends ConsumerState<ChessBoardFromFEN> {
  late BoardState boardState;

  @override
  void initState() {
    final game = bishop.Game.fromPgn(widget.chessBoardFenModel.fen);

    final squaresState = game.squaresState(Squares.white);

    boardState = squaresState.board;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final boardSettingsValue = ref.watch(boardSettingsProvider);
    final boardColorEnum = ref
        .read(boardSettingsRepository)
        .getBoardColorEnum(boardSettingsValue.boardColor);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 48.sp, vertical: 8.sp),
      child: InkWell(
        onTap: () {
          if (widget.chessBoardFenModel.status != '*') {
            // Navigator.push(
            //   context,
            //   MaterialPageRoute(
            //     builder:
            //         (_) => ChessBoardScreen(
            //           currentIndex: index,
            //           games: [
            //             ChessBoardFenModel.fromGamesTourModel(
            //               data.gamesTourModels[index],
            //             ),
            //           ],
            //         ),
            //   ),
            // );
          } else {
            showDialog(
              context: context,
              builder:
                  (_) => AlertDialog(
                    title: const Text("No PGN Data"),
                    content: const Text("This game has no PGN data available."),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("OK"),
                      ),
                    ],
                  ),
            );
          }
        },
        child: Column(
          children: [
            PlayerFirstRowDetailWidget(
              name: widget.chessBoardFenModel.gmName,
              firstGmRank: widget.chessBoardFenModel.firstGmRank,
              countryCode: widget.chessBoardFenModel.firstGmCountryCode,
              // flagAsset: 'assets/usa_flag.png',
              time: widget.chessBoardFenModel.firstGmTime,
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
                  // Main Board area
                  Expanded(
                    child: Container(
                      color: Colors.transparent,
                      child: AbsorbPointer(
                        child: Board(
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
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 4.h),
            PlayerSecondRowDetailWidget(
              name: widget.chessBoardFenModel.gmSecondName,
              countryCode: widget.chessBoardFenModel.secondGmCountryCode,
              time: widget.chessBoardFenModel.secondGmTime,
              secondGmRank: widget.chessBoardFenModel.secondGmRank,
            ),
          ],
        ),
      ),
    );
  }
}
