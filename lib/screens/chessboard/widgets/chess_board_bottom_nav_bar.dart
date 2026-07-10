import 'dart:math' as math;
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_navbar.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

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
  final VoidCallback? onGamebaseToggle;
  final bool isGamebaseActive;
  final bool showGamebaseButton;

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
    this.onGamebaseToggle,
    this.isGamebaseActive = false,
    this.showGamebaseButton = false,
  });

  /// Height of the floating control island. It retains the board's familiar
  /// compact footprint while growing enough for the depth label at large
  /// Dynamic Type sizes.
  static double preferredHeight(BuildContext context) {
    final isTablet = ResponsiveHelper.isTablet;
    final baseHeight =
        isTablet ? kBottomNavigationBarHeight + 14 : kBottomNavigationBarHeight;
    final labelHeight = MediaQuery.textScalerOf(
      context,
    ).scale(isTablet ? 11 : 10);
    return math.max(baseHeight, labelHeight + 38).clamp(baseHeight, 88);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buttonCount = showGamebaseButton ? 5 : 4;
    final isTablet = ResponsiveHelper.isTablet;
    final isTabletLandscape = isTablet && ResponsiveHelper.isLandscape;
    final media = MediaQuery.of(context);
    final safeWidth =
        media.size.width - media.viewPadding.left - media.viewPadding.right;
    final islandWidth =
        math
            .min(math.max(0.0, safeWidth - 24), isTablet ? 560.0 : 420.0)
            .toDouble();
    final barHeight = preferredHeight(context);
    final buttonWidth = (islandWidth - 8) / buttonCount;

    // Watch the centralized engine depth status provider
    final depthSnapshot = ref.watch(engineDepthStatusProvider);
    final gaugeProgress = depthSnapshot?.progress;

    // Check if user wants to see depth overlay
    final engineSettings = ref.watch(engineSettingsProviderNew).valueOrNull;
    final showDepthOverlay = engineSettings?.showDepthOverlay ?? true;

    // Format depth text like "D:12"; show "..." while loading if overlay is enabled
    String? depthText;
    if (showDepthOverlay) {
      if (gaugeProgress != null) {
        depthText =
            'D:${gaugeProgress.depth.clamp(0, 99).toString().padLeft(2, '0')}';
      } else {
        depthText = '...';
      }
    }

    Widget semanticControl({
      required String label,
      required Widget child,
      required VoidCallback? onTap,
      bool? toggled,
    }) {
      return Semantics(
        label: label,
        button: true,
        enabled: onTap != null,
        toggled: toggled,
        onTap: onTap,
        child: ExcludeSemantics(child: child),
      );
    }

    final buttonsRow = Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showGamebaseButton)
          semanticControl(
            label:
                isGamebaseActive
                    ? 'Hide Gamebase explorer'
                    : 'Show Gamebase explorer',
            toggled: isGamebaseActive,
            onTap: onGamebaseToggle,
            child: ChessSvgBottomNavbar(
              key: e2eKey(E2eIds.boardGamebaseToggle),
              width: buttonWidth,
              svgPath: SvgAsset.libraryNavIcon,
              onPressed: onGamebaseToggle,
              isActive: isGamebaseActive,
            ),
          ),
        semanticControl(
          label:
              showEngineAnalysis
                  ? 'Hide engine analysis${depthText == null ? '' : ', $depthText'}'
                  : 'Show engine analysis',
          toggled: showEngineAnalysis,
          onTap: toggleEngineVisibility,
          child: ChessSvgBottomNavbar(
            key: e2eKey(E2eIds.boardEngineToggle),
            width: buttonWidth,
            svgPath: SvgAsset.laptop,
            onPressed: toggleEngineVisibility,
            onLongPress: onEngineSettingsLongPress,
            isActive: showEngineAnalysis,
            depthText: showEngineAnalysis ? depthText : null,
          ),
        ),
        semanticControl(
          label: 'Flip board',
          onTap: onFlip,
          child: ChessSvgBottomNavbar(
            key: e2eKey(E2eIds.boardFlip),
            width: buttonWidth,
            svgPath: SvgAsset.refresh,
            onPressed: onFlip,
          ),
        ),
        semanticControl(
          label: 'Previous move. Long press to repeat',
          onTap: canMoveBackward ? onLeftMove : null,
          child: ChessSvgBottomNavbarWithLongPress(
            key: e2eKey(E2eIds.boardMoveBack),
            svgPath: SvgAsset.left_arrow,
            width: buttonWidth,
            onPressed: canMoveBackward ? onLeftMove : null,
            onLongPressStart: canMoveBackward ? onLongPressBackwardStart : null,
            onLongPressEnd: onLongPressBackwardEnd,
          ),
        ),
        semanticControl(
          label:
              showUnseenMoveBadge
                  ? 'Next move, new move available. Long press to repeat'
                  : 'Next move. Long press to repeat',
          onTap: canMoveForward ? onRightMove : null,
          child: ChessSvgBottomNavbarWithLongPress(
            key: e2eKey(E2eIds.boardMoveForward),
            svgPath: SvgAsset.right_arrow,
            width: buttonWidth,
            onPressed: canMoveForward ? onRightMove : null,
            onLongPressStart: canMoveForward ? onLongPressForwardStart : null,
            onLongPressEnd: onLongPressForwardEnd,
            showBadge: showUnseenMoveBadge,
          ),
        ),
      ],
    );

    final island = GlassContainer(
      key: const ValueKey<String>('board-floating-bottom-controls'),
      width: islandWidth,
      height: barHeight,
      padding: const EdgeInsets.all(4),
      alignment: Alignment.center,
      useOwnLayer: true,
      quality: GlassQuality.standard,
      shape: LiquidRoundedSuperellipse(borderRadius: barHeight / 2),
      child: buttonsRow,
    );

    final controls = Center(
      child: GestureDetector(
        onHorizontalDragStart: isTabletLandscape ? (_) {} : null,
        onHorizontalDragUpdate: isTabletLandscape ? (_) {} : null,
        onHorizontalDragEnd: isTabletLandscape ? (_) {} : null,
        behavior: HitTestBehavior.opaque,
        child: island,
      ),
    );

    return Semantics(
      container: true,
      label: 'Chess board controls',
      child: controls,
    );
  }
}
