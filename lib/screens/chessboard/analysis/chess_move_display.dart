import 'package:flutter/material.dart';

import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';

import 'chess_game.dart';
import 'chess_game_navigator.dart';

class ChessMoveDisplay extends StatelessWidget {
  const ChessMoveDisplay({
    super.key,
    required this.move,
    required this.currentFen,
    this.movePointer = const [],
    this.onClick,
  });

  final ChessMove move;
  final String currentFen;
  final ChessMovePointer movePointer;
  final void Function(ChessMovePointer)? onClick;

  @override
  Widget build(BuildContext context) {
    final isWhiteMove = move.turn == ChessColor.black;
    final isSelected = currentFen == move.fen;

    return InkWell(
      onTap: () {
        onClick?.call(movePointer);
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
        decoration: BoxDecoration(
          color:
              isSelected
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
          style: AppTypography.textXsMedium.copyWith(color: kWhiteColor70),
        ),
      ),
    );
  }
}
