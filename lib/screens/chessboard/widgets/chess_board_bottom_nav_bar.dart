import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_navbar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChessBoardBottomNavBar extends ConsumerWidget {
  final int gameIndex;
  final VoidCallback? onLeftMove;
  final VoidCallback? onRightMove;
  final VoidCallback onFlip;
  final VoidCallback? toggleEngineVisibility;
  final VoidCallback? onEngineSettingsLongPress;
  final VoidCallback? onLongPressBackwardStart;
  final VoidCallback? onLongPressBackwardEnd;
  final VoidCallback? onLongPressForwardStart;
  final VoidCallback? onLongPressForwardEnd;
  final bool canMoveForward;
  final bool canMoveBackward;
  final bool showEngineAnalysis;
  final bool showUnseenMoveBadge;

  const ChessBoardBottomNavBar({
    super.key,
    required this.gameIndex,
    required this.onLeftMove,
    required this.onRightMove,
    required this.onFlip,
    required this.canMoveForward,
    required this.canMoveBackward,
    required this.showEngineAnalysis,
    required this.showUnseenMoveBadge,
    this.toggleEngineVisibility,
    this.onEngineSettingsLongPress,
    this.onLongPressBackwardStart,
    this.onLongPressBackwardEnd,
    this.onLongPressForwardStart,
    this.onLongPressForwardEnd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.of(context).size.width / 4; // 4 buttons now

    // Watch the centralized engine depth status provider
    final depthSnapshot = ref.watch(engineDepthStatusProvider);
    final activeComponent = depthSnapshot?.component;
    final gaugeProgress = depthSnapshot?.progress;

    // Check if user wants to see depth overlay
    final engineSettings = ref.watch(engineSettingsProviderNew).valueOrNull;
    final showDepthOverlay = engineSettings?.showDepthOverlay ?? true;

    // Format depth text like "D:12"; show "..." while loading if overlay is enabled
    String? depthText;
    if (showDepthOverlay) {
      if (gaugeProgress != null) {
        depthText = 'D:${gaugeProgress.depth.clamp(0, 99).toString().padLeft(2, '0')}';
      } else {
        depthText = '...';
      }
    }

    // COMPREHENSIVE DEBUG LOGGING - Verify dynamic depth search is working
    if (showEngineAnalysis) {
      if (gaugeProgress != null && depthText != null) {
        final fenFragment = gaugeProgress.fenFragment;
        final fragmentLength =
            fenFragment.length < 20 ? fenFragment.length : 20;
        final fragmentPreview = fenFragment.substring(0, fragmentLength);
        final fragmentSuffix = fenFragment.length > fragmentLength ? '...' : '';
        // TEMPO-01-COMMENT
        // debugPrint(
        //   '📊 ═══ DEPTH DISPLAY UPDATE (Game $gameIndex) ═══\n'
        //   '   Depth: ${gaugeProgress.depth}\n'
        //   '   Nodes: ${gaugeProgress.kiloNodes}k\n'
        //   '   Display: $depthText\n'
        //   '   Component: ${activeComponent ?? EngineComponent.evaluationGauge}\n'
        //   '   FEN Fragment: $fragmentPreview$fragmentSuffix\n'
        //   '   ═══════════════════════════════════════',
        // );
      } else {
        debugPrint(
          '⚠️  BottomNav (Game $gameIndex): Engine analysis ON but NO depth data available yet (overlay=${showDepthOverlay})',
        );
      }
    }

    return Container(
      width: MediaQuery.of(context).size.width,
      decoration: const BoxDecoration(color: kBlackColor),
      child: SafeArea(
        top: false, // Allow navbar to extend below app bar
        child: SizedBox(
          height: kBottomNavigationBarHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Computer/Engine Analysis Toggle Button
              ChessSvgBottomNavbar(
                width: width,
                svgPath: SvgAsset.laptop,
                onPressed: toggleEngineVisibility,
                onLongPress: onEngineSettingsLongPress,
                isActive: showEngineAnalysis,
                depthText: showEngineAnalysis ? depthText : null,
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
                showBadge: showUnseenMoveBadge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
