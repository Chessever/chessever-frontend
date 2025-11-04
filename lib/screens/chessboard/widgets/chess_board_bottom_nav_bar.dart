import 'package:chessever2/providers/engine_settings_provider.dart';
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

    // Watch engine depth tracker for live depth display
    final progressMap = ref.watch(engineDepthTrackerProvider);

    EngineComponent? activeComponent;
    EngineSearchProgress? gaugeProgress;

    if (progressMap.containsKey(EngineComponent.evaluationGauge)) {
      activeComponent = EngineComponent.evaluationGauge;
      gaugeProgress = progressMap[EngineComponent.evaluationGauge];
    } else if (progressMap.containsKey(EngineComponent.cascadeEval)) {
      activeComponent = EngineComponent.cascadeEval;
      gaugeProgress = progressMap[EngineComponent.cascadeEval];
    } else if (progressMap.containsKey(EngineComponent.principalVariation)) {
      activeComponent = EngineComponent.principalVariation;
      gaugeProgress = progressMap[EngineComponent.principalVariation];
    }

    // Format depth text like "D:12"
    final depthText = gaugeProgress != null
        ? 'D:${gaugeProgress.depth.clamp(0, 99).toString().padLeft(2, '0')}'
        : null;

    // COMPREHENSIVE DEBUG LOGGING - Verify dynamic depth search is working
    if (showEngineAnalysis) {
      if (depthText != null) {
        debugPrint(
          '📊 ═══ DEPTH DISPLAY UPDATE (Game $gameIndex) ═══\n'
          '   Depth: ${gaugeProgress!.depth}\n'
          '   Nodes: ${gaugeProgress.kiloNodes}k\n'
          '   Display: $depthText\n'
          '   Component: ${activeComponent ?? EngineComponent.evaluationGauge}\n'
          '   FEN Fragment: ${gaugeProgress.fenFragment.substring(0, 20)}...\n'
          '   ═══════════════════════════════════════',
        );
      } else {
        debugPrint(
          '⚠️  BottomNav (Game $gameIndex): Engine analysis ON but NO depth data available yet',
        );
      }
    }

    return Container(
      width: MediaQuery.of(context).size.width,
      decoration: const BoxDecoration(color: kBlackColor),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(top: 8.h),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
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
