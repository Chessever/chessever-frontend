import 'package:chessever2/widgets/hub_illustration.dart';
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
  const HubSceneBackdrop({super.key, required this.scene});
  final HubScene scene;

  @override
  Widget build(BuildContext context) => HubIllustration(
    asset: switch (scene) {
      HubScene.miniatures => 'assets/pngs/hub_miniatures_icon.webp',
      HubScene.library => 'assets/pngs/hub_library_archive_v2.webp',
      HubScene.smartEvents => 'assets/pngs/hub_smart_events_icon.webp',
      HubScene.mostLiked => 'assets/pngs/hub_most_liked_icon.webp',
      HubScene.myPrep => 'assets/pngs/hub_my_prep_study_v2.webp',
      _ => 'assets/pngs/hub_${scene.name}_simple.webp',
    },
    framed: scene == HubScene.myPrep || scene == HubScene.library,
  );
}

class HubLibraryBackdrop extends StatelessWidget {
  const HubLibraryBackdrop({super.key});

  @override
  Widget build(BuildContext context) =>
      const HubSceneBackdrop(scene: HubScene.library);
}
