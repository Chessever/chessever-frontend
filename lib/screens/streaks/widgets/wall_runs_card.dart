import 'dart:math' as math;

import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Run lengths on the chart: 3 to 19 one column each, then 20+.
const int _kFirstRun = kStreakWallMin;
const int _kColumns = 18;

/// Tallest column, in squares.
const int _kMaxCells = 11;

/// Players per run length, one column each from 3 to 20+, as stacked squares.
/// Column height grows with the square root of the count, so the long tail
/// still shows next to the crowd at three; each column burns in its level's
/// colour and brightens towards its top.
@immutable
class WallRunBins {
  const WallRunBins(this.counts, this.total);

  factory WallRunBins.of(List<StreakRow> rows) {
    final counts = List<int>.filled(_kColumns, 0);
    for (final r in rows) {
      final i = (r.currentStreak - _kFirstRun).clamp(0, _kColumns - 1);
      counts[i]++;
    }
    return WallRunBins(counts, rows.length);
  }

  /// counts[i] is run length i + 3; the last is 20 and over.
  final List<int> counts;
  final int total;

  int get peak => counts.fold(0, math.max);

  /// Squares in column [i]: at least one for any player, none for nobody.
  int cells(int i) {
    final c = counts[i];
    if (c <= 0) return 0;
    return math.max(1, (math.sqrt(c / peak) * _kMaxCells).round());
  }

  static int runOf(int i) => i + _kFirstRun;
}

class WallRunsCard extends StatelessWidget {
  const WallRunsCard({super.key, required this.rows});

  final List<StreakRow> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bins = WallRunBins.of(rows);
    final muted = colors.textPrimary.withValues(alpha: 0.7);

    return Container(
      padding: EdgeInsets.fromLTRB(14.w, 14.w, 14.w, 12.w),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(4.w),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Runs right now',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: wallText(15, 20, FontWeight.w700, colors.textPrimary),
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: wallCount(bins.total),
                      style: wallText(
                        12,
                        16,
                        FontWeight.w700,
                        colors.textPrimary,
                        tabular: true,
                      ),
                    ),
                    TextSpan(text: bins.total == 1 ? ' player' : ' players'),
                  ],
                ),
                maxLines: 1,
                style: wallText(12, 16, FontWeight.w500, muted),
              ),
            ],
          ),
          SizedBox(height: 12.w),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final colW = width / _kColumns;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    label: _describe(bins),
                    excludeSemantics: true,
                    child: CustomPaint(
                      size: Size(width, 104.w),
                      painter: _RunsPainter(
                        bins,
                        unit: 1.w,
                        palette: wallFirePalette(context),
                        // Paper needs a higher floor before the faintest
                        // square clears 3:1.
                        alphaFloor: context.isLightTheme ? 0.76 : 0.45,
                      ),
                    ),
                  ),
                  SizedBox(height: 6.w),
                  _Ticks(colW: colW),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _describe(WallRunBins bins) {
    final parts = <String>[];
    for (var i = 0; i < _kColumns; i++) {
      if (bins.counts[i] == 0) continue;
      final run = i == _kColumns - 1 ? '20 or more' : '${WallRunBins.runOf(i)}';
      parts.add('$run wins: ${bins.counts[i]}');
    }
    return 'Players per run length. ${parts.join(', ')}';
  }
}

/// 3, 5, 10 and 20+, each centred under its own column.
class _Ticks extends StatelessWidget {
  const _Ticks({required this.colW});

  final double colW;

  @override
  Widget build(BuildContext context) {
    final style = wallText(
      11,
      16,
      FontWeight.w500,
      context.colors.textSecondary,
      tabular: true,
    );
    const ticks = [(0, '3'), (2, '5'), (7, '10'), (_kColumns - 1, '20+')];
    final labelW = 30.w;
    return ExcludeSemantics(
      child: SizedBox(
        height: 16.w,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final (i, label) in ticks)
              Positioned(
                left: i * colW + colW / 2 - labelW / 2,
                width: labelW,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    textAlign: TextAlign.center,
                    style: style,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RunsPainter extends CustomPainter {
  _RunsPainter(
    this.bins, {
    required this.unit,
    this.palette = kWallFire,
    this.alphaFloor = 0.45,
  });

  final WallRunBins bins;

  /// One design pixel in logical pixels.
  final double unit;

  /// One colour per [StreakLevel].
  final List<Color> palette;

  /// Opacity of a column's bottom square; each square above it steps up to
  /// full at the top.
  final double alphaFloor;

  @override
  void paint(Canvas canvas, Size size) {
    final colW = size.width / _kColumns;
    // The design's 8 px square with a 1.3 px gap, never wider than its lane.
    final cell = math.min(8 * unit, colW - 2);
    final gap = 1.3 * unit;
    final radius = Radius.circular(0.8 * unit);
    final paint = Paint()..isAntiAlias = true;
    for (var i = 0; i < _kColumns; i++) {
      final n = bins.cells(i);
      if (n == 0) continue;
      final color = palette[streakLevel(WallRunBins.runOf(i)).index];
      final x = i * colW + (colW - cell) / 2;
      for (var z = 0; z < n; z++) {
        final y = size.height - (z + 1) * (cell + gap) + gap;
        paint.color = color.withValues(
          alpha: alphaFloor + (1 - alphaFloor) * (z + 1) / n,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, y, cell, cell), radius),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RunsPainter old) =>
      old.unit != unit ||
      old.alphaFloor != alphaFloor ||
      !identical(old.palette, palette) ||
      !_sameCounts(old.bins, bins);

  static bool _sameCounts(WallRunBins a, WallRunBins b) {
    for (var i = 0; i < _kColumns; i++) {
      if (a.counts[i] != b.counts[i]) return false;
    }
    return true;
  }
}
