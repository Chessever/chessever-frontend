import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_flame.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/providers/streak_providers.dart';
import 'package:chessever2/screens/streaks/streaks_screen.dart';
import 'package:chessever2/screens/streaks/widgets/player_streak_format.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Where the streak wall stands, as far as the rail cares.
enum _WallPhase { loading, ready, failed }

_WallPhase _wallPhase(AsyncValue<List<StreakRow>> wall) {
  if (wall.hasValue) return _WallPhase.ready;
  if (wall.hasError && !wall.isLoading) return _WallPhase.failed;
  return _WallPhase.loading;
}

/// Tile size: the avatar, the run, the name and its level word over the
/// strip, and nothing the segments above already say.
double get _tileWidth => 112.w;
double get _tileHeight => 172.w;

/// Streaks: the longest live winning runs, one time class at a time. The
/// runs of players the viewer follows come first (whatever their rating),
/// then the strongest 2400+ runs from the streak wall. "All streaks" opens
/// the wall on the same class.
class WhosHotSection extends ConsumerStatefulWidget {
  const WhosHotSection({super.key});

  @override
  ConsumerState<WhosHotSection> createState() => _WhosHotSectionState();
}

class _WhosHotSectionState extends ConsumerState<WhosHotSection> {
  @override
  void initState() {
    super.initState();
    // After this frame: a re-read publishes a loading state, which a provider
    // may not do while the tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshIfStale());
  }

  void _refreshIfStale() {
    if (!mounted) return;
    final wall = ref.read(streakWallProvider);
    if (wall.isLoading && !wall.hasValue) return;
    unawaited(ref.read(streakWallProvider.notifier).refreshIfStale());
  }

  void _openWall(StreakTimeClass tc) {
    HapticFeedbackService.navigation();
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StreaksScreen(initialClass: tc),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tc = ref.watch(discoveryHotClassProvider);
    final phase = ref.watch(streakWallProvider.select(_wallPhase));
    final items = ref.watch(discoveryStreakRowsProvider(tc));

    final Widget body;
    if (items.isNotEmpty) {
      body = DiscoveryRail(
        gap: 10,
        children: [
          for (final item in items)
            DiscoveryStreakTile(
              key: ValueKey('hot_${item.row.fideId}'),
              row: item.row,
              followed: item.followed,
            ),
        ],
      );
    } else {
      body = switch (phase) {
        _WallPhase.loading => DiscoverySkeletonRail(
          width: _tileWidth,
          height: _tileHeight,
          count: 4,
        ),
        _WallPhase.failed => DiscoveryNotice(
          text: "Couldn't load live streaks",
          actionLabel: 'Retry',
          onAction: () =>
              unawaited(ref.read(streakWallProvider.notifier).refresh()),
        ),
        _WallPhase.ready => DiscoveryNotice(
          text: 'No live ${tc.label.toLowerCase()} runs at 2400+ right now',
        ),
      };
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DiscoverySectionHeader(
          title: 'Streaks',
          trailing: DiscoveryAction(
            label: 'All streaks',
            arrow: true,
            onTap: () => _openWall(tc),
          ),
        ),
        DiscoverySegments<StreakTimeClass>(
          values: StreakTimeClass.values,
          selected: tc,
          label: (t) => t.label,
          leading: (t) => TimeControlGlyph(wallTimeClassAsset(t), size: 14.w),
          semanticsPrefix: 'Time control',
          onSelect: (t) =>
              ref.read(discoveryHotClassProvider.notifier).state = t,
        ),
        SizedBox(height: 12.w),
        body,
      ],
    );
  }
}

/// One live run: the player's avatar with its flag, the flame and the run
/// length, the surname, the level word, and the run itself as a strip (the
/// loss that anchors it, then the wins). A player the viewer follows wears a
/// small star before the name. Tapping opens the player's streak card on
/// that class; a long-press lifts the tile into the wall's own focus menu
/// (open card, open profile, My Space).
class DiscoveryStreakTile extends ConsumerWidget {
  const DiscoveryStreakTile({
    super.key,
    required this.row,
    this.followed = false,
  });

  final StreakRow row;
  final bool followed;

  /// The text lines, the flame row and the run strip fill the fixed plate
  /// with a few points to spare at 1x; 1.1 keeps them inside the padding.
  static const double _maxTextScale = 1.1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = row.currentStreak;
    // The spec's ember orange, deepened on the light plate so it still reads.
    final warm = context.isLightTheme
        ? const Color(0xFFB4470F)
        : const Color(0xFFF59A3C);

    void open() => openWallStreakCard(context, row);
    // No lifted copy, as on the wall's podium: the shared menu is at least
    // 200 wide, and a narrow tile stretched to it would distort.
    void menu() => unawaited(showWallRowMenu(context, ref, row));

    final nameStyle = discoveryType(
      context,
      DiscoveryType.body,
      weight: FontWeight.w700,
    );
    final name = _SnugName(text: row.shortName, style: nameStyle);

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: _maxTextScale,
      // excludeSemantics drops the gesture actions below, so the node carries
      // them itself: screen readers, Switch Access and Voice Access can open
      // the card and the menu.
      child: Semantics(
        container: true,
        button: true,
        label: [
          row.displayName,
          if (followed) 'following',
          row.timeClass.label,
          '$n wins in a row',
          row.level.word,
        ].join(', '),
        excludeSemantics: true,
        onTap: open,
        onLongPress: menu,
        onLongPressHint: 'More actions',
        child: WallPressable(
          pressScale: 0.97,
          onTap: open,
          onLongPress: menu,
          child: SizedBox(
            width: _tileWidth,
            height: _tileHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(4.w),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(12.w, 14.w, 12.w, 12.w),
                child: Column(
                  children: [
                    WallAvatar(
                      row: row,
                      size: 52.w,
                      showFlag: true,
                      ringColor: context.colors.surface,
                    ),
                    SizedBox(height: 10.w),
                    SizedBox(
                      height: 30.w,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          PixelFlame(streak: n, size: 26.w),
                          SizedBox(width: 4.w),
                          // A three-digit run shrinks to the tile rather
                          // than spilling past it.
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.bottomLeft,
                              child: Text(
                                '$n',
                                maxLines: 1,
                                textHeightBehavior: const TextHeightBehavior(
                                  applyHeightToLastDescent: false,
                                ),
                                style: discoveryType(
                                  context,
                                  DiscoveryType.display,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 4.w),
                    if (followed)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Following is information, not an action: the
                          // star wears the name's own ink, stepped back the
                          // way a segment glyph rests beside its label, so
                          // it never outshouts the picked tab above.
                          CustomPaint(
                            size: Size.square(9.w),
                            painter: _StarPainter(
                              nameStyle.color!.withValues(alpha: 0.55),
                            ),
                          ),
                          SizedBox(width: 4.w),
                          Flexible(child: name),
                        ],
                      )
                    else
                      name,
                    Text(
                      row.level.word.toLowerCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: discoveryType(
                        context,
                        DiscoveryType.meta,
                        weight: FontWeight.w600,
                        color: warm,
                      ),
                    ),
                    const Spacer(),
                    _RunStrip(wins: n),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The surname on one line. A long one (Abdusattorov, Nepomniachtchi) eases
/// a little smaller rather than lose its end; past [minScale] it keeps its
/// size and ends in an ellipsis, so a name never turns into fine print. The
/// line keeps its height either way, so the level word below stays level
/// across the rail.
class _SnugName extends StatelessWidget {
  const _SnugName({required this.text, required this.style});

  final String text;
  final TextStyle style;

  static const double minScale = 0.78;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final plain = Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: style,
        );
        if (!box.maxWidth.isFinite || box.maxWidth <= 0) return plain;
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final width = painter.width;
        final height = painter.height;
        painter.dispose();
        if (width <= box.maxWidth || box.maxWidth / width < minScale) {
          return plain;
        }
        return SizedBox(
          width: box.maxWidth,
          height: height,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(text, maxLines: 1, softWrap: false, style: style),
          ),
        );
      },
    );
  }
}

/// A small five-point star with rounded joins: this is someone you follow.
class _StarPainter extends CustomPainter {
  const _StarPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = size.shortestSide / 2;
    final inner = outer * 0.48;
    // A five-point star's box is taller above its centre than below; drop
    // the centre a touch so it sits optically centred on the name's line.
    final c = size.center(Offset.zero) + Offset(0, outer * 0.08);
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    // Filled, then stroked in the same ink with round joins, so the points
    // read soft at nine pixels instead of pin-sharp.
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = outer * 0.22
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_StarPainter oldDelegate) => oldDelegate.color != color;
}

/// The run as a strip of small squares: the loss that anchors it, drawn
/// hollow so it never reads as one more ember, then up to eleven wins, the
/// latest three brightest.
class _RunStrip extends StatelessWidget {
  const _RunStrip({required this.wins});

  final int wins;

  // Paper: the pale amber reads 1.5:1 and the red cell needs the deeper
  // danger ink; the burnt win cell already clears 3:1.
  static const _freshOnPaper = Color(0xFFB4470F);
  static const _maxShown = 11;

  @override
  Widget build(BuildContext context) {
    final isLight = context.isLightTheme;
    final loss = isLight ? context.colors.danger : StreakFire.loss;
    final fresh = isLight ? _freshOnPaper : StreakFire.light;
    final side = 6.w;
    final gap = 2.w;
    return LayoutBuilder(
      builder: (context, constraints) {
        // As many wins as the tile holds after the loss, up to eleven.
        final fits = ((constraints.maxWidth + gap) / (side + gap)).floor() - 1;
        final shown = wins.clamp(0, math.min(_maxShown, math.max(fits, 0)));
        final colors = [
          loss,
          for (var i = 0; i < shown; i++)
            i >= shown - 3 ? fresh : StreakFire.outer,
        ];
        return _strip(colors, side, gap);
      },
    );
  }

  Widget _strip(List<Color> colors, double side, double gap) {
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < colors.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            SizedBox(
              width: side,
              height: side,
              // The first cell is the loss: an outline, not a fill.
              child: DecoratedBox(
                decoration: i == 0
                    ? BoxDecoration(
                        border: Border.all(color: colors[i], width: 1.w),
                        borderRadius: BorderRadius.circular(1.w),
                      )
                    : BoxDecoration(
                        color: colors[i],
                        borderRadius: BorderRadius.circular(1.w),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
