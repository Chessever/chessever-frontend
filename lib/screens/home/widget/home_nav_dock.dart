import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/home/start_screen.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar_widget.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:chessever2/widgets/search_mode/search_count_badge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The phone dock's geometry: one frosted capsule floating over the foot of
/// the page, [normalHeight] tall across the screen. Heading back up a page
/// (the section's chrome at 1) it stands there; reading on (the chrome at
/// 0) it has left whole: slid down past the screen's edge ([slide]) and
/// faded out.
///
/// Its slot in the Scaffold is [extent] tall whether the capsule is there
/// or not, so the capsule coming and going never lays the page out again:
/// the page runs under the slot ([Scaffold.extendBody]) and pads its end by
/// it ([MediaQuery.paddingOf]), so a list's last row clears the capsule
/// when it is shown and nothing jumps while it moves.
@immutable
class HomeNavMetrics {
  const HomeNavMetrics({
    required this.gap,
    required this.count,
    required this.screenWidth,
    this.inset = 0,
  });

  /// [count] marks on the dock of the screen [context] is on.
  ///
  /// The gap under the capsule rides the system's own bottom inset: on an
  /// iPhone the capsule sits a little into the home indicator's strip
  /// (`inset - 12`, 22 on a Face ID phone), never closer than 12 to the
  /// screen's edge; on Android it stays wholly above the gesture bar or the
  /// three buttons, which it must never cover.
  factory HomeNavMetrics.of(BuildContext context, {required int count}) {
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return HomeNavMetrics(
      gap: ios ? math.max(minGap, inset - 12) : math.max(minGap, inset),
      count: count,
      screenWidth: MediaQuery.sizeOf(context).width,
      inset: inset,
    );
  }

  /// Space under the capsule, to the screen's bottom edge.
  final double gap;

  /// Marks on the dock.
  final int count;
  final double screenWidth;

  /// The system's own strip at the screen's foot (the home indicator's,
  /// the gesture bar's, the three buttons'): all that covers the page's
  /// foot with the dock away.
  final double inset;

  /// The capsule's height.
  static const double normalHeight = 56;

  /// The least space between the capsule and the screen's bottom edge.
  static const double minGap = 12;

  /// The capsule's margin to either side of the screen, and the widest it
  /// ever gets (a landscape phone).
  static const double sideMargin = 16;
  static const double maxWidth = 440;

  /// Inside the capsule's round ends, before the first mark and after the
  /// last: the marks never touch the rim.
  static const double padding = 10;

  /// How far below the capsule its contact shadow reaches, with room to
  /// spare: leaving, the capsule slides this much past the screen's edge
  /// too, so no smear of it is left behind.
  static const double shadowReach = 12;

  /// The Scaffold's slot: constant, so the capsule coming and going moves
  /// the dock alone, never the page.
  double get extent => gap + normalHeight;

  /// How far the page's foot is covered with the dock away: the system's
  /// own strip ([inset]), the room a page centred between the bars keeps
  /// clear of (Feed).
  double get awayExtent => inset;

  /// [awayExtent], under the name Feed reads it by (from when the dock drew
  /// in to a smaller capsule instead of leaving).
  double get compactExtent => awayExtent;

  /// How far floating buttons over the dock come down as it leaves: from
  /// the end-float corner over the capsule to the one over the system's own
  /// strip, where a page with no dock stands them.
  double get ride => math.max(0.0, extent - inset);

  /// How far the capsule slides to be wholly off the screen, its contact
  /// shadow included.
  double get slide => gap + normalHeight + shadowReach;

  double get normalWidth =>
      math.max(0, math.min(screenWidth - 2 * sideMargin, maxWidth));

  @override
  bool operator ==(Object other) =>
      other is HomeNavMetrics &&
      other.gap == gap &&
      other.count == count &&
      other.screenWidth == screenWidth &&
      other.inset == inset;

  @override
  int get hashCode => Object.hash(gap, count, screenWidth, inset);
}

/// The dock's metrics, for a page under it that composes itself between the
/// bars (Feed keeps its posts centred in the room the dock leaves) or rides
/// buttons over it (Events' Live first). Absent on a tablet, which has the rail
/// instead, and on pushed pages.
class HomeNavScope extends InheritedWidget {
  const HomeNavScope({super.key, required this.metrics, required super.child});

  final HomeNavMetrics metrics;

  static HomeNavMetrics? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeNavScope>()?.metrics;

  @override
  bool updateShouldNotify(HomeNavScope oldWidget) =>
      metrics != oldWidget.metrics;
}

/// The phone's way between sections: the section marks on one frosted
/// capsule ([GlassSurface], the floating buttons' own material) floating
/// over the page.
///
/// It follows the section's scroll chrome ([chrome]), on the chrome's own
/// value and so on its spring: reading on, the capsule slides down past the
/// screen's edge and fades out at once, leaving the whole page to the
/// reader; heading back up, it slides back and fades in. The reader's
/// speed decides how quickly (the chrome's spring takes it: a flick brings
/// the dock straight back, a slow drag eases it in). With no chrome (a
/// test, a still section) it stands.
///
/// Only paint and compositing change as it moves: the capsule is moved
/// where it is painted, never laid out again, its glass fades through its
/// own material ([GlassFade]: the frost is never put under an opacity), the
/// marks fade in a layer of their own. Gone, it paints nothing, takes no
/// taps (the page under it takes them) and is out of the semantics tree;
/// mostly gone, it already takes no taps.
///
/// Its slot is [HomeNavMetrics.extent] tall at every frame, so the page
/// under it is never laid out again as it comes and goes. Each mark's
/// target runs from the capsule's top down to the screen's edge, so the
/// strip under the capsule is never dead.
///
/// A soft scrim of the page's own ground ([scrim]) rises behind it, so the
/// capsule and the system's own bar under it read over any content. It
/// fades in over many eased steps, with no edge of its own, and leaves with
/// the dock. Feed has its own deck there and turns it off.
class HomeNavDock extends ConsumerWidget {
  const HomeNavDock({super.key, this.chrome, this.scrim = true});

  /// How much of the section's chrome is shown: 1 the dock in place, 0 the
  /// dock gone. Null stands it in place.
  final ValueListenable<double>? chrome;

  /// Whether the page's ground rises behind the dock.
  final bool scrim;

  /// How far the scrim reaches above the dock's slot.
  static const double scrimReach = 24;

  /// Under this much of the chrome the dock takes no taps: it is mostly
  /// past the screen's edge and nearly faded, on its way out or only just
  /// arriving.
  static const double tapFloor = 0.5;

  /// How much of the dock is drawn at [shown] of the chrome: one for one,
  /// so it fades exactly as far as it has slid.
  static double fadeAt(double shown) => shown.clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(visibleBottomNavItemsProvider);
    final selected = ref.watch(selectedBottomNavBarItemProvider);
    final unread = ref.watch(inboxHasUnreadProvider);
    final botvinnikUnread = unread && items.contains(BottomNavBarItem.botvinnik)
        ? ref.watch(inboxUnreadCountProvider)
        : 0;
    final m = HomeNavMetrics.of(context, count: items.length);
    final shown = chrome;
    final fade = shown == null ? null : _DockFade(shown);

    final width = m.normalWidth;
    final left = (m.screenWidth - width) / 2;
    final slotWidth = items.isEmpty
        ? 0.0
        : math.max(0.0, width - 2 * HomeNavMetrics.padding) / items.length;

    Widget glass = GlassSurface(
      key: const ValueKey('home-nav-capsule'),
      borderRadius: BorderRadius.circular(HomeNavMetrics.normalHeight / 2),
      child: const SizedBox.expand(),
    );
    Widget marks = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          BottomNavBarWidget(
            key: bottomNavBarItemKey(item),
            width: slotWidth,
            bottomInset: m.gap,
            semanticsValue: switch (item) {
              BottomNavBarItem.botvinnik when botvinnikUnread > 0 =>
                '$botvinnikUnread unread Inbox ${botvinnikUnread == 1 ? 'message' : 'messages'}',
              BottomNavBarItem.profile when unread => 'Unread Inbox messages',
              _ => null,
            },
            isSelected: selected == item,
            dotId: item == BottomNavBarItem.botvinnik && botvinnikUnread > 0
                ? null
                : bottomNavBarDotIds[item],
            onTap: () => selectBottomNavBarItem(ref, item),
            glyph: (ink, side) {
              final mark = bottomNavBarGlyph(
                item,
                ink: ink,
                side: side,
                selected: selected == item,
              );
              if (item != BottomNavBarItem.botvinnik || botvinnikUnread == 0) {
                return mark;
              }
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  mark,
                  PositionedDirectional(
                    top: -6,
                    end: -10,
                    child: IgnorePointer(
                      child: SearchCountBadge(
                        key: const ValueKey('botvinnik-dock-unread-badge'),
                        count: botvinnikUnread,
                        diameter: 16,
                      ),
                    ),
                  ),
                ],
              );
            },
            title: namesBottomNavBarIcons[item]!,
            onLongPress: () =>
                unawaited(makeStartScreenDefault(context, ref, section: item)),
          ),
      ],
    );
    if (fade != null) {
      // The glass scales its own plate, rim, shadow and frost; the marks,
      // which hold no glass, fade in their own layer.
      glass = GlassFade(opacity: fade, child: glass);
      marks = FadeTransition(opacity: fade, child: marks);
    }

    final capsule = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: left,
          width: width,
          bottom: m.gap,
          height: HomeNavMetrics.normalHeight,
          child: glass,
        ),
        // The marks: each target from the capsule's top to the screen's
        // edge, its mark centred in the capsule.
        Positioned(
          left: left + HomeNavMetrics.padding,
          width: math.max(0, width - 2 * HomeNavMetrics.padding),
          bottom: 0,
          height: HomeNavMetrics.normalHeight + m.gap,
          child: marks,
        ),
      ],
    );

    return RepaintBoundary(
      child: SizedBox(
        key: const ValueKey('home-nav-dock'),
        height: m.extent,
        width: double.infinity,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            if (scrim)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: m.extent + scrimReach,
                child: IgnorePointer(child: _DockScrim(shown: shown)),
              ),
            if (shown == null)
              capsule
            else
              _DockSlide(shown: shown, slide: m.slide, child: capsule),
          ],
        ),
      ),
    );
  }
}

/// The dock's fade as an [Animation], read off the chrome's value
/// ([HomeNavDock.fadeAt]) for [GlassFade] and [FadeTransition], which then
/// follow the chrome with no rebuild of the dock. Equal for one chrome, so
/// a rebuilt dock hands its glass and marks the same fade.
class _DockFade extends Animation<double> {
  _DockFade(this.shown);

  final ValueListenable<double> shown;

  @override
  double get value => HomeNavDock.fadeAt(shown.value);

  @override
  AnimationStatus get status {
    final v = value;
    if (v <= 0) return AnimationStatus.dismissed;
    if (v >= 1) return AnimationStatus.completed;
    return AnimationStatus.forward;
  }

  @override
  void addListener(VoidCallback listener) => shown.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => shown.removeListener(listener);

  // Nothing reads the fade's status changes: the glass and the marks follow
  // its value.
  @override
  void addStatusListener(AnimationStatusListener listener) {}

  @override
  void removeStatusListener(AnimationStatusListener listener) {}

  @override
  bool operator ==(Object other) =>
      other is _DockFade && identical(other.shown, shown);

  @override
  int get hashCode => identityHashCode(shown);
}

/// Moves the dock's capsule down by [slide] times how far the chrome has
/// gone (`1 - shown`), where it is painted: nothing is laid out or rebuilt
/// as it moves, and taps and the semantics tree follow it to where it is
/// drawn. Gone, it paints nothing and is out of the semantics tree; under
/// [HomeNavDock.tapFloor] it takes no taps, which fall through to the page.
class _DockSlide extends SingleChildRenderObjectWidget {
  const _DockSlide({
    required this.shown,
    required this.slide,
    required Widget super.child,
  });

  final ValueListenable<double> shown;
  final double slide;

  @override
  _RenderDockSlide createRenderObject(BuildContext context) =>
      _RenderDockSlide(shown: shown, slide: slide);

  @override
  void updateRenderObject(BuildContext context, _RenderDockSlide renderObject) {
    renderObject
      ..shown = shown
      ..slide = slide;
  }
}

class _RenderDockSlide extends RenderProxyBox {
  _RenderDockSlide({required this._shown, required this._slide});

  ValueListenable<double> _shown;
  set shown(ValueListenable<double> value) {
    if (identical(value, _shown)) return;
    if (attached) {
      _shown.removeListener(_moved);
      value.addListener(_moved);
    }
    _shown = value;
    _moved();
  }

  double _slide;
  set slide(double value) {
    if (value == _slide) return;
    _slide = value;
    markNeedsPaint();
  }

  /// Whether the dock was gone at the last move, to tell the semantics tree
  /// only when that changes.
  bool _gone = false;

  double get _f => _shown.value.clamp(0.0, 1.0);

  double get _dy => (1 - _f) * _slide;

  void _moved() {
    markNeedsPaint();
    final gone = _f <= 0;
    if (gone != _gone) {
      _gone = gone;
      markNeedsSemanticsUpdate();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _shown.addListener(_moved);
    _gone = _f <= 0;
  }

  @override
  void detach() {
    _shown.removeListener(_moved);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || _f <= 0) return;
    context.paintChild(child, offset.translate(0, _dy));
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_f < HomeNavDock.tapFloor) return false;
    return super.hitTest(result, position: position);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: Offset(0, _dy),
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(0, _dy, 0, 1);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_f > 0) super.visitChildrenForSemantics(visitor);
  }
}

/// The page's ground rising behind the dock: from nothing at its top to
/// [_strength] at the screen's edge, over many eased steps, so no line or
/// band shows where it starts. It leaves with the dock, its strength
/// scaled by the dock's fade where it is painted (no layer, no rebuild).
class _DockScrim extends StatelessWidget {
  const _DockScrim({required this.shown});

  /// The chrome the dock follows; null stands the scrim in full.
  final ValueListenable<double>? shown;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _ScrimPainter(ground: context.colors.background, shown: shown),
    size: Size.infinite,
  );
}

class _ScrimPainter extends CustomPainter {
  _ScrimPainter({required this.ground, required this.shown})
    : super(repaint: shown);

  final Color ground;
  final ValueListenable<double>? shown;

  static const double _strength = 0.92;
  static const int _steps = 14;

  /// The stops, and each one's share of [_strength]: eased in and out
  /// (smoothstep), so there is no slope break at either end.
  static final List<double> _stops = [
    for (var i = 0; i < _steps; i++) i / (_steps - 1),
  ];
  static final List<double> _eased = [
    for (final t in _stops) t * t * (3 - 2 * t),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final f = HomeNavDock.fadeAt(shown?.value ?? 1);
    if (f <= 0 || size.isEmpty) return;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          for (final e in _eased)
            ground.withValues(alpha: ground.a * _strength * e * f),
        ],
        stops: _stops,
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_ScrimPainter oldDelegate) =>
      oldDelegate.ground != ground || !identical(oldDelegate.shown, shown);
}
