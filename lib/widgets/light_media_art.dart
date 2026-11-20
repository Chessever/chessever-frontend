import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/text_scale.dart';
import 'package:flutter/widgets.dart';

// Light theme: data pictures on cards (a player's photo, a favourites strip,
// a federation's flag) are shown crisp, at their true colour and full
// strength, inside a region of their own. Nothing is laid over them and they
// are never dimmed. The only fades are short ones at a picture's own edge:
// where a moving strip enters and leaves, and down the left edge of a
// portrait as it meets the card's words. Each is a `BlendMode.dstIn` mask
// on the picture's own alpha, smootherstep-eased over many stops so it never
// shows a band where it starts.

/// Stops in every fade here.
const int kLightFadeSteps = 16;

/// The share of a portrait's width its left edge fades over (the rest of the
/// photo is opaque).
const double kPortraitFadeShare = 0.35;

/// The share of a moving strip's width each end fades over.
const double kStripFadeShare = 0.12;

/// Smootherstep: no slope at either end, so a fade neither starts nor stops
/// on an edge the eye can find.
double lightFadeEase(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * x * x * (x * (x * 6 - 15) + 10);
}

const Color _kOpaque = Color(0xFF000000);

/// Smoothstep: gentler through its middle than [lightFadeEase], for a fade
/// that should feel long (a portrait's edge against a dark backdrop).
double _smoothstep(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * x * (3 - 2 * x);
}

/// Alpha rising from clear at [from] to opaque at [to], eased, as colours and
/// stops for a gradient running 0..1.
({List<Color> colors, List<double> stops}) _rise(
  double from,
  double to, {
  double Function(double) ease = lightFadeEase,
}) {
  final colors = <Color>[];
  final stops = <double>[];
  for (var i = 0; i <= kLightFadeSteps; i++) {
    final t = i / kLightFadeSteps;
    stops.add(from + (to - from) * t);
    colors.add(_kOpaque.withValues(alpha: ease(t)));
  }
  return (colors: colors, stops: stops);
}

/// A portrait's mask: clear at its left edge, opaque from
/// [kPortraitFadeShare] of its width on.
LinearGradient portraitEdgeFade() {
  final rise = _rise(0, kPortraitFadeShare, ease: _smoothstep);
  return LinearGradient(
    colors: [...rise.colors, _kOpaque],
    stops: [...rise.stops, 1],
  );
}

/// A moving strip's mask: clear at both ends, opaque between the
/// [kStripFadeShare] at each end.
LinearGradient stripEdgeFade() {
  final rise = _rise(0, kStripFadeShare);
  return LinearGradient(
    colors: [...rise.colors, ...rise.colors.reversed],
    stops: [...rise.stops, ...rise.stops.reversed.map((s) => 1 - s)],
  );
}

/// [child] masked through its own alpha by [gradient] (one of the fades
/// above), so it shows at its true colour wherever it shows.
class LightEdgeFade extends StatelessWidget {
  const LightEdgeFade({super.key, required this.gradient, required this.child});

  final Gradient gradient;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: gradient.createShader,
      child: child,
    );
  }
}

/// Light theme: a player's photo on a full-width search card. It sits whole
/// at the card's right edge, as tall as the card, at full strength; only its
/// left edge fades into the card, over [kPortraitFadeShare] of its width.
///
/// The card's words keep to the left of [wordsClearance]: they never cross
/// the opaque part of the photo.
class LightCardPortrait {
  const LightCardPortrait._();

  /// The photo's width over its height.
  static const double aspect = 0.75;

  /// The photo's width on a card [height] tall.
  static double width(double height) => height * aspect;

  /// The part of the photo that is fully opaque, from the card's right edge.
  static double opaqueWidth(double height) =>
      width(height) * (1 - kPortraitFadeShare);

  /// How far from the card's right edge its words stop: halfway into the
  /// photo's fade, where the photo is still faint.
  static double wordsClearance(double height) =>
      width(height) * (1 - kPortraitFadeShare / 2);
}

/// The width a search card's photo is decoded at: the dark card's, so a
/// player's photo is one cache entry in both themes and on both card sizes.
int lightPhotoCacheWidth(BuildContext context) =>
    (200 * MediaQuery.devicePixelRatioOf(context)).toInt();

/// Loads the photo at [url] and builds [builder] with it once it is on hand:
/// covering its box (anchored by [alignment]), at full strength. [builder]
/// gets null while the photo loads, when it fails and when there is no
/// [url], so a card makes room for a photo only once there is one to show:
/// a card without a photo never cuts its words for one, and never moves them
/// when it turns out to have none.
///
/// A photo already decoded is there on the first frame; one that arrives
/// later fades in briefly.
class LightPhotoLoader extends StatefulWidget {
  const LightPhotoLoader({
    super.key,
    required this.url,
    required this.builder,
    this.alignment = Alignment.center,
  });

  final String? url;
  final Alignment alignment;
  final Widget Function(BuildContext context, Widget? photo) builder;

  @override
  State<LightPhotoLoader> createState() => _LightPhotoLoaderState();
}

class _LightPhotoLoaderState extends State<LightPhotoLoader> {
  ImageStream? _stream;
  ImageInfo? _photo;

  /// The photo arrived after the card was first drawn.
  bool _late = false;

  late final ImageStreamListener _listener = ImageStreamListener(
    _onPhoto,
    onError: _onError,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(LightPhotoLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _resolve();
  }

  void _resolve() {
    final url = widget.url;
    final stream = url == null
        ? null
        : ResizeImage.resizeIfNeeded(
            lightPhotoCacheWidth(context),
            null,
            CachedNetworkImageProvider(url),
          ).resolve(createLocalImageConfiguration(context));
    if (stream != null && stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _replace(null);
    _late = false;
    _stream = stream;
    stream?.addListener(_listener);
  }

  void _onPhoto(ImageInfo photo, bool synchronousCall) {
    setState(() {
      _replace(photo);
      _late = !synchronousCall;
    });
  }

  void _onError(Object error, StackTrace? stack) {
    if (_photo == null) return;
    setState(() => _replace(null));
  }

  void _replace(ImageInfo? photo) {
    _photo?.dispose();
    _photo = photo;
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _replace(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    if (photo == null) return widget.builder(context, null);
    Widget image = RawImage(
      image: photo.image,
      scale: photo.scale,
      fit: BoxFit.cover,
      alignment: widget.alignment,
      filterQuality: FilterQuality.medium,
    );
    if (_late) {
      image = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 180),
        builder: (context, shown, child) =>
            Opacity(opacity: shown, child: child),
        child: image,
      );
    }
    return widget.builder(context, image);
  }
}

/// Light theme: a full-width search card [height] tall, with the photo at
/// [url] as its portrait ([LightCardPortrait]) and its [words] over the rest.
/// [words] is told whether the photo is on the card, so the words keep clear
/// of it only while it is.
class LightPortraitCard extends StatelessWidget {
  const LightPortraitCard({
    super.key,
    required this.url,
    required this.height,
    required this.words,
  });

  final String? url;
  final double height;
  final Widget Function(BuildContext context, bool photo) words;

  @override
  Widget build(BuildContext context) {
    return LightPhotoLoader(
      url: url,
      builder: (context, photo) => Stack(
        fit: StackFit.expand,
        children: [
          if (photo != null)
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: LightCardPortrait.width(height),
              child: LightEdgeFade(gradient: portraitEdgeFade(), child: photo),
            ),
          words(context, photo != null),
        ],
      ),
    );
  }
}

/// Light theme: the photo at [url] as a half-width search card's avatar, a
/// circle filling its box at full strength with its own edge deepened a
/// touch into a fine rim (as the Favorites photos are). It stands above the
/// card's name, so the name keeps the card's whole width. Nothing shows
/// until the photo is on hand, and nothing when there is none.
class LightAvatarPhoto extends StatelessWidget {
  const LightAvatarPhoto({super.key, required this.url});

  final String url;

  /// The most the avatar stands: the Favorites photos' size, grown with the
  /// text. Where the card has less room above the name it takes that room,
  /// its top then as far from the card's edge as its side.
  static double side(BuildContext context) => 36.sp * context.textGrowth;

  @override
  Widget build(BuildContext context) {
    return LightPhotoLoader(
      url: url,
      // A head-and-shoulders photo keeps the face in its upper part.
      alignment: const Alignment(0, -0.3),
      builder: (context, photo) => photo == null
          ? const SizedBox.expand()
          : DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x24000000), width: 1),
              ),
              child: ClipOval(child: SizedBox.expand(child: photo)),
            ),
    );
  }
}

/// Light theme: a player's name on a half-width card, at the card's fixed
/// size (never shrunk). The name steps down the app's name rule until one
/// form fits: the full name, then the first name's initial and the rest
/// ("M. Carlsen"), then the surname alone. Only a surname still wider than
/// the card fades at its end, clear a point before the edge so no sliver of
/// a cut letter is left standing. A screen reader always hears the full
/// name.
class LightCardName extends StatelessWidget {
  const LightCardName({super.key, required this.name, required this.style});

  final String name;
  final TextStyle style;

  /// The forms tried, longest first.
  static List<String> forms(String name) {
    final full = name.trim();
    final parts = full.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final words = parts.toList();
    if (words.length < 2) return [full];
    return [
      full,
      '${words.first.characters.first}. ${words.skip(1).join(' ')}',
      words.last,
    ];
  }

  /// Where the end fade starts and ends, in logical pixels from the right.
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
        final rise = _rise((w - clearInset) / w, (w - fadeWidth) / w);
        return SizedBox(
          width: w,
          child: LightEdgeFade(
            gradient: LinearGradient(
              colors: [_kOpaque, ...rise.colors.reversed],
              stops: [0, ...rise.stops.reversed],
            ),
            child: text,
          ),
        );
      },
    );
  }
}
