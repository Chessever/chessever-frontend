import 'dart:io' as io;

import 'package:chessever2/screens/my_space/widgets/pixel_art.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/widgets/player_streak_format.dart';
import 'package:chessever2/screens/streaks/widgets/player_run_strip.dart'
    show kStreakRunFold;
import 'package:chessever2/utils/share_card.dart';
import 'package:chessever2/utils/share_card_palette.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessground/chessground.dart' show PieceSet;
import 'package:dartchess/dartchess.dart' show PieceKind;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const Color _kInk = Color(0xFF0C0C0E);
const Color _kWhite = Color(0xFFFFFFFF);

/// 70% white, pre-blended onto [_kInk]: opaque, so an ember behind a word
/// never shows through its strokes.
const Color _kMuted = Color(0xFFB6B6B7);
const Color _kGrey = Color(0xFF8E8E93);
const Color _kTitle = Color(0xFFE9EDCC);
const Color _kCyan = Color(0xFF0FB4E5);

/// The king inside the ChessEver mark, tinted to the app icon's deep cyan.
const Color _kKingInk = Color(0xFF0084C8);

/// The level word and the latest win on paper: [StreakFire.warmInk]'s light
/// value, a burnt tone of the flame that clears AA where the orange cannot.
const Color _kWarmOnPaper = Color(0xFFA8481A);

/// The dark card's flame: outer, mid, core.
const List<Color> _kDarkFlame = [
  StreakFire.outer,
  StreakFire.mid,
  StreakFire.core,
];

/// Paper inks the flame the way My Space's streaks door does
/// ([PixelPalette.light]): the dark card's pale core and amber wash out on
/// the page, the paper fire keeps its silhouette.
final List<Color> _kPaperFlame = [
  PixelPalette.light.fireOuter,
  PixelPalette.light.fireMid,
  PixelPalette.light.fireCore,
];

/// Paper embers, slot for slot with [StreakFire.embers] (outer, mid, light,
/// core). The pale light and core take the paper sparks' deep amber and rim,
/// as [PixelPalette.light]'s sparks re-ink the dark ones.
final List<Color> _kPaperEmbers = [
  PixelPalette.light.fireOuter,
  PixelPalette.light.fireMid,
  PixelPalette.light.spark,
  PixelPalette.light.fireOuter,
];

/// The words, squares and fire of the card, one set per edition. The mark
/// is art and reads on both grounds, so it stays.
@immutable
class _StreakInk {
  const _StreakInk({
    required this.page,
    required this.text,
    required this.muted,
    required this.grey,
    required this.title,
    required this.warm,
    required this.loss,
    required this.latest,
    required this.flame,
    required this.embers,
  });

  final Color page;
  final Color text;
  final Color muted;
  final Color grey;
  final Color title;
  final Color warm;
  final Color loss;
  final Color latest;

  /// Flame blocks: outer, mid, core.
  final List<Color> flame;

  /// Ember slots, in [StreakFire.embers] order.
  final List<Color> embers;

  /// The design's original dark set.
  static const dark = _StreakInk(
    page: _kInk,
    text: _kWhite,
    muted: _kMuted,
    grey: _kGrey,
    title: _kTitle,
    warm: StreakFire.mid,
    loss: StreakFire.loss,
    latest: StreakFire.light,
    flame: _kDarkFlame,
    embers: StreakFire.embers,
  );

  static _StreakInk of(BuildContext context) {
    final p = ShareCardPalette.of(context);
    if (!p.isLight) return dark;
    return _StreakInk(
      page: p.bg,
      text: p.textHi,
      muted: p.textMid,
      grey: p.textLo,
      title: p.gold,
      warm: _kWarmOnPaper,
      loss: p.loss,
      latest: _kWarmOnPaper,
      flame: _kPaperFlame,
      embers: _kPaperEmbers,
    );
  }
}

/// The 9:16 card a player's streak is shared as (Streaks-ShareCard design):
/// the big block flame, the count, "in a row", who, the run as squares, and
/// where to see it live. A fixed 360 x 640 canvas, independent of the phone's
/// size, dark or on paper as the capture's [ShareCardPalette] says;
/// [shareStreakCard] renders it at 3x to a 1080 x 1920 PNG.
class StreakShareCard extends StatelessWidget {
  const StreakShareCard({
    super.key,
    required this.player,
    required this.timeClass,
  });

  static const double width = 360;
  static const double height = 640;

  final PlayerStreaks player;
  final StreakTimeClass timeClass;

  /// The count a card leads with: the live run, else the best ever.
  static int countFor(PlayerStreaks p, StreakTimeClass tc) {
    final run = p.run(tc);
    if (run == null) return 0;
    return run.currentStreak > 0 ? run.currentStreak : run.bestStreak;
  }

  /// Whether a class has anything worth sharing.
  static bool canShare(PlayerStreaks p, StreakTimeClass tc) =>
      countFor(p, tc) > 0;

  static TextStyle _style(
    double size,
    double line, {
    FontWeight weight = FontWeight.w500,
    Color color = _kWhite,
    double letterSpacing = 0,
  }) {
    return TextStyle(
      fontFamily: 'InterDisplay',
      fontSize: size,
      height: line / size,
      leadingDistribution: TextLeadingDistribution.even,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures()],
      decoration: TextDecoration.none,
    );
  }

  // The layout's measures, shared by the widgets and [_wordRects] so the
  // ember keep-clear always matches where the words are drawn.
  static const double _inset = 24;
  static const double _lockupTop = 26;
  static const double _markSize = 24;
  static const double _markGap = 8;
  static const double _columnTop = 276;
  static const double _gapLevel = 8;
  static const double _gapName = 30;
  static const double _gapMeta = 4;
  static const double _gapRun = 22;
  static const double _gapCaption = 12;
  static const double _linkBottom = 22;

  @override
  Widget build(BuildContext context) {
    final ink = _StreakInk.of(context);
    final run = player.run(timeClass);
    final live = (run?.currentStreak ?? 0) > 0;
    final n = countFor(player, timeClass);
    final rating = player.ratings[timeClass];
    final meta = [
      streakCountry(player.fed),
      if (rating != null && rating > 0) '$rating',
    ].whereType<String>().join(' · ');
    final squares =
        live && run != null ? _stripColors(run, ink) : const <Color>[];
    final lossFirst =
        live && run != null && _hasAnchorLoss(run.currentRunGames);
    final hidden = live && run != null ? _hiddenWins(run) : 0;

    const brand = 'ChessEver';
    final brandStyle = _style(15, 20, weight: FontWeight.w700, color: ink.text);
    final count = '$n';
    final countStyle = _style(
      132,
      116,
      weight: FontWeight.w700,
      color: ink.text,
      letterSpacing: 3,
    );
    final level = live ? 'in a row' : 'best run';
    final levelStyle = _style(20, 24, weight: FontWeight.w700, color: ink.warm);
    final nameStyle = _style(26, 30, weight: FontWeight.w700, color: ink.text);
    final metaSpan = TextSpan(
      children: [
        if (player.title != null)
          TextSpan(
            text: player.title,
            style: TextStyle(color: ink.title, fontWeight: FontWeight.w700),
          ),
        if (player.title != null && meta.isNotEmpty)
          const TextSpan(text: ' · '),
        TextSpan(text: meta),
      ],
    );
    final metaStyle = _style(14, 18, color: ink.muted);
    final caption = '${timeClass.label} wins over the board';
    final captionStyle = _style(13, 18, color: ink.muted);
    const link = 'streaks.chessever.com';
    final linkStyle = _style(12, 16, color: ink.grey);

    final words = _wordRects(
      brand: TextSpan(text: brand, style: brandStyle),
      count: TextSpan(text: count, style: countStyle),
      level: TextSpan(text: level, style: levelStyle),
      name: TextSpan(text: player.displayName, style: nameStyle),
      meta: TextSpan(style: metaStyle, children: [metaSpan]),
      run: squares.isEmpty ? null : _RunSquares.sizeOf(squares.length, hidden),
      caption: TextSpan(text: caption, style: captionStyle),
      link: TextSpan(text: link, style: linkStyle),
    );

    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: ink.page,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _ShareScenePainter(
                  flame: ink.flame,
                  embers: ink.embers,
                  clear: words,
                ),
              ),
            ),
            Positioned(
              left: _inset,
              top: _lockupTop,
              child: Row(
                children: [
                  const StreakBrandMark(size: _markSize),
                  const SizedBox(width: _markGap),
                  Text(brand, style: brandStyle),
                ],
              ),
            ),
            Positioned(
              left: _inset,
              right: _inset,
              top: _columnTop,
              child: Column(
                children: [
                  Text(count, maxLines: 1, style: countStyle),
                  const SizedBox(height: _gapLevel),
                  Text(level, style: levelStyle),
                  const SizedBox(height: _gapName),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      player.displayName,
                      maxLines: 1,
                      style: nameStyle,
                    ),
                  ),
                  const SizedBox(height: _gapMeta),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text.rich(metaSpan, maxLines: 1, style: metaStyle),
                  ),
                  if (squares.isNotEmpty) ...[
                    const SizedBox(height: _gapRun),
                    _RunSquares(
                      colors: squares,
                      hidden: hidden,
                      lossFirst: lossFirst,
                      countColor: ink.muted,
                    ),
                  ],
                  const SizedBox(height: _gapCaption),
                  Text(caption, style: captionStyle),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: _linkBottom,
              child: Text(link, textAlign: TextAlign.center, style: linkStyle),
            ),
          ],
        ),
      ),
    );
  }

  /// Where the card's words sit, in card pixels: the lockup, the column
  /// (stacked as it lays out, a fitted line scaled down to the column's
  /// width) and the link. No ember is drawn inside one, so a square never
  /// muddies a stroke. The card is a fixed canvas captured without text
  /// scaling, so the words are measured the same way.
  static List<Rect> _wordRects({
    required InlineSpan brand,
    required InlineSpan count,
    required InlineSpan level,
    required InlineSpan name,
    required InlineSpan meta,
    required Size? run,
    required InlineSpan caption,
    required InlineSpan link,
  }) {
    const column = width - 2 * _inset;
    final rects = <Rect>[];

    final brandSize = _measure(brand);
    rects.add(
      Rect.fromLTWH(
        _inset,
        _lockupTop,
        _markSize + _markGap + brandSize.width,
        brandSize.height > _markSize ? brandSize.height : _markSize,
      ),
    );

    var y = _columnTop;
    void line(Size size, {double gap = 0, bool fit = false}) {
      final k = fit && size.width > column ? column / size.width : 1.0;
      final w = size.width * k > column ? column : size.width * k;
      final h = size.height * k;
      y += gap;
      rects.add(Rect.fromLTWH((width - w) / 2, y, w, h));
      y += h;
    }

    line(_measure(count));
    line(_measure(level), gap: _gapLevel);
    line(_measure(name), gap: _gapName, fit: true);
    line(_measure(meta), gap: _gapMeta, fit: true);
    if (run != null) line(run, gap: _gapRun);
    line(_measure(caption), gap: _gapCaption);

    final linkSize = _measure(link);
    rects.add(
      Rect.fromLTWH(
        (width - linkSize.width) / 2,
        height - _linkBottom - linkSize.height,
        linkSize.width,
        linkSize.height,
      ),
    );
    return rects;
  }

  /// One line's natural size, unscaled.
  static Size _measure(InlineSpan span) {
    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout();
    final size = painter.size;
    painter.dispose();
    return size;
  }

  /// Wins older than the fold are counted, not drawn.
  static int _hiddenWins(StreakClassRun run) {
    final wins = run.currentRunGames.where((g) => g.isWin).length;
    return wins > kStreakRunFold ? wins - kStreakRunFold : 0;
  }

  /// Whether the run opens on the loss it is counted from.
  static bool _hasAnchorLoss(List<StreakGame> games) =>
      games.isNotEmpty && !games.first.isWin;

  /// The anchor loss, then up to [kStreakRunFold] wins, the latest set apart
  /// (lighter on the dark card, deeper on paper).
  static List<Color> _stripColors(StreakClassRun run, _StreakInk ink) {
    final games = run.currentRunGames;
    final hasLoss = _hasAnchorLoss(games);
    final wins = games.where((g) => g.isWin).length;
    final shown = wins > kStreakRunFold ? kStreakRunFold : wins;
    return [
      if (hasLoss) ink.loss,
      for (var i = 0; i < shown; i++)
        i == shown - 1 ? ink.latest : StreakFire.outer,
    ];
  }
}

class _RunSquares extends StatelessWidget {
  const _RunSquares({
    required this.colors,
    required this.hidden,
    required this.lossFirst,
    required this.countColor,
  });

  final List<Color> colors;
  final int hidden;

  /// The first square is the anchor loss (the hidden count follows it).
  final bool lossFirst;

  /// Ink of the hidden-wins count.
  final Color countColor;

  static const double _side = 14;
  static const double _gap = 4;

  static TextStyle _countStyle(Color color) =>
      StreakShareCard._style(12, 14, weight: FontWeight.w700, color: color);

  /// The row's size for [squares] squares and [hidden] counted wins.
  static Size sizeOf(int squares, int hidden) {
    var w = squares * _side + (squares - 1) * _gap;
    var h = _side;
    if (hidden > 0) {
      final count = StreakShareCard._measure(
        TextSpan(text: '+$hidden', style: _countStyle(_kWhite)),
      );
      w += count.width + _gap;
      if (count.height > h) h = count.height;
    }
    return Size(w, h);
  }

  @override
  Widget build(BuildContext context) {
    Widget square(Color c) => Container(
      width: _side,
      height: _side,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(2),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < colors.length; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          // Hidden wins sit between the loss and the wins drawn, as a count.
          if (hidden > 0 && i == (lossFirst ? 1 : 0)) ...[
            Text('+$hidden', style: _countStyle(countColor)),
            const SizedBox(width: _gap),
          ],
          square(colors[i]),
        ],
      ],
    );
  }
}

// --------------------------------------------------------------------------
// The scene: embers and the 13 x 17 block flame, from the design's seed.

/// One block of the share card's scene, in card pixels. It keeps its slot,
/// not a colour, so each edition inks the same scene.
@immutable
class _Block {
  const _Block(
    this.rect,
    this.slot,
    this.opacity,
    this.radius, {
    this.ember = false,
  });

  final Rect rect;

  /// Index into the edition's flame (outer, mid, core) or, for an [ember],
  /// its embers.
  final int slot;
  final bool ember;
  final double opacity;
  final double radius;
}

double _round2(double v) => (v * 100).round() / 100;

/// Built once, exactly in the design's draw order (seed 23: the flame's
/// blocks first, then 70 ember attempts that skip the flame's box).
final List<_Block> _kShareScene = _buildShareScene();

List<_Block> _buildShareScene() {
  final rnd = PixelRandom(23);
  const s = 13.0;
  final cols = kStreaksBitmap.first.length;
  final ox = (StreakShareCard.width - cols * s) / 2;
  const oy = 58.0;
  const fire = {'O': 0, 'M': 1, 'C': 2};

  final flame = <_Block>[];
  for (var r = 0; r < kStreaksBitmap.length; r++) {
    final row = kStreaksBitmap[r];
    for (var c = 0; c < row.length; c++) {
      final ch = row[c];
      if (ch == '.') continue;
      final v = rnd.next();
      final opacity = ch == 'O' ? 0.7 + v * 0.3 : 0.85 + v * 0.15;
      // A pulse duration and delay in the design; drawn still here.
      if (v < 0.14) {
        rnd.next();
        rnd.next();
      }
      flame.add(
        _Block(
          Rect.fromLTWH(
            (ox + c * s + 0.8).roundToDouble(),
            (oy + r * s + 0.8).roundToDouble(),
            s - 1.6,
            s - 1.6,
          ),
          fire[ch]!,
          _round2(opacity),
          1,
        ),
      );
    }
  }

  final embers = <_Block>[];
  for (var k = 0; k < 70; k++) {
    final y = 30 + rnd.next() * 600;
    final size = 2 + rnd.next() * 7 * (y / StreakShareCard.height);
    final x = 6 + rnd.next() * 348;
    if (y > 60 && y < 290 && x > ox - 8 && x < ox + cols * s + 8) continue;
    final slot = (rnd.next() * 4).floor();
    final o = _round2((0.05 + rnd.next() * 0.22) * (0.3 + y / 700));
    final side = (size * 10).round() / 10;
    embers.add(
      _Block(
        Rect.fromLTWH(x.roundToDouble(), y.roundToDouble(), side, side),
        slot,
        o,
        0.8,
        ember: true,
      ),
    );
  }
  // Embers sit behind the flame, as in the SVG.
  return [...embers, ...flame];
}

/// How far an ember keeps from a word's box, in card pixels.
const double _kEmberClearance = 5;

class _ShareScenePainter extends CustomPainter {
  const _ShareScenePainter({
    required this.flame,
    required this.embers,
    this.clear = const [],
  });

  final List<Color> flame;
  final List<Color> embers;

  /// The words' boxes, in card pixels: an ember reaching into one (or within
  /// [_kEmberClearance] of it) is not drawn. The rest keep the design's seat.
  final List<Rect> clear;

  bool _behindWords(Rect ember) =>
      clear.any((w) => w.inflate(_kEmberClearance).overlaps(ember));

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / StreakShareCard.width;
    final paint = Paint()..isAntiAlias = true;
    for (final b in _kShareScene) {
      if (b.ember && _behindWords(b.rect)) continue;
      final color = b.ember ? embers[b.slot] : flame[b.slot];
      paint.color = color.withValues(alpha: b.opacity);
      final r = Rect.fromLTWH(
        b.rect.left * k,
        b.rect.top * k,
        b.rect.width * k,
        b.rect.height * k,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(b.radius * k)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ShareScenePainter old) =>
      !identical(old.flame, flame) ||
      !identical(old.embers, embers) ||
      !listEquals(old.clear, clear);
}

// --------------------------------------------------------------------------
// The ChessEver mark: four cyan corner squares and the centre square with
// the king, on the app icon's 800-unit grid.

/// The king drawn inside [StreakBrandMark].
final ImageProvider kStreakMarkKing =
    PieceSet.cburnett.assets[PieceKind.blackKing]!;

class StreakBrandMark extends StatelessWidget {
  const StreakBrandMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final u = size / 800;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _MarkPainter())),
          Positioned(
            left: 340 * u,
            top: 336 * u,
            width: 120 * u,
            height: 120 * u,
            child: Image(
              image: kStreakMarkKing,
              color: _kKingInk,
              colorBlendMode: BlendMode.srcIn,
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 800;
    final paint = Paint()..color = _kCyan;
    void square(double x, double y, double side, double radius) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * u, y * u, side * u, side * u),
          Radius.circular(radius * u),
        ),
        paint,
      );
    }

    square(192, 192, 138, 10);
    square(470, 192, 138, 10);
    square(192, 470, 138, 10);
    square(470, 470, 138, 10);
    square(322, 322, 156, 8);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => false;
}

// --------------------------------------------------------------------------
// Rendering and sharing.

/// One-line caption that rides with the image where the platform keeps text.
String streakShareCaption(PlayerStreaks p, StreakTimeClass tc) {
  final run = p.run(tc);
  final n = run?.currentStreak ?? 0;
  final who = [if (p.title != null) p.title!, p.displayName].join(' ');
  if (n > 0) {
    return '$who: $n ${streakWinsWord(tc, n)} in a row over the board.';
  }
  final best = run?.bestStreak ?? 0;
  return '$who: best run of $best ${streakWinsWord(tc, best)} in a row '
      'over the board.';
}

/// Renders [StreakShareCard] off-screen at 3x (1080 x 1920) and hands the PNG
/// to the native share sheet with the player's streak link. Failures raise one
/// danger snack; nothing throws out of here.
Future<void> shareStreakCard(
  BuildContext context, {
  required PlayerStreaks player,
  required StreakTimeClass timeClass,
  Rect? origin,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    // The king is the only image on the card; have it decoded before the
    // snapshot so the mark is never captured half-drawn.
    try {
      await precacheImage(kStreakMarkKing, context);
    } catch (_) {}
    if (!context.mounted) return;

    final media = MediaQuery.of(context);
    final bytes = await captureCardPng(
      context,
      width: StreakShareCard.width,
      pixelRatio: 3,
      minHeightFactor: StreakShareCard.height / StreakShareCard.width,
      child: MediaQuery(
        // A fixed canvas: the phone's text size must not reflow the card.
        data: media.copyWith(textScaler: TextScaler.noScaling),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: StreakShareCard(player: player, timeClass: timeClass),
        ),
      ),
    );
    if (bytes == null) throw StateError('Streak card render produced no image');

    final dir = await getTemporaryDirectory();
    final file = io.File(
      '${dir.path}/chessever_streak_${player.fideId}_${timeClass.wire}.png',
    );
    await file.writeAsBytes(bytes, flush: true);

    final url = streakShareUrl(player.fideId, timeClass);
    await shareFilesWithText(
      [XFile(file.path, mimeType: 'image/png')],
      text: '${streakShareCaption(player, timeClass)} $url',
      subject: '${player.displayName} on ChessEver Streaks',
      sharePositionOrigin: origin ?? const Rect.fromLTWH(0, 0, 1, 1),
    );
  } catch (error) {
    debugPrint('[Streaks] share card failed: $error');
    if (messenger != null && messenger.mounted) {
      showAppSnackOn(
        messenger,
        "Couldn't create the streak card",
        tone: AppSnackTone.danger,
      );
    }
  }
}
