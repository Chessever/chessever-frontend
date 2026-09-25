import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_art.dart';
import 'package:flutter/material.dart';

// Full-tile artwork for the four hub tiles (My Likes, My Prep, Feed,
// Collection), the way Today's Favorites fills its tile with the followed
// players' photos and Countrymen with the flag. One recipe for all four so
// the pair on each page reads as one family: the section's own animated
// pixel object, large, filling the tile and running off its top and right
// edges, softened only where the label sits, under the tile's own ramp.

/// Softens [child] toward the tile's left edge, where the title and caption
/// sit: the picture still reaches across the whole tile (as Favorites'
/// photos do) but stays quiet behind the words and full from the middle on.
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
          Color(0x26000000),
          Color(0x59000000),
          Color(0xD9000000),
          Color(0xFF000000),
        ],
        stops: [0.0, 0.22, 0.42, 0.58],
      ).createShader(bounds),
      child: child,
    );
  }
}

/// One of My Space's pixel objects (the heart, the magnifier, the trophy,
/// the library) as a hub tile's full picture, with its shader running (the
/// glint, the pulsing blocks, the heart's embers, the magnifier's scan).
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
        // The whole object, as tall as the tile and across its right two
        // thirds, so it fills the card like Favorites' mosaic and still reads
        // as the heart, the magnifier, the trophy or the library. The same
        // box for all four tiles, so each pair matches.
        final box = Rect.fromLTRB(
          size.width * 0.34,
          size.height * 0.02,
          size.width * 1.02,
          size.height * 1.02,
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
