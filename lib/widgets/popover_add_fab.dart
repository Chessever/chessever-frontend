import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:chessever2/widgets/ink_fab.dart' show InkFabSize;
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

/// A page's add button, in the floating slot, cut from the same frosted
/// glass as every floating button ([GlassSurface]). A tap springs a
/// popover out of it, pointing at it, with everything the page can add; the
/// "+" turns an eighth of a turn into a "×" while it is open.
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
  late final SingleMotionController _turn = SingleMotionController(
    motion: const CupertinoMotion.snappy(snapToEnd: true),
    vsync: this,
  );
  bool _open = false;

  @override
  void dispose() {
    _turn.dispose();
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
    if (_open) return;
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
    setState(() => _open = true);
    _setTurn(1);
    final picked = await navigator.push<T>(
      _PopoverRoute<T>(
        anchor: anchor,
        title: widget.label,
        choices: widget.choices,
      ),
    );
    if (!mounted) return;
    setState(() => _open = false);
    _setTurn(0);
    if (picked != null) widget.onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final saving = widget.onSave != null;
    final reduce = MediaQuery.disableAnimationsOf(context);
    // The floating buttons' side, so the swap between them never shifts.
    final side = InkFabSize.regular.disc;

    return Semantics(
      container: true,
      button: true,
      label: saving ? widget.saveLabel ?? widget.label : widget.label,
      expanded: saving ? null : _open,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: SizedBox.square(
          dimension: side,
          // The app's press, as on every floating button.
          child: PressSpring(
            pressedScale: 0.9,
            builder: (context, press, child) {
              final scale = 1 - 0.1 * press;
              return Transform.scale(
                scale: (scale - 1).abs() < 0.001 ? 1.0 : scale,
                // The same frosted glass as every floating button: the
                // page shows through, blurred, behind a quiet plate.
                child: GlassSurface(lift: press.clamp(0.0, 1.0), child: child),
              );
            },
            // Saving swaps the "+" for a check in place: same button, same
            // spot, now the way to save.
            child: Center(
              child: AnimatedSwitcher(
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                child: saving
                    ? Icon(
                        Icons.check_rounded,
                        key: const ValueKey<String>('popover_fab_save'),
                        size: side * 0.46,
                        color: GlassStyle.of(context).ink,
                      )
                    : AnimatedBuilder(
                        key: const ValueKey<String>('popover_fab_add'),
                        animation: _turn,
                        builder: (context, child) => Transform.rotate(
                          // "+" to "×": an eighth of a turn.
                          angle: _turn.value * math.pi / 4,
                          child: child,
                        ),
                        child: CustomPaint(
                          size: Size.square(side * 0.36),
                          painter: _PlusPainter(
                            color: GlassStyle.of(context).ink,
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

/// The "+": two bars with round caps, drawn so they cross at the exact
/// centre (a font glyph's plus sits on its own baseline, not on centre).
class _PlusPainter extends CustomPainter {
  const _PlusPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.14
      ..strokeCap = StrokeCap.round;
    final c = size.center(Offset.zero);
    final r = size.width / 2 - paint.strokeWidth / 2;
    canvas.drawLine(c.translate(-r, 0), c.translate(r, 0), paint);
    canvas.drawLine(c.translate(0, -r), c.translate(0, r), paint);
  }

  @override
  bool shouldRepaint(_PlusPainter old) => old.color != color;
}

/// The popover as a route: back and the scrim both close it, and it sits
/// over the whole page (bottom bar included) while it is open.
class _PopoverRoute<T> extends PopupRoute<T> {
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

  // The popover springs itself; the route adds no fade of its own.
  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _Popover<T>(anchor: anchor, title: title, choices: choices);
}

class _Popover<T> extends StatefulWidget {
  const _Popover({
    required this.anchor,
    required this.title,
    required this.choices,
  });

  final Rect anchor;
  final String title;
  final List<PopoverAddChoice<T>> choices;

  @override
  State<_Popover<T>> createState() => _PopoverState<T>();
}

class _PopoverState<T> extends State<_Popover<T>>
    with SingleTickerProviderStateMixin {
  static const double _width = 236;
  static const double _pointerWidth = 18;
  static const double _pointerHeight = 9;
  static const double _gap = 10;
  static const double _radius = 16;

  late final SingleMotionController _show = SingleMotionController(
    motion: const CupertinoMotion.snappy(snapToEnd: true),
    vsync: this,
  );
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _show.value = 1;
      } else {
        _show.animateTo(1);
      }
    });
  }

  @override
  void dispose() {
    _show.dispose();
    super.dispose();
  }

  void _close([T? picked]) {
    if (_closing) return;
    _closing = true;
    if (picked != null) HapticFeedbackService.selection();
    void pop() {
      if (mounted) Navigator.of(context).pop(picked);
    }

    if (MediaQuery.disableAnimationsOf(context) || _show.value <= 0.04) {
      return pop();
    }
    // Let go the moment it has visibly gone, not when the spring's tail
    // settles, so a picked row's sheet follows without a pause.
    void watch() {
      if (_show.value > 0.04) return;
      _show.removeListener(watch);
      pop();
    }

    _show.addListener(watch);
    _show.animateTo(0);
  }

  Widget _card(BuildContext context, Color surface, Color edge) {
    final colors = context.colors;
    final light = context.isLightTheme;
    final anchor = widget.anchor;
    return Container(
      width: _width,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: edge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: light ? 0.12 : 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
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
    final edge = colors.textPrimary.withValues(alpha: light ? 0.08 : 0.1);
    final card = _card(context, surface, edge);
    return Stack(
      children: [
        // The scrim: a faint dim that springs in with the popover; a tap
        // anywhere outside it closes the popover.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: AnimatedBuilder(
              animation: _show,
              builder: (context, _) => ColoredBox(
                color: Colors.black.withValues(
                  alpha: (light ? 0.08 : 0.22) * _show.value.clamp(0.0, 1.0),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: right,
          bottom: bottom,
          child: AnimatedBuilder(
            animation: _show,
            builder: (context, child) {
              final t = _show.value;
              return Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * 8),
                  child: Transform.scale(
                    scale: 0.88 + 0.12 * t,
                    alignment: origin,
                    child: child,
                  ),
                ),
              );
            },
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: widget.title,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  card,
                  Padding(
                    padding: EdgeInsets.only(
                      right: tipFromRight - _pointerWidth / 2,
                    ),
                    child: CustomPaint(
                      size: const Size(_pointerWidth, _pointerHeight),
                      painter: _PointerPainter(fill: surface, edge: edge),
                    ),
                  ),
                ],
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

/// The popover's pointer: a small triangle under the card aimed at the
/// button, in the card's own fill with its edge on the two slanted sides.
class _PointerPainter extends CustomPainter {
  const _PointerPainter({required this.fill, required this.edge});

  final Color fill;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);
    canvas.drawPath(path..close(), Paint()..color = fill);
    final sides = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);
    canvas.drawPath(
      sides,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PointerPainter old) =>
      old.fill != fill || old.edge != edge;
}
