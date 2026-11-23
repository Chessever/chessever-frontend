import 'dart:math' as math;

import 'package:chessever2/widgets/hub_illustration.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

export 'hub_paired_hearts.dart' show HubLikesBackdrop;

/// Full-card contextual artwork, independent of game or network data.
enum HubScene {
  feed,
  news,
  miniatures,
  reports,
  library,
  smartEvents,
  mostLiked,
  myPrep,
  collections,
  events,
}

/// A [HubScene]'s picture as a hub tile's full artwork. Each scene has a
/// drawing for the dark media tile and its own drawing for the light paper
/// tile ([lightAsset]); the paper tile lays no wash over it.
class HubSceneBackdrop extends StatelessWidget implements HubPaperArtwork {
  const HubSceneBackdrop({super.key, required this.scene, this.shift = 0});
  final HubScene scene;

  /// How far right a study scene's picture sits of the card's edge.
  final double shift;

  /// [scene]'s drawing for the dark tile.
  static String darkAsset(HubScene scene) => switch (scene) {
    HubScene.miniatures => 'assets/pngs/hub_miniatures_icon.webp',
    HubScene.library => 'assets/pngs/hub_library_icon.webp',
    HubScene.smartEvents => 'assets/pngs/hub_smart_events_icon.webp',
    HubScene.mostLiked => 'assets/pngs/hub_most_liked_icon.webp',
    HubScene.myPrep => 'assets/pngs/hub_my_prep_icon.webp',
    _ => 'assets/pngs/hub_${scene.name}_simple.webp',
  };

  /// [scene]'s drawing for the light tile, beside its dark one with a
  /// `_light` suffix: same subject and seat, made for paper.
  static String lightAsset(HubScene scene) =>
      darkAsset(scene).replaceFirst(RegExp(r'\.webp$'), '_light.webp');

  @override
  Widget build(BuildContext context) => HubIllustration(
    asset: darkAsset(scene),
    lightAsset: lightAsset(scene),
    framed: scene == HubScene.myPrep || scene == HubScene.library,
    shift: shift,
  );
}

/// A [HubScene] on a tile that spans a whole [HubTileRow]. The picture keeps
/// a paired tile's width on the row's right, so its subject has the scale,
/// crop and seat of the right column above it at every width, and the row's
/// left stays calm for the label. Its left edge fades into the tile's own
/// ground, so no seam shows where the picture begins.
class HubRowSceneBackdrop extends StatelessWidget implements HubPaperArtwork {
  const HubRowSceneBackdrop({super.key, required this.scene});
  final HubScene scene;

  /// Eased from clear to full over the picture's first fifth: only its quiet
  /// field fades, never the subject.
  static Shader _leftFade(Rect bounds) => const LinearGradient(
    colors: [
      Colors.transparent,
      Color(0x10ffffff),
      Color(0x40ffffff),
      Color(0x80ffffff),
      Color(0xc0ffffff),
      Color(0xf0ffffff),
      Colors.white,
    ],
    stops: [0, .03, .07, .11, .15, .19, .22],
  ).createShader(bounds);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // The artwork box is the tile less its 1px border on each side, so a
      // paired tile's box is half the row less the gap, less its own border.
      final width = math.min(
        constraints.maxWidth,
        (constraints.maxWidth - HubTileRow.gap) / 2 - 1,
      );
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: width,
          height: constraints.maxHeight,
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: _leftFade,
            child: HubSceneBackdrop(scene: scene),
          ),
        ),
      );
    },
  );
}

class HubLibraryBackdrop extends StatelessWidget implements HubPaperArtwork {
  const HubLibraryBackdrop({super.key});

  // The picture alone moves: on paper its ground still reaches the card's
  // left edge.
  @override
  Widget build(BuildContext context) =>
      HubSceneBackdrop(scene: HubScene.library, shift: 12.w);
}
