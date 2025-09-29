import 'package:chessever2/screens/chessboard/chessboard_with_analysis_screen/chess_board_with_analysis_screen.dart';
import 'package:chessever2/screens/chessboard/chessboard_with_analysis_screen/chess_game.dart';
import 'package:chessever2/screens/chessboard/chessboard_with_analysis_screen/chess_game_navigator.dart';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';

class ChessMoveDisplay extends StatelessWidget {
  final String currentFen;
  final ChessMove move;
  final ChessMovePointer movePointer;
  final void Function(ChessMovePointer)? onClick;

  const ChessMoveDisplay({
    super.key,
    required this.move,
    required this.currentFen,
    this.onClick,
    this.movePointer = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (move.variations != null && move.variations!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMove(),
          ...move.variations!.mapIndexed(
            (index, line) => Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.sp),
              child: ChessLineDisplay(
                line: line,
                currentFen: currentFen,
                movePointer: [...movePointer, index],
                onClick: onClick,
              ),
            ),
          )
        ],
      );
    }

    return _buildMove();
  }

  _buildMove() {
    final isWhiteMove = move.turn == ChessColor.black;
    final isSelected = currentFen == move.fen;

    return InkWell(
      onTap: () {
        if (onClick != null) {
          onClick!(movePointer);
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 6.sp,
          vertical: 2.sp,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? kWhiteColor70.withValues(alpha: .4)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4.sp),
          border: Border.all(
            color: isSelected ? kWhiteColor : Colors.transparent,
            width: 0.5,
          ),
        ),
        child: Text(
          isWhiteMove ? '${move.num}. ${move.san}' : move.san,
          style: AppTypography.textXsMedium.copyWith(
            color: kWhiteColor70,
          ),
        ),
      ),
    );
  }
}
