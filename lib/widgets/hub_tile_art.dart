import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryMiniBoard;
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_art.dart';
import 'package:flutter/material.dart';

// Full-bleed artwork for the hub tiles (My Likes, My Prep, Feed,
// Collection), the way Today's Favorites fills its tile with the followed
// players' photos and Countrymen with the flag: the picture fills the tile
// from the right and dissolves before it reaches the label, and the tile's
// own ramp keeps the type on ink.

/// Fades [child] out toward the tile's left edge, so a full-bleed picture
/// never sits under the title and caption: transparent across the label's
/// side, fully drawn from a little past the middle.
class HubArtFade extends StatelessWidget {
  const HubArtFade({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0x00000000),
          Color(0x00000000),
          Color(0x8C000000),
          Color(0xFF000000),
        ],
        stops: [0.0, 0.30, 0.52, 0.70],
      ).createShader(bounds),
      child: child,
    );
  }
}

/// One of My Space's pixel objects (the heart, the trophy...) drawn large
/// across the tile's right side, running off its right edge, with its
/// embers still rising: the object is the tile's picture, not a badge.
class HubPixelBackdrop extends StatelessWidget {
  const HubPixelBackdrop({super.key, required this.section});

  final SpaceSection section;

  @override
  Widget build(BuildContext context) {
    final tone = PixelTone.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
        // Taller than the tile's inside and pushed past its right edge, so
        // the object reads as a picture that continues beyond the card.
        final box = Rect.fromLTRB(
          size.width * 0.44,
          size.height * 0.06,
          size.width * 1.12,
          size.height * 1.06,
        );
        return HubArtFade(
          child: PixelArtView(
            scene: PixelScene.backdrop(
              PixelArt.door(section, tone: tone),
              size,
              box,
            ),
          ),
        );
      },
    );
  }
}

/// A board, or several, in the viewer's own board theme as a hub tile's
/// picture: [HubBoardBackdrop] for one position (the game Feed opens on),
/// [HubBoardMosaic] for a set (the openings in My Prep).
class HubBoardBackdrop extends StatelessWidget {
  const HubBoardBackdrop({super.key, required this.fen, this.lastMove});

  final String fen;

  /// The move that reached [fen], as UCI, highlighted like the game cards.
  final String? lastMove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
        // A little taller than the tile, right-aligned, so the board runs
        // off the top, bottom and right edges and reads as a photograph of
        // the position rather than a thumbnail.
        final side = (size.height * 1.18).floorToDouble();
        return HubArtFade(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                right: -side * 0.12,
                top: (size.height - side) / 2,
                child: DiscoveryMiniBoard(
                  fen: fen,
                  size: side,
                  lastMove: lastMove,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Positions in a loose grid of small boards across the tile's right side,
/// the way Favorites lays out its players' photos: whole boards in two
/// rows, the last column running off the edge.
class HubBoardMosaic extends StatelessWidget {
  const HubBoardMosaic({super.key, required this.positions});

  /// FEN and, when known, the UCI move that reached it.
  final List<({String fen, String? lastMove})> positions;

  @override
  Widget build(BuildContext context) {
    if (positions.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
        const gap = 6.0;
        // Two rows that together overfill the height a little, so the grid
        // bleeds off the top and bottom as well as the right.
        final side = ((size.height + gap * 2) / 2).floorToDouble();
        final left = size.width * 0.40;
        final columns = ((size.width - left) / (side + gap)).ceil() + 1;
        final top = (size.height - (side * 2 + gap)) / 2;
        final children = <Widget>[];
        var i = 0;
        for (var row = 0; row < 2; row++) {
          // The second row steps half a board to the right, like a wall.
          final offset = row.isOdd ? (side + gap) / 2 : 0.0;
          for (var col = 0; col < columns; col++) {
            final p = positions[i % positions.length];
            i++;
            children.add(
              Positioned(
                left: left + offset + col * (side + gap),
                top: top + row * (side + gap),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: DiscoveryMiniBoard(
                    fen: p.fen,
                    size: side,
                    lastMove: p.lastMove,
                  ),
                ),
              ),
            );
          }
        }
        return HubArtFade(
          child: Stack(clipBehavior: Clip.hardEdge, children: children),
        );
      },
    );
  }
}

/// A photograph (a collection's cover) filling the tile, cropped to it and
/// faded toward the label; [fallback] while it loads or when it fails.
class HubPhotoBackdrop extends StatelessWidget {
  const HubPhotoBackdrop({
    super.key,
    required this.url,
    required this.fallback,
  });

  final String url;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final cacheWidth = (size.width * dpr).round();
        // Only the photo is faded here: the fallback fades itself.
        return CachedNetworkImage(
          imageUrl: url,
          memCacheWidth: cacheWidth,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholderFadeInDuration: Duration.zero,
          imageBuilder: (context, image) => HubArtFade(
            child: Image(
              image: ResizeImage.resizeIfNeeded(cacheWidth, null, image),
              width: size.width,
              height: size.height,
              fit: BoxFit.cover,
            ),
          ),
          placeholder: (_, __) => fallback,
          errorWidget: (_, __, ___) => fallback,
        );
      },
    );
  }
}
