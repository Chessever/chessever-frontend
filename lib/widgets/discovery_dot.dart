import 'dart:async';

import 'package:chessever2/services/discovery_dots/discovery_dots_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// How a dot's message is shown once its target is reached.
enum DiscoveryDotMessage {
  /// A small bubble beside the surface. For surfaces that stay on screen
  /// after the tap: tabs, toggles, bar buttons.
  bubble,

  /// The app snack. For surfaces whose tap leaves the screen (a tile that
  /// opens a page, a drawer row), where a bubble would point at nothing.
  snack,
}

/// Marks [child] as a surface the admin console can put a dot on.
///
/// With no dot published for [id] this is a pass-through: the child lays out,
/// paints and hit-tests exactly as it would bare. The wrapper keeps the same
/// shape either way, so a dot arriving or leaving never remounts the child.
///
/// Reaching the surface retires the dot. That is a tap on it, or, for a
/// surface that can also be reached by swiping (a tab), [selected] turning
/// true.
class DiscoveryDotAnchor extends ConsumerStatefulWidget {
  const DiscoveryDotAnchor({
    super.key,
    required this.id,
    required this.child,
    this.selected,
    this.alignment = Alignment.topRight,
    this.offset = Offset.zero,
    this.message = DiscoveryDotMessage.bubble,
  });

  /// Anchor id from the surface catalog, or null for a surface with none.
  final String? id;
  final Widget child;

  /// For tabs: whether this one is the current tab.
  final bool? selected;

  /// Where in [child] the dot sits, before [offset].
  final Alignment alignment;

  /// Nudges the dot from [alignment], in logical pixels.
  final Offset offset;

  final DiscoveryDotMessage message;

  @override
  ConsumerState<DiscoveryDotAnchor> createState() => _DiscoveryDotAnchorState();
}

class _DiscoveryDotAnchorState extends ConsumerState<DiscoveryDotAnchor> {
  Offset? _down;
  OverlayEntry? _bubble;
  Timer? _bubbleLife;

  @override
  void didUpdateWidget(DiscoveryDotAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Arrived by swipe: the tab was never tapped, but it has been reached.
    if (widget.selected == true && oldWidget.selected == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _acknowledge();
      });
    }
  }

  @override
  void dispose() {
    _removeBubble();
    super.dispose();
  }

  void _removeBubble() {
    _bubbleLife?.cancel();
    _bubbleLife = null;
    _bubble?.remove();
    _bubble = null;
  }

  void _acknowledge() {
    final id = widget.id;
    if (id == null) return;
    final message = ref.read(discoveryDotsProvider.notifier).acknowledge(id);
    if (message == null) return;
    switch (widget.message) {
      case DiscoveryDotMessage.snack:
        showAppSnack(context, message, duration: const Duration(seconds: 5));
      case DiscoveryDotMessage.bubble:
        _showBubble(message);
    }
  }

  void _showBubble(String message) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final box = context.findRenderObject();
    if (overlay == null || box is! RenderBox || !box.hasSize) {
      showAppSnack(context, message, duration: const Duration(seconds: 5));
      return;
    }
    _removeBubble();
    final target = box.localToGlobal(Offset.zero) & box.size;
    final entry = OverlayEntry(
      builder: (_) => _DiscoveryBubbleLayer(
        target: target,
        message: message,
        onDismiss: _removeBubble,
      ),
    );
    _bubble = entry;
    overlay.insert(entry);
    _bubbleLife = Timer(const Duration(seconds: 6), _removeBubble);
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.id;
    final lit =
        id != null &&
        ref.watch(discoveryDotsProvider.select((s) => s.lit.contains(id)));

    // A raw Listener sits outside the gesture arena, so the surface's own tap,
    // long-press and drag recognizers are untouched.
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: lit ? (event) => _down = event.position : null,
      onPointerCancel: lit ? (_) => _down = null : null,
      onPointerUp: lit
          ? (event) {
              final down = _down;
              _down = null;
              if (down == null) return;
              if ((event.position - down).distance > kTouchSlop) return;
              _acknowledge();
            }
          : null,
      child: Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (lit)
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: widget.alignment,
                  child: Transform.translate(
                    offset: widget.offset,
                    child: const DiscoveryDotMark(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The dot itself: the brand accent, breathing slowly. Still when the system
/// asks for reduced motion.
class DiscoveryDotMark extends StatefulWidget {
  const DiscoveryDotMark({super.key});

  static const double size = 8;

  @override
  State<DiscoveryDotMark> createState() => _DiscoveryDotMarkState();
}

class _DiscoveryDotMarkState extends State<DiscoveryDotMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 900),
    vsync: this,
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: 0.35,
    end: 1,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'New',
      child: RepaintBoundary(
        child: FadeTransition(
          opacity: _opacity,
          child: Container(
            width: DiscoveryDotMark.size,
            height: DiscoveryDotMark.size,
            decoration: BoxDecoration(
              // Brand cyan is ~2:1 on paper, so light uses the deep accent.
              color: context.isLightTheme
                  ? context.colors.accentText
                  : kPrimaryColor,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen layer holding one bubble. Touching anywhere dismisses it and
/// the touch still reaches whatever is underneath.
class _DiscoveryBubbleLayer extends StatelessWidget {
  const _DiscoveryBubbleLayer({
    required this.target,
    required this.message,
    required this.onDismiss,
  });

  final Rect target;
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => onDismiss(),
      child: Padding(
        padding: media.padding,
        child: CustomSingleChildLayout(
          delegate: _BubbleLayout(
            target: target.shift(-media.padding.topLeft),
            // Open toward the roomier half of the screen.
            below: target.center.dy < media.size.height / 2,
          ),
          child: _DiscoveryBubble(message: message),
        ),
      ),
    );
  }
}

class _BubbleLayout extends SingleChildLayoutDelegate {
  const _BubbleLayout({required this.target, required this.below});

  final Rect target;
  final bool below;

  static const double _margin = 12;
  static const double _gap = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: (constraints.maxWidth - _margin * 2).clamp(0, 300),
        maxHeight: constraints.maxHeight,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) => positionDependentBox(
    size: size,
    childSize: childSize,
    target: target.center,
    preferBelow: below,
    verticalOffset: target.height / 2 + _gap,
    margin: _margin,
  );

  @override
  bool shouldRelayout(_BubbleLayout oldDelegate) =>
      target != oldDelegate.target || below != oldDelegate.below;
}

class _DiscoveryBubble extends StatefulWidget {
  const _DiscoveryBubble({required this.message});

  final String message;

  @override
  State<_DiscoveryBubble> createState() => _DiscoveryBubbleState();
}

class _DiscoveryBubbleState extends State<_DiscoveryBubble> {
  static const _settle = CupertinoMotion.snappy(
    duration: Duration(milliseconds: 260),
  );

  // Fully readable from the first frame; only its size settles.
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _settled = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLight = context.isLightTheme;
    return SingleMotionBuilder(
      motion: _settle,
      value: _settled ? 1.0 : 0.94,
      active: !MediaQuery.disableAnimationsOf(context),
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      // The same capsule as the app snack: ink in dark, paper in light.
      child: Semantics(
        liveRegion: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isLight ? context.colors.popup : const Color(0xFF08080A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isLight
                  ? context.colors.textPrimary.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.08),
            ),
            boxShadow: [
              isLight
                  ? const BoxShadow(
                      color: Color(0x2E0E1A1C),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    )
                  : BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Text(
              widget.message,
              style: AppTypography.textSmMedium.copyWith(
                color: isLight
                    ? context.colors.textPrimary
                    : Colors.white.withValues(alpha: 0.94),
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
