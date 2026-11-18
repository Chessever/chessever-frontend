import 'package:flutter/widgets.dart';

/// The Live-first mark, shared with chessever.com and the desktop app.
///
/// A port of the web's `MarkLive` (`src/broadcast/components/icons.tsx` in
/// the web repository): a solid board square broadcasting, the two arcs being
/// the signal leaving it. Every control that brings live games or events
/// first wears this mark, so it reads the same in the phone app, the desktop
/// app and the website. It replaced a lightning bolt, which collided with the
/// Blitz time-control mark.
///
/// The phone mark keeps the web's centered square and uses taller, lighter
/// arcs to match the weight of the other toolbar glyphs.
///
/// Like [Icon], [size] and [color] fall back to the ambient [IconTheme].
class LiveFirstMark extends StatelessWidget {
  const LiveFirstMark({super.key, this.size, this.color});

  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final dimension = size ?? iconTheme.size ?? 16;
    var ink = color ?? iconTheme.color ?? const Color(0xFFFFFFFF);
    final opacity = iconTheme.opacity;
    if (color == null && opacity != null && opacity != 1.0) {
      ink = ink.withValues(alpha: ink.a * opacity);
    }
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: dimension,
        child: CustomPaint(painter: LiveFirstMarkPainter(ink)),
      ),
    );
  }
}

/// Paints [LiveFirstMark] into any square box.
class LiveFirstMarkPainter extends CustomPainter {
  const LiveFirstMarkPainter(this.color);

  final Color color;

  static const double _grid = 16;
  static const double _stroke = 1.5;
  static const Radius _arcRadius = Radius.circular(6.5);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _grid;
    canvas.save();
    canvas.translate(
      (size.width - _grid * scale) / 2,
      (size.height - _grid * scale) / 2,
    );
    canvas.scale(scale);

    canvas.drawRect(
      const Rect.fromLTWH(6.5, 6.5, 3, 3),
      Paint()..color = color,
    );

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawPath(
      Path()
        ..moveTo(4.4, 3.2)
        ..arcToPoint(
          const Offset(4.4, 12.8),
          radius: _arcRadius,
          clockwise: false,
        ),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(11.6, 3.2)
        ..arcToPoint(const Offset(11.6, 12.8), radius: _arcRadius),
      stroke,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(LiveFirstMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
