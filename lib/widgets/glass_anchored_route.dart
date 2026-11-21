import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/widgets/popup_glass.dart';
import 'package:chessever2/widgets/window_metrics_dismissal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringSimulation;
import 'package:flutter/rendering.dart';
import 'package:motor/motor.dart';

/// A route that hangs over the page for a moment (a menu, a popover, a
/// dropdown): the page stays on screen and live under it.
///
/// A page that pauses its work while another route covers it
/// (`RouteAware.didPushNext`) keeps running under one of these, and has
/// nothing to resume when it closes.
abstract interface class TransientOverlayRoute {}

/// How every anchored glass surface moves: the shared glass menu
/// (`showTabletSafeMenu`), dropdowns (`GlassDropdown`), the panels that
/// drop from a chip (`GlassPopoverLayer`), the add button's popover, the tag
/// picker, the focus menu's panels and the board's game switcher.
///
/// The panel is on screen at full strength from its first frame (glass
/// under an opacity loses its frost) and grows from [openScale] on the open
/// spring, out of the point nearest what opened it, while the dim
/// ([AnchoredGlassDim]) rides the same progress.
///
/// It closes by folding shut into that point on the [close] spring, the
/// game switcher's: the whole glass (plate, rim, shadow and frost) keeps
/// most of its width and folds its height away to nothing while its rows
/// fade and the dim clears, so nothing is left on screen to vanish when the
/// panel is finally taken away ([GlassFold]). What the reader picked never
/// waits on the fold: the result is handed over as the close begins, and
/// the page under a folding panel already takes taps.
abstract final class GlassAnchoredMotion {
  /// The open: no bounce, so the panel never grows past its slot; quick, so
  /// the glass is re-rendered for as few frames as the grow needs.
  static const CupertinoMotion open = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 220),
    snapToEnd: true,
  );

  /// Done once what is left cannot be seen: half a percent of the way is
  /// 0.04% of the panel's scale (a fraction of a point on the widest menu)
  /// and 0.2% of the dim, so the spring's invisible tail costs no frames.
  static const Tolerance tolerance = Tolerance(distance: 0.005, velocity: 0.05);

  /// The close: the game switcher's fold spring. Shorter than the open, no
  /// bounce, so the fold never opens back up before it shuts.
  static const CupertinoMotion close = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 200),
    snapToEnd: true,
  );

  /// Done when the fold holds two thousandths of the panel's height (under
  /// a point on the tallest menu): the last frame a panel is drawn in holds
  /// no glass a reader can see, so taking it away changes nothing.
  static const Tolerance closeTolerance = Tolerance(
    distance: 0.002,
    velocity: 0.04,
  );

  /// The scale the panel opens from.
  static const double openScale = 0.92;

  /// The open spring from [from] (0 shut, 1 open).
  static Simulation simulation({required double from, double velocity = 0}) =>
      SpringSimulation(
        open.description,
        from,
        1.0,
        velocity,
        tolerance: tolerance,
        snapToEnd: true,
      );

  /// The close spring from [from] down to 0. It starts at rest whatever
  /// the open was doing: a close begun mid-open folds from where the panel
  /// is, never past it first.
  static Simulation closeSimulation({required double from}) => SpringSimulation(
    close.description,
    from,
    0.0,
    0,
    tolerance: closeTolerance,
    snapToEnd: true,
  );

  /// The panel's scale at [progress] of the open, landed exactly on 1 so
  /// its text is never drawn resampled at rest.
  static double scaleAt(double progress) =>
      _snapToOne(openScale + (1 - openScale) * progress.clamp(0.0, 1.0));

  /// The fold's width at [left] of the close (1 as it begins, 0 shut): it
  /// narrows only to [openScale], so the panel reads as folding shut, not
  /// shrinking away.
  static double foldWidthAt(double left) => scaleAt(left);

  /// Below this many points of height the strip a fold leaves fades out as
  /// it shuts, glass and all, so its last frame draws nothing (a strip that
  /// thin has no frost to lose to the fade).
  static const double foldFadeHeight = 6;

  /// The whole panel's alpha (0 to 255) once its fold has left it
  /// [height] points tall.
  static int foldAlpha(double height) {
    if (height >= foldFadeHeight) return 255;
    return (255 * height / foldFadeHeight).round().clamp(0, 255);
  }

  /// The fold's height at [left] of the close: all of it, to nothing.
  static double foldHeightAt(double left) => _snapToOne(left.clamp(0.0, 1.0));

  static double _snapToOne(double value) =>
      (value - 1).abs() < 0.0005 ? 1.0 : value;
}

/// One anchored panel's open and fold, read off its 0-to-1 [parent]
/// progress (a route's animation, or a popover's own controller).
///
/// As an animation its value is what is left of the close: 1 while the
/// panel opens and rests, then down to 0 as it folds. That is the rows'
/// opacity ([GlassFoldFade]); the glass itself is only ever scaled
/// ([GlassFoldTransition]).
///
/// [close] starts the fold from wherever the panel is (a close begun
/// mid-open folds from that size), so the panel never jumps.
class GlassFold extends Animation<double>
    with AnimationWithParentMixin<double> {
  GlassFold(this.parent);

  @override
  final Animation<double> parent;

  double? _closeFrom;
  double _scaleFrom = 1;

  /// Whether the fold has begun.
  bool get closing => _closeFrom != null;

  /// Starts the fold. The progress must then run down to 0.
  void close() {
    if (_closeFrom != null) return;
    final from = parent.value.clamp(0.0, 1.0);
    _scaleFrom = GlassAnchoredMotion.scaleAt(from);
    _closeFrom = math.max(from, 0.001);
  }

  /// What is left of the close: 1 until it begins, then down to 0.
  @override
  double get value {
    final from = _closeFrom;
    if (from == null) return 1.0;
    return (parent.value / from).clamp(0.0, 1.0);
  }

  /// The open's scale, held where it was once the fold begins.
  double get openScale => _closeFrom == null
      ? GlassAnchoredMotion.scaleAt(parent.value)
      : _scaleFrom;

  /// The fold alone: 1 on both axes until the close begins.
  double get foldX => closing ? GlassAnchoredMotion.foldWidthAt(value) : 1.0;
  double get foldY => closing ? GlassAnchoredMotion.foldHeightAt(value) : 1.0;

  /// The panel's scale on each axis: the open's, then the fold's.
  double get scaleX => openScale * foldX;
  double get scaleY => openScale * foldY;
}

/// Scales [child] by [fold]: the open's grow and the close's fold
/// ([GlassFold.scaleX], [GlassFold.scaleY]) about [alignment], the point of
/// the panel nearest what opened it. With [includeOpen] false only the fold
/// applies (a panel whose open is scaled by something else).
///
/// Repainted, never rebuilt, as [fold] runs. A fold at nothing draws
/// nothing; taps follow the scaled panel.
class GlassFoldTransition extends SingleChildRenderObjectWidget {
  const GlassFoldTransition({
    super.key,
    required this.fold,
    this.alignment = Alignment.center,
    this.includeOpen = true,
    super.child,
  });

  final GlassFold fold;
  final AlignmentGeometry alignment;
  final bool includeOpen;

  @override
  RenderGlassFoldTransition createRenderObject(BuildContext context) =>
      RenderGlassFoldTransition(
        fold: fold,
        alignment: alignment.resolve(Directionality.maybeOf(context)),
        includeOpen: includeOpen,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlassFoldTransition renderObject,
  ) {
    renderObject
      ..fold = fold
      ..alignment = alignment.resolve(Directionality.maybeOf(context))
      ..includeOpen = includeOpen;
  }
}

/// The render object behind [GlassFoldTransition].
class RenderGlassFoldTransition extends RenderProxyBox {
  RenderGlassFoldTransition({
    required this._fold,
    required this._alignment,
    required this._includeOpen,
  });

  GlassFold _fold;
  set fold(GlassFold value) {
    if (identical(value, _fold)) return;
    if (attached) _fold.removeListener(_onFold);
    _fold = value;
    if (attached) _fold.addListener(_onFold);
    _onFold();
  }

  Alignment _alignment;
  set alignment(Alignment value) {
    if (value == _alignment) return;
    _alignment = value;
    markNeedsPaint();
  }

  bool _includeOpen;
  set includeOpen(bool value) {
    if (value == _includeOpen) return;
    _includeOpen = value;
    _onFold();
  }

  final LayerHandle<OpacityLayer> _fadeLayer = LayerHandle<OpacityLayer>();
  bool _fading = false;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _fold.addListener(_onFold);
  }

  @override
  void detach() {
    _fold.removeListener(_onFold);
    super.detach();
  }

  @override
  void dispose() {
    _fadeLayer.layer = null;
    super.dispose();
  }

  void _onFold() {
    final fading = _alpha < 255;
    if (fading != _fading) {
      _fading = fading;
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _fading;

  double get _scaleX => _includeOpen ? _fold.scaleX : _fold.foldX;
  double get _scaleY => _includeOpen ? _fold.scaleY : _fold.foldY;

  /// The last points of a fold fade out ([GlassAnchoredMotion.foldAlpha]).
  int get _alpha => _fold.closing && hasSize
      ? GlassAnchoredMotion.foldAlpha(size.height * _scaleY)
      : 255;

  Matrix4? get _transform {
    final sx = _scaleX;
    final sy = _scaleY;
    if (sx == 1 && sy == 1) return null;
    final origin = _alignment.alongSize(size);
    return Matrix4.translationValues(origin.dx, origin.dy, 0)
      ..scaleByDouble(sx, sy, 1, 1)
      ..translateByDouble(-origin.dx, -origin.dy, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    final alpha = _alpha;
    // Folded to nothing: nothing to draw.
    if (child == null || _scaleX <= 0 || _scaleY <= 0 || alpha == 0) {
      layer = null;
      _fadeLayer.layer = null;
      return;
    }
    if (alpha == 255) {
      _fadeLayer.layer = null;
      _paintFolded(context, offset);
      return;
    }
    _fadeLayer.layer = context.pushOpacity(
      offset,
      alpha,
      _paintFolded,
      oldLayer: _fadeLayer.layer,
    );
  }

  void _paintFolded(PaintingContext context, Offset offset) {
    final transform = _transform;
    if (transform == null) {
      layer = null;
      context.paintChild(child!, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      transform,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer? : null,
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      hitTestChildren(result, position: position);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (_scaleX <= 0 || _scaleY <= 0) return false;
    final transform = _transform;
    if (transform == null) {
      return super.hitTestChildren(result, position: position);
    }
    return result.addWithPaintTransform(
      transform: transform,
      position: position,
      hitTest: (result, position) =>
          super.hitTestChildren(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final own = _transform;
    if (own != null) transform.multiply(own);
  }
}

/// Hands an anchored panel's [GlassFold] to what is drawn on its glass, so
/// the rows can fade as it folds ([GlassFoldFade]).
class GlassFoldScope extends InheritedWidget {
  const GlassFoldScope({super.key, required this.fold, required super.child});

  final GlassFold fold;

  static GlassFold? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GlassFoldScope>()?.fold;

  @override
  bool updateShouldNotify(GlassFoldScope oldWidget) =>
      !identical(oldWidget.fold, fold);
}

/// The rows on an anchored panel's glass: whole until the panel folds, then
/// fading as it does (an opacity of 1 costs no layer). Outside a
/// [GlassFoldScope] it is [child] unchanged. Put it inside the glass, never
/// around it: glass under an opacity loses its frost.
class GlassFoldFade extends StatelessWidget {
  const GlassFoldFade({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fold = GlassFoldScope.maybeOf(context);
    if (fold == null) return child;
    return FadeTransition(opacity: fold, child: child);
  }
}

/// [child] stops taking taps once [fold] begins: a folding panel is on its
/// way out, and a tap meant for the page under it must reach the page.
class GlassFoldIgnorePointer extends StatefulWidget {
  const GlassFoldIgnorePointer({
    super.key,
    required this.fold,
    required this.child,
  });

  final GlassFold fold;
  final Widget child;

  @override
  State<GlassFoldIgnorePointer> createState() => _GlassFoldIgnorePointerState();
}

class _GlassFoldIgnorePointerState extends State<GlassFoldIgnorePointer> {
  late bool _closing = widget.fold.closing;

  @override
  void initState() {
    super.initState();
    widget.fold.addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(GlassFoldIgnorePointer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.fold, widget.fold)) return;
    oldWidget.fold.removeStatusListener(_onStatus);
    widget.fold.addStatusListener(_onStatus);
    _closing = widget.fold.closing;
  }

  @override
  void dispose() {
    widget.fold.removeStatusListener(_onStatus);
    super.dispose();
  }

  void _onStatus(AnimationStatus _) {
    final closing = widget.fold.closing;
    if (closing != _closing && mounted) setState(() => _closing = closing);
  }

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(ignoring: _closing, child: widget.child);
}

/// The anchored glass routes' motion ([GlassAnchoredMotion]): the open
/// spring forward, the [fold] on the close spring back, and under reduced
/// motion a close in the frame it is popped. The page reads
/// [readMotionPreference] in `buildPage`.
mixin GlassAnchoredTransition<T> on TransitionRoute<T> {
  GlassFold? _fold;
  bool _reduceMotion = false;

  /// The panel's open and fold, read off this route's progress.
  GlassFold get fold => _fold ??= GlassFold(animation!);

  /// Records whether animations are off, for the close.
  @protected
  void readMotionPreference(BuildContext context) {
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  Duration get transitionDuration => GlassAnchoredMotion.open.duration;

  /// Only used under reduced motion: the close is then instant.
  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Simulation? createSimulation({required bool forward}) {
    final controller = this.controller;
    if (forward) {
      return GlassAnchoredMotion.simulation(
        from: controller?.value ?? 0.0,
        velocity: controller?.velocity ?? 0.0,
      );
    }
    if (_reduceMotion) return null;
    return GlassAnchoredMotion.closeSimulation(from: controller?.value ?? 1.0);
  }

  @override
  bool didPop(T? result) {
    fold.close();
    return super.didPop(result);
  }
}

/// How an anchored menu sits against the rect that opened it.
enum GlassMenuAnchoring {
  /// Over the anchor, as [showMenu] places a menu: at its top, grown toward
  /// the roomier side.
  over,

  /// Off the anchor, as a dropdown drops: below it when it fits there, above
  /// it when it fits there, else over it from the roomier side.
  drop,
}

/// Builds an anchored route's panel.
typedef GlassAnchoredPanelBuilder = Widget Function(BuildContext context);

/// The one route every anchored glass menu opens on: the shared glass menu
/// (`showGlassMenu`, `showTabletSafeMenu`, `GlassPopupMenuButton`) and every
/// dropdown (`GlassDropdown`).
///
/// It dims the page with [AnchoredGlassDim] (a plain tint that rides the
/// route's spring, never a blur), leaving [hole] (the control that opened
/// it) lit; [dimmed] is false for a menu inside another popup, whose page is
/// dimmed already. The panel is placed against [anchor] ([anchoring], with
/// [gap] off a dropdown's anchor), kept 8 points inside the safe area and
/// the keyboard, and grown about the point of it nearest the anchor on the
/// open spring ([GlassAnchoredMotion]); it folds shut into that point as it
/// closes ([GlassFold]: the panel's rows fade through [GlassFoldFade]). A
/// change of the window's size closes it at once: the anchor no longer
/// marks the control.
///
/// [dismissGuard] keeps taps on the page from closing it for that long
/// after it opens (the tablets' phantom tap).
class GlassAnchoredRoute<T> extends PopupRoute<T>
    with GlassAnchoredTransition<T>
    implements TransientOverlayRoute {
  GlassAnchoredRoute({
    required this.anchor,
    required this.anchoring,
    required this.builder,
    required this.barrierLabel,
    required this.capturedThemes,
    required this._dim,
    this.hole,
    this.gap = 4,
    Duration dismissGuard = Duration.zero,
    super.traversalEdgeBehavior,
  }) : _dismissGuard = dismissGuard,
       _guarding = dismissGuard > Duration.zero;

  /// The rect that opened the menu, in the navigator's overlay coordinates.
  final Rect anchor;
  final GlassMenuAnchoring anchoring;
  final GlassAnchoredPanelBuilder builder;
  final CapturedThemes capturedThemes;

  /// The control that opened the menu, left out of the dim.
  final RRect? hole;

  /// Between a dropped panel and its anchor.
  final double gap;

  final Color _dim;

  @override
  final String barrierLabel;

  final Duration _dismissGuard;
  Timer? _guardTimer;
  bool _guarding;

  /// Whether the page under the menu is dimmed.
  bool get dimmed => _dim.a > 0;

  /// The route paints its own dim (it leaves [hole] lit); the barrier only
  /// takes the dismissing tap.
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => !_guarding;

  @override
  TickerFuture didPush() {
    if (_guarding) {
      _guardTimer = Timer(_dismissGuard, () {
        _guarding = false;
        // Rebuilds the barrier so it picks up the new dismissible value.
        if (isActive) changedInternalState();
      });
    }
    return super.didPush();
  }

  @override
  void dispose() {
    _guardTimer?.cancel();
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final media = MediaQuery.of(context);
    readMotionPreference(context);
    final fold = this.fold;
    final panel = GlassFoldScope(
      fold: fold,
      child: capturedThemes.wrap(Builder(builder: builder)),
    );
    return WindowMetricsDismissal(
      onChanged: () {
        if (isActive) navigator?.removeRoute(this);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (dimmed)
            IgnorePointer(
              child: CustomPaint(
                painter: GlassScrimPainter(
                  color: _dim,
                  hole: hole,
                  progress: animation,
                ),
              ),
            ),
          MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
            removeLeft: true,
            removeRight: true,
            child: GlassMenuPlacement(
              position: anchor,
              anchoring: anchoring,
              gap: gap,
              padding: media.padding.copyWith(
                bottom: media.padding.bottom > media.viewInsets.bottom
                    ? media.padding.bottom
                    : media.viewInsets.bottom,
              ),
              avoidBounds: DisplayFeatureSubScreen.avoidBounds(media).toSet(),
              textDirection: Directionality.of(context),
              fold: media.disableAnimations ? null : fold,
              // Its own layer: the springs move the panel without
              // repainting the glass or its rows.
              child: RepaintBoundary(child: panel),
            ),
          ),
        ],
      ),
    );
  }
}

/// The anchored menus' dim over the page ([AnchoredGlassDim]), leaving
/// [hole] (the control that opened the menu, in the painter's coordinates)
/// lit, so the trigger still reads, and reads as attached to its menu. A
/// plain tint, never a blur.
///
/// With [progress] the tint rides it (0 none, 1 [color]) and repaints on
/// its own, with no rebuild.
class GlassScrimPainter extends CustomPainter {
  GlassScrimPainter({required this.color, this.hole, this.progress})
    : super(repaint: progress);

  /// The dim at rest.
  final Color color;
  final RRect? hole;
  final Animation<double>? progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = (progress?.value ?? 1.0).clamp(0.0, 1.0);
    final alpha = color.a * t;
    if (alpha <= 0) return;
    final paint = Paint()..color = color.withValues(alpha: alpha);
    final rect = Offset.zero & size;
    final cut = hole;
    if (cut == null) {
      canvas.drawRect(rect, paint);
      return;
    }
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect)
        ..addRRect(cut),
      paint,
    );
  }

  @override
  bool shouldRepaint(GlassScrimPainter old) =>
      old.color != color || old.hole != hole || old.progress != progress;
}

// Material's menu metrics ([showMenu]): 8 points from the screen's edges.
const double _kScreenPadding = 8;

/// Places an anchored menu against [position] (a rect relative to this box,
/// usually the overlay): [GlassMenuAnchoring.over] where [showMenu] would
/// put it, [GlassMenuAnchoring.drop] off it as a dropdown drops, [gap]
/// away. Either way it stays 8 points inside [padding] and inside the
/// display sub-screen nearest the anchor. [fold] (null for none) scales the
/// menu about the point of it nearest the anchor's centre, so it grows out
/// of what opened it and folds shut back into it.
///
/// Fills the space it is given and hit-tests only the menu, so taps beside
/// it reach the route's barrier.
class GlassMenuPlacement extends SingleChildRenderObjectWidget {
  const GlassMenuPlacement({
    super.key,
    required this.position,
    this.anchoring = GlassMenuAnchoring.over,
    this.gap = 0,
    this.padding = EdgeInsets.zero,
    this.avoidBounds = const <Rect>{},
    this.textDirection = TextDirection.ltr,
    this.fold,
    required Widget super.child,
  });

  final Rect position;
  final GlassMenuAnchoring anchoring;
  final double gap;
  final EdgeInsets padding;
  final Set<Rect> avoidBounds;
  final TextDirection textDirection;
  final GlassFold? fold;

  @override
  RenderGlassMenuPlacement createRenderObject(BuildContext context) =>
      RenderGlassMenuPlacement(
        position: position,
        anchoring: anchoring,
        gap: gap,
        padding: padding,
        avoidBounds: avoidBounds,
        textDirection: textDirection,
        fold: fold,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlassMenuPlacement renderObject,
  ) {
    renderObject
      ..position = position
      ..anchoring = anchoring
      ..gap = gap
      ..padding = padding
      ..avoidBounds = avoidBounds
      ..textDirection = textDirection
      ..fold = fold;
  }
}

/// The render object behind [GlassMenuPlacement].
class RenderGlassMenuPlacement extends RenderProxyBox {
  RenderGlassMenuPlacement({
    required this._position,
    this._anchoring = GlassMenuAnchoring.over,
    this._gap = 0,
    this._padding = EdgeInsets.zero,
    this._avoidBounds = const <Rect>{},
    this._textDirection = TextDirection.ltr,
    this._fold,
  });

  Rect _position;
  set position(Rect value) {
    if (value == _position) return;
    _position = value;
    markNeedsLayout();
  }

  GlassMenuAnchoring _anchoring;
  set anchoring(GlassMenuAnchoring value) {
    if (value == _anchoring) return;
    _anchoring = value;
    markNeedsLayout();
  }

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  EdgeInsets _padding;
  set padding(EdgeInsets value) {
    if (value == _padding) return;
    _padding = value;
    markNeedsLayout();
  }

  Set<Rect> _avoidBounds;
  set avoidBounds(Set<Rect> value) {
    if (setEquals(value, _avoidBounds)) return;
    _avoidBounds = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  GlassFold? _fold;
  set fold(GlassFold? value) {
    if (identical(value, _fold)) return;
    if (attached) _fold?.removeListener(_onFold);
    _fold = value;
    if (attached) _fold?.addListener(_onFold);
    _onFold();
  }

  final LayerHandle<OpacityLayer> _fadeLayer = LayerHandle<OpacityLayer>();
  bool _fading = false;

  void _onFold() {
    final fading = _alpha < 255;
    if (fading != _fading) {
      _fading = fading;
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _fading;

  /// The last points of a fold fade out ([GlassAnchoredMotion.foldAlpha]).
  int get _alpha {
    final fold = _fold;
    final menu = child;
    if (fold == null || !fold.closing || menu == null || !menu.hasSize) {
      return 255;
    }
    return GlassAnchoredMotion.foldAlpha(menu.size.height * _scaleY);
  }

  @override
  void dispose() {
    _fadeLayer.layer = null;
    super.dispose();
  }

  /// Where the menu sits, and the point (in its own box) it scales about.
  Offset _offset = Offset.zero;
  Offset _origin = Offset.zero;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _fold?.addListener(_onFold);
  }

  @override
  void detach() {
    _fold?.removeListener(_onFold);
    super.detach();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    final menu = child;
    if (menu == null) return;
    // At most the box less 8 points (and the unsafe area) on every side.
    menu.layout(
      BoxConstraints.loose(
        size,
      ).deflate(const EdgeInsets.all(_kScreenPadding) + _padding),
      parentUsesSize: true,
    );
    final menuSize = menu.size;
    final anchor = _position;
    final screens = DisplayFeatureSubScreen.subScreensInBounds(
      Offset.zero & size,
      _avoidBounds,
    );
    var screen = screens.first;
    for (final candidate in screens) {
      if ((candidate.center - anchor.center).distance <
          (screen.center - anchor.center).distance) {
        screen = candidate;
      }
    }
    _offset = switch (_anchoring) {
      GlassMenuAnchoring.over => _over(screen, menuSize),
      GlassMenuAnchoring.drop => _drop(screen, menuSize),
    };
    // The point of the menu nearest the anchor's centre.
    final local = anchor.center - _offset;
    _origin = Offset(
      local.dx.clamp(0.0, menuSize.width),
      local.dy.clamp(0.0, menuSize.height),
    );
  }

  /// [showMenu]'s placement: at the anchor's top, aligned to the edge of it
  /// nearer the screen's edge, then fitted into [screen].
  Offset _over(Rect screen, Size menu) {
    final anchor = _position;
    final left = anchor.left;
    final right = size.width - anchor.right;
    final double x;
    if (left > right) {
      // Nearer the right edge: grow to the left, aligned to the right edge.
      x = anchor.right - menu.width;
    } else if (left < right) {
      x = anchor.left;
    } else {
      x = switch (_textDirection) {
        TextDirection.rtl => anchor.right - menu.width,
        TextDirection.ltr => anchor.left,
      };
    }
    return _fit(screen, menu, Offset(x, anchor.top));
  }

  /// A dropdown's placement: below the anchor when it fits there, above it
  /// when it fits there, else over it from the roomier side, so no row is
  /// ever off screen ([DropdownButton]'s menu does the same).
  Offset _drop(Rect screen, Size menu) {
    final anchor = _position;
    final pad = _padding;
    final x = switch (_textDirection) {
      TextDirection.rtl => anchor.right - menu.width,
      TextDirection.ltr => anchor.left,
    };
    final top = screen.top + _kScreenPadding + pad.top;
    final bottom = screen.bottom - _kScreenPadding - pad.bottom;
    final below = bottom - (anchor.bottom + _gap);
    final above = anchor.top - _gap - top;
    final double y;
    if (menu.height <= below) {
      y = anchor.bottom + _gap;
    } else if (menu.height <= above) {
      y = anchor.top - _gap - menu.height;
    } else {
      y = below >= above ? bottom - menu.height : top;
    }
    return _fit(screen, menu, Offset(x, y));
  }

  Offset _fit(Rect screen, Size menu, Offset wanted) {
    var x = wanted.dx;
    var y = wanted.dy;
    final pad = _padding;
    if (x < screen.left + _kScreenPadding + pad.left) {
      x = screen.left + _kScreenPadding + pad.left;
    } else if (x + menu.width > screen.right - _kScreenPadding - pad.right) {
      x = screen.right - menu.width - _kScreenPadding - pad.right;
    }
    if (y < screen.top + _kScreenPadding + pad.top) {
      y = screen.top + _kScreenPadding + pad.top;
    } else if (y + menu.height > screen.bottom - _kScreenPadding - pad.bottom) {
      y = screen.bottom - menu.height - _kScreenPadding - pad.bottom;
    }
    return Offset(x, y);
  }

  double get _scaleX => _fold?.scaleX ?? 1.0;
  double get _scaleY => _fold?.scaleY ?? 1.0;

  Matrix4 get _transform {
    final sx = _scaleX;
    final sy = _scaleY;
    final transform = Matrix4.translationValues(_offset.dx, _offset.dy, 0);
    if (sx != 1 || sy != 1) {
      transform
        ..translateByDouble(_origin.dx, _origin.dy, 0, 1)
        ..scaleByDouble(sx, sy, 1, 1)
        ..translateByDouble(-_origin.dx, -_origin.dy, 0, 1);
    }
    return transform;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final alpha = _alpha;
    // Folded to nothing: nothing to draw.
    if (child == null || _scaleX <= 0 || _scaleY <= 0 || alpha == 0) {
      layer = null;
      _fadeLayer.layer = null;
      return;
    }
    if (alpha == 255) {
      _fadeLayer.layer = null;
      _paintPlaced(context, offset);
      return;
    }
    _fadeLayer.layer = context.pushOpacity(
      offset,
      alpha,
      _paintPlaced,
      oldLayer: _fadeLayer.layer,
    );
  }

  void _paintPlaced(PaintingContext context, Offset offset) {
    final menu = child!;
    final sx = _scaleX;
    final sy = _scaleY;
    if (sx == 1 && sy == 1) {
      layer = null;
      context.paintChild(menu, offset + _offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      (context, offset) => context.paintChild(menu, offset),
      oldLayer: layer is TransformLayer ? layer as TransformLayer? : null,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final menu = child;
    if (menu == null || _scaleX <= 0 || _scaleY <= 0) return false;
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) => menu.hitTest(result, position: position),
    );
  }

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_transform);
  }
}
