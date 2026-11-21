import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The material a centred popup is cut from: the floating buttons' frosted
/// glass ([GlassSurface]) at the size of a panel.
///
/// What is behind the panel (and only the panel) shows through, blurred,
/// under a plate of the popup's own surface tone. The plate is denser than a
/// button's, because a popup carries paragraphs: body text has to read at
/// 4.5:1 or better over the busiest page it can open on. A fine grain is
/// laid into the plate so the blurred wash never bands, the edge is the
/// plate's own lit rim (brighter at the top, where a soft sheen catches the
/// light), and the shadow is one tight contact shadow cast downwards, drawn
/// only outside the panel so it never darkens the glass from beneath.
@immutable
class PopupGlassStyle {
  const PopupGlassStyle({
    required this.plate,
    required this.rimTop,
    required this.rimBottom,
    required this.sheen,
    required this.shadow,
    required this.grain,
    required this.scrim,
  });

  /// How much of the plate covers the blurred backdrop.
  static const double _lightCover = 0.86;
  static const double _darkCover = 0.85;

  /// The plate over the blurred backdrop, already at its alpha.
  ///
  /// It is solved, not picked: over the page the popup opens on, dimmed by
  /// the scrim, the glass averages out to [tone], the popup's own surface.
  /// A plain tone at partial strength would sink toward the dimmed page (a
  /// grey cast on paper), and the controls inside that were drawn on that
  /// surface would stand out of it as tiles. The busy parts of the page
  /// (boards, pictures) still show through as frost.
  final Color plate;

  /// The rim, lit from above and fading toward the bottom.
  final Color rimTop;
  final Color rimBottom;

  /// The light along the top lip, fading out over [sheenDepth].
  final Color sheen;

  /// One light, from above: short, low, tinted.
  final BoxShadow shadow;

  /// How strongly the grain is laid into the plate (0 none).
  final double grain;

  /// The page dimming under a popup: the barrier's alpha at rest.
  final double scrim;

  /// How far the backdrop is blurred, in logical pixels of sigma. Wide
  /// enough that type and board squares behind melt into a wash, so nothing
  /// behind competes with the popup's own text.
  static const double blurSigma = 22;

  /// How far down the top sheen reaches.
  static const double sheenDepth = 36;

  /// How much of the blurred page a frosted bottom sheet's plate covers in
  /// light: every panel a sheet route shows ([PopupGlassSheetScope]), the
  /// sheet glass itself and the cards that float in a sheet route alike.
  ///
  /// The popups' 86% cannot carry the paper: over a dimmed page it would
  /// need a plate whiter than white, and the 14% of page that shows through
  /// pulled the glass 21 levels grey over a dark board. At 94% the plate is
  /// solved to the paper exactly, and the darkest board behind moves it
  /// under ten levels, still mint (see `test/sheet_glass_tint_probe_test.dart`).
  /// Dark keeps the popups' coverage: there the frost reads as depth, not
  /// as dirt.
  static const double sheetLightCover = 0.94;

  /// The frost rule, the one performance policy for every glass panel: a
  /// panel is blurred live only while it is at most this share of the
  /// screen's height. Taller than that it keeps the glass's look (a solved
  /// plate at full cover, so exactly its own tone, with the same lit top
  /// rim, sheen, grain and contact shadow) and drops the live backdrop
  /// blur.
  ///
  /// A live backdrop blur is paid on every frame the screen redraws (a
  /// clock ticking on the page behind, a list scrolling inside), and it
  /// scales with the panel's area. Under a short panel that leaves the page
  /// in view around it (a menu, a dialog, a picker or explainer sheet) the
  /// frost is what the eye reads as glass, and it is cheap. Past about 60%
  /// of the screen the page is only a strip above the panel, the frost
  /// shows in slivers between the panel's rows and cards, and it costs the
  /// most, frame after frame as the content scrolls: the games sheet, My
  /// Space's add sheet, sign-in, the explorer's filters, the tracking
  /// explainer, a player's score card, the share preview.
  ///
  /// Measured on the sheets bench (`test/sheets_open_perf_test.dart`, host
  /// raster of the whole open screen at 3x, median of 8 interleaved runs,
  /// 2026-11-21): a 760 pt sheet opaque 28.4 ms, solid glass 36.8 ms,
  /// frosted 72.3 ms; a 416 pt sheet opaque 28.6 ms, frosted 53.2 ms. The
  /// solid glass is within a grain fill of the old opaque surface; the live
  /// blur doubles the frame.
  ///
  /// The choice is made once, from the height the panel first lays out at,
  /// and held while it is open (a sheet dragged across the line, or one
  /// that grows as it loads, never swaps material mid-gesture). So a page
  /// that is full height by nature declares it ([PopupGlass.solid],
  /// `GlassSheet.solid`) rather than trusting its first frame, which a
  /// loading list can lay out short.
  ///
  /// A panel of any height is solid when it says so ([PopupGlass.solid]:
  /// its content animates continuously, or opaque content covers most of
  /// it), or under [PopupGlassNoFrost] (a panel over a near-opaque stage,
  /// such as a teaching card on its dark scrim, has nothing behind it to
  /// frost). See `test/popup_consolidation_test.dart` ("the frost rule").
  static const double frostMaxScreenShare = 0.6;

  /// The style for a popup whose surface is [tone] (the theme's surface
  /// when null): the colour its opaque panel used to be.
  ///
  /// [cover] overrides how much of the blurred backdrop the plate covers.
  /// Only a tone whose own text sits close to 4.5:1 needs it (a denser plate
  /// keeps the brightest board behind from pulling that text under AA); null
  /// keeps the theme's coverage.
  ///
  /// [page] is the page under the glass as its dim leaves it: the plate is
  /// solved over it. Null is the page under a centred popup's [scrim]; an
  /// anchored menu passes [AnchoredGlassDim.pageOf] (its lighter dim), a
  /// menu inside another popup that popup's surface.
  static PopupGlassStyle of(
    BuildContext context, {
    Color? tone,
    double? cover,
    Color? page,
  }) {
    final colors = context.colors;
    final surface = tone ?? colors.surface;
    final light = context.isLightTheme;
    final scrim = light ? 0.30 : 0.62;
    final edge = _Edge.of(light: light, ink: colors.textPrimary);
    return PopupGlassStyle(
      plate: _solvedPlate(
        tone: surface,
        page: page ?? _dimmed(colors.background, colors.scrim, scrim),
        cover: cover ?? (light ? _lightCover : _darkCover),
      ),
      rimTop: edge.rimTop,
      rimBottom: edge.rimBottom,
      sheen: edge.sheen,
      shadow: edge.shadow,
      grain: 0.025,
      scrim: scrim,
    );
  }

  /// [page] under the barrier's tint at [strength], as the scrim draws it.
  static Color _dimmed(Color page, Color scrim, double strength) =>
      Color.alphaBlend(scrim.withValues(alpha: strength), page);

  /// The plate colour that, laid at [cover] over [page], gives [tone]:
  /// channel by channel `(tone - (1 - cover) * page) / cover`, held to what
  /// a colour can be.
  static Color _solvedPlate({
    required Color tone,
    required Color page,
    required double cover,
  }) {
    double solve(double t, double p) => (t - (1 - cover) * p) / cover;
    var red = solve(tone.r, page.r);
    var green = solve(tone.g, page.g);
    var blue = solve(tone.b, page.b);
    // A tone the plate cannot reach (paper over a dimmed page needs a plate
    // whiter than white) is not clamped channel by channel: that flattens
    // the plate to pure white and the glass averages to a neutral grey,
    // losing the mint. The three channels move together instead, so the
    // glass keeps the tone's hue and chroma exactly and gives up only a
    // step of lightness.
    final over = math.max(red, math.max(green, blue)) - 1;
    if (over > 0) {
      red -= over;
      green -= over;
      blue -= over;
    }
    final under = -math.min(red, math.min(green, blue));
    if (under > 0) {
      red += under;
      green += under;
      blue += under;
    }
    return Color.from(
      alpha: cover,
      red: red.clamp(0.0, 1.0),
      green: green.clamp(0.0, 1.0),
      blue: blue.clamp(0.0, 1.0),
    );
  }

  /// The page a glass panel stands on, as the plate was solved over it:
  /// [page] when the panel names one, else the page under a centred popup's
  /// [scrim].
  static Color pageUnder(BuildContext context, {Color? page}) {
    if (page != null) return page;
    final colors = context.colors;
    return _dimmed(colors.background, colors.scrim, of(context).scrim);
  }

  /// The colour that, laid flat under [plate], makes the glass read as
  /// [tone] exactly: what a panel that has dropped its live blur
  /// ([frostMaxScreenShare]) stands on, so it is an opaque plate in its own
  /// tone. Where the plate could be solved to the tone over its page this
  /// is that page; where it could not (paper over a dimmed page), it is the
  /// colour that still lands on the tone.
  static Color solidUnderlay(Color plate, Color tone) {
    final cover = plate.a;
    if (cover >= 1) return tone;
    double under(double t, double p) =>
        ((t - cover * p) / (1 - cover)).clamp(0.0, 1.0);
    return Color.from(
      alpha: 1,
      red: under(tone.r, plate.r),
      green: under(tone.g, plate.g),
      blue: under(tone.b, plate.b),
    );
  }

  /// This style with an opaque plate in [tone]: a solid panel's.
  PopupGlassStyle _solidIn(Color tone) => PopupGlassStyle(
    plate: tone.withValues(alpha: 1),
    rimTop: rimTop,
    rimBottom: rimBottom,
    sheen: sheen,
    shadow: shadow,
    grain: grain,
    scrim: scrim,
  );
}

/// The glass's edge in one theme: the lit rim (bright along the top lip,
/// settling quiet down the sides), the sheen under the lip and the one
/// tight contact shadow cast down. Shared by every panel ([PopupGlassStyle])
/// and the solid chips ([SolidGlassDecoration]).
@immutable
class _Edge {
  const _Edge({
    required this.rimTop,
    required this.rimBottom,
    required this.sheen,
    required this.shadow,
  });

  factory _Edge.of({required bool light, required Color ink}) => light
      ? _Edge(
          rimTop: Colors.white.withValues(alpha: 0.95),
          rimBottom: ink.withValues(alpha: 0.10),
          sheen: Colors.white.withValues(alpha: 0.45),
          shadow: BoxShadow(
            color: ink.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        )
      : _Edge(
          rimTop: Colors.white.withValues(alpha: 0.15),
          rimBottom: Colors.white.withValues(alpha: 0.04),
          sheen: Colors.white.withValues(alpha: 0.02),
          shadow: const BoxShadow(
            color: Color(0x66000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        );

  final Color rimTop;
  final Color rimBottom;
  final Color sheen;
  final BoxShadow shadow;
}

/// A chip of the popups' glass too small and too brief to frost (a
/// tooltip): an opaque plate in [tone] with the glass's own edge (the lit
/// rim, brighter along the top lip, and the sheen under it) and one tight
/// contact shadow cast down, at a chip's scale. No backdrop filter and no
/// line drawn evenly around it.
///
/// [light] picks the theme's edge, [ink] tints the light theme's quiet rim
/// and shadow (the theme's text colour), as [PopupGlassStyle.of] does.
@immutable
class SolidGlassDecoration extends Decoration {
  const SolidGlassDecoration({
    required this.tone,
    required this.light,
    required this.ink,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  final Color tone;
  final bool light;
  final Color ink;
  final BorderRadius borderRadius;

  /// The chip's shadow: the panels' contact shadow drawn tighter, for a
  /// chip a line of type tall.
  BoxShadow get shadow {
    final panel = _Edge.of(light: light, ink: ink).shadow;
    return BoxShadow(
      color: panel.color,
      blurRadius: 8,
      offset: const Offset(0, 3),
    );
  }

  @override
  EdgeInsetsGeometry get padding => EdgeInsets.zero;

  @override
  bool hitTest(Size size, Offset position, {TextDirection? textDirection}) =>
      borderRadius.toRRect(Offset.zero & size).contains(position);

  @override
  Path getClipPath(Rect rect, TextDirection textDirection) =>
      Path()..addRRect(borderRadius.toRRect(rect));

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _SolidGlassPainter(this, onChanged);

  @override
  bool operator ==(Object other) =>
      other is SolidGlassDecoration &&
      other.tone == tone &&
      other.light == light &&
      other.ink == ink &&
      other.borderRadius == borderRadius;

  @override
  int get hashCode => Object.hash(tone, light, ink, borderRadius);
}

class _SolidGlassPainter extends BoxPainter {
  _SolidGlassPainter(this._decoration, super.onChanged);

  final SolidGlassDecoration _decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final decoration = _decoration;
    final edge = _Edge.of(light: decoration.light, ink: decoration.ink);
    final rect = offset & size;
    final shape = decoration.borderRadius.toRRect(rect);

    // The contact shadow, only outside the chip.
    final shadow = decoration.shadow;
    final reach = shadow.blurRadius * 2 + shadow.offset.distance + 4;
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect.inflate(reach))
        ..addRRect(shape),
    );
    canvas.drawRRect(shape.shift(shadow.offset), shadow.toPaint());
    canvas.restore();

    canvas.drawRRect(shape, Paint()..color = decoration.tone);

    canvas.save();
    canvas.clipRRect(shape);
    final sheen = Rect.fromLTWH(
      rect.left,
      rect.top,
      rect.width,
      math.min(PopupGlassStyle.sheenDepth, rect.height) / 2,
    );
    canvas.drawRect(
      sheen,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [edge.sheen, edge.sheen.withValues(alpha: 0)],
        ).createShader(sheen),
    );
    canvas.restore();

    canvas.drawRRect(
      shape.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [edge.rimTop, edge.rimBottom],
          // Lit along the top lip, quiet by the chip's middle.
          stops: const [0, 0.6],
        ).createShader(rect),
    );
  }
}

/// The one dim under every anchored glass surface: the shared glass menu
/// (`showTabletSafeMenu`), dropdowns (`GlassDropdown`), the panels that drop
/// from a chip (`GlassPopoverLayer`: an event's categories, a smart event's
/// tiers), the board's game switcher, the add button's popover and the tag
/// picker.
///
/// Lighter than a centred popup's ([PopupGlassStyle.scrim]): an anchored
/// menu belongs to the page it hangs from, and the control that opened it
/// stays readable. A panel that hangs from a chip or a button (the game
/// switcher, the category and tier chips, the add button, the tag chip, a
/// `GlassPopupMenuButton`) leaves that control out of the dim entirely
/// (`GlassScrimPainter.hole`); a dropdown drops clear of its field, which
/// reads through this light tint.
/// The glass is solved over the page this dim leaves ([pageOf]) at a denser
/// [cover], so it still averages to its own tone and its text reads at
/// 4.5:1 over the busiest page (live boards); see
/// `test/anchored_glass_contrast_test.dart`.
/// A plain tint, never a blur.
abstract final class AnchoredGlassDim {
  /// The scrim's strength under an anchored menu, light theme.
  static const double light = 0.10;

  /// The scrim's strength under an anchored menu, dark theme.
  static const double dark = 0.40;

  /// How much of the blurred page an anchored panel's plate covers (see
  /// [PopupGlassStyle.of]'s `cover`): denser than a centred popup's,
  /// because the lighter dim leaves more of the page's contrast to show
  /// through. The frost that does show is about what a dialog's shows over
  /// its darker dim, and the inks keep their dialog-dim contrast or better
  /// (secondary text 4.58:1, accents 6.2:1 over live boards, dark).
  static const double cover = 0.92;

  /// This theme's strength.
  static double strengthOf(BuildContext context) =>
      context.isLightTheme ? light : dark;

  /// The dim at rest.
  static Color colorOf(BuildContext context) =>
      context.colors.scrim.withValues(alpha: strengthOf(context));

  /// The page as the dim leaves it: what an anchored panel's glass is solved
  /// over ([PopupGlassStyle.of]'s `page`).
  static Color pageOf(BuildContext context) =>
      Color.alphaBlend(colorOf(context), context.colors.background);
}

/// A pointer on a [PopupGlass] panel's bottom edge, aimed down at what the
/// panel grows from (a popover over its button).
///
/// It is cut from the same glass as the panel: one silhouette, one backdrop
/// filter, one plate, one rim, so nothing marks where the panel ends and the
/// pointer begins.
@immutable
class PopupGlassPointer {
  const PopupGlassPointer({
    required this.width,
    required this.height,
    required this.tipX,
  });

  /// The pointer's base, along the panel's bottom edge.
  final double width;

  /// How far below the panel the tip reaches. The panel's box grows by it.
  final double height;

  /// The tip's distance from the panel's left edge.
  final double tipX;

  /// How far the pointer's base flares into the panel's bottom edge on each
  /// side: a soft fillet where the two meet, never a notch.
  static const double _fillet = 3;

  /// How much the tip is rounded off: a pointed tip, not a needle.
  static const double _tipRound = 1.5;

  /// The panel and its pointer as one outline, in a box of [size] (the
  /// pointer's height included).
  Path silhouette(Size size, BorderRadius radius) {
    final body = Rect.fromLTWH(
      0,
      0,
      size.width,
      math.max(0, size.height - height),
    );
    final half = width / 2;
    final tip = tipX.clamp(half, math.max(half, size.width - half)).toDouble();
    final bottom = body.bottom;
    // The fillets stay on the bottom edge's straight run, clear of the
    // panel's rounded corners.
    final fillet = math
        .min(
          _fillet,
          math.min(
            tip - half - radius.bottomLeft.x,
            size.width - radius.bottomRight.x - (tip + half),
          ),
        )
        .clamp(0.0, _fillet)
        .toDouble();
    final side = math.sqrt(half * half + height * height);
    if (side <= 0) return Path()..addRRect(radius.toRRect(body));
    // Unit steps down the left side (base to tip) and up the right one.
    final down = Offset(half, height) / side;
    final up = Offset(half, -height) / side;
    final round = math.min(_tipRound, side / 3);
    final apex = Offset(tip, bottom + height);
    final left = Offset(tip - half, bottom);
    final right = Offset(tip + half, bottom);
    final nearApex = apex - down * round;
    final pastApex = apex + up * round;
    final leftFlare = left + down * fillet;
    final rightFlare = right - up * fillet;
    return Path.combine(
      PathOperation.union,
      Path()..addRRect(radius.toRRect(body)),
      Path()
        // Overlaps the body by a point, so the union leaves no seam.
        ..moveTo(left.dx - fillet, bottom - 1)
        ..lineTo(left.dx - fillet, bottom)
        ..quadraticBezierTo(left.dx, bottom, leftFlare.dx, leftFlare.dy)
        ..lineTo(nearApex.dx, nearApex.dy)
        ..quadraticBezierTo(apex.dx, apex.dy, pastApex.dx, pastApex.dy)
        ..lineTo(rightFlare.dx, rightFlare.dy)
        ..quadraticBezierTo(right.dx, bottom, right.dx + fillet, bottom)
        ..lineTo(right.dx + fillet, bottom - 1)
        ..close(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PopupGlassPointer &&
      other.width == width &&
      other.height == height &&
      other.tipX == tipX;

  @override
  int get hashCode => Object.hash(width, height, tipX);
}

/// Several [PopupGlass] panels that sit side by side (the focus menu's quick
/// buttons, its list and its destructive group) frosted by one backdrop
/// filter behind all of them.
///
/// The panels inside draw only their plates, sheens and rims; the frost is
/// this cluster's, read once for the whole group, so the gutters between the
/// panels are frosted too (page text never shows sharp between two panels).
/// With [panels] (their rects in the cluster's box, each rounded by
/// [borderRadius]) the frost is cut to the panels and the gutters between
/// them, and stops where the panels' corners begin: at the cluster's edge a
/// gutter ends between two rounded corners, never as a square slab behind
/// them. Without, it fills the cluster's box, rounded by [borderRadius]. It
/// casts the one contact shadow, from that outline.
class PopupGlassCluster extends StatelessWidget {
  const PopupGlassCluster({
    super.key,
    required this.borderRadius,
    required this.child,
    this.panels,
  });

  final BorderRadius borderRadius;
  final List<Rect>? panels;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = PopupGlassStyle.of(context);
    final outline = _ClusterOutline(borderRadius, panels);
    return CustomPaint(
      foregroundPainter: _ShadowPainter(
        borderRadius: borderRadius,
        shadow: style.shadow,
        outline: outline,
      ),
      child: ClipPath(
        clipper: _OutlineClipper(outline),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: PopupGlassStyle.blurSigma,
            sigmaY: PopupGlassStyle.blurSigma,
          ),
          child: _ClusterScope(child: child),
        ),
      ),
    );
  }
}

/// A cluster's outline: its panels (each rounded) and the gutters between
/// them, the gutters inset from the cluster's edge by the corner radius.
@immutable
class _ClusterOutline {
  const _ClusterOutline(this.radius, this.panels);

  final BorderRadius radius;
  final List<Rect>? panels;

  Path path(Size size) {
    final box = Offset.zero & size;
    final panels = this.panels;
    if (panels == null || panels.isEmpty) {
      return Path()..addRRect(radius.toRRect(box));
    }
    // Same-direction subpaths fill as their union.
    final inset = math.max(
      math.max(radius.topLeft.x, radius.topRight.x),
      math.max(radius.bottomLeft.x, radius.bottomRight.x),
    );
    final path = Path();
    final core = box.deflate(inset);
    if (!core.isEmpty) path.addRect(core);
    for (final panel in panels) {
      path.addRRect(radius.toRRect(panel));
    }
    return path;
  }

  @override
  bool operator ==(Object other) =>
      other is _ClusterOutline &&
      other.radius == radius &&
      listEquals(other.panels, panels);

  @override
  int get hashCode => Object.hash(radius, Object.hashAll(panels ?? const []));
}

class _OutlineClipper extends CustomClipper<Path> {
  const _OutlineClipper(this.outline);

  final _ClusterOutline outline;

  @override
  Path getClip(Size size) => outline.path(size);

  @override
  bool shouldReclip(_OutlineClipper old) => old.outline != outline;
}

/// Marks the panels under a [PopupGlassCluster]: their frost is the
/// cluster's.
class _ClusterScope extends InheritedWidget {
  const _ClusterScope({required super.child});

  @override
  bool updateShouldNotify(_ClusterScope oldWidget) => false;
}

/// A centred popup's panel, in [PopupGlassStyle]'s frosted glass.
///
/// It takes the place of the popup's outer `Container`: [width], [height],
/// [constraints] and [padding] mean what they mean there, and [borderRadius]
/// is the panel's corner. The content is drawn on the glass unchanged, in a
/// repaint boundary of its own.
///
/// [tone] is the colour the popup's opaque panel was (the theme's surface
/// when null): the glass averages out to it, so what the popup draws on it
/// keeps the contrast it was designed with.
///
/// One backdrop filter, clipped to the panel's rounded rect, so only the
/// panel's area is blurred. It is never put in a [BackdropGroup]: a shared
/// backdrop is read once, before the scrim and the page above the group's
/// first filter are drawn, which is not what is behind a popup. Never put
/// the panel under an [Opacity] either: the filter would lose its backdrop
/// and the frost would drop out for the fade. Scale it.
///
/// A bottom sheet is the same glass, rounded at the top only
/// (`BorderRadius.vertical(top: ...)`) and [openBottom]: its lower edge is
/// the screen's (or the keyboard's), so the rim stops at the sides and
/// draws no line along it.
///
/// A panel taller than [PopupGlassStyle.frostMaxScreenShare] of the screen,
/// or one that is [solid], is the same material without the live blur: an
/// opaque plate in [tone], with the same rim, sheen, grain and shadow.
class PopupGlass extends StatelessWidget {
  const PopupGlass({
    super.key,
    required this.child,
    required this.borderRadius,
    this.width,
    this.height,
    this.constraints,
    this.padding,
    this.tone,
    this.openBottom = false,
    this.cover,
    this.page,
    this.pointer,
    this.solid = false,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color? tone;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;

  /// The panel's bottom edge sits on the screen's (a bottom sheet): no rim
  /// is drawn along it.
  final bool openBottom;

  /// See [PopupGlassStyle.of]: null keeps the theme's coverage, or a
  /// sheet's ([PopupGlassStyle.sheetLightCover]) in a sheet route's light.
  final double? cover;

  /// The page under the glass as its dim leaves it (see [PopupGlassStyle.of]);
  /// null is a centred popup's.
  final Color? page;

  /// A pointer on the bottom edge, cut from the same glass. [width],
  /// [height] and [constraints] size the panel above it; the box grows by
  /// the pointer's height.
  final PopupGlassPointer? pointer;

  /// Never blurred, whatever its height: an opaque plate in [tone] with the
  /// same rim, top sheen, grain and shadow, and no backdrop filter at all.
  ///
  /// For a panel whose content animates continuously (the blur would be
  /// paid again on every frame it is open) or is mostly covered by opaque
  /// content (the frost would show only in slivers between it). A panel
  /// taller than [PopupGlassStyle.frostMaxScreenShare] of the screen is
  /// solid without asking.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final surface = tone ?? context.colors.surface;
    final inSheet =
        context.getInheritedWidgetOfExactType<PopupGlassSheetScope>() != null;
    final frosted = PopupGlassStyle.of(
      context,
      tone: tone,
      cover:
          cover ??
          (inSheet && context.isLightTheme
              ? PopupGlassStyle.sheetLightCover
              : null),
      page: page,
    );
    final style = solid ? frosted._solidIn(surface) : frosted;
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    // Under a [PopupGlassCluster] the frost and the shadow are the
    // cluster's: this panel is only its plate.
    final clustered =
        context.getInheritedWidgetOfExactType<_ClusterScope>() != null;
    final pointer = this.pointer;
    Widget content = _GlassMaterial(
      tone: surface,
      grain: style.grain,
      child: RepaintBoundary(child: child),
    );
    final inset = padding;
    if (inset != null) content = Padding(padding: inset, child: content);

    var box = constraints;
    if (width != null || height != null) {
      box =
          box?.tighten(width: width, height: height) ??
          BoxConstraints.tightFor(width: width, height: height);
    }
    if (pointer != null) {
      // The body keeps its size; the pointer hangs below it.
      if (box != null) {
        content = ConstrainedBox(constraints: box, child: content);
      }
      content = Padding(
        padding: EdgeInsets.only(bottom: pointer.height),
        child: content,
      );
    }

    Widget glass = CustomPaint(
      painter: _PlatePainter(
        style: style,
        borderRadius: borderRadius,
        devicePixelRatio: ratio,
        openBottom: openBottom,
        pointer: pointer,
      ),
      child: content,
    );
    if (!clustered && !solid) {
      glass = BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: PopupGlassStyle.blurSigma,
          sigmaY: PopupGlassStyle.blurSigma,
        ),
        child: glass,
      );
      // The frost rule ([PopupGlassStyle.frostMaxScreenShare]): a panel
      // taller than it is solid, an opaque plate in its own tone.
      glass = _FrostGate(
        tone: surface,
        underlay: PopupGlassStyle.solidUnderlay(style.plate, surface),
        child: glass,
      );
    }
    glass = pointer == null
        ? ClipRRect(borderRadius: borderRadius, child: glass)
        : ClipPath(
            clipper: _SilhouetteClipper(pointer, borderRadius),
            child: glass,
          );

    Widget panel = clustered
        ? glass
        : CustomPaint(
            // Drawn after the glass, so the blur never samples it.
            foregroundPainter: _ShadowPainter(
              borderRadius: borderRadius,
              shadow: style.shadow,
              pointer: pointer,
            ),
            child: glass,
          );

    if (pointer == null && box != null) {
      panel = ConstrainedBox(constraints: box, child: panel);
    }
    return panel;
  }
}

/// Clips a panel with a pointer to its one silhouette.
class _SilhouetteClipper extends CustomClipper<Path> {
  const _SilhouetteClipper(this.pointer, this.borderRadius);

  final PopupGlassPointer pointer;
  final BorderRadius borderRadius;

  @override
  Path getClip(Size size) => pointer.silhouette(size, borderRadius);

  @override
  bool shouldReclip(_SilhouetteClipper old) =>
      old.pointer != pointer || old.borderRadius != borderRadius;
}

/// The plate, its grain, the top sheen and the lit rim: everything the
/// glass is, behind the content.
class _PlatePainter extends CustomPainter {
  const _PlatePainter({
    required this.style,
    required this.borderRadius,
    required this.devicePixelRatio,
    this.openBottom = false,
    this.pointer,
  });

  final PopupGlassStyle style;
  final BorderRadius borderRadius;
  final double devicePixelRatio;
  final bool openBottom;
  final PopupGlassPointer? pointer;

  /// This plate opaque in [tone] (the same rim, sheen and grain): what a
  /// panel the frost rule keeps from blurring paints. Itself when it
  /// already is.
  _PlatePainter solidIn(Color tone) {
    final solid = tone.withValues(alpha: 1);
    if (style.plate == solid) return this;
    return _PlatePainter(
      style: style._solidIn(tone),
      borderRadius: borderRadius,
      devicePixelRatio: devicePixelRatio,
      openBottom: openBottom,
      pointer: pointer,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = style.plate);

    final grain = _Grain.tile;
    if (grain != null && style.grain > 0) {
      final scale = 1 / devicePixelRatio;
      canvas.drawRect(
        rect,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, style.grain)
          ..shader = ui.ImageShader(
            grain,
            TileMode.repeated,
            TileMode.repeated,
            Matrix4.diagonal3Values(scale, scale, 1).storage,
            filterQuality: FilterQuality.none,
          ),
      );
    }

    final sheenRect = Rect.fromLTWH(
      0,
      0,
      size.width,
      math.min(PopupGlassStyle.sheenDepth, size.height),
    );
    canvas.drawRect(
      sheenRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [style.sheen, style.sheen.withValues(alpha: 0)],
        ).createShader(sheenRect),
    );

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [style.rimTop, style.rimBottom],
        // The lit lip is the top edge's; the sides settle to the quiet rim
        // within the first stretch of the panel.
        stops: [0, math.min(1, 96 / math.max(size.height, 1))],
      ).createShader(rect);
    final pointer = this.pointer;
    if (pointer != null) {
      // One rim around the panel and its pointer: none across the
      // pointer's base. Inset half a stroke, as the plain outline is.
      canvas.save();
      canvas.translate(0.5, 0.5);
      canvas.drawPath(
        pointer.silhouette(
          Size(math.max(0, size.width - 1), math.max(0, size.height - 1)),
          borderRadius,
        ),
        rim,
      );
      canvas.restore();
    } else if (openBottom) {
      // The rim's bottom run is the last pixel row: leave it out.
      canvas.save();
      canvas.clipRect(
        Rect.fromLTWH(0, 0, size.width, math.max(0, size.height - 1)),
      );
      canvas.drawRRect(borderRadius.toRRect(rect).deflate(0.5), rim);
      canvas.restore();
    } else {
      canvas.drawRRect(borderRadius.toRRect(rect).deflate(0.5), rim);
    }
  }

  @override
  bool shouldRepaint(_PlatePainter old) =>
      old.style.plate != style.plate ||
      old.style.rimTop != style.rimTop ||
      old.style.rimBottom != style.rimBottom ||
      old.style.sheen != style.sheen ||
      old.style.grain != style.grain ||
      old.borderRadius != borderRadius ||
      old.devicePixelRatio != devicePixelRatio ||
      old.openBottom != openBottom ||
      old.pointer != pointer;
}

/// The contact shadow, cast down from one light and drawn only outside the
/// panel: under translucent glass a shadow would show through as a darker
/// box inside it.
class _ShadowPainter extends CustomPainter {
  const _ShadowPainter({
    required this.borderRadius,
    required this.shadow,
    this.pointer,
    this.outline,
  });

  final BorderRadius borderRadius;
  final BoxShadow shadow;
  final PopupGlassPointer? pointer;
  final _ClusterOutline? outline;

  @override
  void paint(Canvas canvas, Size size) {
    if (shadow.color.a <= 0) return;
    final pointer = this.pointer;
    final cluster = outline;
    final reach = shadow.blurRadius * 2 + shadow.offset.distance + 8;
    if (pointer != null || cluster != null) {
      final outline = pointer != null
          ? pointer.silhouette(size, borderRadius)
          : cluster!.path(size);
      canvas.save();
      // Only outside the outline (its subpaths may overlap: a difference,
      // not an even-odd fill).
      canvas.clipPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect((Offset.zero & size).inflate(reach)),
          outline,
        ),
      );
      canvas.drawPath(outline.shift(shadow.offset), shadow.toPaint());
      canvas.restore();
      return;
    }
    final shape = borderRadius.toRRect(Offset.zero & size);
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(shape.outerRect.inflate(reach))
        ..addRRect(shape),
    );
    canvas.drawRRect(
      shape.shift(shadow.offset).inflate(shadow.spreadRadius),
      shadow.toPaint(),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShadowPainter old) =>
      old.shadow != shadow ||
      old.borderRadius != borderRadius ||
      old.pointer != pointer ||
      old.outline != outline;
}

/// A tile of film grain, one texel per device pixel: equal parts lighter
/// and darker specks around a neutral middle, so laid over the plate it
/// dithers the blurred wash without shifting its tone.
abstract final class _Grain {
  static const int _side = 128;
  static ui.Image? _tile;
  static bool _failed = false;

  static ui.Image? get tile {
    if (_tile != null || _failed) return _tile;
    try {
      final random = math.Random(1709);
      // Four strengths each way: finer grain than one flat speck.
      final light = List.generate(4, (_) => <double>[]);
      final dark = List.generate(4, (_) => <double>[]);
      for (var y = 0; y < _side; y++) {
        for (var x = 0; x < _side; x++) {
          final v = random.nextDouble() * 2 - 1;
          final bucket = math.min(3, (v.abs() * 4).floor());
          (v >= 0 ? light : dark)[bucket]
            ..add(x + 0.5)
            ..add(y + 0.5);
        }
      }
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      for (var bucket = 0; bucket < 4; bucket++) {
        final alpha = (bucket + 1) / 4;
        for (final (points, base) in [
          (light[bucket], Colors.white),
          (dark[bucket], Colors.black),
        ]) {
          canvas.drawRawPoints(
            ui.PointMode.points,
            Float32List.fromList(points),
            Paint()
              ..color = base.withValues(alpha: alpha)
              ..strokeWidth = 1
              ..strokeCap = StrokeCap.square,
          );
        }
      }
      final picture = recorder.endRecording();
      _tile = picture.toImageSync(_side, _side);
      picture.dispose();
    } catch (_) {
      _failed = true;
    }
    return _tile;
  }
}

/// Marks the panels of a bottom sheet route (`showGlassModalBottomSheet`):
/// a frosted [PopupGlass] below it, the sheet glass or a card floating in
/// the route, takes the sheets' light coverage
/// ([PopupGlassStyle.sheetLightCover]) unless it names its own. Menus and
/// dialogs opened from a sheet are routes of their own, outside it.
class PopupGlassSheetScope extends InheritedWidget {
  const PopupGlassSheetScope({super.key, required super.child});

  @override
  bool updateShouldNotify(PopupGlassSheetScope oldWidget) => false;
}

/// Takes the live blur away from every [PopupGlass] below it, whatever its
/// height; see [PopupGlassStyle.frostMaxScreenShare]. The panels keep their
/// material: an opaque plate in their tone, with rim, sheen and grain.
class PopupGlassNoFrost extends InheritedWidget {
  const PopupGlassNoFrost({super.key, required super.child});

  @override
  bool updateShouldNotify(PopupGlassNoFrost oldWidget) => false;
}

/// Decides, once, whether its [BackdropFilter] child blurs live
/// ([PopupGlassStyle.frostMaxScreenShare]) and, when it does not, makes the
/// panel an opaque plate in [tone]: the plate under the filter is swapped
/// for the solid one ([PopupGlass.solid]'s), so the panel costs what a
/// declared solid one does, one opaque fill and no blend. Should the plate
/// not be found there, [underlay] is laid flat under the translucent plate
/// instead ([PopupGlassStyle.solidUnderlay]), which reads the same.
class _FrostGate extends SingleChildRenderObjectWidget {
  const _FrostGate({
    required this.tone,
    required this.underlay,
    required super.child,
  });

  final Color tone;
  final Color underlay;

  /// The tallest the panel may be and blur live; below zero, never.
  static double _limit(BuildContext context) {
    if (context.dependOnInheritedWidgetOfExactType<PopupGlassNoFrost>() !=
        null) {
      return -1;
    }
    final screen = MediaQuery.maybeSizeOf(context)?.height;
    return screen == null
        ? double.infinity
        : screen * PopupGlassStyle.frostMaxScreenShare;
  }

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFrostGate(tone, underlay, _limit(context));

  @override
  void updateRenderObject(BuildContext context, _RenderFrostGate gate) {
    gate
      ..tone = tone
      ..underlay = underlay
      ..limit = _limit(context)
      ..rebuilt();
  }
}

class _RenderFrostGate extends RenderProxyBox {
  _RenderFrostGate(this._tone, this._underlay, this._limit);

  Color _tone;
  set tone(Color value) {
    if (value == _tone) return;
    _tone = value;
    if (_frosted == false) markNeedsLayout();
  }

  /// The plate was swapped for the solid one on the last layout.
  bool _swapped = false;

  /// The frosted plate the solid one replaced, for a new screen that
  /// decides to frost after all.
  _PlatePainter? _frostedPlate;

  Color _underlay;
  set underlay(Color value) {
    if (value == _underlay) return;
    _underlay = value;
    if (_frosted == false) markNeedsPaint();
  }

  double _limit;
  set limit(double value) {
    if (value == _limit) return;
    _limit = value;
    // A new screen (a rotation, a split view): decide again.
    _frosted = null;
    markNeedsLayout();
  }

  /// The decision, made from the first height the panel lays out at and
  /// held after; null until then.
  bool? _frosted;

  /// The panel was built again: its [BackdropFilter] came back enabled and
  /// its plate translucent, so a panel that does not blur is laid out again
  /// to switch the one off and swap the other.
  void rebuilt() {
    if (_frosted == false) markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    if (_frosted == null && size.height > 0) {
      _frosted = size.height <= _limit;
    }
    final filter = child;
    var swapped = false;
    if (filter is RenderBackdropFilter) {
      filter.enabled = _frosted ?? true;
      final plate = filter.child;
      final painter = plate is RenderCustomPaint ? plate.painter : null;
      if (painter is _PlatePainter) {
        plate as RenderCustomPaint;
        if (_frosted == false) {
          // Setting the same painter again is free; a translucent one is
          // the frosted plate a rebuild handed back.
          final solid = painter.solidIn(_tone);
          if (!identical(solid, painter)) _frostedPlate = painter;
          plate.painter = solid;
          swapped = true;
        } else if (painter.style.plate.a >= 1 && _frostedPlate != null) {
          // Decided again (a new screen) to frost: a gated panel's own
          // plate is always translucent, so an opaque one is the swap.
          plate.painter = _frostedPlate;
        }
      }
    }
    if (swapped != _swapped) {
      _swapped = swapped;
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_frosted == false && !_swapped) {
      context.canvas.drawRect(offset & size, Paint()..color = _underlay);
    }
    super.paint(context, offset);
  }
}

/// The material of the [PopupGlass] around it, for [PopupGlassFill].
class _GlassMaterial extends InheritedWidget {
  const _GlassMaterial({
    required this.tone,
    required this.grain,
    required super.child,
  });

  final Color tone;
  final double grain;

  @override
  bool updateShouldNotify(_GlassMaterial old) =>
      old.tone != tone || old.grain != grain;
}

/// A band of the solid glass around it: an opaque plate in the panel's own
/// tone with its grain, and no rim and no sheen. For a bar pinned inside a
/// panel that must hide what scrolls under it (a sheet's action bar over
/// its list): on a solid panel ([PopupGlass.solid], or one taller than
/// [PopupGlassStyle.frostMaxScreenShare]) it is the very same surface, so
/// the glass carries the bar with no band across it.
///
/// The tone is the enclosing [PopupGlass]'s; [tone] overrides it.
class PopupGlassFill extends StatelessWidget {
  const PopupGlassFill({super.key, required this.child, this.tone});

  final Widget child;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final glass = context.dependOnInheritedWidgetOfExactType<_GlassMaterial>();
    return CustomPaint(
      painter: _FillPainter(
        tone: tone ?? glass?.tone ?? context.colors.surface,
        grain: glass?.grain ?? PopupGlassStyle.of(context).grain,
        devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
      ),
      child: child,
    );
  }
}

class _FillPainter extends CustomPainter {
  const _FillPainter({
    required this.tone,
    required this.grain,
    required this.devicePixelRatio,
  });

  final Color tone;
  final double grain;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = tone.withValues(alpha: 1));
    final tile = _Grain.tile;
    if (tile == null || grain <= 0) return;
    final scale = 1 / devicePixelRatio;
    canvas.drawRect(
      rect,
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, grain)
        ..shader = ui.ImageShader(
          tile,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.diagonal3Values(scale, scale, 1).storage,
          filterQuality: FilterQuality.none,
        ),
    );
  }

  @override
  bool shouldRepaint(_FillPainter old) =>
      old.tone != tone ||
      old.grain != grain ||
      old.devicePixelRatio != devicePixelRatio;
}
