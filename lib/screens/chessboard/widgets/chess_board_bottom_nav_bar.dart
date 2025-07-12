import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_navbar.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChessBoardBottomNavBar extends ConsumerWidget {
  final VoidCallback onLeftMove;
  final VoidCallback onRightMove;
  final VoidCallback onPlayPause;
  final VoidCallback onReset;
  final bool isPlaying;
  final int currentMove;
  final int totalMoves;

  const ChessBoardBottomNavBar({
    super.key,
    required this.onLeftMove,
    required this.onRightMove,
    required this.onPlayPause,
    required this.onReset,
    required this.isPlaying,
    required this.currentMove,
    required this.totalMoves,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8),
      width: MediaQuery.of(context).size.width,
      decoration: const BoxDecoration(color: Colors.black),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Reset Game Button
            ChessBoardBottomNavbar(
              svgPath: SvgAsset.laptop,
              onPressed: () {
                print('Reset button pressed');
                onReset();
              },
            ),

            // Play/Pause Button
            ChessBoardBottomNavbar(
              svgPath: isPlaying ? SvgAsset.laptop : SvgAsset.refresh, // Use appropriate pause/play icons
              onPressed: () {
                print('Play/Pause button pressed');
                onPlayPause();
              },
            ),

            // Previous Move Button
            ChessBoardBottomNavbar(
              svgPath: SvgAsset.left_arrow,
              onPressed: currentMove > 0 ? () {
                print('Previous button pressed');
                onLeftMove();
              } : null,
            ),

            // Next Move Button
            ChessBoardBottomNavbar(
              svgPath: SvgAsset.right_arrow,
              onPressed: currentMove < totalMoves ? () {
                print('Next button pressed');
                onRightMove();
              } : null,
            ),

            // Chat Button
            ChessBoardBottomNavbar(
                svgPath: SvgAsset.chat,
                onPressed: () {
                  print('Chat button pressed');
                }
            ),
          ],
        ),
      ),
    );
  }
}