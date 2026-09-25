import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Asset key of the fragment shader that draws every pixel-art object.
/// Registered under `flutter: shaders:` in pubspec.yaml.
const String kPixelArtShaderAsset = 'shaders/space_door.frag';

/// The sparkle colours the shader draws itself (see `kCyan` there); only the
/// static fallback painter reads these.
const Color _kCyan = Color(0xFF0FB4E5);
const Color _kWhite = Color(0xFFFFFFFF);

/// Which surface a pixel object is drawn on. The art is designed as light
/// blocks on a black tile; on paper the same shapes are inked instead.
enum PixelTone {
  dark,
  light;

  /// The tone of the theme [context] is in.
  static PixelTone of(BuildContext context) =>
      context.isLightTheme ? PixelTone.light : PixelTone.dark;
}

/// The block colours of every pixel object, per [PixelTone].
///
/// [dark] is the original design, byte for byte. [light] inks the same
/// shapes for paper: the strong checker, the accent and the reds clear 3:1
/// on the light surface and page tokens at rest, and the fire clears it
/// through the whole flicker (see [flickerDip]), so no object dissolves into
/// the tile or page it sits on.
@immutable
class PixelPalette {
  const PixelPalette({
    required this.square,
    required this.squareAlt,
    required this.accent,
    required this.red,
    required this.redBright,
    required this.whitePiece,
    required this.blackPiece,
    required this.handle,
    required this.handleAlt,
    required this.fireOuter,
    required this.fireOuterCool,
    required this.fireMid,
    required this.fireCore,
    required this.spark,
    required this.sparks,
    this.fireRimOpacity = 0.85,
    this.flickerDip,
  });

  /// The checker square that carries the silhouette.
  final Color square;

  /// The quieter checker square.
  final Color squareAlt;

  /// Stars, ribbons, rims and the scan line.
  final Color accent;
  final Color red;

  /// The one-in-five heart block that catches the light.
  final Color redBright;
  final Color whitePiece;
  final Color blackPiece;

  /// The magnifier handle, in two steps.
  final Color handle;
  final Color handleAlt;

  /// Fire, outside in. [fireOuterCool] is the flame's rim before a streak
  /// reaches five.
  final Color fireOuter;
  final Color fireOuterCool;
  final Color fireMid;
  final Color fireCore;

  /// Sparks thrown by the small flame.
  final Color spark;

  /// Embers for the large streak flame ([kStreaksBitmap]), cycled in order.
  final List<Color> sparks;

  /// The streak flame's rim at rest. The dark tile softens it; paper keeps it
  /// solid, because the rim carries the silhouette.
  final double fireRimOpacity;

  /// How far a fire block's opacity dips as it flickers; null keeps the
  /// design's .38. Paper dips less, so even the dimmest frame of the flame
  /// holds 3:1 on the page.
  final double? flickerDip;

  static const PixelPalette dark = PixelPalette(
    square: Color(0xFFDEE3E6),
    squareAlt: Color(0xFF8CA2AD),
    accent: Color(0xFF0FB4E5),
    red: Color(0xFFF5453A),
    redBright: Color(0xFFFF8A7F),
    whitePiece: Color(0xFFFFFFFF),
    blackPiece: Color(0xFF0C0C0E),
    handle: Color(0xFF5A5A5E),
    handleAlt: Color(0xFF6E6E73),
    fireOuter: Color(0xFFE4552A),
    fireOuterCool: Color(0xFFE76530),
    fireMid: Color(0xFFF59A3C),
    fireCore: Color(0xFFFFE08A),
    spark: Color(0xFFFFB454),
    sparks: [Color(0xFFFFB454), Color(0xFFF59A3C), Color(0xFFFFE08A)],
  );

  static const PixelPalette light = PixelPalette(
    square: Color(0xFF2B3F43),
    squareAlt: Color(0xFF6A8388),
    accent: Color(0xFF007399),
    red: Color(0xFFC53128),
    redBright: Color(0xFFD9463C),
    whitePiece: Color(0xFFD3DCDD),
    blackPiece: Color(0xFF0E1A1C),
    handle: Color(0xFF4D5E61),
    handleAlt: Color(0xFF58696B),
    // Red rim, orange body, amber core: each holds 3:1 on the mint page and
    // the surfaces at the bottom of the flicker (opacity .8), 4.4:1 at rest.
    fireOuter: Color(0xFFB42A0E),
    fireOuterCool: Color(0xFFA8481A),
    fireMid: Color(0xFFB8480A),
    fireCore: Color(0xFFA35600),
    spark: Color(0xFFAD5A00),
    sparks: [Color(0xFFAD5A00), Color(0xFFB8480A), Color(0xFFB42A0E)],
    fireRimOpacity: 1,
    flickerDip: 0.2,
  );

  static PixelPalette of(PixelTone tone) =>
      tone == PixelTone.light ? light : dark;
}

const int _kMaxEmbers = 5;
const int _kMaxSparkles = 3;

/// What a single block does over time.
enum PixelFx {
  /// Holds still; catches the diagonal glint on door art.
  none,

  /// Opacity 1 -> .55 -> 1.
  pulse,

  /// Opacity 1 -> .62 -> 1 (fire); [PixelCell.dip] can make it shallower.
  flicker,

  /// Slides down a few pixels and back.
  drift,
}

/// The seeded generator the design files use (mulberry32), ported bit for bit
/// so the per-block opacity jitter matches the HTML source exactly.
class PixelRandom {
  PixelRandom(int seed) : _t = seed & 0xffffffff;

  /// Seeds from a string the way the HTML does (`seed * 31 + charCode`).
  factory PixelRandom.forKey(String key) {
    var seed = 0;
    for (final unit in key.codeUnits) {
      seed = (seed * 31 + unit) & 0xffffffff;
    }
    return PixelRandom(seed);
  }

  int _t;

  static int _imul(int a, int b) {
    final al = a & 0xffff;
    final ah = (a >>> 16) & 0xffff;
    final bl = b & 0xffff;
    final bh = (b >>> 16) & 0xffff;
    final mid = ((ah * bl + al * bh) & 0xffff) << 16;
    return (al * bl + mid) & 0xffffffff;
  }

  double next() {
    _t = (_t + 0x6D2B79F5) & 0xffffffff;
    var r = _imul(_t ^ (_t >>> 15), 1 | _t);
    r = (r ^ ((r + _imul(r ^ (r >>> 7), 61 | r)) & 0xffffffff)) & 0xffffffff;
    return ((r ^ (r >>> 14)) & 0xffffffff) / 4294967296.0;
  }
}

/// One block of a bitmap.
@immutable
class PixelCell {
  const PixelCell({
    required this.col,
    required this.row,
    required this.color,
    required this.opacity,
    this.fx = PixelFx.none,
    this.period = 0,
    this.phase = 0,
    this.dip,
  });

  final int col;
  final int row;
  final Color color;
  final double opacity;
  final PixelFx fx;

  /// How far [PixelFx.pulse] or [PixelFx.flicker] pulls the opacity down at
  /// the trough, 0..1; null keeps the effect's own depth (.45 / .38).
  final double? dip;

  /// Seconds per full cycle. For [PixelFx.drift] this is twice the CSS
  /// duration, because the source loops it with `alternate`.
  final double period;

  /// Position in the cycle at time zero, 0..1.
  final double phase;
}

/// A loose block that rises and falls above the art (sparks over a flame,
/// hearts drifting off the heart). Positioned in cell units from the grid
/// origin, plus a fixed pixel offset, so it scales with the art.
@immutable
class PixelEmberSpec {
  const PixelEmberSpec({
    required this.xCells,
    required this.yCells,
    required this.sizeCells,
    required this.color,
    required this.opacity,
    required this.period,
    required this.phase,
    this.yPx = 0,
  });

  final double xCells;
  final double yCells;
  final double yPx;
  final double sizeCells;
  final Color color;
  final double opacity;
  final double period;
  final double phase;
}

/// A size-independent pixel object: the bitmap, the styled blocks and the
/// loose extras. Laid out for a given box by [PixelScene].
@immutable
class PixelArt {
  const PixelArt._({
    required this.id,
    required this.bitmap,
    required this.cells,
    this.embers = const [],
    this.scanRow,
    this.glint = false,
    this.sparkles = false,
    this.shareTexture = false,
    this.timeOffset = 0,
    this.palette = PixelPalette.dark,
  });

  /// Stable identity; also the texture cache key.
  final String id;

  /// Source bitmap; `.` is empty, any other character is a block.
  final List<String> bitmap;
  final List<PixelCell> cells;
  final List<PixelEmberSpec> embers;

  /// Draws a cyan scan line across the art above this row.
  final int? scanRow;

  /// Still blocks catch a diagonal glint every 5.5 s.
  final bool glint;

  /// Up to three "+" sparkles twinkle around the art.
  final bool sparkles;

  /// Door art keeps one texture for the app's lifetime (nine tiny images);
  /// everything else owns and releases its own.
  final bool shareTexture;

  /// Seconds added to the clock so neighbouring doors do not glint in step.
  final double timeOffset;

  /// The colours the blocks were drawn from; the scan line takes its accent.
  final PixelPalette palette;

  int get cols => bitmap.first.length;
  int get rows => bitmap.length;

  int get textureWidth => math.max(cols, _kMaxEmbers * 2);
  int get textureHeight => rows * 3 + 1;

  static final Map<(SpaceSection, PixelTone), PixelArt> _doors = {};

  /// The object on a My Space row's door tile. The dark tone is the design
  /// and keeps its original id (and so its shared texture); the light tone
  /// is the same shape inked for paper, without the white sparkles the
  /// shader cannot recolour.
  static PixelArt door(
    SpaceSection section, {
    PixelTone tone = PixelTone.dark,
  }) => _doors.putIfAbsent((section, tone), () => _buildDoor(section, tone));

  /// The small 9 x 12 streak flame. Hotter streaks burn faster and throw
  /// sparks (10+: two, 20+: three).
  static PixelArt flame(int streak, {PixelTone tone = PixelTone.dark}) =>
      _buildFlame(streak, tone);

  /// RGBA bytes for the shader's data texture (see shaders/space_door.frag).
  Uint8List encodeTexture() {
    final w = textureWidth;
    final bytes = Uint8List(w * textureHeight * 4);
    void put(int x, int y, int r, int g, int b, int a) {
      final i = (y * w + x) * 4;
      bytes[i] = r;
      bytes[i + 1] = g;
      bytes[i + 2] = b;
      bytes[i + 3] = a;
    }

    int byte(double v) => (v.clamp(0.0, 1.0) * 255).round();
    int channel(double v) => (v * 255).round().clamp(0, 255);

    // Meta rows exist for every texel so the alpha channel is always opaque;
    // only the colour row uses alpha to mark an empty cell.
    for (var y = rows; y < rows * 3; y++) {
      for (var x = 0; x < w; x++) {
        put(x, y, 0, 0, 0, 255);
      }
    }
    for (final c in cells) {
      put(
        c.col,
        c.row,
        channel(c.color.r),
        channel(c.color.g),
        channel(c.color.b),
        255,
      );
      put(
        c.col,
        rows + c.row,
        byte(c.opacity),
        c.fx.index * 40,
        byte(c.phase),
        255,
      );
      // Green 0 keeps the effect's own dip, so the design's bytes stand.
      final dip = c.dip == null ? 0 : math.max(1, byte(c.dip!));
      put(c.col, rows * 2 + c.row, byte(c.period / 8), dip, 0, 255);
    }
    final emberRow = rows * 3;
    for (var i = 0; i < embers.length && i < _kMaxEmbers; i++) {
      final e = embers[i];
      put(
        i,
        emberRow,
        channel(e.color.r),
        channel(e.color.g),
        channel(e.color.b),
        255,
      );
      put(
        _kMaxEmbers + i,
        emberRow,
        byte(e.opacity),
        byte(e.phase),
        byte(e.period / 8),
        255,
      );
    }
    return bytes;
  }
}

// ---------------------------------------------------------------------------
// Bitmaps. Ported from the My Space design (HookTile / Flame).

/// King with a favourite star.
const List<String> kPlayersBitmap = [
  '.....X.....s..',
  '....XXX..sssss',
  '.....X....sss.',
  '..XX.X.XX.s.s.',
  '.XXXXXXXXX....',
  '.XXXXXXXXX....',
  '..XXXXXXX.....',
  '...XXXXX......',
  '...XXXXX......',
  '...XXXXX......',
  '..XXXXXXX.....',
  '.XXXXXXXXX....',
  '.XXXXXXXXX....',
];

/// Pawn under a scan line (someone you are preparing for).
const List<String> kLinksBitmap = [
  '...XXX...',
  '..XXXXX..',
  '..XXXXX..',
  '...XXX...',
  '..XXXXX..',
  '...XXX...',
  '...XXX...',
  '..XXXXX..',
  '.XXXXXXX.',
  'XXXXXXXXX',
  'XXXXXXXXX',
];

const List<String> kLikesBitmap = [
  '.XXX...XXX.',
  'XXXXX.XXXXX',
  'XXXXXXXXXXX',
  'XXXXXXXXXXX',
  'XXXXXXXXXXX',
  '.XXXXXXXXX.',
  '..XXXXXXX..',
  '...XXXXX...',
  '....XXX....',
  '.....X.....',
];

/// Trophy with a star.
const List<String> kEventsBitmap = [
  '...........s..',
  '.........sssss',
  'XXXXXXXXX.sss.',
  'X.XXXXX.X.s.s.',
  'X.XXXXX.X.....',
  '.XXXXXXX......',
  '..XXXXX.......',
  '...XXX........',
  '....X.........',
  '....X.........',
  '..XXXXX.......',
  '.XXXXXXX......',
];

/// Board corner with a bookmark ribbon (c), a mated king (r) and two white
/// (w) and one black (k) piece block.
const List<String> kOpeningsBitmap = [
  '.....ccc',
  'XXXwrccc',
  'XXXXXccc',
  'XXXXkccc',
  'XXXXXcXc',
  'XXXXXXwX',
  'XXXXXXXX',
  'XXXXXXXX',
  'XXXXXXXX',
];

/// Magnifying glass over a board: cyan rim (R), board (x), one pulsing
/// square (m), grey handle (H).
const List<String> kGamesBitmap = [
  '..RRRRR......',
  '.RxxxxxR.....',
  'RxxxxxxxR....',
  'RxxxxmxxR....',
  'RxxxxxxxR....',
  'RxxxxxxxR....',
  'RxxxxxxxR....',
  '.RxxxxxR.....',
  '..RRRRRHH....',
  '.......HHH...',
  '........HHH..',
  '.........HHH.',
  '..........HH.',
];

/// The large streak flame (the streak share card): outer (O), mid (M),
/// core (C).
const List<String> kStreaksBitmap = [
  '......O......',
  '......OO.....',
  '.....OOO.....',
  '.....OOOO....',
  '....OOOOO..O.',
  '....OOMOOO.O.',
  '...OOOMMOOOO.',
  '..OOOMMMMOOO.',
  '..OOMMMMMMOOO',
  '.OOOMMMCMMMOO',
  '.OOMMMCCCMMOO',
  'OOOMMCCCCMMOO',
  'OOMMMCCCCCMMO',
  'OOMMCCCCCCMMO',
  '.OOMMCCCCMMO.',
  '..OOMMCCMMO..',
  '...OOOMMOO...',
];

/// Funnel: board blocks drift in at the top (X), funnel body (f), cyan
/// output blocks below (c).
const List<String> kSmartEventsBitmap = [
  'X...X..X..X',
  '..X...X...X',
  'X...X...X..',
  'fffffffffff',
  '.fffffffff.',
  '..fffffff..',
  '...fffff...',
  '....fff....',
  '....fff....',
  '...........',
  '....c.c....',
  '.....c.....',
];

/// The 9 x 12 streak flame used next to streak counts.
const List<String> kFlameBitmap = [
  '....O....',
  '....OO...',
  '...OOO...',
  '...OOOO.O',
  '..OOMOOOO',
  '.OOMMMOOO',
  '.OMMCMMOO',
  'OOMCCCMMO',
  'OMMCCCCMO',
  'OMMCCCMMO',
  '.OOMMMOO.',
  '..OOOOO..',
];

/// Three boards stacked back to front with a one-block gap between slabs.
/// Each block holds its slab index (0 = front).
final List<String> kLibraryBitmap = _libraryBitmap();

List<String> _libraryBitmap() {
  const n = 13;
  final g = List.generate(n, (_) => List.filled(n, '.'));
  // [x, y, slab]
  const slabs = [
    [4, 0, 2],
    [2, 2, 1],
    [0, 4, 0],
  ];
  for (final sl in slabs) {
    final x = sl[0], y = sl[1], slab = sl[2];
    for (var e = -1; e < 9; e++) {
      if (y - 1 >= 0 && x + e + 1 < n) g[y - 1][x + e + 1] = '.';
      if (x + 9 < n && y + e >= 0 && y + e < n) g[y + e][x + 9] = '.';
    }
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        final rr = y + r, cc = x + c;
        if (rr < n && cc < n) g[rr][cc] = '$slab';
      }
    }
  }
  return [for (final row in g) row.join()];
}

/// The bitmap drawn on a section's door.
List<String> doorBitmap(SpaceSection section) => switch (section) {
  SpaceSection.library => kLibraryBitmap,
  SpaceSection.players => kPlayersBitmap,
  SpaceSection.events => kEventsBitmap,
  SpaceSection.openings => kOpeningsBitmap,
  SpaceSection.likes => kLikesBitmap,
  SpaceSection.games => kGamesBitmap,
  SpaceSection.smartEvents => kSmartEventsBitmap,
  SpaceSection.links => kLinksBitmap,
};

/// The design's name for each door; it seeds the jitter.
String _designKind(SpaceSection section) => switch (section) {
  SpaceSection.library => 'library',
  SpaceSection.players => 'players',
  SpaceSection.events => 'events',
  SpaceSection.openings => 'openings',
  SpaceSection.likes => 'likes',
  SpaceSection.games => 'analyses',
  SpaceSection.smartEvents => 'smart',
  // The pawn under a scan line was the design's Profiles door; Shortcuts
  // keeps it, and its seed, so the art stays exactly as drawn.
  SpaceSection.links => 'profiles',
};

// ---------------------------------------------------------------------------
// Styling. Each builder draws from the generator in exactly the order the
// HTML does, so jitter and timings line up with the design.

class _Style {
  const _Style(
    this.color,
    this.opacity, [
    this.fx = PixelFx.none,
    this.period = 0,
    this.phase = 0,
    this.dip,
  ]);

  final Color color;
  final double opacity;
  final PixelFx fx;
  final double period;
  final double phase;
  final double? dip;
}

double _fixed(double v, int digits) {
  final m = math.pow(10, digits);
  return (v * m).round() / m;
}

/// Phase that reproduces a CSS `animation-delay` for a looping cycle.
double _phaseFor(double delay, double period) =>
    period <= 0 ? 0 : (-delay / period) % 1.0;

_Style _pulse(Color color, double opacity, double dur, [double delay = 0]) =>
    _Style(color, opacity, PixelFx.pulse, dur, _phaseFor(delay, dur));

_Style _flicker(
  Color color,
  double opacity,
  double dur,
  double delay, [
  double? dip,
]) => _Style(color, opacity, PixelFx.flicker, dur, _phaseFor(delay, dur), dip);

_Style _drift(Color color, double opacity, double dur, double delay) =>
    _Style(color, opacity, PixelFx.drift, dur * 2, _phaseFor(delay, dur * 2));

List<PixelCell> _cellsFrom(
  List<String> rows,
  _Style Function(int r, int c, int nr, String ch) style,
) {
  final nr = rows.length;
  final cells = <PixelCell>[];
  for (var r = 0; r < nr; r++) {
    final row = rows[r];
    for (var c = 0; c < row.length; c++) {
      final ch = row[c];
      if (ch == '.') continue;
      final s = style(r, c, nr, ch);
      cells.add(
        PixelCell(
          col: c,
          row: r,
          color: s.color,
          opacity: _fixed(s.opacity, 2),
          fx: s.fx,
          period: s.period,
          phase: s.phase,
          dip: s.dip,
        ),
      );
    }
  }
  return cells;
}

Color _checker(PixelPalette p, int r, int c, {required bool oddIsLight}) =>
    ((r + c) % 2 == 1) == oddIsLight ? p.square : p.squareAlt;

PixelArt _buildDoor(SpaceSection section, PixelTone tone) {
  final p = PixelPalette.of(tone);
  final kind = _designKind(section);
  final rnd = PixelRandom.forKey(kind);
  final bitmap = doorBitmap(section);
  var embers = const <PixelEmberSpec>[];
  int? scanRow;

  final List<PixelCell> cells;
  switch (section) {
    case SpaceSection.players:
    case SpaceSection.events:
      cells = _cellsFrom(bitmap, (r, c, nr, ch) {
        final v = rnd.next();
        if (ch == 's') return _pulse(p.accent, 1, 1.6);
        return _Style(_checker(p, r, c, oddIsLight: true), 0.4 + v * 0.5);
      });
    case SpaceSection.links:
      scanRow = 6;
      cells = _cellsFrom(bitmap, (r, c, nr, ch) {
        final v = rnd.next();
        if (r < 6) return _Style(p.accent, 0.45 + v * 0.5);
        return _Style(_checker(p, r, c, oddIsLight: true), 0.22 + v * 0.3);
      });
    case SpaceSection.likes:
      cells = _cellsFrom(bitmap, (r, c, nr, ch) {
        final v = rnd.next();
        final color = v > 0.8 ? p.redBright : p.red;
        final opacity = 0.5 + v * 0.5;
        if (v < 0.22) {
          final dur = _fixed(1.6 + rnd.next() * 1.8, 2);
          final delay = _fixed(rnd.next() * 2, 2);
          return _pulse(color, opacity, dur, delay);
        }
        return _Style(color, opacity);
      });
      embers = [
        for (var k = 0; k < 4; k++)
          _ember(
            rnd,
            sizeBase: 0.45,
            sizeSpan: 0.3,
            xBase: 1,
            lift: 4,
            color: p.red,
            opBase: 0.35,
            opSpan: 0.4,
            durBase: 2.4,
            durSpan: 1.6,
          ),
      ];
    case SpaceSection.library:
      cells = _cellsFrom(bitmap, (r, c, nr, ch) {
        final x = rnd.next();
        final slab = int.parse(ch);
        final base = slab == 0 ? 0.8 : (slab == 1 ? 0.42 : 0.22);
        return _Style(
          (r + c) % 2 == 1 ? p.squareAlt : p.square,
          base + x * (slab == 0 ? 0.2 : 0.12),
        );
      });
    case SpaceSection.openings:
      cells = _cellsFrom(bitmap, (r, c, nr, ch) {
        final v = rnd.next();
        switch (ch) {
          case 'c':
            return _Style(p.accent, 0.85 + v * 0.15);
          case 'r':
            return _pulse(p.red, 1, 1.8);
          case 'w':
            return _Style(p.whitePiece, 1);
          case 'k':
            return _Style(p.blackPiece, 1);
        }
        return _Style(
          (r - 1 + c) % 2 != 0 ? p.squareAlt : p.square,
          0.4 + v * 0.5,
        );
      });
    case SpaceSection.games:
      cells = _cellsFrom(bitmap, (r, c, nr, ch) {
        final v = rnd.next();
        switch (ch) {
          case 'R':
            return _Style(p.accent, 0.85 + v * 0.15);
          case 'H':
            return _Style(v < 0.5 ? p.handle : p.handleAlt, 1);
          case 'm':
            return _pulse(p.accent, 1, 1.6);
        }
        return _Style(_checker(p, r, c, oddIsLight: false), 0.55 + v * 0.4);
      });
    case SpaceSection.smartEvents:
      cells = _cellsFrom(bitmap, (r, c, nr, ch) {
        final v = rnd.next();
        if (ch == 'X') {
          final dur = _fixed(1.8 + rnd.next() * 1.6, 2);
          final delay = _fixed(rnd.next(), 2);
          return _drift(
            v < 0.5 ? p.square : p.squareAlt,
            0.3 + v * 0.5,
            dur,
            delay,
          );
        }
        if (ch == 'f') {
          return _Style(_checker(p, r, c, oddIsLight: false), 0.3 + v * 0.45);
        }
        return _pulse(p.accent, 1, 2, _fixed(r * 0.3, 1));
      });
  }

  var seed = 0;
  for (final unit in kind.codeUnits) {
    seed = (seed * 31 + unit) & 0xffff;
  }
  final light = tone == PixelTone.light;
  return PixelArt._(
    id: light ? 'door:$kind:light' : 'door:$kind',
    bitmap: bitmap,
    cells: cells,
    embers: embers,
    scanRow: scanRow,
    glint: true,
    // The shader paints sparkles in fixed white and cyan, invisible or loud
    // on paper; the light art goes without them.
    sparkles: !light,
    shareTexture: true,
    timeOffset: (seed % 1000) / 1000 * 5.5,
    palette: p,
  );
}

/// A block floating above the art, drawn in the HTML's argument order:
/// size, x, y, opacity, duration, delay.
PixelEmberSpec _ember(
  PixelRandom rnd, {
  required double sizeBase,
  required double sizeSpan,
  required double xBase,
  required double lift,
  required Color color,
  required double opBase,
  required double opSpan,
  required double durBase,
  required double durSpan,
}) {
  final size = sizeBase + rnd.next() * sizeSpan;
  final x = xBase + rnd.next() * 9;
  final yPx = -(lift + rnd.next() * 10);
  final opacity = _fixed(opBase + rnd.next() * opSpan, 2);
  final dur = _fixed(durBase + rnd.next() * durSpan, 2);
  final delay = _fixed(rnd.next(), 2);
  return PixelEmberSpec(
    xCells: x,
    yCells: -size,
    yPx: yPx,
    sizeCells: size,
    color: color,
    opacity: opacity,
    period: dur * 2,
    phase: _phaseFor(delay, dur * 2),
  );
}

PixelArt _buildFlame(int streak, PixelTone tone) {
  final p = PixelPalette.of(tone);
  final n = math.max(0, streak);
  final lvl = n >= 20 ? 3 : (n >= 10 ? 2 : (n >= 5 ? 1 : 0));
  final outer = lvl > 0 ? p.fireOuter : p.fireOuterCool;
  final colors = {'O': outer, 'M': p.fireMid, 'C': p.fireCore};
  final rnd = PixelRandom(n * 7 + 3);
  final speed = const [1.5, 1.2, 1.0, 0.8][lvl];
  final cells = _cellsFrom(kFlameBitmap, (r, c, nr, ch) {
    final key = lvl == 0 && ch == 'M' ? 'O' : ch;
    final dur = _fixed(speed * (0.6 + rnd.next() * 0.6), 2);
    final delay = _fixed((12 - r) * 0.05 + rnd.next() * 0.15, 2);
    return _flicker(
      colors[key]!,
      key == 'O' ? p.fireRimOpacity : 1,
      dur,
      delay,
      p.flickerDip,
    );
  });
  const sparkAt = [
    [6.4, -1.2],
    [2.2, 0.2],
    [4.6, -2.0],
  ];
  final sparkCount = lvl == 3 ? 3 : (lvl == 2 ? 2 : 0);
  return PixelArt._(
    id: tone == PixelTone.light ? 'flame:$n:light' : 'flame:$n',
    bitmap: kFlameBitmap,
    cells: cells,
    palette: p,
    embers: [
      for (var i = 0; i < sparkCount; i++)
        PixelEmberSpec(
          xCells: sparkAt[i][0],
          yCells: sparkAt[i][1],
          sizeCells: 0.7,
          color: p.spark,
          opacity: 1,
          period: (1.2 + i * 0.4) * 2,
          phase: _phaseFor(i * 0.3, (1.2 + i * 0.4) * 2),
        ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Layout.

/// An ember placed in local pixels.
@immutable
class PixelEmber {
  const PixelEmber(this.rect, this.color, this.opacity);

  final Rect rect;
  final Color color;
  final double opacity;
}

/// A "+" sparkle: [origin] is the top-left of its centre block.
@immutable
class PixelSparkle {
  const PixelSparkle(this.origin, this.block, {required this.cyan});

  final Offset origin;
  final double block;
  final bool cyan;
}

@immutable
class PixelScanLine {
  const PixelScanLine({
    required this.y,
    required this.x0,
    required this.x1,
    required this.thickness,
    required this.color,
    required this.period,
  });

  final double y;
  final double x0;
  final double x1;
  final double thickness;
  final Color color;
  final double period;
}

/// A [PixelArt] laid out in a box of [size] local pixels.
@immutable
class PixelScene {
  const PixelScene._({
    required this.art,
    required this.size,
    required this.layout,
    required this.origin,
    required this.cell,
    required this.gap,
    required this.radius,
    required this.embers,
    required this.emberRise,
    required this.emberRadius,
    required this.sparkles,
    required this.scan,
    required this.driftAmplitude,
    required this.paintBounds,
  });

  /// Door tile layout, ported from the design: narrow tiles centre the art in
  /// x 14..w-14, y 44..h-[labelReserve]; wide ones (> 200 px) use the right
  /// 56 % and ignore [labelReserve], since their label sits beside the art.
  factory PixelScene.door(
    PixelArt art,
    Size size, {
    double labelReserve = kDoorLabelReserve,
  }) {
    final h = size.height;
    final box = doorArtBox(size, labelReserve: labelReserve);
    final wide = size.width > 200;
    final pad = wide ? 18.0 : 14.0;
    // Everything below the art's gap: the label plus its bottom padding.
    final labelBand = wide ? 22.0 : labelReserve - 8 - pad;
    return PixelScene._fitted(
      art,
      size,
      box,
      layout: 'door',
      sparkleFloor: h - pad - labelBand - 4,
    );
  }

  /// [art] fitted and centred in [box] on a tile of [size], with the door's
  /// sparkles, embers and scan line. For tiles whose label is laid out
  /// beside the art rather than under it, so no band is kept clear.
  factory PixelScene.inBox(PixelArt art, Size size, Rect box) {
    return PixelScene._fitted(
      art,
      size,
      box,
      layout: 'box',
      sparkleFloor: size.height - 4,
    );
  }

  /// The door layout inside [box]. A sparkle whose "+" would reach below
  /// [sparkleFloor] or past a side of the tile is left out whole.
  factory PixelScene._fitted(
    PixelArt art,
    Size size,
    Rect box, {
    required String layout,
    required double sparkleFloor,
  }) {
    final w = size.width;
    final s = math
        .max(1.0, math.min(box.width / art.cols, box.height / art.rows))
        .floorToDouble();
    final ox = box.left + (box.width - art.cols * s) / 2;
    final oy = box.top + (box.height - art.rows * s) / 2;
    final bb = Rect.fromLTWH(ox, oy, art.cols * s, art.rows * s);

    final embers = [
      for (final e in art.embers.take(_kMaxEmbers))
        PixelEmber(
          Rect.fromLTWH(
            ox + s * e.xCells,
            oy + s * e.yCells + e.yPx,
            s * e.sizeCells,
            s * e.sizeCells,
          ),
          e.color,
          e.opacity,
        ),
    ];

    final sparkles = <PixelSparkle>[];
    if (art.sparkles) {
      final sp = math.max(2, (s * 0.45).round()).toDouble();
      final spots = [
        Offset(bb.left - sp * 2.5, bb.top + bb.height * 0.2),
        Offset(bb.right + sp * 1.5, bb.top + bb.height * 0.55),
        Offset(bb.left + bb.width * 0.3, bb.bottom + sp * 2),
      ];
      for (var i = 0; i < spots.length && i < _kMaxSparkles; i++) {
        final pt = spots[i];
        // The design only kept the centre block on the tile, which let an arm
        // be sliced off by the edge (Openings); require the whole "+".
        if (pt.dy + sp * 1.5 > sparkleFloor ||
            pt.dx - sp < 2 ||
            pt.dx + sp * 2 > w - 2) {
          continue;
        }
        sparkles.add(PixelSparkle(pt, sp, cyan: i == 1));
      }
    }

    final scan = art.scanRow == null
        ? null
        : PixelScanLine(
            y: oy + art.scanRow! * s - 0.5,
            x0: box.left - 4,
            x1: box.right + 4,
            thickness: 2,
            color: art.palette.accent,
            period: 1.8,
          );

    const emberRise = 10.0;
    var bounds = bb;
    for (final e in embers) {
      bounds = bounds.expandToInclude(
        e.rect.translate(0, -emberRise).expandToInclude(e.rect),
      );
    }
    for (final sp in sparkles) {
      bounds = bounds.expandToInclude(
        Rect.fromLTWH(
          sp.origin.dx - sp.block,
          sp.origin.dy - sp.block,
          sp.block * 3,
          sp.block * 3,
        ),
      );
    }
    if (scan != null) {
      bounds = bounds.expandToInclude(
        Rect.fromLTRB(
          scan.x0 - scan.thickness,
          scan.y - scan.thickness,
          scan.x1 + scan.thickness,
          scan.y + scan.thickness,
        ),
      );
    }

    return PixelScene._(
      art: art,
      size: size,
      layout: layout,
      origin: Offset(ox, oy),
      cell: s,
      gap: 1.2,
      radius: 0.6,
      embers: embers,
      emberRise: emberRise,
      emberRadius: 0.6,
      sparkles: sparkles,
      scan: scan,
      driftAmplitude: math.min(6.0, s * 0.75),
      paintBounds: bounds.inflate(1.5),
    );
  }

  /// The streak flame, fitted like the design's `viewBox="0 -2 9 14"`: two
  /// spare rows above the bitmap leave room for the sparks.
  factory PixelScene.flame(PixelArt art, Size size) {
    final unit = math.min(size.width / 9, size.height / 14);
    final ox = (size.width - 9 * unit) / 2;
    final top = (size.height - 14 * unit) / 2;
    final oy = top + 2 * unit;
    final rise = 1.6 * unit;
    final embers = [
      for (final e in art.embers.take(_kMaxEmbers))
        PixelEmber(
          Rect.fromLTWH(
            ox + unit * e.xCells,
            oy + unit * e.yCells,
            unit * e.sizeCells,
            unit * e.sizeCells,
          ),
          e.color,
          e.opacity,
        ),
    ];
    var bounds = Rect.fromLTWH(ox, top, 9 * unit, 14 * unit);
    for (final e in embers) {
      bounds = bounds.expandToInclude(e.rect.translate(0, -rise));
    }
    return PixelScene._(
      art: art,
      size: size,
      layout: 'flame',
      origin: Offset(ox, oy),
      cell: unit,
      gap: 0.16 * unit,
      radius: 0.12 * unit,
      embers: embers,
      emberRise: rise,
      emberRadius: 0.12 * unit,
      sparkles: const [],
      scan: null,
      driftAmplitude: 0,
      paintBounds: bounds.inflate(1),
    );
  }

  final PixelArt art;
  final Size size;
  final String layout;
  final Offset origin;
  final double cell;
  final double gap;
  final double radius;
  final List<PixelEmber> embers;
  final double emberRise;
  final double emberRadius;
  final List<PixelSparkle> sparkles;
  final PixelScanLine? scan;
  final double driftAmplitude;

  /// Everything the art can touch while it animates; the shader only runs
  /// inside this rect.
  final Rect paintBounds;

  Rect get artRect =>
      Rect.fromLTWH(origin.dx, origin.dy, art.cols * cell, art.rows * cell);

  // Origin and cell track the door's label reserve, which moves the art at
  // the same size when the text scale changes.
  @override
  bool operator ==(Object other) =>
      other is PixelScene &&
      other.art.id == art.id &&
      other.size == size &&
      other.layout == layout &&
      other.origin == origin &&
      other.cell == cell;

  @override
  int get hashCode => Object.hash(art.id, size, layout, origin, cell);
}

/// The design's bottom reserve under a narrow door's art: 14 px padding, two
/// 17 px label lines and an 8 px gap.
const double kDoorLabelReserve = 56;

/// The rect a door's art is centred in. On narrow doors [labelReserve] is the
/// band kept clear under the art for the label.
Rect doorArtBox(Size size, {double labelReserve = kDoorLabelReserve}) {
  final w = size.width, h = size.height;
  if (w > 200) {
    return Rect.fromLTWH(
      (w * 0.44).roundToDouble(),
      30,
      (w * 0.56).roundToDouble() - 22,
      h - 60,
    );
  }
  return Rect.fromLTWH(14, 44, w - 28, math.max(0.0, h - 44 - labelReserve));
}

// ---------------------------------------------------------------------------
// Rendering.

/// Draws a [PixelScene] with the shared fragment shader, animated by a ticker
/// that runs only while tickers are enabled here and animations are allowed.
/// Falls back to a static painter when the shader is unavailable (tests,
/// unsupported backends) or until it has loaded.
class PixelArtView extends StatefulWidget {
  const PixelArtView({super.key, required this.scene});

  final PixelScene scene;

  /// Forces the static painter; for tests and screenshots.
  @visibleForTesting
  static bool debugForceStatic = false;

  static Future<ui.FragmentProgram?>? _program;
  static final Map<String, Future<ui.Image>> _sharedTextures = {};

  static bool get _underTest =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  static Future<ui.FragmentProgram?> _loadProgram() {
    return _program ??= () async {
      if (_underTest) return null;
      try {
        return await ui.FragmentProgram.fromAsset(kPixelArtShaderAsset);
      } catch (error) {
        debugPrint('PixelArtView: shader unavailable, drawing static ($error)');
        return null;
      }
    }();
  }

  static Future<ui.Image> _decode(PixelArt art) {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      art.encodeTexture(),
      art.textureWidth,
      art.textureHeight,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  static Future<ui.Image> _texture(PixelArt art) {
    if (!art.shareTexture) return _decode(art);
    return _sharedTextures.putIfAbsent(art.id, () => _decode(art));
  }

  @override
  State<PixelArtView> createState() => _PixelArtViewState();
}

/// Scenes no taller or wider than this (streak flames in rails, rows and
/// badges) run on [_SmallSceneClock] instead of a ticker of their own.
const double _kSmallSceneMaxSide = 64;

/// One clock for every small scene, stepped by a single timer at 30 fps. A
/// rail of ten streak flames then repaints together 30 times a second rather
/// than each flame on every vsync at 60 or 120 Hz. At this size the flicker
/// reads the same.
abstract final class _SmallSceneClock {
  static final ValueNotifier<double> value = ValueNotifier<double>(0);
  static final Stopwatch _watch = Stopwatch();
  static Timer? _timer;
  static int _users = 0;

  static void acquire() {
    if (_users++ > 0) return;
    _watch.start();
    _timer = Timer.periodic(const Duration(microseconds: 33333), (_) {
      // Wrapped so the shader's float time never grows large.
      value.value = (_watch.elapsedMicroseconds / 1e6) % 3600.0;
    });
  }

  static void release() {
    if (--_users > 0) return;
    _timer?.cancel();
    _timer = null;
    _watch.stop();
  }
}

class _PixelArtViewState extends State<PixelArtView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);
  double _clockBase = 0;
  bool _tickersEnabled = true;
  bool _onSharedClock = false;
  // Added to the shared clock so this scene keeps its own phase.
  double _sharedOffset = 0;
  ui.FragmentShader? _shader;
  ui.Image? _texture;
  bool _ownsTexture = false;
  String? _textureFor;
  bool _still = false;

  @override
  void initState() {
    super.initState();
    _clock.value = widget.scene.art.timeOffset;
    if (!PixelArtView.debugForceStatic) _loadShader();
  }

  Future<void> _loadShader() async {
    final program = await PixelArtView._loadProgram();
    if (!mounted || program == null) return;
    final ui.FragmentShader shader;
    try {
      shader = program.fragmentShader();
    } catch (error) {
      debugPrint('PixelArtView: could not create shader ($error)');
      return;
    }
    setState(() => _shader = shader);
    await _loadTexture();
  }

  Future<void> _loadTexture() async {
    final art = widget.scene.art;
    _textureFor = art.id;
    final ui.Image image;
    try {
      image = await PixelArtView._texture(art);
    } catch (error) {
      debugPrint('PixelArtView: texture failed ($error)');
      return;
    }
    if (!mounted || _textureFor != art.id) {
      if (!art.shareTexture) image.dispose();
      return;
    }
    final previous = _ownsTexture ? _texture : null;
    setState(() {
      _texture = image;
      _ownsTexture = !art.shareTexture;
    });
    previous?.dispose();
    _syncTicker();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _tickersEnabled = TickerMode.valuesOf(context).enabled;
    _syncTicker();
  }

  @override
  void didUpdateWidget(PixelArtView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scene.art.id != widget.scene.art.id && _shader != null) {
      _loadTexture();
    }
    _syncTicker();
  }

  void _syncTicker() {
    final run = _shader != null && _texture != null && !_still;
    final small = widget.scene.size.longestSide <= _kSmallSceneMaxSide;
    // The shared clock is not a ticker, so it honours TickerMode here.
    final shared = run && small && _tickersEnabled;
    if (shared != _onSharedClock) {
      _onSharedClock = shared;
      final now = _SmallSceneClock.value.value;
      if (shared) {
        _sharedOffset = _clock.value - now;
        _SmallSceneClock.acquire();
      } else {
        _clock.value = (now + _sharedOffset) % 3600.0;
        _SmallSceneClock.release();
      }
    }
    final own = run && !small;
    if (own && !_ticker.isActive) {
      _clockBase = _clock.value;
      _ticker.start();
    } else if (!own && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    // Wrapped so the shader's float time never grows large.
    _clock.value = (_clockBase + elapsed.inMicroseconds / 1e6) % 3600.0;
  }

  @override
  void dispose() {
    _ticker.dispose();
    if (_onSharedClock) _SmallSceneClock.release();
    _shader?.dispose();
    if (_ownsTexture) _texture?.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    final texture = _texture;
    final CustomPainter painter;
    if (shader != null && texture != null) {
      painter = _ShaderScenePainter(
        shader: shader,
        texture: texture,
        scene: widget.scene,
        clock: _onSharedClock ? _SmallSceneClock.value : _clock,
        clockOffset: _onSharedClock ? _sharedOffset : 0,
        still: _still,
        devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
      );
    } else {
      painter = StaticPixelScenePainter(widget.scene);
    }
    return RepaintBoundary(
      child: CustomPaint(painter: painter, child: const SizedBox.expand()),
    );
  }
}

class _ShaderScenePainter extends CustomPainter {
  _ShaderScenePainter({
    required this.shader,
    required this.texture,
    required this.scene,
    required this.clock,
    required this.clockOffset,
    required this.still,
    required this.devicePixelRatio,
  }) : super(repaint: still ? null : clock);

  final ui.FragmentShader shader;
  final ui.Image texture;
  final PixelScene scene;
  final ValueListenable<double> clock;
  final double clockOffset;
  final bool still;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final s = scene;
    final art = s.art;
    final bb = s.artRect;
    var i = 0;
    void f(double v) => shader.setFloat(i++, v);

    f(s.origin.dx); // uGrid
    f(s.origin.dy);
    f(s.cell);
    f(devicePixelRatio);
    f(art.cols.toDouble()); // uDims
    f(art.rows.toDouble());
    f(s.gap);
    f(s.radius);
    f(art.textureWidth.toDouble()); // uTex
    f(art.textureHeight.toDouble());
    f(s.embers.length.toDouble());
    f(s.emberRise);
    f(still ? 0 : (clock.value + clockOffset) % 3600.0); // uAnim
    f(still ? 1 : 0);
    // Glint: 0 off, 1 brightens (dark tile), 2 deepens toward ink (paper).
    f(art.glint ? (identical(art.palette, PixelPalette.light) ? 2 : 1) : 0);
    f(s.driftAmplitude);
    f(bb.left); // uGlint
    f(bb.top);
    f(bb.width + bb.height);
    f(s.emberRadius);
    for (var k = 0; k < _kMaxSparkles; k++) {
      // uSpark0..2
      if (k < s.sparkles.length) {
        final sp = s.sparkles[k];
        f(sp.origin.dx);
        f(sp.origin.dy);
        f(sp.block);
        f(sp.cyan ? 1 : 0);
      } else {
        f(0);
        f(0);
        f(0);
        f(0);
      }
    }
    for (var k = 0; k < _kMaxEmbers; k++) {
      // uEmber0..4
      if (k < s.embers.length) {
        final e = s.embers[k].rect;
        f(e.left);
        f(e.top);
        f(e.width);
        f(0);
      } else {
        f(0);
        f(0);
        f(0);
        f(0);
      }
    }
    final scan = s.scan;
    f(scan?.y ?? 0); // uScan
    f(scan?.x0 ?? 0);
    f(scan?.x1 ?? 0);
    f(scan?.thickness ?? 0);
    f(scan?.color.r ?? 0); // uScanColor
    f(scan?.color.g ?? 0);
    f(scan?.color.b ?? 0);
    f(scan?.period ?? 1);
    shader.setImageSampler(0, texture);

    canvas.drawRect(s.paintBounds, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_ShaderScenePainter old) =>
      old.scene != scene ||
      old.texture != texture ||
      old.shader != shader ||
      old.still != still ||
      old.devicePixelRatio != devicePixelRatio ||
      old.clock != clock ||
      old.clockOffset != clockOffset;
}

/// Paints a [PixelScene] as its resting frame with plain canvas calls.
class StaticPixelScenePainter extends CustomPainter {
  const StaticPixelScenePainter(this.scene);

  final PixelScene scene;

  @override
  void paint(Canvas canvas, Size size) {
    final s = scene;
    final paint = Paint()..isAntiAlias = true;
    final side = s.cell - s.gap;
    for (final c in s.art.cells) {
      final lo =
          s.origin +
          Offset(c.col * s.cell + s.gap / 2, c.row * s.cell + s.gap / 2);
      paint.color = c.color.withValues(alpha: c.opacity);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          lo & Size(side, side),
          Radius.circular(s.radius),
        ),
        paint,
      );
    }
    for (final e in s.embers) {
      paint.color = e.color.withValues(alpha: e.opacity);
      canvas.drawRRect(
        RRect.fromRectAndRadius(e.rect, Radius.circular(s.emberRadius)),
        paint,
      );
    }
    for (final sp in s.sparkles) {
      final b = sp.block;
      final color = sp.cyan ? _kCyan : _kWhite;
      const arms = [Offset(0, -1), Offset(-1, 0), Offset(1, 0), Offset(0, 1)];
      paint.color = color.withValues(alpha: 0.55);
      for (final d in arms) {
        canvas.drawRect((sp.origin + d * b) & Size(b, b), paint);
      }
      paint.color = color.withValues(alpha: 0.95);
      canvas.drawRect(sp.origin & Size(b, b), paint);
    }
    final scan = s.scan;
    if (scan != null) {
      canvas.drawLine(
        Offset(scan.x0, scan.y),
        Offset(scan.x1, scan.y),
        Paint()
          ..color = scan.color
          ..strokeWidth = scan.thickness
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(StaticPixelScenePainter old) => old.scene != scene;
}
