import 'package:chessever2/widgets/hub_illustration.dart';
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

/// A [HubScene]'s picture as a hub tile's full artwork: one drawing, made
/// for the dark media tile, which is the tile's design in both themes.
class HubSceneBackdrop extends StatelessWidget {
  const HubSceneBackdrop({super.key, required this.scene, this.shift = 0});
  final HubScene scene;

  /// How far right a study scene's picture sits of the card's edge.
  final double shift;

  /// [scene]'s drawing.
  static String asset(HubScene scene) => switch (scene) {
    HubScene.miniatures => 'assets/pngs/hub_miniatures_icon.webp',
    HubScene.library => 'assets/pngs/hub_library_icon.webp',
    HubScene.smartEvents => 'assets/pngs/hub_smart_events_icon.webp',
    HubScene.mostLiked => 'assets/pngs/hub_most_liked_icon.webp',
    HubScene.myPrep => 'assets/pngs/hub_my_prep_icon.webp',
    _ => 'assets/pngs/hub_${scene.name}_simple.webp',
  };

  /// The brightest [scene]'s drawing gets anywhere, as a relative luminance,
  /// measured from the drawing's own pixels (test/media_card_parts_test.dart
  /// holds each figure to the asset). The tile's label shade (the media
  /// card's `MediaTextScrim`) is only as strong as this ground needs: the
  /// Likes heart, dark red on black, needs none.
  static double brightest(HubScene scene) => switch (scene) {
    HubScene.feed => 0.59,
    HubScene.news => 0.59,
    HubScene.miniatures => 0.86,
    HubScene.reports => 0.67,
    HubScene.library => 0.58,
    HubScene.smartEvents => 0.82,
    HubScene.mostLiked => 0.11,
    HubScene.myPrep => 0.53,
    HubScene.collections => 0.66,
  };

  @override
  Widget build(BuildContext context) => HubIllustration(
    asset: asset(scene),
    framed: scene == HubScene.myPrep || scene == HubScene.library,
    shift: shift,
  );
}

class HubLibraryBackdrop extends StatelessWidget {
  const HubLibraryBackdrop({super.key});

  // The picture alone moves; its painted board floor still reaches the
  // card's left edge.
  @override
  Widget build(BuildContext context) =>
      HubSceneBackdrop(scene: HubScene.library, shift: 12.w);
}
