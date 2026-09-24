import 'package:chessever2/screens/my_space/widgets/pixel_art.dart';
import 'package:chessever2/screens/streaks/widgets/player_streak_format.dart';
import 'package:flutter/widgets.dart';

/// One loose fire block in a design frame.
@immutable
class StreakEmber {
  const StreakEmber(this.rect, this.color, this.opacity);

  final Rect rect;
  final Color color;
  final double opacity;
}

double _round(double v, int digits) {
  var m = 1.0;
  for (var i = 0; i < digits; i++) {
    m *= 10;
  }
  return (v * m).round() / m;
}

/// The embers behind the player card's hero, drawn from the design's own
/// seeded generator (Streaks-Player: seed 11, 60 blocks in a 390 x 470 frame,
/// thicker and brighter towards the bottom). Seeded, so every visit shows the
/// same field.
final List<StreakEmber> kPlayerHeroEmbers = _heroEmbers();

List<StreakEmber> _heroEmbers() {
  final rnd = PixelRandom(11);
  final out = <StreakEmber>[];
  for (var k = 0; k < 60; k++) {
    final y = 90 + rnd.next() * 370;
    final s = 2.5 + rnd.next() * 6 * ((y - 90) / 370);
    final x = 6 + rnd.next() * 378;
    final color = StreakFire.embers[(rnd.next() * 4).floor()];
    final o = _round((0.06 + rnd.next() * 0.26) * (0.35 + (y - 90) / 500), 2);
    // The design lets ~30% of them rise; the draw order is kept so the
    // remaining blocks land where the design put them.
    if (rnd.next() < 0.3) {
      rnd.next();
      rnd.next();
    }
    final side = _round(s, 1);
    out.add(
      StreakEmber(
        Rect.fromLTWH(x.roundToDouble(), y.roundToDouble(), side, side),
        color,
        o,
      ),
    );
  }
  return out;
}

/// Paints [embers] laid out in a [frame]-sized design space, scaled uniformly
/// to the canvas width.
class StreakEmberPainter extends CustomPainter {
  const StreakEmberPainter({
    required this.embers,
    required this.frame,
    this.radius = 0.8,
  });

  final List<StreakEmber> embers;
  final Size frame;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (frame.width <= 0) return;
    final k = size.width / frame.width;
    final paint = Paint()..isAntiAlias = true;
    for (final e in embers) {
      final r = Rect.fromLTWH(
        e.rect.left * k,
        e.rect.top * k,
        e.rect.width * k,
        e.rect.height * k,
      );
      if (r.top > size.height) continue;
      paint.color = e.color.withValues(alpha: e.opacity);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(radius * k)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(StreakEmberPainter old) =>
      old.embers != embers || old.frame != frame || old.radius != radius;
}
