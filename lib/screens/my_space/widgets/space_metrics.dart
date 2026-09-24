import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/utils/responsive_helper.dart';

/// My Space layout metrics. The spec is drawn at 390pt; every length goes
/// through `.w` (and only `.w`) so a tile keeps its proportions on any phone:
/// the boards inside the opening and game tiles must stay square.
class SpaceMetrics {
  SpaceMetrics._();

  /// Height of every rail and every tile in it.
  static double get railHeight => 209.w;

  /// Left/right gutter of the page and of each rail.
  static double get gutter => 16.w;

  /// Space between tiles in a rail.
  static double get gap => 12.w;

  /// Door and glyph/player tiles.
  static double get narrow => 120.w;

  /// Event, board and opening tiles.
  static double get wide => 171.w;

  /// Board inside a wide tile (the 10pt left inset is the eval-bar lane).
  static double get board => 161.w;

  /// Swipe distance at which a tile commits to removal.
  static const double removeThreshold = 90;
}

extension SpaceTileShape on SpaceShortcutKind {
  /// Wide tiles carry a board, an image or two lines of event copy.
  bool get isWideTile => switch (this) {
    SpaceShortcutKind.event ||
    SpaceShortcutKind.round ||
    SpaceShortcutKind.game ||
    SpaceShortcutKind.position ||
    SpaceShortcutKind.opening ||
    SpaceShortcutKind.playerOpenings => true,
    _ => false,
  };

  double get tileWidth => isWideTile ? SpaceMetrics.wide : SpaceMetrics.narrow;
}
