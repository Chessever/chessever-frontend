import 'dart:math' as math;
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buttonCount = showGamebaseButton ? 5 : 4;
    final fullWidth = MediaQuery.of(context).size.width;

    // Tablet-specific layout calculations
    final isTablet = ResponsiveHelper.isTablet;
    final isTabletLandscape = isTablet && ResponsiveHelper.isLandscape;
    final isTabletPortrait = isTablet && !ResponsiveHelper.isLandscape;

    // Calculate content width based on orientation
    // Portrait: Match the body content width (85% capped at 720)
    // Landscape: Use full width but with refined max button sizes
    double contentWidth;
    if (isTabletPortrait) {
      contentWidth = math.min(fullWidth * 0.85, 720.0);
    } else if (isTabletLandscape) {
      // In landscape, constrain to a comfortable max width
      contentWidth = math.min(fullWidth, 800.0);
    } else {
      contentWidth = fullWidth;
    }

    // Button sizing with tablet refinements
    final rawButtonWidth = contentWidth / buttonCount;
    // On tablets, limit individual button width for better touch targets
    final buttonWidth =
        isTablet ? math.min(rawButtonWidth, 140.0) : rawButtonWidth;
    final barHeight =
        isTablet
            ? kBottomNavigationBarHeight + 14.0
            : kBottomNavigationBarHeight;

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
        depthText =
            'D:${gaugeProgress.depth.clamp(0, 99).toString().padLeft(2, '0')}';
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
      } else {
        debugPrint(
          '⚠️  BottomNav (Game $gameIndex): Engine analysis ON but NO depth data available yet (overlay=${showDepthOverlay})',
        );
      }
    }

    // Build the navigation buttons row
    final buttonsRow = Row(
      mainAxisSize: isTablet ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Gamebase Explorer Toggle (only shown when showGamebaseButton is true)
        if (showGamebaseButton)
          ChessSvgBottomNavbar(
            key: ValueKey('gamebase_toggle_$isGamebaseActive'),
            width: buttonWidth,
            svgPath: SvgAsset.bookIcon,
            onPressed: onGamebaseToggle,
            isActive: isGamebaseActive,
          ),

        // Computer/Engine Analysis Toggle Button
        ChessSvgBottomNavbar(
          width: buttonWidth,
          svgPath: SvgAsset.laptop,
          onPressed: toggleEngineVisibility,
          onLongPress: onEngineSettingsLongPress,
          isActive: showEngineAnalysis,
          depthText: showEngineAnalysis ? depthText : null,
        ),

        // Flip Board Button
        ChessSvgBottomNavbar(
          width: buttonWidth,
          svgPath: SvgAsset.refresh,
          onPressed: onFlip,
        ),
        ChessSvgBottomNavbarWithLongPress(
          svgPath: SvgAsset.left_arrow,
          width: buttonWidth,
          onPressed: canMoveBackward ? onLeftMove : null,
          onLongPressStart: canMoveBackward ? onLongPressBackwardStart : null,
          onLongPressEnd: onLongPressBackwardEnd,
        ),

        ChessSvgBottomNavbarWithLongPress(
          svgPath: SvgAsset.right_arrow,
          width: buttonWidth,
          onPressed: canMoveForward ? onRightMove : null,
          onLongPressStart: canMoveForward ? onLongPressForwardStart : null,
          onLongPressEnd: onLongPressForwardEnd,
          showBadge: showUnseenMoveBadge,
        ),
      ],
    );

    // Tablet-refined container with subtle top border
    final bar = Container(
      width: fullWidth,
      decoration: BoxDecoration(
        color: kBlackColor,
        // Add subtle top border for visual separation on tablets
        border:
            isTablet
                ? Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.06),
                    width: 1,
                  ),
                )
                : null,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: barHeight,
          child: Center(
            child:
                isTablet
                    // Tablet: Container with refined styling
                    ? Container(
                      height: barHeight - 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D0D0D),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: EdgeInsets.symmetric(vertical: 4),
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: buttonsRow,
                    )
                    // Phone: Full width row
                    : SizedBox(width: contentWidth, child: buttonsRow),
          ),
        ),
      ),
    );

    if (!isTabletLandscape) {
      return bar;
    }

    return GestureDetector(
      // Absorb horizontal drags so taps in the bottom bar don't trigger
      // the parent PageView on tablet landscape.
      onHorizontalDragStart: (_) {},
      onHorizontalDragUpdate: (_) {},
      onHorizontalDragEnd: (_) {},
      behavior: HitTestBehavior.opaque,
      child: bar,
    );
  }
}
