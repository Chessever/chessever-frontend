import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How fast the smart event's games are: the deck fans wider the faster
/// they go.
enum SmartDeckPace { calm, classical, rapid, blitz }

/// The smart event's mark: the stacked-boards deck (My Space's boards
/// glyph, drawn large), dealt differently for every combination so no two
/// cards wear the same one.
///
/// - The boards behind the front one count the events it gathers (one to
///   three), so a busy smart event reads as a thicker deck.
/// - The fan opens with the pace: classical sits nearly square, rapid
///   spreads, blitz splays wide.
/// - The front board carries the level ("GM", or the Elo floor), or, with
///   no level, a few dark squares placed from the combination, like a
///   position of its own.
///
/// Monochrome, in the glyph's two tokens: [ink] for strokes and squares,
/// [background] to knock each board out of the one behind it.
class SmartEventDeck extends StatelessWidget {
  const SmartEventDeck({
    super.key,
    required this.size,
    required this.ink,
    required this.background,
    required this.seed,
    this.behind = 2,
    this.pace = SmartDeckPace.calm,
    this.label,
  });

  /// The side of the square the deck is drawn in.
  final double size;
  final Color ink;
  final Color background;

  /// Picks the front board's squares and nudges the fan, so equal counts
  /// and paces still deal differently. Stable across launches (see
  /// [smartDeckSeed]).
  final int seed;

  /// Boards behind the front one, clamped to 1..3.
  final int behind;
  final SmartDeckPace pace;

  /// Printed on the front board in place of its squares.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final unit = size / 24;
    final face = _SmartDeckPainter.frontRect(unit);
    final text = label;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _SmartDeckPainter(
                ink: ink,
                background: background,
                seed: seed,
                behind: behind.clamp(1, 3),
                pace: pace,
                squares: text == null,
              ),
            ),
          ),
          if (text != null)
            Positioned.fromRect(
              rect: face.deflate(unit * 1.4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: ink,
                    fontSize: unit * (text.length <= 2 ? 5.2 : 3.6),
                    fontWeight: FontWeight.w700,
                    height: 1,
                    letterSpacing: text.length <= 2 ? 0.2 : 0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A stable seed for a smart event's deck, from the parts that make its
/// combination (String.hashCode is not promised to hold across launches).
int smartDeckSeed(Iterable<Object?> parts) {
  var h = 0x811C9DC5;
  for (final unit in parts.join('|').codeUnits) {
    h = ((h ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// The deck's pace for a smart event's time controls: the fastest wins.
SmartDeckPace smartDeckPace(Set<String> formatsAndStates) {
  if (formatsAndStates.contains('blitz')) return SmartDeckPace.blitz;
  if (formatsAndStates.contains('rapid')) return SmartDeckPace.rapid;
  if (formatsAndStates.contains('standard')) return SmartDeckPace.classical;
  return SmartDeckPace.calm;
}

class _SmartDeckPainter extends CustomPainter {
  const _SmartDeckPainter({
    required this.ink,
    required this.background,
    required this.seed,
    required this.behind,
    required this.pace,
    required this.squares,
  });

  final Color ink;
  final Color background;
  final int seed;
  final int behind;
  final SmartDeckPace pace;
  final bool squares;

  /// The front board, on the 24-unit grid the boards glyph is drawn on.
  static Rect frontRect(double unit) =>
      Rect.fromLTWH(6.5 * unit, 5.5 * unit, 11 * unit, 11 * unit);

  /// Dark-square layouts on the front board's 4x4 grid (column, row). Each
  /// reads as a couple of squares of a board, never as a pattern.
  static const List<List<(int, int)>> _layouts = [
    [(1, 1), (2, 2)],
    [(2, 1), (1, 2)],
    [(0, 0), (1, 1), (3, 2)],
    [(1, 0), (2, 1), (1, 2)],
    [(2, 0), (0, 2), (3, 3)],
    [(1, 1), (3, 1), (2, 2)],
    [(0, 1), (2, 3)],
    [(3, 0), (1, 2), (2, 3)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 24;
    // The fan, in degrees, by pace, with a seeded lean of a degree or two
    // so two decks of the same pace still sit differently.
    final spread = switch (pace) {
      SmartDeckPace.calm => 7.0,
      SmartDeckPace.classical => 4.0,
      SmartDeckPace.rapid => 9.0,
      SmartDeckPace.blitz => 15.0,
    };
    final lean = ((seed >> 3) % 5 - 2) * 0.6;

    final back = <({Offset centre, double side, double degrees, double reach})>[
      (
        centre: const Offset(6.6, 12.9),
        side: 8.6,
        degrees: -spread + lean,
        reach: 1,
      ),
      if (behind >= 2)
        (
          centre: const Offset(17.4, 12.9),
          side: 8.6,
          degrees: spread + lean,
          reach: 1,
        ),
      if (behind >= 3)
        (
          centre: const Offset(12, 7.6),
          side: 9.2,
          degrees: spread / 3 + lean,
          reach: 0.8,
        ),
    ];
    // With a single board behind, it leans out on the side the seed picks.
    if (behind == 1 && seed.isOdd) {
      back[0] = (
        centre: const Offset(17.4, 12.9),
        side: 8.6,
        degrees: spread + lean,
        reach: 1,
      );
    }

    final knock = Paint()..color = background;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * unit
      ..strokeJoin = StrokeJoin.round;
    // The furthest board first, so each nearer one knocks it out.
    for (final b in back.reversed) {
      canvas.save();
      canvas.translate(b.centre.dx * unit, b.centre.dy * unit);
      canvas.rotate(b.degrees * math.pi / 180);
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: b.side * unit,
          height: b.side * unit,
        ),
        Radius.circular(1.2 * unit),
      );
      canvas.drawRRect(r, knock);
      canvas.drawRRect(r, edge..color = ink.withValues(alpha: 0.55 * b.reach));
      canvas.restore();
    }

    final face = frontRect(unit);
    final front = RRect.fromRectAndRadius(face, Radius.circular(1.3 * unit));
    canvas.drawRRect(front, knock);
    canvas.drawRRect(front, Paint()..color = ink.withValues(alpha: 0.14));
    canvas.drawRRect(
      front,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3 * unit
        ..color = ink,
    );

    if (!squares) return;
    final cell = (face.width - 2 * unit) / 4;
    final origin = face.topLeft + Offset(unit, unit);
    final square = Paint()..color = ink.withValues(alpha: 0.42);
    for (final (c, r) in _layouts[seed % _layouts.length]) {
      canvas.drawRect(
        Rect.fromLTWH(origin.dx + c * cell, origin.dy + r * cell, cell, cell),
        square,
      );
    }
  }

  @override
  bool shouldRepaint(_SmartDeckPainter old) =>
      old.ink != ink ||
      old.background != background ||
      old.seed != seed ||
      old.behind != behind ||
      old.pace != pace ||
      old.squares != squares;
}
