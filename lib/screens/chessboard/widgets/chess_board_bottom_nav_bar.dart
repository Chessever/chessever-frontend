import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_navbar.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_viewmodel.dart';
import 'package:chessever2/widgets/svg_widget.dart';

class ChessBoardBottomNavBar extends ConsumerWidget {
  final Function() onLeftMove;
  final Function() onRightMove;
  const ChessBoardBottomNavBar({
    super.key,
    required this.onLeftMove,
    required this.onRightMove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chessState = ref.watch(chessViewModelProvider);
    final flipBoard = ref.watch(flipBoardProvider);

    return Container(
      padding: EdgeInsets.symmetric(vertical: 8),
      width: MediaQuery.of(context).size.width,
      decoration: const BoxDecoration(color: Colors.black),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // New Game Button
            ChessBoardBottomNavbar(
              svgPath: SvgAsset.laptop,
              onPressed: () {
                ref.read(chessViewModelProvider.notifier).resetGame();
              },
            ),

            // Simulate/Stop Button
            ChessBoardBottomNavbar(
              svgPath:
                  chessState.simulatingPgn ? SvgAsset.laptop : SvgAsset.refresh,
              onPressed:
                  chessState.simulatingPgn
                      ? () {
                        ref
                            .read(chessViewModelProvider.notifier)
                            .stopSimulation();
                      }
                      : () {
                        ref
                            .read(chessViewModelProvider.notifier)
                            .simulatePgnMoves();
                      },
            ),

            // Previous Move Button
            // ChessBoardBottomNavbar(
            //   svgPath: SvgAsset.left_arrow,
            //   onPressed:
            //       chessState.currentMoveIndex > 0
            //           ? () {
            //             ref
            //                 .read(chessViewModelProvider.notifier)
            //                 .goToPreviousMove();
            //           }
            //           : null,
            // ),
            ChessBoardBottomNavbar(
              svgPath: SvgAsset.left_arrow,
              onPressed: onRightMove,
            ),
            // Next Move Button
            ChessBoardBottomNavbar(
              svgPath: SvgAsset.right_arrow,
              onPressed: onLeftMove,
            ),
            ChessBoardBottomNavbar(svgPath: SvgAsset.chat, onPressed: () {}),
          ],
        ),
      ),
    );
  }
}
