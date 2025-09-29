import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_navbar.dart';
import 'package:chessever2/theme/app_theme.dart';
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
  final VoidCallback? onLongPressForwardButton;
  final VoidCallback? onLongPressBackwardButton;
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
    this.onLongPressForwardButton,
    this.onLongPressBackwardButton
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.of(context).size.width / 5;
    return Container(
      width: MediaQuery.of(context).size.width,
      decoration: const BoxDecoration(color: kBlackColor),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
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
                onLongPress: onLongPressBackwardButton,
              ),
          
              ChessSvgBottomNavbarWithLongPress(
                svgPath: SvgAsset.right_arrow,
                width: width,
                onPressed: canMoveForward ? onRightMove : null,
                onLongPress: onLongPressForwardButton,
              ),
          
              // Chat Button
              ChessSvgBottomNavbar(
                width: width,
                svgPath: SvgAsset.chat,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}
