import 'dart:math' as math;
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/utils/live_stream_coachmark.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_navbar.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChessBoardBottomNavBar extends ConsumerStatefulWidget {
  final int gameIndex;
  final VoidCallback? onLeftMove;
  final VoidCallback? onRightMove;
  final VoidCallback onFlip;
  final VoidCallback? onVideoToggle;
  final bool videoVisible;

  /// Whether this bar belongs to the currently visible game page. The camera
  /// tooltip only auto-shows on the active page so pre-built adjacent pages
  /// never pop a bubble for a stream the reader is not looking at.
  final bool isActivePage;
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

  /// When true (opening explorer page visible), the bar background is lightly
  /// translucent so explorer games under the bar stay faintly visible.
  final bool explorerPanelVisible;

  /// Override for tests. Production persists the hint through the app database.
  final LiveStreamCoachmarkTracker? liveStreamCoachmarkTracker;

  const ChessBoardBottomNavBar({
    super.key,
    required this.gameIndex,
    required this.onLeftMove,
    required this.onRightMove,
    required this.onFlip,
    this.onVideoToggle,
    this.videoVisible = false,
    this.isActivePage = true,
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
    this.explorerPanelVisible = false,
    this.liveStreamCoachmarkTracker,
  });

  @override
  ConsumerState<ChessBoardBottomNavBar> createState() =>
      _ChessBoardBottomNavBarState();
}

class _ChessBoardBottomNavBarState
    extends ConsumerState<ChessBoardBottomNavBar> {
  final GlobalKey _videoToggleTargetKey = GlobalKey();
  OverlayEntry? _videoCoachmarkEntry;
  bool _videoCoachmarkScheduled = false;

  bool get _hasVideoToggle => widget.onVideoToggle != null;
  LiveStreamCoachmarkTracker get _coachmarkTracker =>
      widget.liveStreamCoachmarkTracker ?? liveStreamCoachmarkTracker;

  @override
  void initState() {
    super.initState();
    if (_hasVideoToggle && widget.videoVisible) _scheduleVideoCoachmark();
  }

  @override
  void didUpdateWidget(covariant ChessBoardBottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasVideoToggle || !widget.videoVisible || !widget.isActivePage) {
      _hideVideoCoachmark();
      return;
    }
    final toggleAppeared = oldWidget.onVideoToggle == null;
    final becameActive = !oldWidget.isActivePage;
    final streamOpened = widget.videoVisible && !oldWidget.videoVisible;
    final gameChanged = widget.gameIndex != oldWidget.gameIndex;
    if (widget.videoVisible &&
        (toggleAppeared || becameActive || streamOpened || gameChanged)) {
      _scheduleVideoCoachmark();
    }
  }

  @override
  void dispose() {
    _videoCoachmarkEntry?.remove();
    _videoCoachmarkEntry = null;
    super.dispose();
  }

  /// Readers miss the camera switch, so its first live appearance gets one
  /// persistent, anchored hint. Tapping its close button or camera clears it.
  void _scheduleVideoCoachmark() {
    if (_videoCoachmarkScheduled) return;
    _videoCoachmarkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          !_hasVideoToggle ||
          !widget.videoVisible ||
          !widget.isActivePage) {
        _videoCoachmarkScheduled = false;
        return;
      }
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) {
        _videoCoachmarkScheduled = false;
        return;
      }
      final claimed = await _coachmarkTracker.claim();
      if (!mounted) {
        if (claimed) _coachmarkTracker.release();
        return;
      }
      _videoCoachmarkScheduled = false;
      if (!claimed ||
          !_hasVideoToggle ||
          !widget.videoVisible ||
          !widget.isActivePage) {
        if (claimed) _coachmarkTracker.release();
        return;
      }
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) {
        _coachmarkTracker.release();
        return;
      }
      _videoCoachmarkEntry = OverlayEntry(
        builder:
            (_) => _LiveStreamCoachmark(
              targetKey: _videoToggleTargetKey,
              onClose: _hideVideoCoachmark,
            ),
      );
      overlay.insert(_videoCoachmarkEntry!);
      setState(() {});
      await _coachmarkTracker.markShown();
    });
  }

  void _hideVideoCoachmark() {
    if (_videoCoachmarkEntry == null) return;
    _videoCoachmarkEntry?.remove();
    _videoCoachmarkEntry = null;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final buttonCount = widget.showGamebaseButton ? 5 : 4;
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

    // Build the navigation buttons row
    final buttonsRow = Row(
      mainAxisSize: isTablet ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Gamebase Explorer Toggle (only shown when showGamebaseButton is true)
        if (widget.showGamebaseButton)
          ChessSvgBottomNavbar(
            key: e2eKey(E2eIds.boardGamebaseToggle),
            width: buttonWidth,
            svgPath: SvgAsset.libraryNavIcon,
            onPressed: widget.onGamebaseToggle,
            isActive: widget.isGamebaseActive,
          ),

        // Computer/Engine Analysis Toggle Button
        ChessSvgBottomNavbar(
          key: e2eKey(E2eIds.boardEngineToggle),
          width: buttonWidth,
          svgPath: SvgAsset.laptop,
          onPressed: widget.toggleEngineVisibility,
          onLongPress: widget.onEngineSettingsLongPress,
          isActive: widget.showEngineAnalysis,
          depthText: widget.showEngineAnalysis ? depthText : null,
        ),

        // Events with streams expose video here and board swap in the menu.
        if (widget.onVideoToggle != null)
          SizedBox(
            key: _videoToggleTargetKey,
            width: buttonWidth,
            child: Tooltip(
              message:
                  widget.videoVisible
                      ? 'Turn off the live stream'
                      : 'Turn on the live stream',
              // The bar sits at the screen edge, so the bubble must open up.
              preferBelow: false,
              showDuration: const Duration(seconds: 4),
              // Match the high-contrast coachmark over the dark board bar.
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: kWhiteColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              textStyle: AppTypography.textSmSemiBold.copyWith(
                color: kBackgroundColor,
              ),
              child: IconButton(
                key: const ValueKey('board_video_toggle'),
                onPressed: () {
                  Tooltip.dismissAllToolTips();
                  _hideVideoCoachmark();
                  widget.onVideoToggle?.call();
                },
                icon: Icon(
                  widget.videoVisible
                      ? Icons.videocam_off_outlined
                      : Icons.videocam_outlined,
                  // Material camera glyphs have more inset than the SVG controls.
                  size: 28.sp,
                  color:
                      _videoCoachmarkEntry != null
                          ? context.colors.brand
                          : Colors.white,
                ),
              ),
            ),
          )
        else
          ChessSvgBottomNavbar(
            key: e2eKey(E2eIds.boardFlip),
            width: buttonWidth,
            svgPath: SvgAsset.refresh,
            onPressed: widget.onFlip,
          ),
        ChessSvgBottomNavbarWithLongPress(
          key: e2eKey(E2eIds.boardMoveBack),
          svgPath: SvgAsset.left_arrow,
          width: buttonWidth,
          onPressed: widget.canMoveBackward ? widget.onLeftMove : null,
          onLongPressStart:
              widget.canMoveBackward ? widget.onLongPressBackwardStart : null,
          onLongPressEnd: widget.onLongPressBackwardEnd,
        ),

        ChessSvgBottomNavbarWithLongPress(
          key: e2eKey(E2eIds.boardMoveForward),
          svgPath: SvgAsset.right_arrow,
          width: buttonWidth,
          onPressed: widget.canMoveForward ? widget.onRightMove : null,
          onLongPressStart:
              widget.canMoveForward ? widget.onLongPressForwardStart : null,
          onLongPressEnd: widget.onLongPressForwardEnd,
          showBadge: widget.showUnseenMoveBadge,
        ),
      ],
    );

    // Subtle translucency only while the explorer panel is open — enough to
    // hint that more games sit under the bar, without washing out the chrome.
    const explorerBarAlpha = 0.86;
    final barColor =
        widget.explorerPanelVisible
            ? context.colors.background.withValues(alpha: explorerBarAlpha)
            : context.colors.background;
    final tabletSurface =
        widget.explorerPanelVisible
            ? context.colors.surface.withValues(alpha: explorerBarAlpha)
            : context.colors.surface;

    // Tablet-refined container with subtle top border
    final bar = Container(
      width: fullWidth,
      decoration: BoxDecoration(
        color: barColor,
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
                        color: tabletSurface,
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

    // Bottom nav always stays put so explorer game-card focus arrows remain
    // usable while browsing inline games (games expand covers PV + table instead).
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

class _LiveStreamCoachmark extends StatelessWidget {
  const _LiveStreamCoachmark({required this.targetKey, required this.onClose});

  final GlobalKey targetKey;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    const fill = kBlack3Color;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final popupWidth = math.min(screenWidth - 32, 380.0);
    final targetBox =
        targetKey.currentContext?.findRenderObject() as RenderBox?;
    final targetTop = targetBox?.localToGlobal(Offset.zero).dy ?? screenHeight;
    final targetCenterX =
        targetBox?.localToGlobal(Offset(targetBox.size.width / 2, 0)).dx ??
        screenWidth / 2;
    final centeredLeft = targetCenterX - popupWidth / 2;
    final clampedLeft = centeredLeft.clamp(16.0, screenWidth - popupWidth - 16);
    final arrowLeft = (targetCenterX - clampedLeft - 8).clamp(
      0.0,
      popupWidth - 16,
    );
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            left: clampedLeft,
            bottom: screenHeight - targetTop + 6,
            width: popupWidth,
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    key: const ValueKey('live_stream_toggle_coachmark'),
                    padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Turn off the stream by clicking camera icon.',
                            textAlign: TextAlign.left,
                            style: AppTypography.textSmSemiBold.copyWith(
                              color: kWhiteColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          key: const ValueKey('close_live_stream_coachmark'),
                          onPressed: onClose,
                          tooltip: 'Close',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.close,
                            size: 19,
                            color: kWhiteColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 8,
                    child: Stack(
                      children: [
                        Positioned(
                          left: arrowLeft,
                          child: CustomPaint(
                            key: const ValueKey(
                              'live_stream_toggle_coachmark_arrow',
                            ),
                            size: const Size(16, 8),
                            painter: const _DownArrowPainter(fill),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownArrowPainter extends CustomPainter {
  const _DownArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path =
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width / 2, size.height)
          ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _DownArrowPainter oldDelegate) =>
      oldDelegate.color != color;
}
