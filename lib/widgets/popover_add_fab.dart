import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/glass_anchored_route.dart'
    show
        GlassAnchoredTransition,
        GlassFold,
        GlassFoldTransition,
        GlassScrimPainter;
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:chessever2/widgets/ink_fab.dart' show InkFab, InkFabSize;
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// One row of a [PopoverAddFab]'s popover.
class PopoverAddChoice<T> {
  const PopoverAddChoice({
    required this.leading,
    required this.label,
    required this.value,
  });

  /// The row's mark, in a 22px slot; an [Icon] takes the row's ink.
  final Widget leading;
  final String label;
  final T value;
}

/// A page's add button, in the floating slot: the regular floating disc
/// ([InkFabSize.regular]) cut from the same frosted glass as every floating
/// button ([GlassSurface]), its mark in the same glyph box and ink, with the
/// same press and tooltip. A tap springs a popover out of it, pointing at
/// it, with everything the page can add; the "+" turns an eighth of a turn
/// into a "×" while it is open. Stack it like any floating button
/// ([InkFabStack]).
class PopoverAddFab<T> extends StatefulWidget {
  const PopoverAddFab({
    super.key,
    required this.label,
    required this.choices,
    required this.onPicked,
    this.saveLabel,
    this.onSave,
  });

  /// What the button announces, and the popover's heading.
  final String label;
  final List<PopoverAddChoice<T>> choices;
  final ValueChanged<T> onPicked;

  /// With [onSave] set the button is a save instead: a check, announced as
  /// [saveLabel], and a tap calls [onSave] with no popover.
  final String? saveLabel;
  final VoidCallback? onSave;

  @override
  State<PopoverAddFab<T>> createState() => _PopoverAddFabState<T>();
}

class _PopoverAddFabState<T> extends State<PopoverAddFab<T>>
    with SingleTickerProviderStateMixin {
  /// The "+" to check swap: quick and firm, landing exactly.
  static const _swapMotion = CupertinoMotion.snappy(
    duration: Duration(milliseconds: 260),
    snapToEnd: true,
  );

  late final SingleMotionController _turn = SingleMotionController(
    motion: const CupertinoMotion.snappy(snapToEnd: true),
    vsync: this,
  );

  /// Whether the popover is up. Only the button's semantics read it, so a
  /// toggle rebuilds that one node, not the button.
  final ValueNotifier<bool> _open = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _turn.dispose();
    _open.dispose();
    super.dispose();
  }

  void _setTurn(double value) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _turn.value = value;
    } else {
      _turn.animateTo(value);
    }
  }

  Future<void> _toggle() async {
    if (_open.value) return;
    if (widget.onSave case final save?) {
      HapticFeedbackService.buttonPress();
      save();
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    HapticFeedbackService.buttonPress();
    // In the navigator's own coordinates, where the popover is laid out:
    // the two differ from the screen's when the app sits in part of it.
    final navigator = Navigator.of(context);
    final anchor =
        box.localToGlobal(
          Offset.zero,
          ancestor: navigator.context.findRenderObject(),
        ) &
        box.size;
    _open.value = true;
    _setTurn(1);
    final picked = await navigator.push<T>(
      _PopoverRoute<T>(
        anchor: anchor,
        title: widget.label,
        choices: widget.choices,
      ),
    );
    if (!mounted) return;
    _open.value = false;
    _setTurn(0);
    if (picked != null) widget.onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final saving = widget.onSave != null;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final label = saving ? widget.saveLabel ?? widget.label : widget.label;
    // The floating buttons' disc and touch square, so it sits in a stack
    // exactly like them and the swap between "+" and check never shifts.
    const size = InkFabSize.regular;
    final disc = size.disc;
    // The glyph box every floating button hands its mark ([InkFab]).
    final glyph = disc * InkFab.glyphFraction;

    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: ValueListenableBuilder<bool>(
        valueListenable: _open,
        builder: (context, open, child) => Semantics(
          container: true,
          button: true,
          label: label,
          expanded: saving ? null : open,
          child: child,
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: SizedBox.square(
            dimension: size.side,
            child: Center(
              child: SizedBox.square(
                dimension: disc,
                // The app's press, as on every floating button.
                child: PressSpring(
                  pressedScale: 0.9,
                  builder: (context, press, child) {
                    final scale = 1 - 0.1 * press;
                    return Transform.scale(
                      scale: (scale - 1).abs() < 0.001 ? 1.0 : scale,
                      // The same frosted glass as every floating button:
                      // the page shows through, blurred, behind a quiet
                      // plate.
                      child: GlassSurface(
                        lift: press.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  // Saving swaps the "+" for a check in place: same button,
                  // same spot, now the way to save. The two cross on one
                  // spring, each growing in from a little smaller as it
                  // comes; only the one in force is built at rest.
                  child: Center(
                    child: SingleMotionBuilder(
                      motion: _swapMotion,
                      value: saving ? 1.0 : 0.0,
                      active: !reduce,
                      builder: (context, value, _) {
                        final t = value.clamp(0.0, 1.0);
                        final ink = GlassStyle.of(context).ink;
                        Widget swapIn(double shown, Widget child) {
                          if (shown >= 1) return child;
                          return Opacity(
                            opacity: shown,
                            child: Transform.scale(
                              scale: 0.6 + 0.4 * shown,
                              child: child,
                            ),
                          );
                        }

                        return SizedBox.square(
                          dimension: glyph,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (t < 1)
                                swapIn(
                                  1 - t,
                                  AnimatedBuilder(
                                    key: const ValueKey<String>(
                                      'popover_fab_add',
                                    ),
                                    animation: _turn,
                                    builder: (context, child) =>
                                        Transform.rotate(
                                          // "+" to "×": an eighth of a turn.
                                          angle: _turn.value * math.pi / 4,
                                          child: child,
                                        ),
                                    child: CustomPaint(
                                      painter: _PlusPainter(color: ink),
                                    ),
                                  ),
                                ),
                              if (t > 0)
                                swapIn(
                                  t,
                                  CustomPaint(
                                    key: const ValueKey<String>(
                                      'popover_fab_save',
                                    ),
                                    painter: _CheckPainter(color: ink),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "+" and the check share one stroke: a seventh of the glyph box with
/// round caps, the weight of the search button's magnifier, so every mark in
/// a stack of floating buttons reads as one set.
const double _strokeShare = 0.14;

/// The "+": two bars with round caps, drawn so they cross at the exact
/// centre (a font glyph's plus sits on its own baseline, not on centre).
class _PlusPainter extends CustomPainter {
  const _PlusPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * _strokeShare
      ..strokeCap = StrokeCap.round;
    final c = size.center(Offset.zero);
    final r = size.width / 2 - paint.strokeWidth / 2;
    canvas.drawLine(c.translate(-r, 0), c.translate(r, 0), paint);
    canvas.drawLine(c.translate(0, -r), c.translate(0, r), paint);
  }

  @override
  bool shouldRepaint(_PlusPainter old) => old.color != color;
}

/// The save check, drawn like the "+": the same stroke and round caps, its
/// two arms at 45 degrees, spanning the glyph box's full width and centred
/// on it top to bottom (caps included).
class _CheckPainter extends CustomPainter {
  const _CheckPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * _strokeShare;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // The caps reach the box's sides, so the arms run between the stroke's
    // half widths. The long arm is twice the short one, both at 45 degrees,
    // so the check is two thirds as tall as its run, centred on the box top
    // to bottom (the caps and the join stick out the same half stroke).
    final left = stroke / 2;
    final run = s - stroke;
    final shortArm = run / 3;
    final longArm = run - shortArm;
    final top = (size.height - longArm) / 2;
    final path = Path()
      ..moveTo(left, top + longArm - shortArm)
      ..lineTo(left + shortArm, top + longArm)
      ..lineTo(left + run, top);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.color != color;
}

/// The popover as a route: back and the scrim both close it, and it sits
/// over the whole page (bottom bar included) while it is open. It moves as
/// every anchored glass surface does ([GlassAnchoredTransition]): it grows
/// out of the button on the open spring and folds shut back into it on
/// close, the pick handed over as the fold begins.
class _PopoverRoute<T> extends PopupRoute<T> with GlassAnchoredTransition<T> {
  _PopoverRoute({
    required this.anchor,
    required this.title,
    required this.choices,
  });

  final String title;
  final List<PopoverAddChoice<T>> choices;

  /// The add button's rect in the navigator's coordinates.
  final Rect anchor;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => 'Close';

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    readMotionPreference(context);
    return _Popover<T>(
      anchor: anchor,
      title: title,
      choices: choices,
      progress: animation,
      fold: fold,
    );
  }
}

class _Popover<T> extends StatefulWidget {
  const _Popover({
    required this.anchor,
    required this.title,
    required this.choices,
    required this.progress,
    required this.fold,
  });

  final Rect anchor;
  final String title;
  final List<PopoverAddChoice<T>> choices;

  /// The route's progress: the dim rides it.
  final Animation<double> progress;

  /// The panel's grow and fold, and its rows' opacity.
  final GlassFold fold;

  @override
  State<_Popover<T>> createState() => _PopoverState<T>();
}

class _PopoverState<T> extends State<_Popover<T>> {
  static const double _width = 236;
  static const double _pointerWidth = 18;
  static const double _pointerHeight = 9;
  static const double _gap = 10;
  static const double _radius = 16;

  bool _closed = false;

  /// Pops at once with [picked]: the route folds the popover shut while the
  /// pick (a row's sheet) already follows.
  void _close([T? picked]) {
    if (_closed) return;
    _closed = true;
    if (picked != null) HapticFeedbackService.selection();
    Navigator.of(context).pop(picked);
  }

  Widget _card(BuildContext context, Color surface, double tipX) {
    final colors = context.colors;
    final anchor = widget.anchor;
    // The popover's panel is the popups' frosted glass, averaging to the
    // surface the opaque card was; its lit rim is the edge. The pointer is
    // cut from the same glass: one silhouette, one frost, one rim, so the
    // tip never reads as a separate piece.
    return PopupGlass(
      width: _width,
      tone: surface,
      page: AnchoredGlassDim.pageOf(context),
      cover: AnchoredGlassDim.cover,
      borderRadius: BorderRadius.circular(_radius),
      padding: const EdgeInsets.symmetric(vertical: 8),
      pointer: PopupGlassPointer(
        width: _pointerWidth,
        height: _pointerHeight,
        tipX: tipX,
      ),
      constraints: BoxConstraints(
        maxHeight: math.max(
          44,
          anchor.top -
              MediaQuery.paddingOf(context).top -
              _gap -
              _pointerHeight -
              8,
        ),
      ),
      // The rows fade as it folds; the glass itself never does.
      child: FadeTransition(
        opacity: widget.fold,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Text(
                  widget.title,
                  style: AppTypography.textXsMedium.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              for (final choice in widget.choices)
                _PopoverRow(
                  leading: choice.leading,
                  label: choice.label,
                  onTap: () => _close(choice.value),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A route page has no Material of its own: without one, text falls
    // back to the debug style.
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) =>
            _layout(context, constraints.biggest),
      ),
    );
  }

  Widget _layout(BuildContext context, Size size) {
    final colors = context.colors;
    final light = context.isLightTheme;
    final anchor = widget.anchor;
    // Right-aligned with the button, the pointer over its centre.
    final right = math.max(8.0, size.width - anchor.right);
    final bottom = size.height - anchor.top + _gap;
    final tipFromRight = anchor.width / 2;
    final tipX = _width - tipFromRight;
    final origin = Alignment(tipX / _width * 2 - 1, 1);
    final surface = light ? colors.popup : colors.surface;
    final card = _card(context, surface, tipX);
    return Stack(
      children: [
        // The scrim: a plain dim that springs in with the popover, never a
        // blur; a tap anywhere outside it closes the popover.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: CustomPaint(
              size: Size.infinite,
              // The anchored menus' dim, riding the popover's spring
              // (repainted, never rebuilt). The button stays lit: it is the
              // popover's close.
              painter: GlassScrimPainter(
                color: AnchoredGlassDim.colorOf(context),
                progress: widget.progress,
                hole: RRect.fromRectAndRadius(
                  Rect.fromCircle(
                    center: anchor.center,
                    radius: InkFabSize.regular.disc / 2 + 1,
                  ),
                  Radius.circular(InkFabSize.regular.disc / 2 + 1),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: right,
          bottom: bottom,
          // Scaled, never faded: the panel is glass. It grows out of the
          // pointer's tip and folds shut back into it. Under reduced motion
          // it opens at full size and the route takes it away at once.
          child: GlassFoldTransition(
            fold: widget.fold,
            alignment: origin,
            includeOpen: !MediaQuery.disableAnimationsOf(context),
            child: RepaintBoundary(
              child: Semantics(
                scopesRoute: true,
                namesRoute: true,
                explicitChildNodes: true,
                label: widget.title,
                child: card,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PopoverRow extends StatefulWidget {
  const _PopoverRow({
    required this.leading,
    required this.label,
    required this.onTap,
  });

  final Widget leading;
  final String label;
  final VoidCallback onTap;

  @override
  State<_PopoverRow> createState() => _PopoverRowState();
}

class _PopoverRowState extends State<_PopoverRow> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: Container(
          height: 48,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _down
                ? colors.textPrimary.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              IconTheme.merge(
                data: IconThemeData(size: 22, color: colors.textPrimary),
                child: SizedBox.square(
                  dimension: 22,
                  child: Center(child: widget.leading),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textSmMedium.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
