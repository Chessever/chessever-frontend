import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_viewmodel.dart';
import 'package:chessever2/widgets/svg_widget.dart';

class ChessBottomNavBar extends ConsumerWidget {
  const ChessBottomNavBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chessState = ref.watch(chessViewModelProvider);
    final flipBoard = ref.watch(flipBoardProvider);

    return Container(
      height: 150, // Reduced height for better proportions with 24px icons
      width: MediaQuery.of(context).size.width,
      decoration: const BoxDecoration(color: Colors.black),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // New Game Button
            _buildBottomNavButton(
              context,
              svgPath: 'assets/svgs/laptop.svg',
              onPressed: () {
                ref.read(chessViewModelProvider.notifier).resetGame();
              },
            ),

            // Simulate/Stop Button
            _buildBottomNavButton(
              context,
              svgPath:
                  chessState.simulatingPgn
                      ? 'assets/svgs/stop.svg'
                      : 'assets/svgs/refresh.svg',
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
            _buildBottomNavButton(
              context,
              svgPath: 'assets/svgs/left_arrow.svg',
              onPressed:
                  chessState.currentMoveIndex > 0
                      ? () {
                        ref
                            .read(chessViewModelProvider.notifier)
                            .goToPreviousMove();
                      }
                      : null,
            ),

            // Next Move Button
            _buildBottomNavButton(
              context,
              svgPath: 'assets/svgs/right_arrow.svg',
              onPressed:
                  chessState.currentMoveIndex < chessState.pgnMoves.length
                      ? () {
                        ref
                            .read(chessViewModelProvider.notifier)
                            .goToNextMove();
                      }
                      : null,
            ),

            // More Options Button
            _buildBottomNavButton(
              context,
              svgPath:
                  'assets/svgs/dots_three.svg', // Fixed path (was svgs_dots_three.svg)
              onPressed: () {
                _showMoreOptions(context, ref, flipBoard);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavButton(
    BuildContext context, {
    required String svgPath,
    required VoidCallback? onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 56, // 48px for touch target + 8px padding
        height: 56,
        padding: const EdgeInsets.all(16), // Centers the 24px icon
        child: SvgWidget(
          svgPath,
          height: 24,
          width: 24,
          colorFilter: ColorFilter.mode(
            onPressed != null ? Colors.white : Colors.white.withOpacity(0.3),
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }

  void _showMoreOptions(BuildContext context, WidgetRef ref, bool flipBoard) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: SvgWidget(
                  'assets/svgs/rotate_left.svg',
                  height: 24,
                  width: 24,
                ),
                title: const Text('Flip Board'),
                onTap: () {
                  ref.read(flipBoardProvider.notifier).state = !flipBoard;
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: SvgWidget(
                  'assets/svgs/settings.svg',
                  height: 24,
                  width: 24,
                ),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
