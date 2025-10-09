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
  final VoidCallback onFlip;
  final VoidCallback? toggleAnalysisMode;
  final bool canMoveForward;
  final bool canMoveBackward;
  final bool isAnalysisMode;

  const ChessBoardBottomNavBar({
    super.key,
    required this.gameIndex,
    required this.onLeftMove,
    required this.onRightMove,
    required this.onFlip,
    required this.canMoveForward,
    required this.canMoveBackward,
    required this.toggleAnalysisMode,
    required this.isAnalysisMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.of(context).size.width / 4;
    return Container(
      width: MediaQuery.of(context).size.width,
      decoration: const BoxDecoration(color: kBlackColor),
      child: SafeArea(
        child: SizedBox(
          height: 56.h,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Reset Game Button
                ChessSvgBottomNavbar(
                  width: width,
                  svgPath: isAnalysisMode ? SvgAsset.bookIcon : SvgAsset.laptop,
                  onPressed: () {
                    toggleAnalysisMode?.call();
                  },
                ),

                // Flip Board Button
                ChessSvgBottomNavbar(
                  width: width,
                  svgPath: SvgAsset.refresh,
                  onPressed: onFlip,
                ),
                ChessSvgBottomNavbarWithLongPress(
                  svgPath: SvgAsset.left_arrow,
                  width: width,
                  onPressed: canMoveBackward ? onLeftMove : null,
                  onLongPressStart:
                      canMoveBackward
                          ? () =>
                              ref
                                  .read(
                                    chessBoardScreenProviderNew(
                                      gameIndex,
                                    ).notifier,
                                  )
                                  .startLongPressBackward()
                          : null,
                  onLongPressEnd:
                      () =>
                          ref
                              .read(
                                chessBoardScreenProviderNew(gameIndex).notifier,
                              )
                              .stopLongPress(),
                ),

                ChessSvgBottomNavbarWithLongPress(
                  svgPath: SvgAsset.right_arrow,
                  width: width,
                  onPressed: canMoveForward ? onRightMove : null,
                  onLongPressStart:
                      canMoveForward
                          ? () =>
                              ref
                                  .read(
                                    chessBoardScreenProviderNew(
                                      gameIndex,
                                    ).notifier,
                                  )
                                  .startLongPressForward()
                          : null,
                  onLongPressEnd:
                      () =>
                          ref
                              .read(
                                chessBoardScreenProviderNew(gameIndex).notifier,
                              )
                              .stopLongPress(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
