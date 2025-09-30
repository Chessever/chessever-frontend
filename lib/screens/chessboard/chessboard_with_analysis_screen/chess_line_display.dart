import 'package:chessever2/screens/chessboard/chessboard_with_analysis_screen/chess_game.dart';
import 'package:chessever2/screens/chessboard/chessboard_with_analysis_screen/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/chessboard_with_analysis_screen/chess_move_display.dart';

import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

class ChessLineDisplay extends StatelessWidget {
  final List<ChessMove> line;
  final String currentFen;
  final ChessMovePointer movePointer;
  final void Function(ChessMovePointer)? onClick;

  const ChessLineDisplay({
    super.key,
    required this.line,
    required this.currentFen,
    this.movePointer = const [],
    this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4.0,
      runSpacing: 4.0,
      children: line.mapIndexed((moveIndex, move) {
        final currentMovePointer = [...movePointer, moveIndex];

        final moveWidget = ChessMoveDisplay(
          move: move,
          currentFen: currentFen,
          movePointer: currentMovePointer,
          onClick: onClick,
        );

        if (move.variations != null && move.variations!.isNotEmpty) {
          List<Widget> children = [moveWidget];

          children
              .addAll(move.variations!.mapIndexed((varIndex, variationLine) {
            final variationLinePointer = [...currentMovePointer, varIndex];

            return Text.rich(
              TextSpan(
                text: '(',
                style:
                    AppTypography.textXsMedium.copyWith(color: kWhiteColor70),
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4.sp),
                      child: ChessLineDisplay(
                        line: variationLine,
                        currentFen: currentFen,
                        movePointer: variationLinePointer,
                        onClick: onClick,
                      ),
                    ),
                  ),
                  TextSpan(text: ')'),
                ],
              ),
            );
          }));

          return Wrap(
            spacing: 4.0,
            children: children,
          );
        }

        return moveWidget;
      }).toList(),
    );
  }
}
