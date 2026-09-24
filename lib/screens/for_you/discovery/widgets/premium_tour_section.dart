import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/utils/legible_ink.dart';
import 'package:chessever2/screens/countrymen/countrymen_tab_screen.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/library/miniatures_screen.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// The position the opening-tree tile shows and opens: the French Defence,
/// Advance Variation, after 3.e5.
const String kDiscoveryTourOpeningFen =
    'rnbqkbnr/ppp2ppp/4p3/3pP3/3P4/8/PPP2PPP/RNBQKBNR b KQkq - 0 3';
const String _kTourOpeningLastMove = 'e4e5';

final Uri _kDesktopUri = Uri.parse('https://chessever.com/desktop');

/// Tile width, before responsive scaling.
const double _kTourTileWidth = 152;

/// The tile's text follows the system text size up to this factor, as the
/// streak hero does; past it the fixed-width tile would crush its copy.
const double _kTourMaxTextScale = 1.15;

TextScaler _tourScaler(BuildContext context) =>
    MediaQuery.textScalerOf(context).clamp(maxScaleFactor: _kTourMaxTextScale);

TextStyle _tourTitleStyle(BuildContext context) =>
    discoveryType(context, DiscoveryType.label, weight: FontWeight.w600);

TextStyle _tourCtaStyle(BuildContext context) => discoveryType(
  context,
  DiscoveryType.meta,
  weight: FontWeight.w600,
  color: context.colors.accentText,
);

/// The padlock's slot at the end of a tile's outcome: the page's one gap,
/// then the lock ([DiscoveryPadlock]'s one placement).
Size _tourLockSlot() => Size(DiscoveryPadlock.gap + 8.w, 10.w);

/// Lines the longest of [texts] needs at [width], so every tile on the rail
/// can reserve that many and no outcome is ever cut short. With [trailing],
/// each text is measured with that inline slot after its last word, as the
/// outcome's padlock rides.
int _linesNeeded(
  BuildContext context,
  Iterable<String> texts,
  TextStyle style,
  TextScaler scaler,
  double width, {
  Size? trailing,
}) {
  // Measure exactly as `Text` lays out: the ambient style merged under ours,
  // and the system Bold Text setting on top, since bolder glyphs wrap sooner.
  var resolved = DefaultTextStyle.of(context).style.merge(style);
  if (MediaQuery.boldTextOf(context)) {
    resolved = resolved.merge(const TextStyle(fontWeight: FontWeight.bold));
  }
  final direction = Directionality.of(context);
  var lines = 1;
  for (final text in texts) {
    final painter = TextPainter(
      text: TextSpan(
        style: resolved,
        children: [
          TextSpan(text: text),
          if (trailing != null) ...[
            const TextSpan(text: kDiscoveryGlue),
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: SizedBox.shrink(),
            ),
          ],
        ],
      ),
      textDirection: direction,
      textScaler: scaler,
    );
    if (trailing != null) {
      painter.setPlaceholderDimensions([
        PlaceholderDimensions(
          size: trailing,
          alignment: PlaceholderAlignment.middle,
        ),
      ]);
    }
    painter.layout(maxWidth: width);
    lines = math.max(lines, painter.computeLineMetrics().length);
    painter.dispose();
  }
  return lines;
}

/// One Premium outcome on the tour rail.
class _TourItem {
  const _TourItem({
    required this.id,
    required this.featureId,
    required this.title,
    required this.cta,
    required this.visual,
    required this.onUnlocked,
  });

  final String id;

  /// What the upgrade unlocks, as the paywall and its analytics know it
  /// ('most_liked_rankings'): the same id the feature's own lock sends.
  final String featureId;

  final String title;

  /// The outcome Premium unlocks, short. Where a section on the page already
  /// sells the same outcome in its own upgrade line, the tile never repeats
  /// that sentence, and never repeats its own title either.
  final String cta;
  final Widget visual;

  /// Where the viewer lands once Premium is confirmed.
  final FutureOr<void> Function() onUnlocked;
}

/// "With Premium": a rail of what Premium unlocks, each tile naming its
/// outcome ("Review a top game", "Prepare for this player") with the padlock
/// after it. Every tile goes through the Premium guard and, once unlocked,
/// straight to that outcome. Shown to free accounts only; subscribers
/// already have all of it.
///
/// Each outcome sentence is said once per page: the tiles for reviews,
/// rankings and the Miniatures archive use a shorter line of their own, as
/// their sections' upgrade lines carry the full sentence. Every tile stays,
/// so no way into the paywall is lost.
class PremiumTourSection extends ConsumerWidget {
  const PremiumTourSection({
    super.key,
    required this.onShowMostLiked,
    required this.onShowAnalyzed,
  });

  /// Brings the Most Liked section into view (after switching it to Week).
  final VoidCallback onShowMostLiked;

  /// Brings the Analyzed games section into view.
  final VoidCallback onShowAnalyzed;

  void _push(BuildContext context, Widget screen) {
    unawaited(
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => screen)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hottest = ref
        .watch(discoveryHotRowsProvider(StreakTimeClass.standard))
        .firstOrNull;
    final country = ref.watch(discoveryCountryProvider);
    // Rankings are sold only once Most Liked can rank. With the function
    // missing, paying would land on the same not-live notice.
    final rankingNotLive = ref.watch(
      mostLikedProvider(
        MostLikedQuery(MostLikedPeriod.today, DateTime.now()),
      ).select((r) => r.valueOrNull?.status == MostLikedStatus.notLive),
    );

    final items = <_TourItem>[
      _TourItem(
        id: 'reviews',
        featureId: 'analyzed_games',
        title: 'Full game reviews',
        // 'See turning points' is Analyzed games' own upgrade line.
        cta: 'Review a top game',
        visual: const _ReviewVisual(),
        onUnlocked: () {
          final games =
              ref.read(discoveryAnalyzedGamesProvider).valueOrNull ?? const [];
          if (games.isEmpty) {
            onShowAnalyzed();
          } else {
            openDiscoveryGame(context, ref, games, 0);
          }
        },
      ),
      if (!rankingNotLive)
        _TourItem(
          id: 'rankings',
          featureId: 'most_liked_rankings',
          title: 'Most liked rankings',
          // The full sentence (kMostLikedUpgradeCta) is Most liked's own
          // upgrade line.
          cta: "See the week's top games",
          visual: const _PeriodsVisual(),
          onUnlocked: () {
            ref.read(mostLikedPeriodProvider.notifier).state =
                MostLikedPeriod.week;
            onShowMostLiked();
          },
        ),
      _TourItem(
        id: 'prep',
        featureId: 'opponent_prep',
        title: 'Opponent prep',
        cta: 'Prepare for this player',
        visual: hottest == null
            ? DiscoveryMiniBoard(
                fen: kDiscoveryTourOpeningFen,
                lastMove: _kTourOpeningLastMove,
                size: 64.w,
              )
            // The flag's cut-out ring takes the tile's own fill, so it reads
            // as a notch in the photo, not a dark box parked behind the flag.
            : WallAvatar(
                row: hottest,
                size: 64.w,
                showFlag: true,
                ringColor: context.colors.surface,
              ),
        onUnlocked: () {
          if (hottest == null) {
            Navigator.of(context).pushNamed('/favorites_screen');
            return;
          }
          _push(
            context,
            PlayerProfileScreen(
              fideId: hottest.fideId,
              playerName: hottest.displayName,
              title: hottest.title,
              federation: hottest.fed,
              rating: hottest.rating,
            ),
          );
        },
      ),
      _TourItem(
        id: 'miniatures',
        featureId: 'miniatures_archive',
        title: 'Miniatures archive',
        // 'Explore the Miniatures archive' is the Miniatures section's own
        // upgrade line.
        cta: 'Browse past days',
        visual: const _ArchiveVisual(),
        onUnlocked: () => _push(context, const MiniaturesScreen()),
      ),
      _TourItem(
        id: 'tree',
        featureId: 'opening_tree',
        title: 'Full opening tree',
        cta: 'Explore this position',
        visual: DiscoveryMiniBoard(
          fen: kDiscoveryTourOpeningFen,
          lastMove: _kTourOpeningLastMove,
          size: 72.w,
        ),
        onUnlocked: () => _push(
          context,
          const GamebaseExplorerScreen(initialFen: kDiscoveryTourOpeningFen),
        ),
      ),
      _TourItem(
        id: 'countrymen',
        featureId: 'countrymen',
        title: 'Countrymen',
        cta: country == null
            ? "Follow your country's players"
            : 'Follow ${country.name}',
        visual: _FlagVisual(countryCode: country?.countryCode),
        onUnlocked: () => _push(context, const CountrymenTabScreen()),
      ),
      _TourItem(
        id: 'library',
        featureId: 'synced_library',
        title: 'Synced library',
        cta: 'Save to a synced personal database',
        visual: const _DatabaseVisual(),
        onUnlocked: () {
          ref.read(selectedBottomNavBarItemProvider.notifier).state =
              BottomNavBarItem.library;
        },
      ),
      _TourItem(
        id: 'desktop',
        featureId: 'desktop_app',
        title: 'ChessEver Desktop',
        cta: 'Continue on your computer',
        visual: const _DesktopVisual(),
        onUnlocked: () async {
          if (await canLaunchUrl(_kDesktopUri)) {
            await launchUrl(_kDesktopUri, mode: LaunchMode.externalApplication);
          }
        },
      ),
    ];

    // Every tile reserves the rows the longest title and the longest outcome
    // need, so the rail's text shares one baseline and nothing truncates.
    final scaler = _tourScaler(context);
    final width = _kTourTileWidth.w;
    final titleLines = _linesNeeded(
      context,
      items.map((item) => item.title),
      _tourTitleStyle(context),
      scaler,
      width,
    );
    final ctaLines = _linesNeeded(
      context,
      items.map((item) => item.cta),
      _tourCtaStyle(context),
      scaler,
      width,
      trailing: _tourLockSlot(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const DiscoverySectionHeader(title: 'With Premium'),
        SizedBox(height: 8.w),
        DiscoveryRail(
          // Static tiles with no fetches of their own: all of them mount.
          lazy: false,
          children: [
            for (final item in items)
              _TourTile(
                key: ValueKey('tour_${item.id}'),
                item: item,
                titleLines: titleLines,
                ctaLines: ctaLines,
                onTap: () => unlockThen(
                  context,
                  ref,
                  item.onUnlocked,
                  featureId: item.featureId,
                  returnTo: discoveryReturnTo('premium_tour'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TourTile extends StatelessWidget {
  const _TourTile({
    super.key,
    required this.item,
    required this.titleLines,
    required this.ctaLines,
    required this.onTap,
  });

  final _TourItem item;

  /// Rows reserved for the title and the outcome, shared by the whole rail.
  final int titleLines;
  final int ctaLines;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width = _kTourTileWidth.w;
    return Semantics(
      container: true,
      button: true,
      label: '${item.title}, ${item.cta}, Premium',
      excludeSemantics: true,
      // The child's tap is excluded with its semantics; without this the
      // node announces a button that screen readers cannot activate.
      onTap: onTap,
      child: WallPressable(
        pressScale: 0.97,
        onTap: onTap,
        // Clamped through an aspect-free wrapper so the tile does not depend
        // on all of MediaQuery (a keyboard's viewInsets would rebuild it on
        // every frame of the animation).
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: _kTourMaxTextScale,
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: width,
                  height: 96.w,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4.w),
                    child: ColoredBox(
                      color: context.colors.surface,
                      child: Center(child: item.visual),
                    ),
                  ),
                ),
                SizedBox(height: 8.w),
                _ReservedText(
                  item.title,
                  lines: titleLines,
                  style: _tourTitleStyle(context),
                ),
                SizedBox(height: 2.w),
                _ReservedText(
                  item.cta,
                  lines: ctaLines,
                  style: _tourCtaStyle(context),
                  // The tile's one padlock, after the outcome it gates.
                  locked: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [text] in a slot always [lines] rows tall, so a short string holds the
/// same height as the rail's longest one. A [locked] text ends in the
/// padlock, inline, so it follows the last word on any line.
class _ReservedText extends StatelessWidget {
  const _ReservedText(
    this.text, {
    required this.lines,
    required this.style,
    this.locked = false,
  });

  final String text;
  final int lines;
  final TextStyle style;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Opacity(
          opacity: 0,
          child: Text(
            List.filled(lines, ' ').join('\n'),
            maxLines: lines,
            style: style,
          ),
        ),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: text),
              if (locked) ...[
                // Glued to the last word: the lock never wraps alone.
                const TextSpan(text: kDiscoveryGlue),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: EdgeInsets.only(left: DiscoveryPadlock.gap),
                    child: DiscoveryPadlock(color: style.color),
                  ),
                ),
              ],
            ],
          ),
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- visuals

/// The engine's verdict over a real analyzed game, as a win-chance curve with
/// its turning points marked. Falls back to that game's final position, and
/// to a plain boards mark when there is no analyzed game at all.
class _ReviewVisual extends ConsumerWidget {
  const _ReviewVisual();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final curve = ref.watch(discoveryReviewCurveProvider).valueOrNull;
    if (curve != null) {
      return CustomPaint(
        // Centred, with the tile's own margin on both sides.
        size: Size(_kTourTileWidth.w - 28.w, 52.w),
        painter: _EvalCurvePainter(
          curve: curve,
          plate: context.colors.surfaceRecessed,
          midline: context.colors.dividerStrong,
          ink: context.colors.textPrimaryMuted,
          fill: context.colors.textPrimary.withValues(alpha: 0.08),
          // Paper: the burnt orange dots sit at 2.9:1 on the plate; the
          // same hue a step deeper clears 3:1.
          turn: legibleHueInk(
            context,
            const Color(0xFFC55A1E),
            minContrast: 3,
            on: context.colors.surfaceRecessed,
          ),
        ),
      );
    }
    final games = ref.watch(discoveryAnalyzedGamesProvider).valueOrNull;
    final first = games == null || games.isEmpty ? null : games.first;
    final fen = first?.fen?.trim() ?? '';
    return DiscoveryMiniBoard(
      fen: first != null && fen.isNotEmpty ? fen : kDiscoveryTourOpeningFen,
      lastMove: first != null && fen.isNotEmpty
          ? first.lastMove
          : _kTourOpeningLastMove,
      size: 72.w,
    );
  }
}

/// White's win chance from a centipawn score (the Lichess curve).
double _winChance(int cp) => 2 / (1 + math.exp(-0.00368208 * cp)) - 1;

/// A swing of this much win chance in one move is marked as a turning point.
const double _kTurningPoint = 0.35;

class _EvalCurvePainter extends CustomPainter {
  const _EvalCurvePainter({
    required this.curve,
    required this.plate,
    required this.midline,
    required this.ink,
    required this.fill,
    required this.turn,
  });

  final List<int> curve;
  final Color plate;
  final Color midline;
  final Color ink;
  final Color fill;
  final Color turn;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(h / 16)),
      Paint()..color = plate,
    );
    canvas.drawLine(
      Offset(0, h / 2),
      Offset(w, h / 2),
      Paint()
        ..color = midline
        ..strokeWidth = 1,
    );

    final n = curve.length;
    if (n < 2) return;
    final points = <Offset>[
      for (var i = 0; i < n; i++)
        Offset(i / (n - 1) * w, h - (1 + _winChance(curve[i])) / 2 * h),
    ];

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    final area = Path.from(line)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
      line,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    final dot = Paint()..color = turn;
    for (var i = 1; i < n; i++) {
      final swing = (_winChance(curve[i]) - _winChance(curve[i - 1])).abs();
      if (swing >= _kTurningPoint) canvas.drawCircle(points[i], 3, dot);
    }
  }

  @override
  bool shouldRepaint(_EvalCurvePainter oldDelegate) =>
      !identical(oldDelegate.curve, curve) ||
      oldDelegate.ink != ink ||
      oldDelegate.plate != plate ||
      oldDelegate.turn != turn;
}

/// The Most liked tabs as they stand for a free account: Today picked, and
/// Week, Month and Year beside it. The page's own segment look, turned on
/// its side to fit the tile. The tile's one padlock follows its outcome, so
/// the picture carries none of its own.
class _PeriodsVisual extends StatelessWidget {
  const _PeriodsVisual();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final light = context.isLightTheme;
    // A well cut into the tile, the thumb raised out of it.
    final well = light
        ? DiscoverySegments.fills(context).$1
        : colors.background;
    final thumb = light ? colors.surface : colors.surfaceRecessed;
    Widget row(MostLikedPeriod period) {
      final picked = period == MostLikedPeriod.today;
      final text = Text(
        period.label,
        maxLines: 1,
        style: discoveryType(
          context,
          DiscoveryType.meta,
          weight: picked ? FontWeight.w600 : FontWeight.w500,
          color: picked ? colors.textPrimary : colors.textSecondary,
        ),
      );
      return Container(
        height: 19.w,
        padding: EdgeInsets.symmetric(horizontal: 8.w),
        decoration: picked
            ? BoxDecoration(
                color: thumb,
                borderRadius: BorderRadius.circular(5.w),
              )
            : null,
        child: Align(alignment: Alignment.centerLeft, child: text),
      );
    }

    return ExcludeSemantics(
      child: MediaQuery.withNoTextScaling(
        child: Container(
          width: 92.w,
          padding: EdgeInsets.all(2.w),
          decoration: BoxDecoration(
            color: well,
            borderRadius: BorderRadius.circular(7.w),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [for (final p in MostLikedPeriod.values) row(p)],
          ),
        ),
      ),
    );
  }
}

/// The archive in hand: three of today's miniatures fanned like cards (the
/// opening-tree position stands in while they load), over the archive's
/// real size from the community index.
class _ArchiveVisual extends ConsumerWidget {
  const _ArchiveVisual();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(miniaturesTotalCountProvider).valueOrNull;
    final minis =
        ref.watch(discoveryTodayMiniaturesProvider).valueOrNull ?? const [];
    final boards = [
      for (var i = 0; i < 3; i++)
        if (i < minis.length && (minis[i].game.fen?.trim().isNotEmpty ?? false))
          (fen: minis[i].game.fen!.trim(), lastMove: minis[i].game.lastMove)
        else
          (fen: kDiscoveryTourOpeningFen, lastMove: _kTourOpeningLastMove),
    ];
    final side = 40.w;
    final outline = context.isLightTheme
        ? Colors.black.withValues(alpha: 0.1)
        : Colors.white.withValues(alpha: 0.1);
    Widget board(({String fen, String? lastMove}) b, double turn, double dx) {
      return Transform.translate(
        offset: Offset(dx, turn == 0 ? 0 : 3.w),
        child: Transform.rotate(
          angle: turn,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border.all(color: outline, width: 1),
            ),
            child: DiscoveryMiniBoard(
              fen: b.fen,
              lastMove: b.lastMove,
              size: side,
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: side * 2.3,
          height: side + 8.w,
          child: Stack(
            alignment: Alignment.center,
            children: [
              board(boards[1], -0.16, -side * 0.62),
              board(boards[2], 0.16, side * 0.62),
              board(boards[0], 0, 0),
            ],
          ),
        ),
        if (total != null && total > 0) ...[
          SizedBox(height: 4.w),
          Text(
            wallCount(total),
            maxLines: 1,
            style: discoveryType(
              context,
              DiscoveryType.meta,
              weight: FontWeight.w700,
              color: context.colors.textPrimary,
              tabular: true,
            ),
          ),
        ],
      ],
    );
  }
}

/// The viewer's flag, washed back behind the tile.
class _FlagVisual extends StatelessWidget {
  const _FlagVisual({required this.countryCode});

  final String? countryCode;

  @override
  Widget build(BuildContext context) {
    final code = countryCode;
    if (code == null || code.isEmpty) {
      // Country not known yet: a hand of federations, the way Countrymen
      // reads (a flag per player), rather than a stand-in glyph.
      final w = 34.w;
      final h = 24.w;
      Widget flag(String fed, double turn, double dx) => Transform.translate(
        offset: Offset(dx, turn == 0 ? 0 : 2.w),
        child: Transform.rotate(
          angle: turn,
          child: FederationFlag(
            federation: fed,
            width: w,
            height: h,
            borderRadius: BorderRadius.circular(3.w),
          ),
        ),
      );
      return ExcludeSemantics(
        child: SizedBox(
          width: w * 2.4,
          height: h + 10.w,
          child: Stack(
            alignment: Alignment.center,
            children: [
              flag('NOR', -0.14, -w * 0.6),
              flag('USA', 0.14, w * 0.6),
              flag('IND', 0, 0),
            ],
          ),
        ),
      );
    }
    return SizedBox.expand(
      child: Opacity(
        opacity: 0.25,
        child: FittedBox(
          fit: BoxFit.cover,
          child: CountryFlag.fromCountryCode(
            code,
            theme: const ImageTheme(width: 200, height: 150),
          ),
        ),
      ),
    );
  }
}

/// A synced personal database, up to 100,000 games: the figure is the
/// picture.
class _DatabaseVisual extends StatelessWidget {
  const _DatabaseVisual();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '100,000',
          maxLines: 1,
          style: discoveryType(context, DiscoveryType.display),
        ),
        Text(
          'games',
          maxLines: 1,
          style: discoveryType(context, DiscoveryType.meta),
        ),
      ],
    );
  }
}

/// The desktop app: a laptop with a real position on its screen, drawn in
/// the viewer's own board theme.
class _DesktopVisual extends StatelessWidget {
  const _DesktopVisual();

  @override
  Widget build(BuildContext context) {
    final side = 76.w;
    final k = side / 24;
    // The screen's inner box in the painter's 24-unit grid: x 4..20,
    // y 5..15.5, less the stroke.
    final board = 8.6 * k;
    return SizedBox.square(
      dimension: side,
      child: Stack(
        children: [
          CustomPaint(
            size: Size.square(side),
            painter: _LaptopPainter(context.colors.textPrimary),
          ),
          Positioned(
            left: 12 * k - board / 2,
            top: 10.25 * k - board / 2,
            child: DiscoveryMiniBoard(
              fen: kDiscoveryTourOpeningFen,
              lastMove: _kTourOpeningLastMove,
              size: board,
            ),
          ),
        ],
      ),
    );
  }
}

/// The design's laptop: a round-cornered screen over a round-capped base.
class _LaptopPainter extends CustomPainter {
  const _LaptopPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1 * k
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(4 * k, 5 * k, 16 * k, 10.5 * k),
        Radius.circular(1.2 * k),
      ),
      stroke,
    );
    canvas.drawLine(Offset(2 * k, 18.5 * k), Offset(22 * k, 18.5 * k), stroke);
  }

  @override
  bool shouldRepaint(_LaptopPainter oldDelegate) => oldDelegate.color != color;
}
