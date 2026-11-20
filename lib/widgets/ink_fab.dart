import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The two sizes a floating button comes in: the page's main action, and a
/// smaller one stacked above it.
enum InkFabSize {
  regular,
  small;

  /// The drawn disc.
  double get disc => switch (this) {
    InkFabSize.regular => 52.ic.clamp(50.0, 58.0),
    InkFabSize.small => 44.ic.clamp(42.0, 48.0),
  };

  /// The square the button takes and answers touches in: its [disc], but
  /// never under the 44pt minimum target. The small disc draws at 42 on most
  /// phones narrower or shorter than the 393x852 base, so it is centred in
  /// the square there. Pages that clear the floating buttons read this.
  double get side => math.max(disc, 44.0);
}

/// A round floating button of frosted glass ([GlassSurface]): the list under
/// it shows through, blurred, behind a thin plate of the page's tone, with
/// the glyph in the glass's quiet ink. It floats in reach without pulling
/// the eye off the boards. While [on] (a toggle) the glass and the glyph take
/// the brand's tonal blue.
///
/// The glyph is drawn by [glyph] in the colour it is handed, at the size it
/// is handed, so any mark (an icon, a painter) takes the button's ink.
class InkFab extends StatefulWidget {
  const InkFab({
    super.key,
    required this.label,
    required this.glyph,
    required this.onTap,
    this.size = InkFabSize.regular,
    this.on,
    this.badgeCount = 0,
  }) : _discKey = null,
       _glyphKey = null,
       _discHidden = false,
       _badgeOpacity = null;

  /// The search button's: its disc and glyph measured for the search
  /// morph, the disc not drawn while the morph's glass carries it, and the
  /// badge stepping back with the other floating buttons.
  const InkFab._handoff({
    required this.label,
    required this.glyph,
    required this.onTap,
    required GlobalKey this._discKey,
    required GlobalKey this._glyphKey,
    required this._discHidden,
    required Animation<double> this._badgeOpacity,
    this.badgeCount = 0,
  }) : size = InkFabSize.regular,
       on = null;

  /// The glyph's size, as a share of the disc.
  static const double glyphFraction = 0.42;

  /// What the button announces and its tooltip.
  final String label;
  final Widget Function(Color color, double size) glyph;
  final VoidCallback? onTap;
  final InkFabSize size;

  /// Null for a plain action; true/false for a toggle.
  final bool? on;

  /// A count (applied filters) on the button's shoulder; hidden at 0.
  final int badgeCount;

  final GlobalKey? _discKey;
  final GlobalKey? _glyphKey;
  final bool _discHidden;
  final Animation<double>? _badgeOpacity;

  @override
  State<InkFab> createState() => _InkFabState();
}

class _InkFabState extends State<InkFab> {
  void _activate() {
    final tap = widget.onTap;
    if (tap == null) return;
    HapticFeedbackService.buttonPress();
    tap();
  }

  @override
  Widget build(BuildContext context) {
    final disc = widget.size.disc;
    final on = widget.on ?? false;
    final style = GlassStyle.of(context);
    final accent = context.colors.accentText;
    // Quiet at rest: the glyph in the glass's own ink. On, the glass takes a
    // breath of the brand's tonal blue and the glyph wears it, which reads
    // across the room without a bright disc shouting from the corner.
    final glyphColor = on ? accent : style.ink;
    Widget glyph = widget.glyph(glyphColor, disc * InkFab.glyphFraction);
    final glyphKey = widget._glyphKey;
    if (glyphKey != null) glyph = KeyedSubtree(key: glyphKey, child: glyph);
    final discKey = widget._discKey;

    // The app's press ([PressSpring]): down under the finger, back with a
    // little pop, and the glass brightening while held.
    Widget button = SizedBox.square(
      dimension: disc,
      child: PressSpring(
        pressedScale: 0.9,
        child: Center(child: glyph),
        builder: (context, press, child) {
          final scale = 1 - 0.1 * press;
          Widget glass = GlassSurface(
            tint: on ? accent.withValues(alpha: 0.16) : null,
            lift: press.clamp(0.0, 1.0),
            child: child,
          );
          // Measured inside the press, so the search morph lifts the glass
          // at the size the finger left it.
          if (discKey != null) glass = KeyedSubtree(key: discKey, child: glass);
          return Transform.scale(
            scale: (scale - 1).abs() < 0.001 ? 1.0 : scale,
            child: glass,
          );
        },
      ),
    );
    if (discKey != null) {
      // Laid out (the glass flies back to it) but not drawn while the
      // search morph's glass is the button.
      button = Opacity(opacity: widget._discHidden ? 0 : 1, child: button);
    }

    final count = widget.badgeCount;
    final badgeOpacity = widget._badgeOpacity;
    Widget badge() {
      final drawn = SearchCountBadge(count: count);
      // The search button's count leaves on the morph's own window; any
      // other button's steps back with its glass ([GlassFade]).
      return badgeOpacity == null
          ? GlassFade.content(context, drawn)
          : FadeTransition(opacity: badgeOpacity, child: drawn);
    }

    return Tooltip(
      message: widget.label,
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        button: true,
        toggled: widget.on,
        enabled: widget.onTap != null,
        label: count > 0 ? '${widget.label}, $count applied' : widget.label,
        onTap: widget.onTap == null ? null : _activate,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _activate,
          child: SizedBox.square(
            dimension: widget.size.side,
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  button,
                  if (count > 0) Positioned(top: -2, right: -2, child: badge()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The page's search: opens the full-page search of whatever list it floats
/// over.
///
/// Under a [SearchModeHost] it hands off to it: the tap lifts its own glass
/// (as pressed) into the morph, the disc stays hidden while the search is
/// open, and closing flies the glass back into it. [onTap] then only
/// observes. Anywhere else it is a plain button that calls [onTap].
class SearchInkFab extends StatefulWidget {
  const SearchInkFab({
    super.key,
    this.onTap,
    this.label = 'Search',
    this.badgeCount = 0,
  });

  final VoidCallback? onTap;
  final String label;
  final int badgeCount;

  @override
  State<SearchInkFab> createState() => _SearchInkFabState();
}

class _SearchInkFabState extends State<SearchInkFab> {
  final GlobalKey _disc = GlobalKey(debugLabel: 'SearchInkFab disc');
  final GlobalKey _glyph = GlobalKey(debugLabel: 'SearchInkFab glyph');
  SearchModeScope? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = SearchModeScope.maybeOf(context);
    _scope?.unregisterSearchButton(_disc);
    scope?.registerSearchButton(disc: _disc, glyph: _glyph);
    _scope = scope;
  }

  @override
  void dispose() {
    _scope?.unregisterSearchButton(_disc);
    super.dispose();
  }

  /// The field's magnifier, in the glass's ink like every glyph in the
  /// stack: the morph carries this same asset into the field.
  static Widget _glyphOf(Color color, double size) => SvgWidget(
    SvgAsset.searchIcon,
    height: size,
    width: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );

  @override
  Widget build(BuildContext context) {
    final scope = SearchModeScope.maybeOf(context);
    if (scope == null) {
      return InkFab(
        label: widget.label,
        badgeCount: widget.badgeCount,
        onTap: widget.onTap,
        glyph: _glyphOf,
      );
    }
    final searching = scope.isSearching;
    // Kept while searching (the glass lands back on it), out of reach.
    return IgnorePointer(
      ignoring: searching,
      child: ExcludeSemantics(
        excluding: searching,
        child: InkFab._handoff(
          label: widget.label,
          badgeCount: widget.badgeCount,
          discKey: _disc,
          glyphKey: _glyph,
          discHidden: scope.searchButtonHidden,
          badgeOpacity: scope.searchButtonBadgeOpacity,
          onTap: () {
            scope.openFromSearchButton(disc: _disc);
            widget.onTap?.call();
          },
          glyph: _glyphOf,
        ),
      ),
    );
  }
}

/// A column of floating buttons: the main one at the bottom where the thumb
/// rests, the smaller ones above it, all on the same right edge. A wider
/// one above (the Live first capsule) grows leftward from that edge, so the
/// main button never leaves its corner as the one above comes, goes or
/// springs to a new width.
///
/// Under a [SearchModeHost], the buttons beside the search one step back as
/// the search opens (down to [SearchModeMotion.siblingScale] as they fade,
/// over the morph's first part), stay away while it is open, and come back
/// as it closes. They fade as glass ([GlassFade]: each [GlassSurface] thins
/// its own material and content), never under an opacity over their
/// backdrop filter, and are not painted at all once gone.
class InkFabStack extends StatelessWidget {
  const InkFabStack({super.key, required this.children});

  final List<Widget> children;

  /// The gap between two buttons of the stack.
  static const double step = 12;

  /// How far up from the bottom a stack reaches: the main (regular) button,
  /// [smallAbove] smaller and [regularAbove] full-size buttons stacked over
  /// it (each a [step] above the last), the Scaffold's margin and the home
  /// indicator's inset. A list under the stack ends this far clear, so no
  /// button covers its last row.
  ///
  /// Read it from the list's context: inside the button slot the Scaffold
  /// has already taken the inset away. A page inside the Home shell, whose
  /// bottom bar the body runs under, adds `MediaQuery.paddingOf(context)
  /// .bottom` on top (the shell hands the bar's slot to the body as padding,
  /// not as view padding).
  static double reach(
    BuildContext context, {
    int smallAbove = 0,
    int regularAbove = 0,
  }) =>
      extent(smallAbove: smallAbove, regularAbove: regularAbove) +
      MediaQuery.viewPaddingOf(context).bottom;

  /// [reach] above the home indicator: the stack and the Scaffold's margin
  /// under it. For a list end that keeps the inset in a part of its own
  /// (one that stays while the search is open and the buttons give way).
  static double extent({int smallAbove = 0, int regularAbove = 0}) =>
      InkFabSize.regular.side +
      smallAbove * (step + InkFabSize.small.side) +
      regularAbove * (step + InkFabSize.regular.side) +
      kFloatingActionButtonMargin;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final scope = SearchModeScope.maybeOf(context);
    Widget place(Widget child) {
      if (scope == null || child is SearchInkFab) return child;
      final searching = scope.isSearching;
      return IgnorePointer(
        ignoring: searching,
        child: ExcludeSemantics(
          excluding: searching,
          child: GlassFade(
            opacity: scope.siblingOpacity,
            child: _DrawnWhileShown(
              opacity: scope.siblingOpacity,
              child: ScaleTransition(scale: scope.siblingScale, child: child),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: step),
          place(children[i]),
        ],
      ],
    );
  }
}

/// Paints [child] only while [opacity] is above 0: a button that has
/// stepped back is not drawn at all (whatever it draws outside its glass
/// included), with no opacity layer over its glass on the way.
class _DrawnWhileShown extends SingleChildRenderObjectWidget {
  const _DrawnWhileShown({required this.opacity, super.child});

  final Animation<double> opacity;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDrawnWhileShown(opacity);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderDrawnWhileShown renderObject,
  ) {
    renderObject.opacity = opacity;
  }
}

class _RenderDrawnWhileShown extends RenderProxyBox {
  _RenderDrawnWhileShown(this._opacity);

  Animation<double> _opacity;
  set opacity(Animation<double> value) {
    if (identical(value, _opacity)) return;
    if (attached) {
      _opacity.removeListener(_onTick);
      value.addListener(_onTick);
    }
    _opacity = value;
    _onTick();
  }

  bool _shown = true;

  void _onTick() {
    final shown = _opacity.value > 0;
    if (shown == _shown) return;
    _shown = shown;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _shown = _opacity.value > 0;
    _opacity.addListener(_onTick);
  }

  @override
  void detach() {
    _opacity.removeListener(_onTick);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_shown) super.paint(context, offset);
  }
}
