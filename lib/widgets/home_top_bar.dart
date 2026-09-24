import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/search_motion.dart';
import 'package:chessever2/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The one top bar every home tab (Events, Feed, For You, Library) wears.
///
/// Each tab owns only its content slot (a search field, a title) and its
/// trailing controls. Everything they share is fixed here, so switching tabs
/// never moves or resizes it: the inset from the status bar, the side
/// gutter, the profile avatar (size, ring, tap target) and the gap after it.
///
/// Every value is Events' shipped bar, which is the reference.
class HomeTopBarMetrics {
  const HomeTopBarMetrics._();

  /// The size handed to [UserAvatar], which draws the circle at `.w`.
  static const double avatarSize = 44;

  /// Between the avatar and the tab's content.
  static double get gap => 16.w;

  /// The bar's left and right gutter.
  static double get horizontalPadding =>
      ResponsiveHelper.adaptive(phone: 20.sp, tablet: 32.sp);

  /// From the top of the screen to the top of the bar.
  static double topInset(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).top + 24.h;

  /// The search field at rest: `SimpleSearchBar`'s 4.sp vertical padding
  /// around Events' filter tile (8.sp padding, 20.h glyph).
  static double get fieldHeight => 8.sp + 16.sp + 20.h;

  /// The search field's type: `SimpleSearchBar` sets its text and its hint
  /// in it.
  static TextStyle get fieldTextStyle => AppTypography.textMdRegular;

  /// The search field's height at the ambient text size: its 4.sp vertical
  /// padding around the taller of the filter tile and one line of
  /// [fieldTextStyle]. The tile is the taller up to about 1.5x, so this is
  /// [fieldHeight] there; past it the line is, and the field grows with the
  /// system text size.
  ///
  /// Every tab's row stands at least this tall, field or not, so the avatar
  /// lands on the same line on every tab at any text size.
  static double fieldExtent(BuildContext context) {
    final style = fieldTextStyle;
    final painter = TextPainter(
      text: TextSpan(style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      // A TextField forces its strut to its own style, so its line is
      // exactly this tall whatever it holds.
      strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
    );
    final line = painter.preferredLineHeight;
    painter.dispose();
    return 8.sp + math.max(16.sp + 20.h, line);
  }

  /// The tallest any control other than the avatar may stand: the avatar
  /// circle as drawn. The row takes the taller of the avatar (a premium ring
  /// adds its own padding, the same on every tab because the avatar is the
  /// same widget) and [fieldExtent], the same on every tab; a taller control
  /// would grow one tab's row and move its avatar.
  static double get controlExtent => avatarSize.w;

  /// The smallest target any control in the bar answers taps across, however
  /// small it is drawn: 44pt square (see [HomeTopBarTapTarget]).
  static const double minTapTarget = 44;

  /// The largest text scale the bar's chrome follows: the avatar's initials,
  /// the tabs' own controls and Feed's title, which is the scale Feed's page
  /// stops at. The search field's text is not chrome: it follows the system
  /// text size, and the row grows with it on every tab ([fieldExtent]).
  static const double maxTextScale = 1.4;
}

/// Positions a home bar row: [HomeTopBarMetrics.topInset] below the top of
/// the screen, [HomeTopBarMetrics.horizontalPadding] in from each side,
/// centred at the tablet content width.
///
/// [trailingOpticalInset] pulls the right gutter in for a row whose last
/// control is a glyph centred in a wider tap target, so the glyph's own edge
/// lands on the gutter rather than its invisible target.
///
/// The frame also carries the bar's tap targets: a control wrapped in a
/// [HomeTopBarTapTarget] answers taps a little past its drawn edge, into the
/// gutter, the inset above the row and the gap below it.
class HomeTopBarFrame extends StatelessWidget {
  const HomeTopBarFrame({
    super.key,
    required this.child,
    this.trailingOpticalInset = 0,
  });

  final Widget child;
  final double trailingOpticalInset;

  @override
  Widget build(BuildContext context) {
    final side = HomeTopBarMetrics.horizontalPadding;
    return _TapTargetScope(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              side,
              HomeTopBarMetrics.topInset(context),
              side - trailingOpticalInset,
              0,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The profile avatar that opens the home sidebar, identical on every tab.
///
/// The whole avatar is one tap target, the premium ring included, and it
/// reads as a single "Open sidebar" button to a screen reader. It is never
/// placed in a box that fixes its height: squeezing the ringed avatar into a
/// 44pt row is what turned it into an oval.
class HomeTopBarAvatar extends StatelessWidget {
  const HomeTopBarAvatar({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    final VoidCallback? handleTap = tap == null
        ? null
        : () {
            HapticFeedbackService.navigation();
            tap();
          };
    // Its own node carrying the tap: without `container` the label would
    // merge into whatever encloses the bar, and `excludeSemantics` would
    // drop the gesture's action, leaving a screen reader nothing to press.
    return Semantics(
      container: true,
      button: handleTap != null,
      label: 'Open sidebar',
      onTap: handleTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: handleTap,
        child: const IgnorePointer(
          child: UserAvatar(size: HomeTopBarMetrics.avatarSize),
        ),
      ),
    );
  }
}

/// The row inside a home bar: avatar, the tab's [content], its [trailing]
/// controls.
///
/// While [focusNode] has focus the row hands its width to the content (the
/// search field): the avatar and the trailing controls squeeze out on
/// [SearchMotion.morph], the spring the field's own morph runs on, and come
/// back when it lets go. Only width closes, so the row never changes height.
///
/// The row stands as tall as the taller of the avatar and the search field at
/// the ambient text size ([HomeTopBarMetrics.fieldExtent]) on every tab,
/// field or not, and centres everything on that height. So the search
/// field's text follows the system text size, as Events' bar always has, and
/// the avatar still lands on the same line on every tab: when a large text
/// size grows the field, every tab's row grows with it.
///
/// Invariant: nothing in [content] or [trailing] may stand taller than that.
/// A control stays within [HomeTopBarMetrics.controlExtent]; a field built
/// from `SimpleSearchBar` stands exactly [HomeTopBarMetrics.fieldExtent].
///
/// The chrome (the avatar's initials, the [trailing] controls) stops growing
/// at [HomeTopBarMetrics.maxTextScale]; the controls are drawn at a fixed
/// size. The avatar and every trailing control sit in a
/// [HomeTopBarTapTarget], so each answers taps across at least
/// [HomeTopBarMetrics.minTapTarget] square however small the phone draws
/// it, without the row's layout changing.
class HomeTopBarRow extends StatelessWidget {
  const HomeTopBarRow({
    super.key,
    required this.content,
    this.showAvatar = true,
    this.onAvatarTap,
    this.avatarKey,
    this.focusNode,
    this.trailing = const <Widget>[],
  });

  final Widget content;
  final bool showAvatar;
  final VoidCallback? onAvatarTap;
  final Key? avatarKey;
  final FocusNode? focusNode;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    Widget chrome(Widget child) => MediaQuery.withClampedTextScaling(
      maxScaleFactor: HomeTopBarMetrics.maxTextScale,
      child: child,
    );
    return Row(
      children: [
        // No width: only holds the row at the field's height, so a tab
        // without a field stands exactly as tall as one with it.
        SizedBox(height: HomeTopBarMetrics.fieldExtent(context)),
        if (showAvatar)
          _FocusSqueeze(
            focusNode: focusNode,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HomeTopBarTapTarget(
                  child: chrome(
                    HomeTopBarAvatar(key: avatarKey, onTap: onAvatarTap),
                  ),
                ),
                SizedBox(width: HomeTopBarMetrics.gap),
              ],
            ),
          ),
        Expanded(child: content),
        if (trailing.isNotEmpty)
          _FocusSqueeze(
            focusNode: focusNode,
            child: chrome(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final control in trailing)
                    HomeTopBarTapTarget(
                      // Keyed as the control is, so the row still matches
                      // its controls by key when the list changes.
                      key: switch (control.key) {
                        final Key key => ValueKey<Key>(key),
                        null => null,
                      },
                      child: control,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A [HomeTopBarRow] in its [HomeTopBarFrame], for tabs whose bar is not the
/// Events search bar. A null [onOpenSidebar] means there is no sidebar to
/// open (the screen is outside the home shell), so no avatar is offered
/// rather than a dead control.
class HomeTopBar extends StatelessWidget {
  const HomeTopBar({
    super.key,
    required this.content,
    this.onOpenSidebar,
    this.avatarKey,
    this.focusNode,
    this.trailing = const <Widget>[],
    this.trailingOpticalInset = 0,
  });

  final Widget content;
  final VoidCallback? onOpenSidebar;
  final Key? avatarKey;
  final FocusNode? focusNode;
  final List<Widget> trailing;
  final double trailingOpticalInset;

  @override
  Widget build(BuildContext context) {
    return HomeTopBarFrame(
      trailingOpticalInset: trailingOpticalInset,
      child: HomeTopBarRow(
        content: content,
        showAvatar: onOpenSidebar != null,
        onAvatarTap: onOpenSidebar,
        avatarKey: avatarKey,
        focusNode: focusNode,
        trailing: trailing,
      ),
    );
  }
}

/// The search field's surface in a home bar, at [lift] 0 (resting) to 1
/// (focused).
///
/// Tonal elevation with a self-coloured edge: the fill steps a hair toward
/// the ink and the stroke is that same surface lifted further, so focus reads
/// as a lit lip rather than a drawn outline. Works in both themes because
/// `textPrimary` flips.
class HomeSearchFieldSurface extends StatelessWidget {
  const HomeSearchFieldSurface({
    super.key,
    required this.lift,
    required this.child,
  });

  final double lift;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = lift.clamp(0.0, 1.0);
    final colors = context.colors;
    final fill = Color.lerp(colors.surface, colors.textPrimary, 0.04 * t)!;
    return DecoratedBox(
      key: const ValueKey('simple-search-field-surface'),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(
          color: Color.lerp(fill, colors.textPrimary, 0.16 * t)!,
        ),
      ),
      // DecoratedBox does not inset for its border, so the stroke costs no
      // layout and the field cannot jump by a pixel when it lights up.
      child: child,
    );
  }
}

/// Squeezes [child] out of the row while [focusNode] has focus. Listening
/// here keeps the collapse off the host screen's build, so the keyboard
/// coming up never rebuilds the tab.
class _FocusSqueeze extends StatelessWidget {
  const _FocusSqueeze({required this.focusNode, required this.child});

  final FocusNode? focusNode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final node = focusNode;
    if (node == null) return child;
    return ListenableBuilder(
      listenable: node,
      child: child,
      builder: (context, child) => SqueezeSlot(
        open: !node.hasFocus,
        motion: SearchMotion.morph,
        child: child!,
      ),
    );
  }
}

/// Answers taps on [child] across at least [HomeTopBarMetrics.minTapTarget]
/// square, centred on it, however small it is drawn, without changing its
/// layout: a 40pt avatar on a narrow phone is still a 44pt target.
///
/// The extra reach is carried by the [HomeTopBarFrame] around the bar, so it
/// takes in the gutter, the inset above the row and the gap below it as well
/// as the space between controls. It only claims spots nothing else would
/// answer: anything there that handles the pointer itself (another control,
/// the search field's text) keeps the tap. The tap is handed on as one just
/// inside the control's edge, through the usual path, so whatever blocks the
/// control's own taps blocks this too. The nearest control wins where two
/// reaches overlap, and a control squeezed out of the row, or caught
/// mid-squeeze, keeps only what it paints. Outside a [HomeTopBarFrame] it
/// adds nothing.
class HomeTopBarTapTarget extends SingleChildRenderObjectWidget {
  const HomeTopBarTapTarget({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTapTarget();
}

class _RenderTapTarget extends RenderProxyBox {
  _RenderTapTargetScope? _scope;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    var node = parent;
    while (node != null && node is! _RenderTapTargetScope) {
      node = node.parent;
    }
    _scope = node as _RenderTapTargetScope?;
    _scope?._targets.add(this);
  }

  @override
  void detach() {
    _scope?._targets.remove(this);
    _scope = null;
    super.detach();
  }
}

/// Where a [HomeTopBarFrame]'s tap targets reach past their drawn edges.
class _TapTargetScope extends SingleChildRenderObjectWidget {
  const _TapTargetScope({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTapTargetScope();
}

class _RenderTapTargetScope extends RenderProxyBox {
  final Set<_RenderTapTarget> _targets = <_RenderTapTarget>{};

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final forwarded = _reachedFrom(position);
    if (forwarded == null) return super.hitTest(result, position: position);
    // In a small control's reach, off the control (possibly just outside
    // this box, in the gap under the row). Whatever handles the pointer there
    // keeps it; otherwise the tap goes to the control.
    final there = BoxHitTestResult();
    final answered =
        super.hitTest(there, position: position) &&
        there.path.any((entry) => entry.target is RenderPointerListener);
    return super.hitTest(result, position: answered ? position : forwarded);
  }

  /// A point well inside the nearest control whose target reaches
  /// [position] from off the control, clear of a rounded corner; null when
  /// none does, or when [position] is on one of them already.
  Offset? _reachedFrom(Offset position) {
    const side = HomeTopBarMetrics.minTapTarget;
    // A parent asks about every point in its own box; no target reaches
    // further than half a target past this one.
    if (_targets.isEmpty ||
        !(Offset.zero & size).inflate(side / 2).contains(position)) {
      return null;
    }
    Rect? nearest;
    var nearestDistance = double.infinity;
    for (final target in _targets) {
      if (!target.attached || !target.hasSize) continue;
      final drawn = MatrixUtils.transformRect(
        target.getTransformTo(this),
        Offset.zero & target.size,
      );
      // Drawn whole, and short of a full target on some side.
      if (drawn.isEmpty ||
          drawn.width < target.size.width - 0.5 ||
          drawn.height < target.size.height - 0.5 ||
          (drawn.width >= side && drawn.height >= side)) {
        continue;
      }
      if (drawn.contains(position)) return null;
      final reach = Rect.fromCenter(
        center: drawn.center,
        width: math.max(drawn.width, side),
        height: math.max(drawn.height, side),
      );
      if (!reach.contains(position)) continue;
      final dx = math.max(
        0.0,
        math.max(drawn.left - position.dx, position.dx - drawn.right),
      );
      final dy = math.max(
        0.0,
        math.max(drawn.top - position.dy, position.dy - drawn.bottom),
      );
      final distance = dx * dx + dy * dy;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = drawn;
      }
    }
    if (nearest == null) return null;
    final core = nearest.deflate(nearest.shortestSide / 4);
    return Offset(
      position.dx.clamp(core.left, core.right),
      position.dy.clamp(core.top, core.bottom),
    );
  }
}
