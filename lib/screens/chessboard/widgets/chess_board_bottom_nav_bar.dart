import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_navbar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChessBoardBottomNavBar extends ConsumerWidget {
  final int gameIndex;
  final VoidCallback? onLeftMove;
  final VoidCallback? onRightMove;
  final VoidCallback onFlip;
  final VoidCallback? toggleAnalysisMode;
  final VoidCallback? onLongPressBackwardStart;
  final VoidCallback? onLongPressBackwardEnd;
  final VoidCallback? onLongPressForwardStart;
  final VoidCallback? onLongPressForwardEnd;
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
    this.onLongPressBackwardStart,
    this.onLongPressBackwardEnd,
    this.onLongPressForwardStart,
    this.onLongPressForwardEnd,
  });

  void _showExitAnalysisConfirmation(
    BuildContext context,
    VoidCallback? onConfirm,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline, color: kPrimaryColor, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Exit Analysis Mode?',
                  style: TextStyle(
                    color: kWhiteColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'This will reset the position to the actual game and clear variant exploration.',
                  style: TextStyle(
                    color: Color(0xFFB0B0B0),
                    fontSize: 14,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFF2A2A2A),
                          foregroundColor: kWhiteColor,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Dismiss',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          onConfirm?.call();
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: kPrimaryColor,
                          foregroundColor: kWhiteColor,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Confirm',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.of(context).size.width / 4;
    return Container(
      width: MediaQuery.of(context).size.width,
      height: 48.h,
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
                  if (isAnalysisMode) {
                    // Show confirmation dialog when exiting analysis mode
                    _showExitAnalysisConfirmation(context, toggleAnalysisMode);
                  } else {
                    // Directly enter analysis mode
                    toggleAnalysisMode?.call();
                  }
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
                    canMoveBackward ? onLongPressBackwardStart : null,
                onLongPressEnd: onLongPressBackwardEnd,
              ),

              ChessSvgBottomNavbarWithLongPress(
                svgPath: SvgAsset.right_arrow,
                width: width,
                onPressed: canMoveForward ? onRightMove : null,
                onLongPressStart:
                    canMoveForward ? onLongPressForwardStart : null,
                onLongPressEnd: onLongPressForwardEnd,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
