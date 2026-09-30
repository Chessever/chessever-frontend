import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:flutter/material.dart';

/// The colours a share image paints with, one set per app theme.
///
/// Share cards are designed artifacts, not screenshots, so they never read
/// `context.colors` (a share can start inside a forced-dark island such as the
/// feed). Instead [captureCardPng] resolves the palette from the APP theme and
/// hands it down through [ShareCardScope]; every card reads it back with
/// [ShareCardPalette.of].
///
/// [dark] keeps the historical brand colours but paints a flat header with no
/// glow, the same construction as [light]; the two editions differ in colour
/// only. [light] is a paper edition built on the light theme tokens: mint
/// paper, white tiles with a self-coloured edge, ink type and the deepened
/// signal colours, every text pair at WCAG AA.
@immutable
class ShareCardPalette {
  const ShareCardPalette._({
    required this.isLight,
    required this.bg,
    required this.surface,
    required this.surfaceLow,
    required this.hairline,
    required this.tileEdge,
    required this.accentFill,
    required this.accentInk,
    required this.gold,
    required this.win,
    required this.loss,
    required this.draw,
    required this.pending,
    required this.textHi,
    required this.textMid,
    required this.textLo,
    required this.pieceWhite,
    required this.pieceWhiteEdge,
    required this.pieceBlack,
    required this.pieceBlackEdge,
    required this.heroTint,
    required this.glowOpacity,
    required this.logoGlow,
    required this.ecoTileAlpha,
    required this.wash,
    required this.band,
  });

  /// True for the paper edition.
  final bool isLight;

  /// The card's page colour.
  final Color bg;

  /// Raised tiles (headline stats, match lists).
  final Color surface;

  /// Recessed wells (result lists, rating strips).
  final Color surfaceLow;

  /// Rules between rows and around tiles.
  final Color hairline;

  /// Edge for a raised tile that would otherwise vanish into [bg]. Null in
  /// dark, where tone alone separates the tile.
  final Color? tileEdge;

  /// Brand cyan for FILLS only (kicker rule). Never text on paper.
  final Color accentFill;

  /// Brand cyan for TEXT (links, ECO codes, winning team score).
  final Color accentInk;

  /// Chess title prefix (GM, IM, ...).
  final Color gold;

  final Color win;
  final Color loss;
  final Color draw;

  /// An unfinished team match.
  final Color pending;

  final Color textHi;
  final Color textMid;
  final Color textLo;

  /// Piece-colour discs (the side a player had).
  final Color pieceWhite;
  final Color? pieceWhiteEdge;
  final Color pieceBlack;
  final Color? pieceBlackEdge;

  /// Alpha of the cyan wash at the top of a hero; 0 draws a flat header.
  final double heroTint;

  /// Alpha of the soft cyan bloom behind a player; 0 draws none.
  final double glowOpacity;

  /// Whether the logo mark carries its cyan bloom.
  final bool logoGlow;

  /// Alpha of the cyan box behind an ECO code; 0 leaves the code bare.
  final double ecoTileAlpha;

  /// A barely-there fill behind a score.
  final Color wash;

  /// The team card's footer band.
  final Color band;

  /// Historical dark brand colours. Header wash, team-hero gradient, player
  /// glow and logo bloom are off (no glow, no hard seam where a tinted hero
  /// meets the page), and ECO codes sit bare in their fixed slot with no
  /// tinted chip (cyan on [surface] clears AA on its own), matching [light].
  static const ShareCardPalette dark = ShareCardPalette._(
    isLight: false,
    bg: Color(0xFF0A0B0D),
    surface: Color(0xFF15171C),
    surfaceLow: Color(0xFF101216),
    hairline: Color(0xFF23262E),
    tileEdge: null,
    accentFill: kPrimaryColor,
    accentInk: kPrimaryColor,
    gold: kLightYellowColor,
    win: kGreenColor2,
    loss: kRedColor,
    draw: Color(0xFF868C97),
    pending: Color(0xFF9AA0A6),
    textHi: Colors.white,
    textMid: Color(0xFFAEB4BF),
    textLo: Color(0xFF868C97),
    pieceWhite: Colors.white,
    pieceWhiteEdge: null,
    pieceBlack: Colors.black,
    // Exactly `Colors.white.withValues(alpha: 0.35)`, as a const.
    pieceBlackEdge: Color.from(alpha: 0.35, red: 1, green: 1, blue: 1),
    heroTint: 0,
    glowOpacity: 0,
    logoGlow: false,
    ecoTileAlpha: 0,
    // Exactly `Colors.white.withValues(alpha: 0.04)`, as a const.
    wash: Color.from(alpha: 0.04, red: 1, green: 1, blue: 1),
    band: Color(0xFF07080B),
  );

  /// Paper edition. Every ink and signal colour is read from
  /// [AppColors.light], so the card follows the light theme's tokens.
  static final ShareCardPalette light = ShareCardPalette._(
    isLight: true,
    bg: AppColors.light.surface,
    surface: const Color(0xFFFFFFFF),
    surfaceLow: const Color(0xFFE8F1F0),
    hairline: const Color(0xFFD3E0DF),
    tileEdge: const Color(0xFFCBDAD9),
    accentFill: AppColors.light.brand,
    accentInk: AppColors.light.accentText,
    gold: AppColors.light.titleAccent,
    win: AppColors.light.success,
    loss: AppColors.light.danger,
    draw: AppColors.light.textTertiary,
    pending: AppColors.light.textTertiary,
    textHi: AppColors.light.textPrimary,
    textMid: AppColors.light.textSecondary,
    textLo: AppColors.light.textTertiary,
    pieceWhite: Colors.white,
    pieceWhiteEdge: AppColors.light.placeholder,
    pieceBlack: AppColors.light.textPrimary,
    pieceBlackEdge: null,
    heroTint: 0,
    glowOpacity: 0,
    logoGlow: false,
    ecoTileAlpha: 0,
    wash: AppColors.light.textPrimary.withValues(alpha: 0.05),
    band: const Color(0xFFE8F1F0),
  );

  static ShareCardPalette forBrightness(Brightness brightness) =>
      brightness == Brightness.light ? light : dark;

  /// The palette the nearest [ShareCardScope] carries, else [dark]: a card
  /// rendered without a scope (tests, detached renders) keeps its historical
  /// look.
  static ShareCardPalette of(BuildContext context) =>
      ShareCardScope.maybeOf(context) ?? dark;
}

/// Hands a [ShareCardPalette] to every share card below it.
class ShareCardScope extends InheritedWidget {
  const ShareCardScope({
    super.key,
    required this.palette,
    required super.child,
  });

  final ShareCardPalette palette;

  static ShareCardPalette? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShareCardScope>()?.palette;

  @override
  bool updateShouldNotify(ShareCardScope oldWidget) =>
      palette != oldWidget.palette;
}

/// Maps the white glyph of a time-control icon to ink and its dark ground to
/// paper, so the owl and the rabbit read as an ink disc on the light card.
const ColorFilter _inkOnPaper = ColorFilter.matrix(<double>[
  -0.902, 0, 0, 0, 244, //
  0, -0.878, 0, 0, 250, //
  0, 0, -0.867, 0, 249, //
  0, 0, 0, 1, 0, //
]);

/// A time-control icon as a share card shows it. The classical and rapid PNGs
/// are white glyphs that disappear on paper, so the light edition inverts
/// them to ink; the blitz bolt is already blue and dark is untouched.
Widget shareTimeControlIcon(
  String asset,
  ShareCardPalette palette, {
  double size = 17,
}) {
  final image = Image.asset(asset, width: size, height: size);
  final isWhiteGlyph =
      asset == PngAsset.classicalIcon || asset == PngAsset.rapidIcon;
  if (!palette.isLight || !isWhiteGlyph) return image;
  return ColorFiltered(colorFilter: _inkOnPaper, child: image);
}
