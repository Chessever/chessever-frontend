import 'package:flutter/material.dart';

import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';

import 'chess_game.dart';
import 'chess_game_navigator.dart';
import 'move_impact_analyzer.dart';

class ChessMoveDisplay extends StatelessWidget {
  const ChessMoveDisplay({
    super.key,
    required this.move,
    required this.currentFen,
    this.movePointer = const [],
    this.onClick,
    this.moveImpact,
  });

  final ChessMove move;
  final String currentFen;
  final ChessMovePointer movePointer;
  final void Function(ChessMovePointer)? onClick;
  final MoveImpactAnalysis? moveImpact;

  @override
  Widget build(BuildContext context) {
    final isWhiteMove = move.turn == ChessColor.black;
    final isSelected = currentFen == move.fen;

    // Determine text color based on move impact
    // Priority: impact color > capture color > selected/unselected color
    // Impact colors are preserved even when selected
    Color textColor = kWhiteColor70;
    if (moveImpact != null && moveImpact!.impact != MoveImpactType.normal) {
      // Use impact color for non-normal moves, regardless of selection
      textColor = moveImpact!.impact.color;
    } else if (move.san.contains('x')) {
      // Bordoish/reddish color for captures (normal impact moves)
      textColor = const Color(0xFFB33A3A);
    } else if (isSelected) {
      // For normal, non-capture moves, use white when selected
      textColor = kWhiteColor;
    }

    final impactSymbol = moveImpact?.impact.symbol ?? '';
    final moveText = isWhiteMove ? '${move.num}. ${move.san}' : move.san;

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
        child: RichText(
          text: TextSpan(
            text: moveText,
            style: AppTypography.textXsMedium.copyWith(
              color: textColor,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
            children: [
              if (impactSymbol.isNotEmpty)
                TextSpan(
                  text: impactSymbol,
                  style: AppTypography.textXsMedium.copyWith(
                    color: moveImpact!.impact.color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
