import 'dart:math' as math;

import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/widgets/feed_classification.dart';
import 'package:chessever2/screens/feed/widgets/feed_format.dart';
import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

/// Floating label surface used by the chart label and the move bubble: the
/// theme's popup surface with its own hairline edge, so the label's ink reads
/// in both themes.
BoxDecoration _labelSurface(BuildContext context) => BoxDecoration(
  color: context.colors.popup,
  borderRadius: BorderRadius.circular(4),
  border: Border.all(color: context.colors.divider),
);

/// The thin progress line along the bottom of a clip. At rest it is a 2px
/// line; under a finger it thickens to 6px, grows a white thumb, and every
/// horizontal position maps to a ply.
///
/// A scrub starts only once a finger has travelled sideways past the drag
/// slop, so a tap on the line or a vertical swipe that starts on it passes
/// through to the clip and the Feed's pager. Once it has started, the drag
/// owns the pointer until release, so it can never turn into a page swipe.
class FeedScrubStrip extends StatelessWidget {
  const FeedScrubStrip({
    required this.progress,
    required this.scrubbing,
    required this.fast,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    this.inset = FeedLayout.sidePadding,
    this.semanticsValue,
    super.key,
  });

  /// 0..1 along the game.
  final double progress;
  final bool scrubbing;
  final bool fast;
  final ValueChanged<double> onStart;
  final ValueChanged<double> onUpdate;
  final VoidCallback onEnd;
  final String? semanticsValue;

  /// Horizontal inset of the line; it lines up with the board column.
  final double inset;

  static const double _center = 17;

  double _fraction(Offset local, double width) {
    final track = math.max(1.0, width - 2 * inset);
    return ((local.dx - inset) / track).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.textPrimary;
    return Semantics(
      label: 'Scrub through the game',
      value: semanticsValue,
      slider: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            // The synthesized scroll actions would report a zero position
            // and jump the game to its start; the slider stays read-only.
            excludeFromSemantics: true,
            gestures: {
              HorizontalDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    HorizontalDragGestureRecognizer
                  >(
                    () => HorizontalDragGestureRecognizer(debugOwner: this),
                    (recognizer) => recognizer
                      // Winning the arena by default (no competitor) must
                      // not start a scrub on touch-down: wait for the slop.
                      ..onlyAcceptDragOnThreshold = true
                      // Start where the finger is once the slop is past,
                      // not where it first landed.
                      ..dragStartBehavior = DragStartBehavior.start
                      // Parenthesised: an unwrapped arrow body swallows the
                      // following cascade sections.
                      ..onStart = ((d) =>
                          onStart(_fraction(d.localPosition, width)))
                      ..onUpdate = ((d) =>
                          onUpdate(_fraction(d.localPosition, width)))
                      ..onEnd = ((_) => onEnd()),
                  ),
            },
            child: SizedBox(
              height: FeedLayout.scrubHeight,
              width: width,
              child: SingleMotionBuilder(
                value: scrubbing ? 1 : 0,
                motion: const CupertinoMotion.snappy(),
                builder: (context, t, _) {
                  final thickness = 2 + 4 * t.clamp(0.0, 1.0);
                  final track = width - 2 * inset;
                  return SingleMotionBuilder(
                    value: progress.clamp(0.0, 1.0),
                    active: !scrubbing,
                    motion: const CupertinoMotion.smooth(),
                    builder: (context, p, _) {
                      final fill = track * p.clamp(0.0, 1.0);
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: inset,
                            right: inset,
                            top: _center - thickness / 2,
                            height: thickness,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: ColoredBox(
                                      color: ink.withValues(alpha: 0.18),
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    bottom: 0,
                                    width: fill,
                                    child: ColoredBox(
                                      color: scrubbing || fast
                                          ? ink
                                          : ink.withValues(alpha: 0.9),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (scrubbing)
                            Positioned(
                              left: inset + fill - 8,
                              top: _center - 8,
                              width: 16,
                              height: 16,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: ink,
                                  shape: BoxShape.circle,
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x73000000),
                                      offset: Offset(0, 1),
                                      blurRadius: 3,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Report chart that rises over the lower half of a clip while scrubbing a
/// game that has evals: the eval curve, the error dots and a cursor on the
/// scrubbed ply.
class FeedReportOverlay extends StatelessWidget {
  const FeedReportOverlay({
    required this.item,
    required this.ply,
    required this.chartWidth,
    super.key,
  });

  final FeedItem item;
  final int ply;
  final double chartWidth;

  static const double chartHeight = 75;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = colors.background;
    final moment = item.plies[ply].moment;
    final judgmentColor = feedIsChartDot(moment)
        ? feedJudgmentColor(moment)
        : null;
    final evalText = feedEvalText(item, ply);
    final n = math.max(1, item.plyCount);
    final cursorX = chartWidth * ply / n;
    final pillText = [
      feedMoveLabel(item, ply),
      if (evalText.isNotEmpty) evalText,
      if (judgmentColor != null) moment!.label,
    ].join('  ');
    final pillStyle = AppTypography.textXxsBold.copyWith(
      fontSize: 10,
      height: 1.4,
      fontWeight: FontWeight.w600,
      color: colors.textPrimary,
      fontFeatures: _tabular,
    );
    // Measure the label so it can be centred on the cursor and clamped by its
    // real width: near the end of a game a long label ("34... Qxe5  -12.3
    // Missed win") must stop at the chart's right edge, not run off-screen.
    const pillInset = 6.0;
    const pillPadX = 7.0;
    final pillMax = math.max(0.0, math.min(260.0, chartWidth - 2 * pillInset));
    final painter = TextPainter(
      text: TextSpan(text: pillText, style: pillStyle),
      textDirection: Directionality.of(context),
      textScaler: TextScaler.noScaling,
      maxLines: 1,
      ellipsis: '\u2026',
    )..layout(maxWidth: math.max(0.0, pillMax - 2 * pillPadX));
    final pillWidth = math.min(
      pillMax,
      painter.width.ceilToDouble() + 2 * pillPadX,
    );
    painter.dispose();
    final pillLeft = (cursorX - pillWidth / 2)
        .clamp(
          pillInset,
          math.max(pillInset, chartWidth - pillInset - pillWidth),
        )
        .toDouble();

    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              bg.withValues(alpha: 0.98),
              bg.withValues(alpha: 0.96),
              bg.withValues(alpha: 0.7),
              bg.withValues(alpha: 0.25),
              bg.withValues(alpha: 0),
            ],
            stops: const [0, 0.58, 0.78, 0.92, 1],
          ),
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: chartWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FeedMoveInfoRow(
                  item: item,
                  ply: ply,
                  trailing: feedPlyText(item, ply),
                  height: 24,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: chartWidth,
                  height: chartHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _ReportChartPainter(
                            item: item,
                            ply: ply,
                            surface: colors.surfaceRecessed,
                            grid: colors.divider,
                            ink: colors.textPrimary,
                            // The text accent, not raw brand cyan: the
                            // cursor must clear 3:1 on the light chart.
                            cursor: colors.accentText,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 5,
                        left: pillLeft,
                        width: pillWidth,
                        child: DecoratedBox(
                          decoration: _labelSurface(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: pillPadX,
                              vertical: 3,
                            ),
                            child: Text(
                              pillText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textScaler: TextScaler.noScaling,
                              style: pillStyle,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportChartPainter extends CustomPainter {
  _ReportChartPainter({
    required this.item,
    required this.ply,
    required this.surface,
    required this.grid,
    required this.ink,
    required this.cursor,
  });

  final FeedItem item;
  final int ply;
  final Color surface;
  final Color grid;
  final Color ink;
  final Color cursor;

  double _y(int i, double h) {
    final share = feedWhiteShare(item, i) ?? 0.5;
    return h - share * h;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    canvas.drawRRect(rrect, Paint()..color = surface);
    canvas.save();
    canvas.clipRRect(rrect);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), gridPaint);
    for (final x in [w / 3, 2 * w / 3]) {
      for (var y = 0.0; y < h; y += 7) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(h, y + 3)), gridPaint);
      }
    }

    final n = item.plyCount;
    if (n > 0) {
      final line = Path();
      final area = Path()..moveTo(0, h);
      for (var i = 0; i <= n; i++) {
        final x = w * i / n;
        final y = _y(i, h);
        if (i == 0) {
          line.moveTo(x, y);
        } else {
          line.lineTo(x, y);
        }
        area.lineTo(x, y);
      }
      area
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(area, Paint()..color = ink.withValues(alpha: 0.08));
      canvas.drawPath(
        line,
        Paint()
          ..color = ink.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );

      final ring = Paint()
        ..color = surface.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      for (var i = 1; i <= n; i++) {
        final moment = item.plies[i].moment;
        if (!feedIsChartDot(moment)) continue;
        final c = Offset(w * i / n, _y(i, h));
        // Error dots are marks on the chart: 3:1 against its surface in
        // either theme, hue kept.
        final dot = feedReadableOn(
          feedJudgmentColor(moment)!,
          surface,
          target: 3,
        );
        canvas.drawCircle(c, 3.5, Paint()..color = dot);
        canvas.drawCircle(c, 3.5, ring);
      }

      final cx = w * ply / n;
      canvas.drawLine(
        Offset(cx, 0),
        Offset(cx, h),
        Paint()
          ..color = cursor.withValues(alpha: 0.8)
          ..strokeWidth = 2,
      );
      canvas.drawCircle(Offset(cx, _y(ply, h)), 5, Paint()..color = ink);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ReportChartPainter old) =>
      old.ply != ply || old.item != item || old.surface != surface;
}

/// "15. Nf3  [badge] Blunder ……… +1.2": the move label, its classification
/// (the board's own badge and word) and a right-aligned trailing figure.
class FeedMoveInfoRow extends StatelessWidget {
  const FeedMoveInfoRow({
    required this.item,
    required this.ply,
    required this.trailing,
    required this.height,
    super.key,
  });

  final FeedItem item;
  final int ply;
  final String trailing;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final moveClass = ply > 0 ? item.plies[ply].effectiveClass : null;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Flexible(
            child: Text(
              feedMoveLabel(item, ply),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textLgBold.copyWith(
                fontSize: 18,
                height: 24 / 18,
                color: colors.textPrimary,
                fontFeatures: _tabular,
              ),
            ),
          ),
          if (moveClass != null) ...[
            const SizedBox(width: 10),
            FeedClassMark(moveClass: moveClass, size: 16),
            const SizedBox(width: 5),
            Text(
              feedClassLabel(moveClass),
              maxLines: 1,
              style: AppTypography.textXsBold.copyWith(
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: feedClassTextColorFor(context, moveClass),
              ),
            ),
          ],
          const Spacer(),
          const SizedBox(width: 10),
          Text(
            trailing,
            maxLines: 1,
            style: AppTypography.textXsBold.copyWith(
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: colors.textPrimaryMuted,
              fontFeatures: _tabular,
            ),
          ),
        ],
      ),
    );
  }
}

/// Move bubble riding the scrub thumb on games with no report yet.
class FeedMoveBubble extends StatelessWidget {
  const FeedMoveBubble({required this.item, required this.ply, super.key});

  final FeedItem item;
  final int ply;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IgnorePointer(
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: DecoratedBox(
          decoration: _labelSurface(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  feedMoveLabel(item, ply),
                  style: AppTypography.textSmBold.copyWith(
                    fontSize: 13,
                    height: 1.2,
                    color: colors.textPrimary,
                    fontFeatures: _tabular,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  feedPlyText(item, ply),
                  style: AppTypography.textXxsMedium.copyWith(
                    fontSize: 11,
                    height: 1.2,
                    color: colors.textPrimaryMuted,
                    fontFeatures: _tabular,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
