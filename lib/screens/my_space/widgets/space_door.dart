import 'dart:math' as math;

import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_art.dart';
import 'package:chessever2/screens/my_space/widgets/space_glyphs.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';

const Color _kTile = Color(0xFF1A1A1C);
const Color _kTilePressed = Color(0xFF232326);
const Color _kNotch = Color(0xFF0C0C0E);
const Color _kCyan = Color(0xFF0FB4E5);

/// What the corner mark of a door says it does.
enum SpaceDoorGlyph {
  /// Adds to the row, in place.
  plus,

  /// Opens the row's full list on its own screen.
  open,
}

/// The first tile of every My Space row: a pixel-block chess object drawn by
/// a fragment shader, with a "+" and the row's action label.
///
/// Tiles wider than 200 px (first-run empty rows) put the art on the right
/// and the label on the left. [locked] adds a padlock notch in the corner.
///
/// Dark, the tile is the design's black plate with white ink; light, it is
/// the surface token with primary ink and the art inked for paper.
class SpaceDoor extends StatefulWidget {
  const SpaceDoor({
    super.key,
    required this.section,
    this.width = 120,
    this.height = 209,
    this.locked = false,
    this.label,
    this.glyph = SpaceDoorGlyph.plus,
    this.onTap,
  });

  final SpaceSection section;
  final double width;
  final double height;
  final bool locked;

  /// Overrides [SpaceSectionX.doorLabel].
  final String? label;

  /// The corner mark: "+" for a door that adds, an up-right arrow for one
  /// that opens a list.
  final SpaceDoorGlyph glyph;
  final VoidCallback? onTap;

  @override
  State<SpaceDoor> createState() => _SpaceDoorState();
}

class _SpaceDoorState extends State<SpaceDoor> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(widget.width, widget.height);
    final wide = widget.width > 200;
    final pad = wide ? 18.0 : 14.0;
    final plus = wide ? 24.0 : 20.0;
    final fontSize = wide ? 18.0 : 13.0;
    final lineHeight = wide ? 22.0 : 17.0;
    final text = widget.label ?? widget.section.doorLabel;
    final tone = PixelTone.of(context);
    final light = tone == PixelTone.light;
    final colors = context.colors;
    final ink = light ? colors.textPrimary : Colors.white;
    final labelStyle = TextStyle(
      fontFamily: 'InterDisplay',
      fontSize: fontSize,
      height: lineHeight / fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1,
      color: ink,
      decoration: TextDecoration.none,
    );
    // Wide tiles keep the label in the left column, clear of the art.
    final labelRight = wide ? widget.width - doorArtBox(size).left + 12 : pad;
    // The label is laid out before the art so a large text scale pushes the
    // art up and shrinks it, instead of the words running into it.
    final inherited = DefaultTextStyle.of(context);
    final label = _DoorLabelLayout.measure(
      text: text,
      style: inherited.style.merge(labelStyle),
      scaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
      direction: Directionality.of(context),
      maxWidth: widget.width - pad - labelRight,
      heightBehavior: inherited.textHeightBehavior,
    );
    final scene = PixelScene.door(
      PixelArt.door(widget.section, tone: tone),
      size,
      labelReserve: math.max(kDoorLabelReserve, pad + label.height + 8),
    );
    final interactive = widget.onTap != null;
    final Color tile;
    if (light) {
      tile = _pressed
          ? Color.alphaBlend(
              colors.textPrimary.withValues(alpha: 0.06),
              colors.surface,
            )
          : colors.surface;
    } else {
      tile = _pressed ? _kTilePressed : _kTile;
    }

    return Semantics(
      container: true,
      button: interactive,
      label: widget.locked ? '$text, locked' : text,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: interactive ? (_) => _setPressed(true) : null,
        onTapUp: interactive ? (_) => _setPressed(false) : null,
        onTapCancel: interactive ? () => _setPressed(false) : null,
        child: SizedBox.fromSize(
          size: size,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: ColoredBox(
              color: tile,
              child: Stack(
                children: [
                  Positioned.fill(child: PixelArtView(scene: scene)),
                  Positioned(
                    left: pad,
                    top: pad,
                    child: switch (widget.glyph) {
                      SpaceDoorGlyph.plus => CustomPaint(
                        size: Size.square(plus),
                        painter: _PlusPainter(ink),
                      ),
                      SpaceDoorGlyph.open => SpaceGlyph(
                        SpaceGlyphKind.arrowUpRight,
                        size: plus,
                        ink: ink,
                      ),
                    },
                  ),
                  Positioned(
                    left: pad,
                    right: labelRight,
                    bottom: pad,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: SizedBox(
                        width: label.width,
                        child: Text(
                          text,
                          style: labelStyle,
                          textScaler: label.scaler,
                          maxLines: _kLabelMaxLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  if (widget.locked)
                    const Positioned(top: 0, right: 0, child: _LockNotch()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A door label never truncates at the 1.3x cap: narrow doors at large text
/// need a third line ("Build a / Smart / Event").
const int _kLabelMaxLines = 3;

/// A door label laid out once, before the art: the wrap width that balances
/// its lines (the design's `text-wrap: balance`, so no word is stranded on
/// the last line) and the height those lines take.
@immutable
class _DoorLabelLayout {
  const _DoorLabelLayout(this.width, this.height, this.scaler);

  final double width;
  final double height;
  final TextScaler scaler;

  static _DoorLabelLayout measure({
    required String text,
    required TextStyle style,
    required TextScaler scaler,
    required TextDirection direction,
    required double maxWidth,
    TextHeightBehavior? heightBehavior,
  }) {
    final available = math.max(0.0, maxWidth);
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      textHeightBehavior: heightBehavior,
      maxLines: _kLabelMaxLines,
    )..layout(maxWidth: available);
    final height = painter.height;
    final lines = painter.computeLineMetrics().length;
    var width = available;
    if (lines >= 2 && !painter.didExceedMaxLines) {
      // Narrowest width that keeps the same line count without breaking a
      // word; the height is unchanged by construction.
      painter
        ..maxLines = lines
        ..layout(maxWidth: available);
      var lo = math.min(painter.minIntrinsicWidth, available);
      var hi = available;
      for (var i = 0; i < 8 && hi - lo > 0.5; i++) {
        final mid = (lo + hi) / 2;
        painter.layout(maxWidth: mid);
        if (painter.didExceedMaxLines) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      width = math.min(hi + 1, available);
    }
    painter.dispose();
    return _DoorLabelLayout(width, height, scaler);
  }
}

/// Two rounded 2.6-unit bars on a 20-unit grid, scaled to the paint size.
class _PlusPainter extends CustomPainter {
  const _PlusPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 20;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.6 * k
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(10 * k, 2.5 * k), Offset(10 * k, 17.5 * k), paint);
    canvas.drawLine(Offset(2.5 * k, 10 * k), Offset(17.5 * k, 10 * k), paint);
  }

  @override
  bool shouldRepaint(_PlusPainter oldDelegate) => oldDelegate.color != color;
}

/// The corner notch on premium-only doors.
class _LockNotch extends StatelessWidget {
  const _LockNotch();

  @override
  Widget build(BuildContext context) {
    // The notch is a cut into the tile, so it takes the page colour; in dark
    // mode that is exactly [_kNotch]. On paper the lock uses the AA-safe
    // accent ink instead of raw cyan.
    final isLight = context.isLightTheme;
    return SizedBox.square(
      dimension: 24,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isLight ? context.colors.background : _kNotch,
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(3)),
        ),
        child: CustomPaint(
          painter: _PadlockPainter(
            isLight ? context.colors.accentText : _kCyan,
          ),
        ),
      ),
    );
  }
}

/// The design's 12 x 14 padlock, fitted into a 10 x 12 box at the centre.
class _PadlockPainter extends CustomPainter {
  const _PadlockPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const k = 10 / 12;
    canvas.save();
    canvas.translate((size.width - 12 * k) / 2, (size.height - 14 * k) / 2);
    canvas.scale(k);
    final shackle = Path()
      ..moveTo(3.25, 6.2)
      ..lineTo(3.25, 4.3)
      ..arcToPoint(const Offset(8.75, 4.3), radius: const Radius.circular(2.75))
      ..lineTo(8.75, 6.2);
    canvas.drawPath(
      shackle,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(1, 6.2, 10, 7),
        const Radius.circular(1.8),
      ),
      Paint()..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PadlockPainter oldDelegate) => oldDelegate.color != color;
}
