import 'dart:math' as math;

import 'package:chessever2/screens/my_space/widgets/pixel_art.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_flame.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Height of the podium stage, before the embers' spill below it.
double wallPodiumHeight() => 232.w;

/// The hottest three runs on the visible wall, #1 raised in the middle, over
/// a bed of embers. Every player is drawn from the first frame; only the
/// embers and the flames move.
class WallPodium extends StatelessWidget {
  const WallPodium({super.key, required this.rows, required this.timeClass});

  /// Already ranked; the first three are used.
  final List<StreakRow> rows;
  final StreakTimeClass timeClass;

  @override
  Widget build(BuildContext context) {
    final top = rows.take(3).toList(growable: false);
    Widget slot(int rank) => rank < top.length
        ? _PodiumPlayer(row: top[rank], rank: rank + 1)
        : const SizedBox.shrink();

    return Semantics(
      container: true,
      label: 'Hottest three',
      child: SizedBox(
        height: wallPodiumHeight(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 252.w,
              child: _EmberBed(seed: 3 + timeClass.index),
            ),
            Positioned(
              left: 16.w,
              right: 16.w,
              bottom: 0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(flex: 100, child: slot(1)),
                  SizedBox(width: 8.w),
                  Expanded(flex: 115, child: slot(0)),
                  SizedBox(width: 8.w),
                  Expanded(flex: 100, child: slot(2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PodiumPlayer extends ConsumerWidget {
  const _PodiumPlayer({required this.row, required this.rank});

  final StreakRow row;
  final int rank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final centre = rank == 1;
    final ink = context.colors.textPrimary;
    final avatar = centre ? 64.w : 52.w;
    final flame = centre ? 46.w : 34.w;
    final number = centre ? 52.w : 38.w;

    return Builder(
      builder: (target) {
        return WallPressable(
          pressScale: 0.97,
          semanticLabel:
              'Number $rank, ${row.displayName}, '
              '${row.currentStreak} wins in a row',
          onTap: () => openWallStreakCard(context, row),
          onLongPress: () => showWallRowMenu(target, ref, row),
          child: Padding(
            padding: EdgeInsets.only(bottom: centre ? 28.w : 0),
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WallAvatar(row: row, size: avatar, showFlag: true),
                  SizedBox(height: 10.w),
                  SizedBox(
                    height: number,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          PixelFlame(streak: row.currentStreak, size: flame),
                          SizedBox(width: 6.w),
                          Text(
                            '${row.currentStreak}',
                            maxLines: 1,
                            // Sized in width units, not font units: the
                            // font scale caps at 40, and this is a display
                            // number that has to hold its 52.
                            style: AppTypography.textSmBold.copyWith(
                              fontSize: number,
                              height: 1,
                              letterSpacing: 1,
                              color: ink,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 8.w),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      row.shortName,
                      maxLines: 1,
                      style: wallText(13, 17, FontWeight.w700, ink),
                    ),
                  ),
                  Text(
                    wallMeta(row, withAge: false),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: wallText(
                      11,
                      15,
                      FontWeight.w500,
                      ink.withValues(alpha: 0.7),
                      tabular: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One square of the ember bed, in the design's 390 x 252 frame.
@immutable
class _Ember {
  const _Ember(
    this.x,
    this.y,
    this.side,
    this.color,
    this.opacity, [
    this.period,
    this.delay = 0,
  ]);

  final double x;
  final double y;
  final double side;
  final Color color;
  final double opacity;

  /// Seconds for one rise; null holds still.
  final double? period;
  final double delay;
}

/// Seeded like the design (mulberry32, draws in the same order), so the bed
/// is stable across rebuilds and each class gets its own.
List<_Ember> _layEmbers(int seed) {
  final r = PixelRandom(seed);
  return [for (var k = 0; k < 46; k++) _nextEmber(r)];
}

_Ember _nextEmber(PixelRandom r) {
  final y = 20 + r.next() * 200;
  final side = 3 + r.next() * 6 * (y / 220);
  final x = 8 + r.next() * 374;
  final color = kWallFire[(r.next() * 4).floor().clamp(0, 3)];
  // Brighter towards the floor, like a fire.
  final opacity = (0.08 + r.next() * 0.28) * (0.4 + y / 330);
  if (r.next() < 0.35) {
    final period = 2.2 + r.next() * 2;
    final delay = r.next();
    return _Ember(x, y, side, color, opacity, period, delay);
  }
  return _Ember(x, y, side, color, opacity);
}

/// Static fire-coloured squares with about a third of them drifting up and
/// back. Stills under reduced motion and whenever tickers are muted (the
/// podium scrolled away, another route on top).
class _EmberBed extends StatefulWidget {
  const _EmberBed({required this.seed});

  final int seed;

  @override
  State<_EmberBed> createState() => _EmberBedState();
}

class _EmberBedState extends State<_EmberBed>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);
  late List<_Ember> _embers = _layEmbers(widget.seed);
  double _base = 0;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(_EmberBed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seed != widget.seed) _embers = _layEmbers(widget.seed);
  }

  void _sync() {
    if (!_still && !_ticker.isActive) {
      _base = _clock.value;
      _ticker.start();
    } else if (_still && _ticker.isActive) {
      _ticker.stop();
      _clock.value = 0;
    }
  }

  void _onTick(Duration elapsed) {
    _clock.value = (_base + elapsed.inMicroseconds / 1e6) % 3600.0;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _EmberPainter(_embers, _clock),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _EmberPainter extends CustomPainter {
  _EmberPainter(this.embers, this.clock) : super(repaint: clock);

  final List<_Ember> embers;
  final ValueListenable<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 390;
    final t = clock.value;
    final paint = Paint()..isAntiAlias = true;
    for (final e in embers) {
      var dy = 0.0;
      final period = e.period;
      if (period != null && t > e.delay) {
        // Up 10 and back, easing at both ends: the CSS `ease-in-out
        // alternate` rise, as a plain cosine of time.
        dy = -10 * (0.5 - 0.5 * math.cos(math.pi * (t - e.delay) / period));
      }
      paint.color = e.color.withValues(alpha: e.opacity);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(e.x * k, (e.y + dy) * k, e.side * k, e.side * k),
          Radius.circular(0.8 * k),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_EmberPainter old) =>
      old.embers != embers || old.clock != clock;
}
