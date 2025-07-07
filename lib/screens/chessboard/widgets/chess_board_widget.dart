import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_second_row_detail_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:squares/squares.dart';
import 'package:square_bishop/square_bishop.dart';
import 'package:square_bishop/square_bishop.dart' as square_bishop;
import 'package:bishop/bishop.dart' as bishop;

class ChessBoardFromFEN extends StatefulWidget {
  const ChessBoardFromFEN({
    super.key,
    required this.fen,
    required this.gmName,
    required this.gmSecondName,
    required this.firstGmCountryCode,
    required this.secondGmCountryCode,
    required this.firstGmTime,
    required this.secondGmTime,
    required this.firstGmRank,
    required this.secongGmRank,
  });

  final String gmName;
  final String gmSecondName;
  final String fen;
  final String firstGmCountryCode;
  final String secondGmCountryCode;
  final String firstGmTime;
  final String secondGmTime;
  final String firstGmRank;
  final String secongGmRank;

  @override
  State<ChessBoardFromFEN> createState() => _ChessBoardFromFENState();
}

class _ChessBoardFromFENState extends State<ChessBoardFromFEN> {
  late BoardState boardState;

  @override
  void initState() {
    super.initState();

    final game = bishop.Game.fromPgn(widget.fen);

    final squaresState = game.squaresState(Squares.white);

    boardState = squaresState.board;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 48.sp, vertical: 8.sp),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            '/chess_screen',
            arguments: {
              'gmName': widget.gmName,
              'gmSecondName': widget.gmSecondName,
              'fen': widget.fen,
              'firstGmCountryCode': widget.firstGmCountryCode,
              'secondGmCountryCode': widget.secondGmCountryCode,
              'firstGmTime': widget.firstGmTime,
              'secondGmTime': widget.secondGmTime,
              'firstGmRank': widget.firstGmRank,
              'secongGmRank': widget.secongGmRank,
            },
          );
        },
        child: Column(
          children: [
            PlayerFirstRowDetailWidget(
              name: widget.gmName,
              firstGmRank: widget.firstGmRank,
              countryCode: widget.firstGmCountryCode,
              // flagAsset: 'assets/usa_flag.png',
              time: widget.firstGmTime,
            ),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: kBlackColor, width: 2.w),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.5),
                    blurRadius: 8.br,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: AbsorbPointer(
                child: Board(
                  size: BoardSize.standard,
                  pieceSet: PieceSet.merida(),
                  playState: PlayState.observing,
                  state: boardState,
                ),
              ),
            ),
            SizedBox(height: 3.h),

            PlayerSecondRowDetailWidget(
              name: widget.gmSecondName,
              countryCode: widget.secondGmCountryCode,
              time: widget.secondGmTime,
              secondGmRank: widget.secongGmRank,
            ),
          ],
        ),
      ),
    );
  }
}
