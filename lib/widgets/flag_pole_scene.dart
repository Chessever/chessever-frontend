import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chessever2/widgets/federation_flag.dart';
import 'package:country_flags/country_flags.dart' show FlagCode;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart' show rootBundle;
// The vector flags country_flags draws come in its own .si format; reading
// one directly is what lets the cloth be warped as a picture.
// ignore: depend_on_referenced_packages
import 'package:jovial_svg/jovial_svg.dart';

// Light theme, Countrymen: the reader's federation flag flying from a slim
// pole on a soft mound. The pole and the mound are a drawing
// ([kFlagPoleSceneAsset]) in the light hub style; the flag is the real flag,
// drawn here as cloth: warped along a slow travelling wave with quiet fold
// shading, at its true colours, crisp at every edge.

/// The light scene: a slim slate pole with a round finial on a pale mound,
/// on a transparent ground so it sits on any light surface. 768x512.
const String kFlagPoleSceneAsset = 'assets/pngs/hub_countrymen_light.webp';

/// One full wave across the cloth.
const Duration kFlagWavePeriod = Duration(milliseconds: 6200);

/// Where the pole sits in [kFlagPoleSceneAsset], as shares of its width and
/// height.
///
/// Measured once on the 1536x1024 master the asset was made from, by
/// scanning its rows and columns for the first pixels that are not the flat
/// ground (#EAF2F2): the finial ball spans x 500..543 and y 61..101, the
/// collar under it y 102..111, the shaft x 512..532 and y 112..821, its base
/// block y 822..839 on the mound's crest, and the mound runs from there to
/// the picture's foot.
abstract final class FlagPoleArt {
  /// Width over height of the picture.
  static const double aspect = 1.5;

  /// The shaft's centre line.
  static const double poleCentre = 522.5 / 1536;

  /// The finial ball's left edge: the leftmost point of the pole.
  static const double finialLeft = 500 / 1536;

  /// The top of the shaft, right under the collar: the cloth's top edge.
  static const double hoistTop = 112 / 1024;

  /// The top of the finial ball.
  static const double finialTop = 61 / 1024;

  /// Where the shaft meets its base block.
  static const double poleFoot = 822 / 1024;

  /// The foot of the base block, where the mound begins.
  static const double moundTop = 840 / 1024;
}

/// The country_flags artwork code for [federation] (an ISO2 or FIDE code, or
/// a country name): `tr`, `gb-sct`. Null when it names no country's flag.
String? flagClothCode(String? federation) {
  final raw = (federation ?? '').trim();
  switch (raw.toUpperCase()) {
    case 'ENG' || 'ENGLAND':
      return 'gb-eng';
    case 'SCO' || 'SCOTLAND':
      return 'gb-sct';
    case 'WLS' || 'WALES':
      return 'gb-wls';
  }
  final iso2 = FederationFlag.iso2Of(raw);
  return iso2 == null ? null : FlagCode.fromCountryCode(iso2);
}

/// The vector art of each flag a cloth flies, read once per session.
abstract final class FlagClothArt {
  static final Map<String, Future<ScalableImage?>> _reading = {};
  static final Map<String, ScalableImage?> _known = {};

  /// Whether [code]'s art has been read (it may have none).
  static bool isKnown(String code) => _known.containsKey(code);

  /// [code]'s art when it has been read; null otherwise or when it has none.
  static ScalableImage? known(String code) => _known[code];

  /// Reads [code]'s art; null when country_flags has none.
  static Future<ScalableImage?> read(String code) =>
      _reading.putIfAbsent(code, () async {
        try {
          final flag = await ScalableImage.fromSIAsset(
            rootBundle,
            'packages/country_flags/res/si/$code.si',
          );
          await flag.prepareImages();
          return _known[code] = flag;
        } catch (_) {
          return _known[code] = null;
        }
      });

  /// The cloth's width over its height for [art]: the flag's own
  /// proportions, within reason (Nepal's pennants and the square flags still
  /// read as cloth on a pole). A plain cloth is 3:2.
  static double aspectOf(ScalableImage? art) {
    final viewport = art?.viewport;
    if (viewport == null || viewport.isEmpty) return 1.5;
    return (viewport.width / viewport.height).clamp(1.0, 2.0);
  }
}

/// Where a [FlagPoleScene] puts its picture and its flag in a box.
@immutable
class FlagPoleLayout {
  /// The picture [height] tall with its bottom edge at [bottom], its pole's
  /// centre line at [poleX]. The flag hangs from the top of the shaft, [cloth]
  /// big at rest.
  factory FlagPoleLayout({
    required double poleX,
    required double bottom,
    required double height,
    required Size cloth,
  }) {
    final width = height * FlagPoleArt.aspect;
    final picture = Rect.fromLTWH(
      poleX - FlagPoleArt.poleCentre * width,
      bottom - height,
      width,
      height,
    );
    // The hoist wraps the right half of the shaft, so the cloth is attached
    // rather than parked beside it.
    final hoist = Offset(poleX, picture.top + FlagPoleArt.hoistTop * height);
    return FlagPoleLayout._(picture, hoist, cloth);
  }

  /// As [FlagPoleLayout.new], with the pole and its flag centred across a box
  /// [width] wide: the span from the finial's left edge to the cloth's fly
  /// edge at rest (the middle of its swing, [flyShare] of its width) has as
  /// much room on either side.
  factory FlagPoleLayout.centred({
    required double width,
    required double bottom,
    required double height,
    required Size cloth,
  }) {
    final reach = finialReach(height);
    return FlagPoleLayout(
      poleX: (width - cloth.width * flyShare + reach) / 2,
      bottom: bottom,
      height: height,
      cloth: cloth,
    );
  }

  const FlagPoleLayout._(this.picture, this.hoist, this.cloth);

  /// Where the cloth's fly edge rests, as a share of its width: the wave
  /// draws it in toward the pole by up to [_ClothPainter.drawIn] at the crest
  /// of a fold and lets it out to the full width between, so it swings about
  /// the middle of that.
  static const double flyShare = 1 - _ClothPainter.drawIn / 2;

  /// How far left of the pole's centre line its finial reaches, for a
  /// picture [height] tall.
  static double finialReach(double height) =>
      (FlagPoleArt.poleCentre - FlagPoleArt.finialLeft) *
      height *
      FlagPoleArt.aspect;

  /// The cloth at rest for [aspect] (width over height): as large as fits
  /// inside [max], in its own proportions.
  static Size fitCloth(Size max, double aspect) {
    final width = math.max(0.0, math.min(max.width, max.height * aspect));
    return Size(width, width / aspect);
  }

  /// Where the scene picture is drawn.
  final Rect picture;

  /// The cloth's top-left corner at rest.
  final Offset hoist;

  /// The cloth's size at rest.
  final Size cloth;

  /// The top of the finial.
  double get finialTop => picture.top + FlagPoleArt.finialTop * picture.height;

  /// The finial's left edge: where the pole and its flag begin.
  double get finialLeft => hoist.dx - finialReach(picture.height);

  /// The cloth's fly edge at rest: where the pole and its flag end.
  double get flyRight => hoist.dx + cloth.width * flyShare;

  @override
  bool operator ==(Object other) =>
      other is FlagPoleLayout &&
      other.picture == picture &&
      other.hoist == hoist &&
      other.cloth == cloth;

  @override
  int get hashCode => Object.hash(picture, hoist, cloth);
}

/// The flagpole scene with [flagCode]'s flag flying, laid out by [layout]
/// for the cloth's own proportions (width over height) in the box it fills.
/// A null [flagCode] flies a plain slate cloth.
///
/// The first time a flag is shown its art is read from the app bundle (a
/// local file, a frame or two); the scene is laid out once it is known, so
/// the pole never shifts when the flag arrives.
///
/// [footFade] eases the picture (the mound and the pole's foot, never the
/// flag) into the surface over that height, ending at [groundLine] (in the
/// box), below which nothing of it is drawn; by default at the picture's own
/// foot, for a scene that ends inside a card rather than at its edge.
class FlagPoleScene extends StatefulWidget {
  const FlagPoleScene({
    super.key,
    required this.flagCode,
    required this.layout,
    this.footFade = 0,
    this.groundLine,
  });

  final String? flagCode;
  final FlagPoleLayout Function(double clothAspect) layout;
  final double footFade;
  final double? groundLine;

  @override
  State<FlagPoleScene> createState() => _FlagPoleSceneState();
}

class _FlagPoleSceneState extends State<FlagPoleScene> {
  /// The flag's art is known (read, or there is none to read).
  bool _ready = false;
  ScalableImage? _art;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(FlagPoleScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flagCode != widget.flagCode) _resolve();
  }

  void _resolve() {
    final code = widget.flagCode;
    if (code == null) {
      _art = null;
      _ready = true;
      return;
    }
    if (FlagClothArt.isKnown(code)) {
      _art = FlagClothArt.known(code);
      _ready = true;
      return;
    }
    _ready = false;
    unawaited(
      FlagClothArt.read(code).then((art) {
        if (!mounted || widget.flagCode != code) return;
        setState(() {
          _art = art;
          _ready = true;
        });
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    final layout = widget.layout(FlagClothArt.aspectOf(_art));
    Widget picture = Image.asset(
      kFlagPoleSceneAsset,
      width: layout.picture.width,
      height: layout.picture.height,
      fit: BoxFit.fill,
      cacheWidth: 768,
      filterQuality: FilterQuality.medium,
    );
    final footFade = widget.footFade;
    if (footFade > 0) {
      final height = layout.picture.height;
      final ground = widget.groundLine ?? layout.picture.bottom;
      final end = ((ground - layout.picture.top) / height).clamp(0.0, 1.0);
      final start = ((ground - footFade - layout.picture.top) / height).clamp(
        0.0,
        end,
      );
      picture = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            for (var i = 0; i <= 12; i++)
              const Color(
                0xFF000000,
              ).withValues(alpha: 1 - _smootherstep(i / 12)),
          ],
          stops: [for (var i = 0; i <= 12; i++) start + (end - start) * i / 12],
        ).createShader(bounds),
        child: picture,
      );
    }
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(rect: layout.picture, child: picture),
            Positioned(
              left: layout.hoist.dx,
              top: layout.hoist.dy,
              width: layout.cloth.width,
              height: layout.cloth.height,
              child: RepaintBoundary(child: WavingFlag(art: _art)),
            ),
          ],
        ),
      ),
    );
  }
}

double _smootherstep(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * x * x * (x * (x * 6 - 15) + 10);
}

/// A flag ([art], from [FlagClothArt]) as waving cloth filling its box,
/// hoisted at the box's left edge. A null [art] flies a plain slate cloth.
///
/// The wave is paint-only: one ticker drives a painter, nothing rebuilds per
/// frame, and the ticker stops whenever [TickerMode] is off (an offstage
/// tab, a covered route).
class WavingFlag extends StatefulWidget {
  const WavingFlag({super.key, required this.art});

  final ScalableImage? art;

  /// Plain cloth: the scene's mid slate.
  static const Color plainCloth = Color(0xFF9FB3B3);

  @override
  State<WavingFlag> createState() => _WavingFlagState();
}

class _WavingFlagState extends State<WavingFlag>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: kFlagWavePeriod,
  );

  /// The flag rasterised at the size and pixel ratio it is drawn at.
  ui.Image? _raster;
  ScalableImage? _rasterArt;
  Size? _rasterSize;
  double? _rasterRatio;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _wave
        ..stop()
        ..value = 0.18;
    } else if (!_wave.isAnimating) {
      unawaited(_wave.repeat());
    }
  }

  @override
  void didUpdateWidget(WavingFlag oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.art != widget.art) _dropRaster();
  }

  void _dropRaster() {
    _raster?.dispose();
    _raster = null;
    _rasterArt = null;
    _rasterSize = null;
    _rasterRatio = null;
  }

  /// [flag] drawn into an image [size] logical pixels big at [ratio].
  ui.Image _rasterise(ScalableImage flag, Size size, double ratio) {
    if (_raster != null &&
        identical(_rasterArt, flag) &&
        _rasterSize == size &&
        _rasterRatio == ratio) {
      return _raster!;
    }
    _dropRaster();
    final width = math.max(1, (size.width * ratio).round());
    final height = math.max(1, (size.height * ratio).round());
    final viewport = flag.viewport;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(width / viewport.width, height / viewport.height);
    flag.paint(canvas);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    _raster = image;
    _rasterArt = flag;
    _rasterSize = size;
    _rasterRatio = ratio;
    return image;
  }

  @override
  void dispose() {
    _wave.dispose();
    _dropRaster();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flag = widget.art;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final cloth = box.biggest;
        if (!cloth.isFinite || cloth.isEmpty) return const SizedBox.shrink();
        return CustomPaint(
          size: cloth,
          painter: _ClothPainter(
            wave: _wave,
            cloth: cloth,
            image: flag == null ? null : _rasterise(flag, cloth, ratio),
          ),
        );
      },
    );
  }
}

/// Paints the cloth at the wave's current phase.
///
/// The cloth is a strip of columns from the hoist (fixed to the pole) to the
/// fly. Each column rides a sine wave travelling toward the fly, its swing
/// growing with its distance from the pole; the flag's picture is mapped onto
/// those columns as a mesh, and a quiet tone across the folds (darker where a
/// fold turns away, lighter where it faces up) gives the cloth its body. The
/// outline is clipped anti-aliased, so every edge stays crisp.
class _ClothPainter extends CustomPainter {
  _ClothPainter({required this.wave, required this.cloth, required this.image})
    : super(repaint: wave);

  final Animation<double> wave;
  final Size cloth;
  final ui.Image? image;

  static const int _columns = 28;

  /// Waves across the cloth.
  static const double _waves = 1.1;

  /// The fly's swing, as a share of the cloth's height.
  static const double _swing = 0.075;

  /// How far the fly draws in toward the pole at the crest of a fold, as a
  /// share of the cloth's width.
  static const double drawIn = 0.03;

  /// The strongest darkening and lightening across a fold.
  static const double _shadow = 0.16;
  static const double _light = 0.12;

  @override
  void paint(Canvas canvas, Size size) {
    final w = cloth.width;
    final h = cloth.height;
    if (w <= 0 || h <= 0) return;
    final phase = wave.value * 2 * math.pi;

    final xs = <double>[];
    final dys = <double>[];
    final tone = <Color>[];
    for (var i = 0; i <= _columns; i++) {
      final u = i / _columns;
      final reach = math.pow(u, 1.25).toDouble();
      final angle = 2 * math.pi * _waves * u - phase;
      xs.add(u * w - w * drawIn * reach * (1 + math.cos(angle)) / 2);
      dys.add(h * _swing * reach * math.sin(angle));
      // The fold's slope, -1..1: positive turns away from the light.
      final slope = (reach * math.cos(angle) + 0.15 * u).clamp(-1.0, 1.0);
      tone.add(
        slope >= 0
            ? const Color(0xFF000000).withValues(alpha: _shadow * slope)
            : const Color(0xFFFFFFFF).withValues(alpha: _light * -slope),
      );
    }

    final outline = Path()..moveTo(xs.first, dys.first);
    for (var i = 1; i <= _columns; i++) {
      outline.lineTo(xs[i], dys[i]);
    }
    for (var i = _columns; i >= 0; i--) {
      outline.lineTo(xs[i], dys[i] + h);
    }
    outline.close();

    canvas.save();
    canvas.clipPath(outline);

    final picture = image;
    final paint = Paint()..isAntiAlias = false;
    // The mesh reaches a pixel past the outline on every free edge, so the
    // anti-aliased clip, not the mesh, decides where the cloth ends.
    final positions = <Offset>[];
    final texture = <Offset>[];
    for (var i = 0; i <= _columns; i++) {
      final u = i / _columns;
      final x = xs[i] + (i == _columns ? 1 : 0);
      positions
        ..add(Offset(x, dys[i] - 1))
        ..add(Offset(x, dys[i] + h + 1));
      if (picture != null) {
        texture
          ..add(Offset(u * picture.width, 0))
          ..add(Offset(u * picture.width, picture.height.toDouble()));
      }
    }
    if (picture != null) {
      paint.shader = ImageShader(
        picture,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
        filterQuality: FilterQuality.medium,
      );
    } else {
      paint.color = WavingFlag.plainCloth;
    }
    canvas.drawVertices(
      ui.Vertices(
        VertexMode.triangleStrip,
        positions,
        textureCoordinates: picture == null ? null : texture,
      ),
      BlendMode.srcOver,
      paint,
    );

    // The folds' tone, as one gradient along the cloth: it varies only from
    // hoist to fly, so a gradient on the columns' own positions matches the
    // mesh exactly.
    final span = xs.last - xs.first;
    if (span > 0) {
      canvas.drawPath(
        outline,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(xs.first, 0),
            Offset(xs.last, 0),
            tone,
            [for (final x in xs) ((x - xs.first) / span).clamp(0.0, 1.0)],
          ),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ClothPainter old) =>
      old.cloth != cloth || old.image != image || old.wave != wave;
}
