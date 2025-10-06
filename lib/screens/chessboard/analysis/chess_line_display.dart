import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';

import 'chess_game.dart';
import 'chess_game_navigator.dart';
import 'chess_move_display.dart';
import 'move_impact_analyzer.dart';

class ChessLineDisplay extends StatelessWidget {
  const ChessLineDisplay({
    super.key,
    required this.line,
    required this.currentFen,
    this.movePointer = const [],
    this.onClick,
    this.allMovesImpact,
  });

  final List<ChessMove> line;
  final String currentFen;
  final ChessMovePointer movePointer;
  final void Function(ChessMovePointer)? onClick;
  final Map<int, MoveImpactAnalysis>? allMovesImpact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4.0,
      runSpacing: 4.0,
      children:
          line.mapIndexed((moveIndex, move) {
            final pointer = [...movePointer, moveIndex];

            final moveWidget = ChessMoveDisplay(
              move: move,
              currentFen: currentFen,
              movePointer: pointer,
              onClick: onClick,
              moveImpact: allMovesImpact?[moveIndex],
            );

            if (move.variations == null || move.variations!.isEmpty) {
              return moveWidget;
            }

            return Wrap(
              spacing: 4.0,
              children: [
                moveWidget,
                ...move.variations!.mapIndexed((variationIndex, variationLine) {
                  final variationPointer = [...pointer, variationIndex];
                  return Text.rich(
                    TextSpan(
                      text: '(',
                      style: AppTypography.textXsMedium.copyWith(
                        color: kWhiteColor70,
                      ),
                      children: [
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4.sp),
                            child: ChessLineDisplay(
                              line: variationLine,
                              currentFen: currentFen,
                              movePointer: variationPointer,
                              onClick: onClick,
                              allMovesImpact: allMovesImpact,
                            ),
                          ),
                        ),
                        const TextSpan(text: ')'),
                      ],
                    ),
                  );
                }),
              ],
            );
          }).toList(),
    );
  }
}
