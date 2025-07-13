import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_navbar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChessBoardBottomNavBar extends ConsumerWidget {
  final VoidCallback onLeftMove;
  final VoidCallback onRightMove;
  final VoidCallback onPlayPause;
  final VoidCallback onReset;
  final VoidCallback onFlip;
  final bool isPlaying;
  final int currentMove;
  final int totalMoves;

  const ChessBoardBottomNavBar({
    super.key,
    required this.onLeftMove,
    required this.onRightMove,
    required this.onPlayPause,
    required this.onReset,
    required this.onFlip,
    required this.isPlaying,
    required this.currentMove,
    required this.totalMoves,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8.sp),
      width: MediaQuery.of(context).size.width,
      decoration: const BoxDecoration(color: kBlackColor),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Reset Game Button
            ChessSvgBottomNavbar(
              svgPath: SvgAsset.laptop,
              onPressed: () {
                onReset();
              },
            ),

            // Flip Board Button
            ChessSvgBottomNavbar(
              svgPath: SvgAsset.refresh,
              onPressed: () {
                onFlip();
              },
            ),

            // Play/Pause Button
            ChessIconBottomNavbar(
              iconData:
                  isPlaying
                      ? Icons.play_circle_outline
                      : Icons.pause_circle_outline,
              // Use appropriate pause/play icons
              onPressed: () {
                onPlayPause();
              },
            ),

            // Previous Move Button
            ChessSvgBottomNavbar(
              svgPath: SvgAsset.left_arrow,
              onPressed:
                  currentMove > 0
                      ? () {
                        onLeftMove();
                      }
                      : null,
            ),

            // Next Move Button
            ChessSvgBottomNavbar(
              svgPath: SvgAsset.right_arrow,
              onPressed:
                  currentMove < totalMoves
                      ? () {
                        onRightMove();
                      }
                      : null,
            ),

            // Chat Button
            ChessSvgBottomNavbar(svgPath: SvgAsset.chat, onPressed: () {}),
          ],
        ),
      ),
    );
  }
}
