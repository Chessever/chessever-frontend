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

class HubLibraryBackdrop extends StatelessWidget implements HubPaperArtwork {
  const HubLibraryBackdrop({super.key});

  // The picture alone moves: on paper its ground still reaches the card's
  // left edge.
  @override
  Widget build(BuildContext context) =>
      HubSceneBackdrop(scene: HubScene.library, shift: 12.w);
}
