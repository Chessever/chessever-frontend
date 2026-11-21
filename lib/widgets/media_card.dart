import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart'
    show getTitleBadgeColor, titleBadgeLegibleFill, titleBadgeLegibleInk;
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:motor/motor.dart';

// Media cards: a picture (the followed players' photo mosaic, a federation's
// flag, a player's portrait over their flag, a hub's drawn art) with white
// type laid over it. They are ONE design in both themes, the dark one: on a
// light page they stand as dark media cards, exactly as dark mode draws them.
//
// The picture is the point, so it is shown as it is: a flag in its own
// colours, a photo whole, the art at full strength. The words are carried by
// one smooth shade rising out of the corner they sit in ([MediaTextScrim]):
// a single gradient, darkest under the words and gone a short, soft way past
// them, so the picture's top and far side (a face, a flag's far field) stay
// as drawn; never a band or a box that follows the lines of type. It is only
// as deep as the words need (3:1 for a large bold name or title, 4.5:1 for
// the smaller lines), and a tight shadow under the type ([kMediaTitleShadows],
// [kMediaCaptionShadows]) firms the glyphs' edges where a bright picture runs
// beneath them.

/// White type on a media card.
const Color kMediaOnInk = Color(0xFFFFFFFF);

/// The quieter line under a media card's title (a caption, a rating and
/// federation): white at [kMediaQuietAlpha]. Quieter by its size and weight
/// more than by its ink.
const double kMediaQuietAlpha = 0.9;

/// [kMediaOnInk] at [kMediaQuietAlpha].
const Color kMediaOnInkQuiet = Color.fromRGBO(255, 255, 255, kMediaQuietAlpha);

/// The shadow under a media card's title or name: tight, soft, one point
/// down, as from a light above. It never carries the contrast on its own
/// (the [MediaTextScrim] does); it keeps the glyphs' edges crisp where a pale
/// picture runs under them.
const List<Shadow> kMediaTitleShadows = [
  Shadow(
    color: Color.fromRGBO(0, 0, 0, 0.42),
    blurRadius: 6,
    offset: Offset(0, 1),
  ),
];

/// [kMediaTitleShadows] for a media card's smaller lines.
const List<Shadow> kMediaCaptionShadows = [
  Shadow(
    color: Color.fromRGBO(0, 0, 0, 0.38),
    blurRadius: 4,
    offset: Offset(0, 1),
  ),
];

/// Gives everything under it the app's dark theme, so a media card on a
/// light page is the very card dark mode shows: its plates, its ink, its
/// drawn art (pixel tones, hub drawings) all resolve as they do in dark.
class MediaTheme extends StatelessWidget {
  const MediaTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Theme(data: AppTheme.darkTheme, child: child);
}

/// A flag filling its box edge to edge (cropped to cover), from the vector
/// flags ([CountryFlag]), crisp however large the card. The small raster
/// flags (100x67 PNGs) blur and stair-step when stretched over a card.
///
/// The flag keeps its own colours: its white is white, its red is its red.
/// Only a faint even deepening keeps its white from glaring beside the dark
/// cards around it. Words over it are carried by the card's
/// [MediaTextScrim], never by recolouring the flag. Build it with
/// [ofFederation].
class MediaFlagBackdrop extends StatelessWidget {
  const MediaFlagBackdrop({super.key, required this.flag});

  /// The flag at its own proportions, at any size.
  final Widget flag;

  /// How much the flag is deepened toward black, evenly.
  static const double deepen = 0.04;

  /// Whether `country_flags` draws a flag for [code] (an ISO alpha-2 or
  /// alpha-3 code). FIDE's neutral federation ("XX") and stray codes have
  /// none: the package's stand-in is a white tile with a question mark,
  /// which at full strength would be a white slab behind white words.
  static bool knows(String? code) =>
      code != null &&
      code.trim().isNotEmpty &&
      FlagCode.fromCountryCode(code.trim().toUpperCase()) != null;

  /// The UK's nations: no ISO alpha-2 code of their own, but vector flags
  /// in `country_flags` (England's is St George's cross).
  static const Map<String, String> _ukNations = {
    'ENG': 'GB-ENG',
    'ENGLAND': 'GB-ENG',
    'SCO': 'GB-SCT',
    'SCOTLAND': 'GB-SCT',
    'WLS': 'GB-WLS',
    'WALES': 'GB-WLS',
  };

  /// The `country_flags` code for [federation], written any way the data
  /// writes it: an ISO alpha-2 code ("NO", "XK"), a FIDE code ("NOR",
  /// "GER", "ENG"), or a country name ("Norway"). Null when it names no
  /// flag the package draws (unknown, FIDE's neutral players).
  static String? flagCodeOf(String? federation) {
    final raw = federation?.trim() ?? '';
    if (raw.isEmpty) return null;
    final upper = raw.toUpperCase();
    final nation = _ukNations[upper];
    if (nation != null) return nation;
    if (upper.length == 2 && upper != 'XX' && knows(upper)) return upper;
    final iso2 = FederationFlag.iso2Of(raw)?.toUpperCase();
    return knows(iso2) ? iso2 : null;
  }

  /// [federation]'s flag as a backdrop (written any way [flagCodeOf]
  /// takes), drawn from the package's vector flags in their own colours;
  /// null when there is none, so the card shows its plain ink.
  static MediaFlagBackdrop? ofFederation(String? federation) {
    final code = flagCodeOf(federation);
    if (code == null) return null;
    return MediaFlagBackdrop(
      flag: CountryFlag.fromCountryCode(
        code,
        theme: const ImageTheme(width: 300, height: 200),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: const BoxDecoration(color: Color.fromRGBO(0, 0, 0, deepen)),
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: flag,
          ),
        ),
      ),
    );
  }
}

/// The shade that carries a media card's words.
///
/// Set it over the card's whole face (a [Positioned.fill] in the card's
/// stack), with the words, padded, as its child. It finds every line of type
/// under it and lays ONE smooth gradient rising out of the edge of the card
/// they sit at (bottom-left words: the bottom edge, from the corner): black
/// held over an ellipse set on the words, then eased away over many stops,
/// so it reads as light falling off toward the picture, never as a band, a
/// box or a shape that traces the type. It is one plain gradient paint (a
/// two-point conical gradient, [MediaScrimShape]): no layer, no blend.
///
/// It is as light and as close to the words as they allow. Over the
/// brightest the picture can be ([ground], a relative luminance; a flag or
/// photo can be white), each line's far corner keeps its own bar: 3:1 for a
/// large bold line (a name, a title, [contrastFor]), 4.5:1 for the smaller
/// ones. Of the shapes that do, the one laying the least black away from
/// the words wins ([RenderMediaTextScrim.shape]), its fade never steeper
/// than a soft edge ([MediaScrimShape.maxSlope]); the photo and the flag
/// beyond the words keep their own light. Over darker drawn art it is
/// lighter; over art dark enough already (the Likes heart) there is none.
///
/// A [MediaScrimSkip] under it (a title badge on its own fill) is left out
/// of the words it answers to.
class MediaTextScrim extends SingleChildRenderObjectWidget {
  const MediaTextScrim({
    super.key,
    this.ground = 1,
    required Widget super.child,
  });

  /// The brightest the picture behind the words can be anywhere on the
  /// card, as a relative luminance (0 black, 1 white).
  final double ground;

  /// WCAG AA for body text.
  static const double bodyContrast = 4.5;

  /// WCAG AA for large text, and for a glyph beside the words (non-text
  /// contrast).
  static const double largeContrast = 3.0;

  /// What the shade aims for over each bar, so rounding never lands under
  /// it.
  static const double margin = 0.15;

  /// A bold line (w600 or heavier) at this size or more counts as large: a
  /// media card's name or title. WCAG's own threshold is 14pt bold (18.66
  /// logical points); the cards' 16-point bold names and titles are held to
  /// the large bar here, as the product sets them, and their measured
  /// contrast is recorded in test/light_media_cards_preview_test.dart.
  static const double largeBoldSize = 16;

  /// Any line at this size or more counts as large, whatever its weight.
  static const double largeSize = 24;

  /// The contrast a line set at [fontSize] (as drawn, after the reader's
  /// text scale) in [weight] must keep: [largeContrast] for large type,
  /// [bodyContrast] otherwise.
  static double contrastFor({
    required double fontSize,
    required FontWeight weight,
  }) {
    final large =
        fontSize >= largeSize ||
        (fontSize >= largeBoldSize - 0.01 && weight.value >= 600);
    return large ? largeContrast : bodyContrast;
  }

  /// The least black, laid over a ground of relative luminance [ground],
  /// that leaves [ink] at [contrast]:1 or better (0 when the ground already
  /// gives it). The ground is taken as a grey of that luminance, darkened
  /// and composited in sRGB as the screen composites it.
  static double shadeFor(
    Color ink, {
    double ground = 1,
    double contrast = bodyContrast,
  }) {
    final key = (ink.toARGB32(), ground, contrast);
    final cached = _shades[key];
    if (cached != null) return cached;
    final v = srgbOf(ground.clamp(0.0, 1.0));
    double contrastAt(double shade) {
      final g = v * (1 - shade);
      final under = Color.from(alpha: 1, red: g, green: g, blue: g);
      return wcagContrast(Color.alphaBlend(ink, under), under);
    }

    var shade = 0.0;
    if (contrastAt(0) < contrast) {
      var lo = 0.0;
      var hi = 1.0;
      for (var i = 0; i < 24; i++) {
        final mid = (lo + hi) / 2;
        if (contrastAt(mid) >= contrast) {
          hi = mid;
        } else {
          lo = mid;
        }
      }
      shade = hi;
    }
    if (_shades.length > 128) _shades.clear();
    return _shades[key] = shade;
  }

  static final Map<(int, double, double), double> _shades = {};

  /// The sRGB value of a grey of relative luminance [luminance].
  static double srgbOf(double luminance) => luminance <= 0.0031308
      ? luminance * 12.92
      : 1.055 * math.pow(luminance, 1 / 2.4) - 0.055;

  /// Smootherstep: no slope at either end, so the fade neither starts nor
  /// stops on an edge the eye can find.
  static double ease(double t) {
    final x = t.clamp(0.0, 1.0);
    return x * x * x * (x * (x * 6 - 15) + 10);
  }

  @override
  RenderMediaTextScrim createRenderObject(BuildContext context) =>
      RenderMediaTextScrim(
        ground: ground,
        textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMediaTextScrim renderObject,
  ) {
    renderObject
      ..ground = ground
      ..textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
  }
}

/// Leaves its child out of the words a [MediaTextScrim] answers to.
class MediaScrimSkip extends SingleChildRenderObjectWidget {
  const MediaScrimSkip({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderScrimSkip();
}

class _RenderScrimSkip extends RenderProxyBox {}

/// Marks its child as a glyph beside a [MediaTextScrim]'s words (a
/// caption's arrow): the shade holds it to non-text contrast, 3:1, however
/// it is drawn (a picture, an SVG). A [CustomPaint] glyph is found without
/// it.
class MediaScrimGlyph extends SingleChildRenderObjectWidget {
  const MediaScrimGlyph({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderScrimGlyph();
}

class _RenderScrimGlyph extends RenderProxyBox {}

/// One line of a [MediaTextScrim]'s words: where it is drawn (in the
/// scrim's own coordinates), the contrast it must keep, and the black that
/// needs under it over the scrim's ground.
typedef MediaScrimLine = ({Rect rect, double contrast, double need});

/// The gradient a [MediaTextScrim] lays, in the scrim's own coordinates.
///
/// [floor] black is held over an ellipse (centred on [centre], [hold] tall
/// and [aspect] times as wide) set over the words, from their middle down to
/// past the card's edge nearest them, so the corner they sit in ([anchor])
/// stays dark. From there it clears by an outer ellipse ([outerCentre],
/// [reach] tall, as wide in proportion): the two are one two-point conical
/// gradient, the outer one shifted toward the words' start so the shade
/// clears past their far end in points of its own, not in points stretched
/// by the ellipse's width. Between the two it eases away on [profile]: most
/// of it over the first stretch, a faint tail after.
@immutable
class MediaScrimShape {
  const MediaScrimShape({
    required this.anchor,
    required this.centre,
    required this.outerCentre,
    required this.aspect,
    required this.hold,
    required this.reach,
    required this.floor,
  });

  /// The corner of the card the words sit in; the shade keeps at least
  /// [cornerShare] of [floor] there.
  final Offset anchor;

  /// The centre of the ellipse over which [floor] holds.
  final Offset centre;

  /// The centre of the ellipse at which the shade is clear.
  final Offset outerCentre;

  /// Both ellipses' width to their height.
  final double aspect;

  /// The held ellipse's half height.
  final double hold;

  /// The clear ellipse's half height.
  final double reach;

  final double floor;

  /// The share of the fade the quick part takes, and its share of the black:
  /// the rest is a faint tail over the whole fade, so the shade has no edge
  /// the eye can find.
  static const double quickSpan = 0.6;
  static const double quickShare = 0.6;

  /// The least share of [floor] kept along the card's edge under the words,
  /// from the corner they sit in.
  static const double cornerShare = 0.8;

  /// The steepest the shade may fall, in black (alpha) per point: as soft
  /// as a Gaussian edge with a sigma of some 6 points, so the shade never
  /// shows an edge, a tip or a point of its own.
  static const double maxSlope = 0.04;

  /// Stops in the fade.
  static const int steps = 32;

  /// The share of [floor] left [t] of the way out (0 on the held ellipse,
  /// 1 on the clear one).
  static double profile(double t) =>
      quickShare * (1 - MediaTextScrim.ease(t / quickSpan)) +
      (1 - quickShare) * (1 - MediaTextScrim.ease(t));

  /// How far out [t] can lie and still keep [share] of [floor].
  static double reachFor(double share) {
    if (share >= 1) return 0;
    if (share <= 0) return 1;
    var lo = 0.0;
    var hi = 1.0;
    for (var i = 0; i < 32; i++) {
      final mid = (lo + hi) / 2;
      if (profile(mid) >= share) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Where the point ([x], [y], in the gradient's own space: the card's
  /// with x divided by the aspect) lies between the circles: at or under 0
  /// inside the first, 1 on the second, as the conical gradient draws it.
  static double conical(
    double x,
    double y, {
    required double startX,
    required double startY,
    required double startRadius,
    required double shift,
    required double grow,
  }) {
    final qx = x - startX;
    final qy = y - startY;
    final c = qx * qx + qy * qy - startRadius * startRadius;
    if (c <= 0) return -1;
    final a = shift * shift - grow * grow;
    final b = -2 * (shift * qx + startRadius * grow);
    if (a.abs() < 1e-9) return -c / b;
    final root = math.sqrt(math.max(0.0, b * b - 4 * a * c));
    return math.max((-b + root) / (2 * a), (-b - root) / (2 * a));
  }

  /// Where [point] lies between the ellipses ([conical]).
  double fadeAt(Offset point) => conical(
    point.dx / aspect,
    point.dy,
    startX: centre.dx / aspect,
    startY: centre.dy,
    startRadius: hold,
    shift: (outerCentre.dx - centre.dx) / aspect,
    grow: reach - hold,
  );

  /// The black at [point].
  double alphaAt(Offset point) {
    final t = fadeAt(point);
    if (t <= 0) return floor;
    if (t >= 1) return 0;
    return floor * profile(t);
  }

  /// The fastest [profile] falls anywhere, per unit of its fade.
  static final double steepestProfile = () {
    var steepest = 0.0;
    for (var i = 0; i <= 1000; i++) {
      steepest = math.max(steepest, profileSlope(i / 1000));
    }
    return steepest;
  }();

  /// How fast [profile] falls at [t], per unit of [t].
  static double profileSlope(double t) {
    double easeSlope(double x) {
      if (x <= 0 || x >= 1) return 0;
      return 30 * x * x * (x - 1) * (x - 1);
    }

    return quickShare * easeSlope(t / quickSpan) / quickSpan +
        (1 - quickShare) * easeSlope(t);
  }

  /// How fast the shade falls at [point], in black per point: [profile]'s
  /// slope times how fast the conical gradient moves across its circles
  /// there, both exact.
  double slopeAt(Offset point) {
    final t = fadeAt(point);
    if (t <= 0 || t >= 1) return 0;
    final shift = (outerCentre.dx - centre.dx) / aspect;
    final grow = reach - hold;
    // The point's offset from the circle it lies on, in the gradient's
    // space, and how that circle moves as t grows.
    final qx = point.dx / aspect - (centre.dx / aspect + t * shift);
    final qy = point.dy - centre.dy;
    final along = shift * qx + grow * (hold + t * grow);
    if (along <= 0) return double.infinity;
    // The gradient of t in the card's space (x scaled back by the aspect).
    final gx = qx / along / aspect;
    final gy = qy / along;
    return floor * profileSlope(t) * math.sqrt(gx * gx + gy * gy);
  }

  /// The steepest the shade falls anywhere on [face], in black per point,
  /// read on a grid [step] points apart.
  double steepestOn(Rect face, {double step = 2}) {
    final area = face.intersect(bounds);
    if (area.isEmpty) return 0;
    var steepest = 0.0;
    for (var y = area.top + step / 2; y < area.bottom; y += step) {
      for (var x = area.left + step / 2; x < area.right; x += step) {
        steepest = math.max(steepest, slopeAt(Offset(x, y)));
      }
    }
    return steepest;
  }

  /// Where the shade is not clear.
  Rect get bounds => Rect.fromCenter(
    center: outerCentre,
    width: 2 * reach * aspect,
    height: 2 * reach,
  );

  /// The gradient as a shader, for a scrim painted at [offset]: one conical
  /// gradient between the two circles, stretched to ellipses by its matrix.
  Shader shader(Offset offset) {
    final colors = <Color>[];
    final stops = <double>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      stops.add(t);
      colors.add(Color.fromRGBO(0, 0, 0, floor * profile(t)));
    }
    // The gradient's own space is the card's with x divided by the aspect:
    // the matrix (column-major) scales it back.
    final matrix = Float64List.fromList([
      aspect, 0, 0, 0, //
      0, 1, 0, 0, //
      0, 0, 1, 0, //
      0, 0, 0, 1, //
    ]);
    Offset inner(Offset p) =>
        Offset((p.dx + offset.dx) / aspect, p.dy + offset.dy);
    final start = inner(centre);
    final end = inner(outerCentre);
    if ((end - start).distance < 1e-3) {
      // Concentric: a plain radial gradient, its stops moved out past the
      // held circle.
      final held = hold / reach;
      return ui.Gradient.radial(
        end,
        reach,
        colors,
        [for (final t in stops) held + (1 - held) * t],
        TileMode.clamp,
        matrix,
      );
    }
    return ui.Gradient.radial(
      end,
      reach,
      colors,
      stops,
      TileMode.clamp,
      matrix,
      start,
      hold,
    );
  }
}

/// The render object of [MediaTextScrim]: the card's face, its words under
/// it, the shade painted first.
class RenderMediaTextScrim extends RenderProxyBox {
  RenderMediaTextScrim({required this._ground, required this._textDirection});

  double get ground => _ground;
  double _ground;
  set ground(double value) {
    if (value == _ground) return;
    _ground = value;
    markNeedsPaint();
  }

  /// The words' reading direction: they start, and the shade is anchored,
  /// on its start side.
  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsPaint();
  }

  /// Every line of type under it (and every painted glyph beside it, such
  /// as a caption's arrow), with the contrast it keeps and the black it
  /// needs over [ground].
  List<MediaScrimLine> lines() {
    final out = <MediaScrimLine>[];

    MediaScrimLine glyph(RenderBox node) => (
      rect: MatrixUtils.transformRect(
        node.getTransformTo(this),
        Offset.zero & node.size,
      ),
      contrast: MediaTextScrim.largeContrast,
      need: MediaTextScrim.shadeFor(
        kMediaOnInkQuiet,
        ground: ground,
        contrast: MediaTextScrim.largeContrast + MediaTextScrim.margin,
      ),
    );

    void visit(RenderObject node) {
      if (node is _RenderScrimSkip) return;
      if (node is _RenderScrimGlyph) {
        if (node.hasSize && !node.size.isEmpty) out.add(glyph(node));
        return;
      }
      if (node is RenderParagraph) {
        final plain = node.text.toPlainText();
        if (plain.trim().isNotEmpty) {
          var contrast = MediaTextScrim.largeContrast;
          final inks = <Color>{};
          void collect(
            InlineSpan span,
            Color? color,
            double size,
            FontWeight weight,
          ) {
            final style = span.style;
            // A span painted with a foreground paint carries its ink there.
            final ink = style?.color ?? style?.foreground?.color ?? color;
            final fontSize = style?.fontSize ?? size;
            final fontWeight = style?.fontWeight ?? weight;
            if (span is TextSpan &&
                (span.text?.trim().isNotEmpty ?? false) &&
                ink != null &&
                ink.a > 0) {
              inks.add(ink);
              contrast = math.max(
                contrast,
                MediaTextScrim.contrastFor(
                  fontSize: node.textScaler.scale(fontSize),
                  weight: fontWeight,
                ),
              );
            }
            span.visitDirectChildren((child) {
              collect(child, ink, fontSize, fontWeight);
              return true;
            });
          }

          collect(node.text, null, 14, FontWeight.w400);
          if (inks.isNotEmpty) {
            var need = 0.0;
            for (final ink in inks) {
              need = math.max(
                need,
                MediaTextScrim.shadeFor(
                  ink,
                  ground: ground,
                  contrast: contrast + MediaTextScrim.margin,
                ),
              );
            }
            final transform = node.getTransformTo(this);
            final bounds = Offset.zero & node.size;
            for (final box in node.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: plain.length),
            )) {
              final rect = box.toRect().intersect(bounds);
              if (rect.isEmpty) continue;
              out.add((
                rect: MatrixUtils.transformRect(transform, rect),
                contrast: contrast,
                need: need,
              ));
            }
          }
        }
      } else if (node is RenderCustomPaint &&
          (node.painter != null || node.foregroundPainter != null) &&
          node.hasSize &&
          !node.size.isEmpty) {
        // A painted glyph beside the words: non-text contrast, 3:1.
        out.add(glyph(node));
      }
      node.visitChildren(visit);
    }

    final root = child;
    if (root != null) visit(root);
    return out;
  }

  /// How long the shade takes to clear above the words, and past their far
  /// end, in heights of the block of words.
  static const double fadeBlocks = 1.4;
  static const double sideFadeBlocks = 1.0;

  /// How far along the words the card's edge under them keeps
  /// [MediaScrimShape.cornerShare] of the floor.
  static const double edgeReach = 1.0;

  /// Black past the words' far end (where a portrait or a flag's far field
  /// stands) costs this many times more than black above them.
  static const double farSideCost = 3;

  /// The widest an ellipse may be, to its height, and still end round on
  /// the card: a wider one is used only when its end falls past the card.
  static const double maxRoundAspect = 3;

  /// How many of the cheapest shapes are read for their slope before the
  /// gentlest of them is taken: a bound on the work. The cards as drawn
  /// find theirs within the first fifteen, small type within some fifty.
  static const int _slopeChecks = 64;

  /// The held ellipse's width to height; where its centre sits along the
  /// words (in shares of their length from their start); and how far in
  /// from the card's edge (in shares of the words' height over that edge;
  /// below 0 is past the edge), tried in turn.
  static const List<double> _aspects = [0.75, 1, 1.5, 2, 3, 4, 6, 8];
  static const List<double> _alongs = [0, 0.25, 0.5];
  static const List<double> _depths = [
    0.9,
    0.8,
    0.7,
    0.6,
    0.45,
    0.3,
    0,
    -0.5,
    -1,
  ];

  /// The gradient its words need; null when they need none (no words, or
  /// art dark enough already).
  ///
  /// Every line keeps its bar at its farthest corner, the card's edge under
  /// the words (from their corner, [edgeReach] of the way along them) keeps
  /// [MediaScrimShape.cornerShare] of the floor, and the shade never falls
  /// steeper than [MediaScrimShape.maxSlope]. Of the shapes that
  /// do, the one laying the least black away from the words wins: black
  /// under and before the lines (where the card runs on into its corner)
  /// costs nothing, the rest costs more the farther from the words it
  /// falls, and more again past their far end ([farSideCost]), so the
  /// picture's far side (a face, a flag's far field) and its top stay as
  /// they are.
  MediaScrimShape? shape() {
    if (!hasSize || size.isEmpty) return null;
    final words = lines();
    if (words.isEmpty) return null;
    var floor = 0.0;
    var ink = words.first.rect;
    for (final line in words) {
      floor = math.max(floor, line.need);
      ink = ink.expandToInclude(line.rect);
    }
    if (floor <= 0.002) return null;

    // The corner of the card the words sit in: on the side they start
    // from, at the edge (top or bottom) they sit nearer.
    final face = Offset.zero & size;
    final left = textDirection == TextDirection.ltr;
    final bottom = face.bottom - ink.bottom <= ink.top - face.top;
    final anchor = Offset(
      left ? face.left : face.right,
      bottom ? face.bottom : face.top,
    );

    // Work from that corner: u along the words from their start edge, v in
    // from the edge they sit at. The card's face is [0, w] by [0, h].
    final w = size.width;
    final h = size.height;
    Offset toFace(double u, double v) =>
        Offset(left ? u : face.right - u, bottom ? face.bottom - v : v);
    final boxes = <({double u0, double u1, double v0, double v1})>[];
    final shares = <double>[];
    var far = 0.0;
    var near = double.infinity;
    var end = 0.0;
    for (final line in words) {
      final r = line.rect;
      final box = (
        u0: left ? r.left : w - r.right,
        u1: left ? r.right : w - r.left,
        v0: bottom ? h - r.bottom : r.top,
        v1: bottom ? h - r.top : r.bottom,
      );
      boxes.add(box);
      shares.add(MediaScrimShape.reachFor(line.need / floor));
      far = math.max(far, box.v1);
      near = math.min(near, box.v0);
      end = math.max(end, box.u1);
    }
    final block = math.max(1.0, far - near);
    // Never so short that the fade alone would fall faster than
    // [MediaScrimShape.maxSlope] at this floor (small type makes a short
    // block): with room to spare for the ellipse's own curve.
    final shortest =
        1.15 *
        floor *
        MediaScrimShape.steepestProfile /
        MediaScrimShape.maxSlope;
    final fade = math.max(fadeBlocks * block, shortest);
    final sideFade = math.max(sideFadeBlocks * block, shortest);

    // The points that must keep their share: each line's corners, and the
    // card's edge under the words, from their corner to their end
    // ([edgeReach]), so the shade always meets that edge and never floats
    // over the card as a shape of its own.
    final edgeShare = MediaScrimShape.reachFor(MediaScrimShape.cornerShare);
    final points = <(double, double, double)>[
      (0, 0, edgeShare),
      (edgeReach * end, 0, edgeShare),
    ];
    for (var i = 0; i < boxes.length; i++) {
      final b = boxes[i];
      for (final u in [b.u0, b.u1]) {
        for (final v in [b.v0, b.v1]) {
          points.add((u, v, shares[i]));
        }
      }
    }

    // What black costs at each point of a coarse grid over the face:
    // nothing under and before a line, more the farther from the words,
    // more again past their far end.
    final step = math.max(4.0, block / 3);
    final samples = <(double, double, double)>[];
    for (var v = step / 2; v < h; v += step) {
      for (var u = step / 2; u < w; u += step) {
        var d = double.infinity;
        for (final b in boxes) {
          final du = math.max(0.0, u - b.u1);
          final dv = math.max(0.0, v - b.v1);
          d = math.min(d, math.sqrt(du * du + dv * dv));
        }
        final weight = math.min(d / block, 3.0) + 0.02;
        samples.add((u, v, u > end ? weight * farSideCost : weight));
      }
    }

    final ranked = <({double cost, MediaScrimShape shape})>[];
    for (final aspect in _aspects) {
      // The clear ellipse's shift toward the words' start, in the
      // gradient's space: past their far end the fade then runs [sideFade]
      // points, whatever the aspect.
      final shift = (sideFade / aspect - fade).clamp(-0.95 * fade, 0.95 * fade);
      for (final along in _alongs) {
        final uc = along * end;
        for (final depth in _depths) {
          final vc = depth * far;
          double t(double u, double v, double radius) =>
              MediaScrimShape.conical(
                u / aspect,
                v,
                startX: uc / aspect,
                startY: vc,
                startRadius: radius,
                shift: shift,
                grow: fade,
              );
          bool fits(double radius) {
            for (final (u, v, share) in points) {
              if (t(u, v, radius) > share + 1e-9) return false;
            }
            return true;
          }

          var lo = 0.0;
          var hi = math.max(1.0, far + h);
          while (!fits(hi) && hi < 1e5) {
            lo = hi;
            hi *= 2;
          }
          for (var i = 0; i < 20; i++) {
            final mid = (lo + hi) / 2;
            if (fits(mid)) {
              hi = mid;
            } else {
              lo = mid;
            }
          }
          // A long, flat ellipse ends in a point: only where that point
          // falls past the card's far edge, out of sight.
          if (aspect > maxRoundAspect && uc + aspect * hi < w) continue;
          var cost = 0.0;
          for (final (u, v, weight) in samples) {
            final at = t(u, v, hi);
            if (at >= 1) continue;
            cost += weight * (at <= 0 ? 1 : MediaScrimShape.profile(at));
          }
          ranked.add((
            cost: cost,
            shape: MediaScrimShape(
              anchor: anchor,
              centre: toFace(uc, vc),
              outerCentre: toFace(uc + shift * aspect, vc),
              aspect: aspect,
              hold: hi,
              reach: hi + fade,
              floor: floor,
            ),
          ));
        }
      }
    }
    if (ranked.isEmpty) return null;
    ranked.sort((a, b) => a.cost.compareTo(b.cost));
    // The cheapest that falls no steeper than [MediaScrimShape.maxSlope]
    // anywhere on the face (else the gentlest of the cheapest few).
    MediaScrimShape? gentlest;
    var gentlestSlope = double.infinity;
    for (final (cost: _, :shape) in ranked.take(_slopeChecks)) {
      final slope = shape.steepestOn(face);
      if (slope <= MediaScrimShape.maxSlope) return shape;
      if (slope < gentlestSlope) {
        gentlestSlope = slope;
        gentlest = shape;
      }
    }
    return gentlest;
  }

  /// [shape], kept between paints. A sibling's animation (the photo
  /// mosaic's drift) repaints the card every frame; the words have not
  /// changed, so neither has their shade. Any change under it (a line
  /// relaid, an ink or a transform changed) marks it for paint or layout,
  /// which drops the kept one.
  MediaScrimShape? _kept;
  bool _keptValid = false;

  @override
  void markNeedsPaint() {
    _keptValid = false;
    super.markNeedsPaint();
  }

  @override
  void performLayout() {
    _keptValid = false;
    super.performLayout();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_keptValid) {
      _kept = child == null ? null : shape();
      _keptValid = true;
    }
    final shade = _kept;
    if (shade != null) {
      final face = (offset & size).intersect(shade.bounds.shift(offset));
      if (!face.isEmpty) {
        context.canvas.drawRect(face, Paint()..shader = shade.shader(offset));
      }
    }
    super.paint(context, offset);
  }
}

/// A media card's portrait, its outer (left) edge fading into the card
/// ([mediaPortraitFade]). The fade is one offscreen pass (a save layer) the
/// size of the portrait; a child that needs a layer of its own (an image
/// still fading in) fades through a shader mask layer instead.
class MediaPortraitFade extends SingleChildRenderObjectWidget {
  const MediaPortraitFade({
    super.key,
    this.share = kMediaPortraitFade,
    super.child,
  });

  /// The share of its width the fade takes ([mediaPortraitFade]).
  final double share;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPortraitFade(share);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderPortraitFade).share = share;
  }
}

class _RenderPortraitFade extends RenderProxyBox {
  _RenderPortraitFade(this._share);

  double get share => _share;
  double _share;
  set share(double value) {
    if (value == _share) return;
    _share = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final rect = offset & size;
    if (child.needsCompositing) {
      final mask = (layer as ShaderMaskLayer? ?? ShaderMaskLayer())
        ..shader = mediaPortraitFade(
          share: share,
        ).createShader(Offset.zero & size)
        ..maskRect = rect
        ..blendMode = BlendMode.dstIn;
      layer = mask;
      context.pushLayer(mask, super.paint, offset);
      return;
    }
    layer = null;
    final shader = mediaPortraitFade(share: share).createShader(rect);
    final canvas = context.canvas;
    canvas.saveLayer(rect, Paint());
    context.paintChild(child, offset);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = shader
        ..blendMode = BlendMode.dstIn,
    );
    canvas.restore();
  }
}

/// A player's title (GM, IM...) on a media card: its colour's fill and the
/// label ink that reads on that fill at AA ([titleBadgeLegibleInk]: GM's
/// bright green takes the dark label), the same in both themes, as the card
/// is. Its own fill backs it, so the card's shade leaves it out
/// ([MediaScrimSkip]).
class MediaTitleBadge extends StatelessWidget {
  const MediaTitleBadge({super.key, required this.title, this.compact = false});

  final String title;

  /// A half-width card's smaller label.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fill = titleBadgeLegibleFill(getTitleBadgeColor(title));
    return MediaScrimSkip(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 5.sp, vertical: 2.sp),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(4.br),
        ),
        child: Text(
          title,
          style: AppTypography.textXsBold.copyWith(
            color: titleBadgeLegibleInk(fill),
            fontSize: compact ? 9.sp : 10.sp,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

/// A set of media cards settling into place as they arrive: they slide the
/// last few points down on a spring and are fully visible from their first
/// frame (nothing fades in from nothing). Still under reduced motion.
class MediaCardsEntrance extends StatelessWidget {
  const MediaCardsEntrance({super.key, required this.child});

  final Widget child;

  /// How far above their place the cards start.
  static double get rise => 8.sp;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return SingleMotionBuilder(
      from: -rise,
      value: 0,
      motion: const CupertinoMotion.smooth(),
      builder: (context, dy, child) => Transform.translate(
        // A spring only nears its rest; land exactly on it so the cards are
        // never resampled a fraction of a pixel off.
        offset: Offset(0, dy.abs() < 0.01 ? 0 : dy),
        child: child,
      ),
      child: child,
    );
  }
}

/// A player's name on a narrow media card, at the card's fixed size (never
/// shrunk). It steps down the app's name rule until one form fits the
/// card's width: the full name, then the first name's initial and the rest
/// ("M. Carlsen"), then the surname alone. Only a surname still wider than
/// the card fades at its end, clear a point before the edge so no sliver of
/// a cut letter is left standing. A screen reader always hears the full
/// name.
class MediaCardName extends StatelessWidget {
  const MediaCardName({super.key, required this.name, required this.style});

  final String name;
  final TextStyle style;

  /// The forms tried, longest first.
  static List<String> forms(String name) {
    final full = name.trim();
    final words = full
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (words.length < 2) return [full];
    return [
      full,
      '${words.first.characters.first}. ${words.skip(1).join(' ')}',
      words.last,
    ];
  }

  /// Where the end fade starts and ends, in logical points from the right.
  static const double fadeWidth = 24;
  static const double clearInset = 1;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        final candidates = forms(name);
        var pick = candidates.last;
        var fits = false;
        for (final form in candidates) {
          final painter = TextPainter(
            text: TextSpan(text: form, style: style),
            textDirection: direction,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          if (width <= box.maxWidth) {
            pick = form;
            fits = true;
            break;
          }
        }
        final text = Text(
          pick,
          style: style,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          semanticsLabel: name,
        );
        if (fits || !box.maxWidth.isFinite || box.maxWidth <= fadeWidth) {
          return text;
        }
        final w = box.maxWidth;
        return SizedBox(
          width: w,
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: _endFade(
              from: (w - fadeWidth) / w,
              to: (w - clearInset) / w,
            ).createShader,
            child: text,
          ),
        );
      },
    );
  }

  /// Opaque up to [from], clear from [to], smootherstep-eased over many
  /// stops between so the fade never shows where it starts.
  static LinearGradient _endFade({required double from, required double to}) {
    const steps = 16;
    final colors = <Color>[const Color(0xFF000000)];
    final stops = <double>[0];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final eased = t * t * t * (t * (t * 6 - 15) + 10);
      stops.add(from + (to - from) * t);
      colors.add(Color.fromRGBO(0, 0, 0, 1 - eased));
    }
    return LinearGradient(colors: colors, stops: stops);
  }
}

/// The share of a portrait's width, from its outer (left) edge, that fades
/// into the card: long, so a studio photo's white backdrop dissolves into
/// the flag with no line where it starts ([mediaPortraitFadeAt]).
const double kMediaPortraitFade = 0.38;

/// The portrait's opacity [t] of the way across its fade (0 at its outer
/// edge, 1 at [kMediaPortraitFade]): smootherstep, eased out once more
/// (`1 - (1 - s)^2`). It leaves the edge with no slope (no line where the
/// photo starts) and arrives with none, but most of its rise comes early:
/// three quarters opaque halfway across and past 97% by seven tenths, so a
/// face (on a head-and-shoulders photo it starts a fifth to three tenths of
/// the cropped width in) is solid and no flag stripe shows through it.
double mediaPortraitFadeAt(double t) {
  final x = t.clamp(0.0, 1.0);
  final s = x * x * x * (x * (x * 6 - 15) + 10);
  return 1 - (1 - s) * (1 - s);
}

/// A media card's portrait mask: clear at its left edge, rising smoothly
/// (many eased stops, [mediaPortraitFadeAt], so no band shows where it
/// starts) to opaque at [share] of its width, opaque from there to its
/// right edge.
LinearGradient mediaPortraitFade({double share = kMediaPortraitFade}) {
  const steps = 20;
  final colors = <Color>[];
  final stops = <double>[];
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    stops.add(share * t);
    colors.add(Color.fromRGBO(0, 0, 0, mediaPortraitFadeAt(t)));
  }
  return LinearGradient(
    colors: [...colors, const Color(0xFF000000)],
    stops: [...stops, 1],
  );
}

/// A player's photo on a media card: whole at the card's right edge (a touch
/// past it, top and bottom, so its own edges never show), its outer edge
/// fading into the flag ([MediaPortraitFade]). Nothing stands in while it
/// loads or when there is none: the flag fills the card. Set it as a child
/// of the card's stack, under the card's [MediaTextScrim]: the words may run
/// over its faded edge, carried by the shade there.
class MediaCardPortrait extends StatelessWidget {
  const MediaCardPortrait({super.key, required this.url, this.compact = false});

  final String url;

  /// A half-width card's tighter overhang.
  final bool compact;

  /// A head-and-shoulders photo keeps the face in its upper part.
  static const Alignment _focus = Alignment(0, -0.3);

  /// The portrait's width to its height.
  static const double aspect = 0.8;

  /// How far it reaches past the card's top and bottom edges.
  static double overhang({bool compact = false}) => compact ? 8.sp : 10.sp;

  /// How far it reaches past the card's right edge.
  static double bleed({bool compact = false}) => compact ? 15.sp : 20.sp;

  @override
  Widget build(BuildContext context) {
    final width = (200 * MediaQuery.devicePixelRatioOf(context)).toInt();
    final over = overhang(compact: compact);
    return Positioned(
      right: -bleed(compact: compact),
      top: -over,
      bottom: -over,
      child: AspectRatio(
        aspectRatio: aspect,
        child: MediaPortraitFade(
          // The photo starts a point inside its mask, where the mask is
          // clear: a mask on a fractional edge would otherwise leave the
          // photo's edge pixels standing as a hairline.
          child: Padding(
            padding: const EdgeInsets.only(left: 1),
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              alignment: _focus,
              filterQuality: FilterQuality.medium,
              memCacheWidth: width,
              placeholder: (_, _) => const SizedBox.shrink(),
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
