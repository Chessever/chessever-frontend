import 'package:chessever2/widgets/hub_illustration.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

export 'hub_paired_hearts.dart' show HubLikesBackdrop;

/// Full-card contextual artwork, independent of game or network data.
enum HubScene {
  feed,
  miniatures,
  reports,
  library,
  smartEvents,
  mostLiked,
  myPrep,
}

class HubSceneBackdrop extends StatelessWidget {
  const HubSceneBackdrop({super.key, required this.scene, this.shift = 0});
  final HubScene scene;

  /// How far right a study scene's picture sits of the card's edge.
  final double shift;

  @override
  Widget build(BuildContext context) => HubIllustration(
    asset: switch (scene) {
      HubScene.miniatures => 'assets/pngs/hub_miniatures_icon.webp',
      HubScene.library => 'assets/pngs/hub_library_icon.webp',
      HubScene.smartEvents => 'assets/pngs/hub_smart_events_icon.webp',
      HubScene.mostLiked => 'assets/pngs/hub_most_liked_icon.webp',
      HubScene.myPrep => 'assets/pngs/hub_my_prep_icon.webp',
      _ => 'assets/pngs/hub_${scene.name}_simple.webp',
    },
    framed: scene == HubScene.myPrep || scene == HubScene.library,
    shift: shift,
  );
}

class HubLibraryBackdrop extends StatelessWidget {
  const HubLibraryBackdrop({super.key});

  // The picture alone moves: on paper its field still reaches the card's
  // left edge.
  @override
  Widget build(BuildContext context) =>
      HubSceneBackdrop(scene: HubScene.library, shift: 12.w);
}
