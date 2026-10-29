import 'package:chessever2/screens/feed/news/news_cover.dart';
import 'package:flutter/material.dart';

/// The same cached picture in the grid, the flight and the reader. The mask
/// and corners change with the flight, instead of snapping to the header's
/// feather on its first frame. No second zoom or image fade competes with it.
class NewsHeroCover extends StatelessWidget {
  const NewsHeroCover({
    super.key,
    required this.tag,
    required this.imageUrl,
    this.radius = BorderRadius.zero,
    this.fadeTop = 0,
    this.fadeBottom = 0,
  });

  final Object tag;
  final String? imageUrl;
  final BorderRadius radius;
  final double fadeTop;
  final double fadeBottom;

  @override
  Widget build(BuildContext context) {
    final picture = _HeroPicture(
      imageUrl: imageUrl,
      pixelWidth:
          (MediaQuery.sizeOf(context).width *
                  MediaQuery.devicePixelRatioOf(context))
              .round()
              .clamp(100, 2500),
      radius: radius,
      fadeTop: fadeTop,
      fadeBottom: fadeBottom,
    );
    if (MediaQuery.disableAnimationsOf(context)) return picture;
    return Hero(
      tag: tag,
      transitionOnUserGestures: true,
      flightShuttleBuilder: (context, animation, direction, from, to) {
        final start = (from.widget as Hero).child as _HeroPicture;
        final end = (to.widget as Hero).child as _HeroPicture;
        final progress = direction == HeroFlightDirection.push
            ? animation
            : ReverseAnimation(animation);
        return AnimatedBuilder(
          animation: progress,
          builder: (context, _) {
            final t = progress.value;
            return _HeroPicture(
              imageUrl: start.imageUrl,
              pixelWidth: start.pixelWidth,
              radius: BorderRadius.lerp(start.radius, end.radius, t)!,
              fadeTop: start.fadeTop + (end.fadeTop - start.fadeTop) * t,
              fadeBottom:
                  start.fadeBottom + (end.fadeBottom - start.fadeBottom) * t,
            );
          },
        );
      },
      child: picture,
    );
  }
}

class _HeroPicture extends StatelessWidget {
  const _HeroPicture({
    required this.imageUrl,
    required this.pixelWidth,
    required this.radius,
    required this.fadeTop,
    required this.fadeBottom,
  });

  final String? imageUrl;
  final int pixelWidth;
  final BorderRadius radius;
  final double fadeTop;
  final double fadeBottom;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: radius,
    child: NewsCover(
      imageUrl: imageUrl,
      pixelWidth: pixelWidth,
      fadeTop: fadeTop,
      fadeBottom: fadeBottom,
      fadeInDuration: Duration.zero,
    ),
  );
}
