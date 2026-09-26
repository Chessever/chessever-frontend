import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The small, drawn marks My Space uses: one stroke weight, rounded joins, a
/// 14% ink wash for volume. They are drawn in two tokens, `#INK` and `#BG`,
/// resolved per theme at build time, so a mark that overlaps itself (the
/// stacked boards) can knock out what sits behind it instead of bleeding
/// through a translucent fill.
enum SpaceGlyphKind {
  database,

  /// A library folder that holds databases rather than games.
  folder,
  bolt,
  heart,
  link,
  flame,
  boards,
  trash,
  arrowUpRight,

  /// A board being set up: the board editor.
  editBoard,

  /// The two-square board with the opening tree growing out of it, the
  /// main line heaviest: the opening explorer.
  explorer,
}

class SpaceGlyph extends StatelessWidget {
  const SpaceGlyph(
    this.kind, {
    super.key,
    required this.size,
    required this.ink,
    this.background,
  });

  final SpaceGlyphKind kind;
  final double size;
  final Color ink;

  /// Knock-out colour for glyphs that overlap themselves (only the boards
  /// glyph does). Defaults to black on the dark theme, as designed, and to
  /// the surface token on paper, where a black knock-out would show.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final knockout =
        background ??
        (context.isLightTheme
            ? context.colors.surface
            : const Color(0xFF000000));
    final svg = _source(
      kind,
    ).replaceAll('#INK', _hex(ink)).replaceAll('#BG', _hex(knockout));
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
  }

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  static String _source(SpaceGlyphKind kind) => switch (kind) {
    SpaceGlyphKind.database => _database,
    SpaceGlyphKind.folder => _folder,
    SpaceGlyphKind.bolt => _bolt,
    SpaceGlyphKind.heart => _heart,
    SpaceGlyphKind.link => _link,
    SpaceGlyphKind.flame => _flame,
    SpaceGlyphKind.boards => _boards,
    SpaceGlyphKind.trash => _trash,
    SpaceGlyphKind.arrowUpRight => _arrowUpRight,
    SpaceGlyphKind.editBoard => _editBoard,
    SpaceGlyphKind.explorer => _explorer,
  };
}

/// A drum of games with a two-square board set into its face.
const _database = '''
<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M3.2 4.7V16.1A6.8 2.4 0 0 0 16.8 16.1V4.7" fill="#INK" fill-opacity="0.14"/>
<ellipse cx="10" cy="4.7" rx="6.8" ry="2.5" fill="#INK" fill-opacity="0.14" stroke="#INK" stroke-width="1.3"/>
<path d="M3.2 4.7V16.1A6.8 2.4 0 0 0 16.8 16.1V4.7" stroke="#INK" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/>
<rect x="7.75" y="9.65" width="4.5" height="4.5" stroke="#INK" stroke-opacity="0.72" stroke-width="0.7"/>
<rect x="7.75" y="9.65" width="2.25" height="2.25" fill="#INK" fill-opacity="0.42"/>
<rect x="10" y="11.9" width="2.25" height="2.25" fill="#INK" fill-opacity="0.42"/>
</svg>
''';

/// A folder with its tab and the same two-square board the database drum
/// carries: a folder of databases.
const _folder = '''
<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M2.8 6.2V15a1.4 1.4 0 0 0 1.4 1.4h11.6a1.4 1.4 0 0 0 1.4-1.4V7.9a1.4 1.4 0 0 0-1.4-1.4H9.6L8.1 4.6H4.2a1.4 1.4 0 0 0-1.4 1.6z" fill="#INK" fill-opacity="0.14" stroke="#INK" stroke-width="1.3" stroke-linejoin="round"/>
<rect x="7.75" y="9.15" width="4.5" height="4.5" stroke="#INK" stroke-opacity="0.72" stroke-width="0.7"/>
<rect x="7.75" y="9.15" width="2.25" height="2.25" fill="#INK" fill-opacity="0.42"/>
<rect x="10" y="11.4" width="2.25" height="2.25" fill="#INK" fill-opacity="0.42"/>
</svg>
''';

const _bolt = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M11 21h-1l1-7H7.5c-.88 0-.33-.75-.31-.78C8.48 10.94 10.42 7.54 13.01 3h1l-1 7h3.51c.4 0 .62.19.4.66C12.97 17.55 11 21 11 21z" fill="#INK"/>
</svg>
''';

const _heart = '''
<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M10 16.4 4.2 10.7a3.7 3.7 0 0 1 5.2-5.3l.6.6.6-.6a3.7 3.7 0 0 1 5.2 5.3z" fill="#INK" fill-opacity="0.14" stroke="#INK" stroke-width="1.3" stroke-linejoin="round"/>
</svg>
''';

const _link = '''
<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M8.6 11.4l2.8-2.8" stroke="#INK" stroke-width="1.4" stroke-linecap="round"/>
<path d="M9.2 6.6l1.3-1.3a3 3 0 0 1 4.2 4.2l-1.3 1.3" stroke="#INK" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M10.8 13.4l-1.3 1.3a3 3 0 0 1-4.2-4.2l1.3-1.3" stroke="#INK" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';

/// Flame keeps its own two-step amber; it is the one warm mark on the page.
const _flame = '''
<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M10 2.6c.5 2.4 3.7 4.2 3.7 8a3.7 3.7 0 0 1-7.4 0c0-1.6.8-2.7 1.7-3.5.1 1.3.7 2.1 1.5 2.3-.3-2.5.1-4.7.5-6.8z" fill="#F59A3C"/>
<path d="M10 9.4c.8 1 1.7 1.8 1.7 3.1a1.7 1.7 0 0 1-3.4 0c0-.8.4-1.4 1-1.9.1.5.3.8.6.9-.1-.7 0-1.4.1-2.1z" fill="#FFB454"/>
</svg>
''';

/// Three boards fanned like a hand of cards: the saved query and its games.
const _boards = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<rect x="2.2" y="8.6" width="8.4" height="8.4" rx="1.2" transform="rotate(-9 6.4 12.8)" fill="#BG" stroke="#INK" stroke-opacity="0.55" stroke-width="1.2"/>
<rect x="13.4" y="8.6" width="8.4" height="8.4" rx="1.2" transform="rotate(8 17.6 12.8)" fill="#BG" stroke="#INK" stroke-opacity="0.55" stroke-width="1.2"/>
<rect x="7" y="5.2" width="10" height="10" rx="1.2" fill="#BG" stroke="#INK" stroke-width="1.3"/>
<rect x="7" y="5.2" width="10" height="10" rx="1.2" fill="#INK" fill-opacity="0.14"/>
<rect x="9.5" y="7.7" width="2.5" height="2.5" fill="#INK" fill-opacity="0.42"/>
<rect x="12" y="10.2" width="2.5" height="2.5" fill="#INK" fill-opacity="0.42"/>
</svg>
''';

const _trash = '''
<svg viewBox="0 0 26 28" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M3 7h20M10 7V4.5A1.5 1.5 0 0 1 11.5 3h3A1.5 1.5 0 0 1 16 4.5V7M5.5 7l1.3 16.2A2 2 0 0 0 8.8 25h8.4a2 2 0 0 0 2-1.8L20.5 7M11 12v8M15 12v8" stroke="#INK" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';

const _arrowUpRight = '''
<svg viewBox="0 0 14 14" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M4 10 10 4M5 3.5h5.5V9" stroke="#INK" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';

/// The two-square board of the database drum, with a pencil laid across its
/// corner; the pencil is knocked out of the board so it reads at small sizes.
const _editBoard = '''
<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
<rect x="2.6" y="5.4" width="10.6" height="10.6" rx="1.2" fill="#INK" fill-opacity="0.14" stroke="#INK" stroke-width="1.3"/>
<rect x="3.25" y="6.05" width="4.65" height="4.65" fill="#INK" fill-opacity="0.42"/>
<rect x="7.9" y="10.7" width="4.65" height="4.65" fill="#INK" fill-opacity="0.42"/>
<path d="M9.6 13.4 16.2 6.8" stroke="#BG" stroke-width="5.2" stroke-linecap="round"/>
<path d="M9.6 13.4 16.2 6.8" stroke="#INK" stroke-width="2.3" stroke-linecap="round"/>
<path d="M8.3 14.7 9.1 13.9" stroke="#INK" stroke-width="1.3" stroke-linecap="round"/>
</svg>
''';

/// The database drum's two-square board with the opening tree growing out
/// of it: one stem, three moves, each landing on the square it reaches; the
/// main line (the middle) lands on a filled one.
const _explorer = '''
<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
<rect x="6.2" y="11" width="7.6" height="7.6" rx="1.2" fill="#INK" fill-opacity="0.14" stroke="#INK" stroke-width="1.3"/>
<rect x="6.85" y="11.65" width="3.15" height="3.15" fill="#INK" fill-opacity="0.42"/>
<rect x="10" y="14.8" width="3.15" height="3.15" fill="#INK" fill-opacity="0.42"/>
<path d="M10 11V8.2M10 8.2 6.4 5.3M10 8.2V4.7M10 8.2 13.6 5.3" stroke="#INK" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/>
<rect x="2.9" y="2.1" width="3.4" height="3.4" rx="0.9" fill="#INK" fill-opacity="0.14" stroke="#INK" stroke-width="1.1"/>
<rect x="8.3" y="1.3" width="3.4" height="3.4" rx="0.9" fill="#INK" stroke="#INK" stroke-width="1.1"/>
<rect x="13.7" y="2.1" width="3.4" height="3.4" rx="0.9" fill="#INK" fill-opacity="0.14" stroke="#INK" stroke-width="1.1"/>
</svg>
''';
