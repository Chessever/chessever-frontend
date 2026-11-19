import 'dart:collection';
import 'dart:math' as math;

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_tiers.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart'
    show resolveSpaceLine, SpaceLine;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/eco_openings.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/widgets/hub_tile.dart' show kHubTileInk;
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// A smart event's plate is a window onto a real board: whole squares cut
// from an 8x8 board, so no square and no piece is ever sliced. An opening
// shows its position after its line with the move that defines it marked;
// a level shows its piece of the title ladder on its home square. The
// plate's own quiet squares, the reader's piece set, one tonal mark as the
// only colour. No glow, gradient, shadow or tag.

/// Files across every plate window: a plate is 5 squares wide.
const int kSmartPlateFiles = 5;

/// Ranks in a plate: four squares tall, the 5:4 of every card plate.
const int kSmartPlateRanks = 4;

/// A window onto the board, White at the bottom: [files] x [ranks] whole
/// squares from file [file] (a = 0) and rank [rank] (the first rank = 0).
@immutable
class SmartBoardWindow {
  const SmartBoardWindow({
    required this.file,
    required this.rank,
    this.files = kSmartPlateFiles,
    this.ranks = kSmartPlateRanks,
  }) : assert(file >= 0 && file + files <= 8),
       assert(rank >= 0 && rank + ranks <= 8);

  final int file;
  final int rank;
  final int files;
  final int ranks;

  bool contains(Square square) =>
      square.file >= file &&
      square.file < file + files &&
      square.rank >= rank &&
      square.rank < rank + ranks;

  /// "b4-f7": the window's corners, bottom left to top right.
  String get label {
    String name(int f, int r) => '${String.fromCharCode(97 + f)}${r + 1}';
    return '${name(file, rank)}-${name(file + files - 1, rank + ranks - 1)}';
  }

  @override
  bool operator ==(Object other) =>
      other is SmartBoardWindow &&
      other.file == file &&
      other.rank == rank &&
      other.files == files &&
      other.ranks == ranks;

  @override
  int get hashCode => Object.hash(file, rank, files, ranks);

  @override
  String toString() => 'SmartBoardWindow($label)';
}

/// The window that shows a position's story best: every square of the
/// defining move ([heavy], worth 3 each) and as many of the moves before it
/// ([light], 1 each) as fit. Ties go to the window nearer the board's
/// centre, then to the one found first (towards a1).
///
/// The Sicilian's ...c5 shows b4-f7 (c5 marked, e4 in view), the Najdorf's
/// ...a6 shows a4-e7, the Queen's Gambit Declined's 4.Nf3 shows c1-g4.
SmartBoardWindow smartBoardWindowFor({
  required Iterable<Square> heavy,
  Iterable<Square> light = const [],
  int files = kSmartPlateFiles,
  int ranks = kSmartPlateRanks,
}) {
  SmartBoardWindow? best;
  var bestScore = -1;
  var bestDistance = double.infinity;
  for (var file = 0; file + files <= 8; file++) {
    for (var rank = 0; rank + ranks <= 8; rank++) {
      final window = SmartBoardWindow(
        file: file,
        rank: rank,
        files: files,
        ranks: ranks,
      );
      var score = 0;
      for (final s in heavy) {
        if (window.contains(s)) score += 3;
      }
      for (final s in light) {
        if (window.contains(s)) score += 1;
      }
      final dx = file + (files - 1) / 2 - 3.5;
      final dy = rank + (ranks - 1) / 2 - 3.5;
      final distance = dx * dx + dy * dy;
      if (score > bestScore ||
          (score == bestScore && distance < bestDistance)) {
        best = window;
        bestScore = score;
        bestDistance = distance;
      }
    }
  }
  return best!;
}

/// The window centred on [square], clamped to the board: a tier's piece in
/// the middle of its crop, the rook in its a1 corner.
SmartBoardWindow smartBoardWindowAround(
  Square square, {
  int files = kSmartPlateFiles,
  int ranks = kSmartPlateRanks,
}) {
  int centred(int at, int span) => (at - (span - 1) ~/ 2).clamp(0, 8 - span);
  return SmartBoardWindow(
    file: centred(square.file, files),
    rank: centred(square.rank, ranks),
    files: files,
    ranks: ranks,
  );
}

/// An opening as its plate shows it: the moves picked (search, a recent
/// search, a pin), else the code's canonical line.
@immutable
class SmartPlateLine {
  const SmartPlateLine({this.ecoCode, this.moves = const []});

  /// An ECO code or family ("B90", "B20-B99").
  final String? ecoCode;

  /// SAN moves from the start ("e4", "c5").
  final List<String> moves;

  String get _key => '${ecoCode ?? ''}|${moves.join(' ')}';

  @override
  bool operator ==(Object other) =>
      other is SmartPlateLine && other._key == _key;

  @override
  int get hashCode => _key.hashCode;
}

/// Where an opening's line arrives: the position, the move that defines it
/// (its last) and where the three moves before it landed.
@immutable
class SmartPlatePosition {
  const SmartPlatePosition({
    required this.fen,
    required this.lastMove,
    this.recent = const [],
  });

  final String fen;
  final NormalMove lastMove;
  final List<Square> recent;

  /// The window [ranks] tall that shows this position best.
  SmartBoardWindow window({int ranks = kSmartPlateRanks}) =>
      smartBoardWindowFor(
        heavy: [lastMove.from, lastMove.to],
        light: recent,
        ranks: ranks,
      );
}

/// Resolved lines, most recently used last: a grid of cards replays each
/// line once, not on every build.
final LinkedHashMap<String, SmartPlatePosition?> _resolved = LinkedHashMap();
const int _resolvedLimit = 64;

/// [line] replayed as its plate shows it, the way an opening pin resolves
/// one: its moves, else the code's canonical line, else its family's. Null
/// when nothing replays (the plate then falls back to the deck).
SmartPlatePosition? resolveSmartPlateLine(SmartPlateLine line) {
  final key = line._key;
  if (_resolved.containsKey(key)) {
    final hit = _resolved.remove(key);
    _resolved[key] = hit;
    return hit;
  }
  final position = _resolve(line);
  _resolved[key] = position;
  if (_resolved.length > _resolvedLimit) _resolved.remove(_resolved.keys.first);
  return position;
}

SmartPlatePosition? _resolve(SmartPlateLine line) {
  bool plays(SpaceLine? l) => l != null && l.ucis.isNotEmpty;
  var resolved = line.moves.isEmpty
      ? null
      : resolveSpaceLine(moves: line.moves);
  final code = line.ecoCode?.trim().toUpperCase() ?? '';
  if (!plays(resolved) && code.isNotEmpty) {
    for (final moves in [
      EcoOpenings.canonicalRecordForCode(code)?.moves,
      EcoOpenings.getFamily(code)?.moves,
      EcoOpenings.canonicalRecordForCode(code.split('-').first.trim())?.moves,
    ]) {
      if (moves == null) continue;
      resolved = resolveSpaceLine(moves: moves);
      if (plays(resolved)) break;
    }
  }
  if (resolved == null || !plays(resolved)) return null;
  final ucis = resolved.ucis;
  final NormalMove last;
  try {
    last = NormalMove.fromUci(ucis.last);
  } on FormatException {
    return null;
  }
  final recent = <Square>[
    for (final uci in ucis.reversed.skip(1).take(3))
      if (uci.length >= 4) ?Square.parse(uci.substring(2, 4)),
  ];
  return SmartPlatePosition(fen: resolved.fen, lastMove: last, recent: recent);
}

/// The position a tier's plate shows: its piece alone, White's, on its home
/// square.
String smartTierPlateFen(SmartEventTier tier) {
  final rows = <String>[];
  for (var rank = 7; rank >= 0; rank--) {
    if (rank != tier.home.rank) {
      rows.add('8');
      continue;
    }
    final before = tier.home.file;
    final after = 7 - before;
    rows.add(
      '${before > 0 ? before : ''}'
      '${tier.piece.uppercaseLetter}'
      '${after > 0 ? after : ''}',
    );
  }
  return '${rows.join('/')} w - - 0 1';
}

/// The plate's own board: quiet squares a step or two off the plate's ink,
/// never the reader's board theme, so every plate reads as one family on
/// the card. [mark] is its one colour, a tonal step of the brand accent.
@immutable
class SmartPlatePalette {
  const SmartPlatePalette._({
    required this.ink,
    required this.scheme,
    required this.mark,
  });

  /// The plate's ground, under the band.
  final Color ink;
  final ChessboardColorScheme scheme;

  /// The defining move's squares, or a tier's home square.
  final Color mark;

  static SmartPlatePalette of(BuildContext context) =>
      context.isLightTheme ? _light : _dark;

  // Dark: grey squares on the hub tiles' ink, light enough that a black
  // piece keeps its edge. The mark is the brand cyan at a third, a muted
  // teal on the grey.
  static final _dark = SmartPlatePalette._(
    ink: kHubTileInk,
    scheme: _scheme(
      light: const Color(0xFF4C4C52),
      dark: const Color(0xFF39393E),
    ),
    mark: const Color(0x520FB4E5),
  );

  // Light: two steps off the recessed surface (#C5D6D5), the mark the
  // accent ink (#005F7D) at a third.
  static final _light = SmartPlatePalette._(
    ink: const Color(0xFFC5D6D5),
    scheme: _scheme(
      light: const Color(0xFFDDE8E7),
      dark: const Color(0xFFAFC3C2),
    ),
    mark: const Color(0x52005F7D),
  );

  /// Two square colours and nothing else: no last-move highlight of the
  /// reader's theme, the plate marks its own squares.
  static ChessboardColorScheme _scheme({
    required Color light,
    required Color dark,
  }) {
    final squares = SolidColorChessboardBackground(
      lightSquare: light,
      darkSquare: dark,
    );
    const none = HighlightDetails(solidColor: Color(0x00000000));
    return ChessboardColorScheme(
      lightSquare: light,
      darkSquare: dark,
      background: squares,
      whiteCoordBackground: squares,
      blackCoordBackground: squares,
      lastMove: none,
      selected: none,
      validMoves: const Color(0x00000000),
      validPremoves: const Color(0x00000000),
    );
  }
}

/// [window] of the board in [fen], [square] points a square, with [marks]
/// in the palette's mark. Exactly [SmartBoardWindow.files] x
/// [SmartBoardWindow.ranks] squares: the board is drawn whole and the
/// window cut from it on square lines, so nothing is sliced.
class SmartEventBoardWindow extends ConsumerWidget {
  const SmartEventBoardWindow({
    super.key,
    required this.square,
    required this.fen,
    required this.window,
    this.marks = const {},
  });

  final double square;
  final String fen;
  final SmartBoardWindow window;
  final Set<Square> marks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = SmartPlatePalette.of(context);
    final pieces =
        ref.watch(
          boardSettingsProviderNew.select((s) => s.valueOrNull?.pieceAssets),
        ) ??
        const BoardSettingsNew().pieceAssets;
    final board = square * 8;
    final highlight = SquareHighlight(
      details: HighlightDetails(solidColor: palette.mark),
    );
    return RepaintBoundary(
      child: ExcludeSemantics(
        child: SizedBox(
          width: square * window.files,
          height: square * window.ranks,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: -square * window.file,
                top: -square * (8 - window.rank - window.ranks),
                width: board,
                height: board,
                child: StaticChessboard(
                  size: board,
                  orientation: Side.white,
                  fen: fen,
                  squareHighlights: {for (final s in marks) s: highlight},
                  settings: StaticChessboardSettings(
                    colorScheme: palette.scheme,
                    pieceAssets: pieces,
                    enableCoordinates: false,
                    // A still picture: a recycled card swaps its position
                    // at once, never slides pieces across.
                    animationDuration: Duration.zero,
                    showLastMove: false,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The plate's margin under a window, one square tall: what a real board's
/// coordinate margin would hold, here the level's floor ("2700+") on the
/// left and the time controls' glyphs on the right, in the plate's ink.
class SmartPlateBand extends StatelessWidget {
  const SmartPlateBand({
    super.key,
    required this.square,
    required this.width,
    this.floor,
    this.glyphs = const [],
  });

  final double square;
  final double width;

  /// The level's floor, printed "2700+"; null prints none.
  final int? floor;

  /// Time-control glyph assets, slow to fast.
  final List<String> glyphs;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final inset = square * 0.32;
    final glyph = math.min(square * 0.56, 14.0);
    final ink = colors.textSecondary;
    return SizedBox(
      width: width,
      height: square,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: inset),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.15,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (floor != null)
                Flexible(
                  child: Text(
                    '$floor+',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    // Its line box is its glyphs' box, so the Row centres
                    // the figures, not a line with room for descenders.
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                      leadingDistribution: TextLeadingDistribution.even,
                    ),
                    style: AppTypography.textXsMedium.copyWith(
                      fontSize: (square * 0.5).clamp(10.5, 13.0),
                      height: 1,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              const Spacer(),
              for (final (i, asset) in glyphs.indexed) ...[
                if (i > 0) SizedBox(width: glyph * 0.4),
                SmartPlateGlyph(asset, size: glyph, ink: ink),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A time-control glyph as a flat mark in [ink], so a plate's one colour
/// stays its board mark (the bolt's blue never comes along). The bolt and
/// the rabbit coin are silhouettes already (the rabbit cut out of its
/// coin); the owl is drawn into its coin, so its coin is kept in [ink] and
/// the owl cut out of it by brightness, the rabbit's way.
class SmartPlateGlyph extends StatelessWidget {
  const SmartPlateGlyph(
    this.asset, {
    super.key,
    required this.size,
    required this.ink,
  });

  /// [PngAsset.classicalIcon], [PngAsset.rapidIcon] or [PngAsset.blitzIcon].
  final String asset;
  final double size;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    if (asset != PngAsset.classicalIcon) {
      return TimeControlGlyph(asset, size: size, tint: ink);
    }
    // Colour: the ink, flat. Alpha: brightness plus coverage less one, so
    // the white coin stays, the black owl and the clear corners go, and the
    // anti-aliased edges keep their softness. The dark-stage original is the
    // one source with a white coin, in either theme.
    final r = (ink.r * 255).roundToDouble();
    final g = (ink.g * 255).roundToDouble();
    final b = (ink.b * 255).roundToDouble();
    final a = ink.a;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(<double>[
        0, 0, 0, 0, r, //
        0, 0, 0, 0, g, //
        0, 0, 0, 0, b, //
        0.299 * a, 0.587 * a, 0.114 * a, a, -255 * a,
      ]),
      child: Image.asset(
        PngAsset.classicalIcon,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        excludeFromSemantics: true,
      ),
    );
  }
}
