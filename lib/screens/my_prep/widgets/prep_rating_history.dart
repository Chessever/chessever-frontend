import 'dart:math' as math;
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';

/// Monthly ratings from actual PGN tags. Touch the plot to read any month.
class PrepRatingHistory extends StatefulWidget {
  const PrepRatingHistory({super.key, required this.points});
  final List<(DateTime, int)> points;
  @override
  State<PrepRatingHistory> createState() => _PrepRatingHistoryState();
}

class _PrepRatingHistoryState extends State<PrepRatingHistory> {
  int? _selected;
  @override
  void didUpdateWidget(PrepRatingHistory old) {
    super.didUpdateWidget(old);
    if (!identical(old.points, widget.points)) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final index = (_selected ?? points.length - 1).clamp(0, points.length - 1);
    final selected = points[index];
    final min = points.map((p) => p.$2).reduce(math.min);
    final max = points.map((p) => p.$2).reduce(math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${selected.$2} · ${prepDateText(selected.$1)}',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            Text(
              '$min–$max',
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            void select(double x) {
              final fraction =
                  ((x - 6) / math.max(1, constraints.maxWidth - 12)).clamp(
                    0,
                    1,
                  );
              final first = points.first.$1.millisecondsSinceEpoch;
              final last = points.last.$1.millisecondsSinceEpoch;
              final time = first + (last - first) * fraction;
              var closest = 0;
              for (var i = 1; i < points.length; i++) {
                if ((points[i].$1.millisecondsSinceEpoch - time).abs() <
                    (points[closest].$1.millisecondsSinceEpoch - time).abs()) {
                  closest = i;
                }
              }
              setState(() => _selected = closest);
            }

            return Semantics(
              label:
                  'Rating history, lowest $min, highest $max, selected ${selected.$2} on ${prepDateText(selected.$1)}',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => select(details.localPosition.dx),
                onHorizontalDragUpdate: (details) =>
                    select(details.localPosition.dx),
                child: SizedBox(
                  height: 112,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _RatingPainter(
                      points,
                      index,
                      context.colors.textPrimary,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                prepDateText(points.first.$1),
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ),
            Text(
              prepDateText(points.last.$1),
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RatingPainter extends CustomPainter {
  _RatingPainter(this.points, this.selected, this.ink);
  final List<(DateTime, int)> points;
  final int selected;
  final Color ink;
  @override
  void paint(Canvas canvas, Size size) {
    final min = points.map((p) => p.$2).reduce(math.min) - 20;
    final max = points.map((p) => p.$2).reduce(math.max) + 20;
    final start = points.first.$1.millisecondsSinceEpoch;
    final span = math.max(1, points.last.$1.millisecondsSinceEpoch - start);
    Offset offset((DateTime, int) point) => Offset(
      6 + (point.$1.millisecondsSinceEpoch - start) / span * (size.width - 12),
      size.height - 6 - (point.$2 - min) / (max - min) * (size.height - 12),
    );
    final path = Path()
      ..moveTo(offset(points.first).dx, offset(points.first).dy);
    for (final point in points.skip(1)) {
      final at = offset(point);
      path.lineTo(at.dx, at.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = ink.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(offset(points[selected]), 4, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_RatingPainter old) =>
      old.points != points || old.selected != selected || old.ink != ink;
}
