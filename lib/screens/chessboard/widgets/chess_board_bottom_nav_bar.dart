import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_navbar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../provider/chess_board_screen_provider_new.dart';

class ChessBoardBottomNavBar extends ConsumerWidget {
  final int gameIndex;
  final VoidCallback? onLeftMove;
  final VoidCallback? onRightMove;
  final VoidCallback onPlayPause;
  final VoidCallback onReset;
  final VoidCallback onFlip;
  final VoidCallback? onJumpToStart;
  final VoidCallback? onJumpToEnd;
  final bool isPlaying;
  final int currentMove;
  final int totalMoves;
  final bool canMoveForward;
  final bool canMoveBackward;
  final bool isAtStart;
  final bool isAtEnd;

  const ChessBoardBottomNavBar({
    super.key,
    required this.gameIndex,
    required this.onLeftMove,
    required this.onRightMove,
    required this.onPlayPause,
    required this.onReset,
    required this.onFlip,
    this.onJumpToStart,
    this.onJumpToEnd,
    required this.isPlaying,
    required this.currentMove,
    required this.totalMoves,
    required this.canMoveForward,
    required this.canMoveBackward,
    required this.isAtStart,
    required this.isAtEnd,
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
              onPressed: () {},
            ),

            // Flip Board Button
            ChessSvgBottomNavbar(
              svgPath: SvgAsset.refresh,
              onPressed: onFlip,
            ),

            // Previous Move Button with Long Press
            // ChessSvgBottomNavbarWithLongPress(
            //   svgPath: SvgAsset.left_arrow,
            //   onPressed: canMoveBackward ? onLeftMove : null,
            //   onLongPressStart: canMoveBackward
            //       ? () => notifier.startLongPressBackward()
            //       : null,
            //   onLongPressEnd: () => notifier.stopLongPress(),
            // ),

            // // Next Move Button with Long Press
            // ChessSvgBottomNavbarWithLongPress(
            //   svgPath: SvgAsset.right_arrow,
            //   onPressed: canMoveForward ? onRightMove : null,
            //   onLongPressStart: canMoveForward
            //       ? () => notifier.startLongPressForward()
            //       : null,
            //   onLongPressEnd: () => notifier.stopLongPress(),
            // ),
            ChessSvgBottomNavbarWithLongPress(
              svgPath: SvgAsset.left_arrow,
              onPressed: canMoveBackward ? onLeftMove : null,
              onLongPressStart:
                  canMoveBackward
                      ? () =>
                          ref
                              .read(
                                chessBoardScreenProviderNew(gameIndex).notifier,
                              )
                              .startLongPressBackward()
                      : null,
              onLongPressEnd:
                  () =>
                      ref
                          .read(chessBoardScreenProviderNew(gameIndex).notifier)
                          .stopLongPress(),
            ),

            ChessSvgBottomNavbarWithLongPress(
              svgPath: SvgAsset.right_arrow,
              onPressed: canMoveForward ? onRightMove : null,
              onLongPressStart:
                  canMoveForward
                      ? () =>
                          ref
                              .read(
                                chessBoardScreenProviderNew(gameIndex).notifier,
                              )
                              .startLongPressForward()
                      : null,
              onLongPressEnd:
                  () =>
                      ref
                          .read(chessBoardScreenProviderNew(gameIndex).notifier)
                          .stopLongPress(),
            ),

            // Chat Button
            ChessSvgBottomNavbar(
              svgPath: SvgAsset.chat,
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}
