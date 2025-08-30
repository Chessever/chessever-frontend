import 'package:advanced_chess_board/models/enums.dart';

class TopMostVisibleItem {
  final TopMostItemType type;
  final String roundId;
  final int? gameIndex;
  final String? gameId;
  final double scrollOffset;
  final double? relativePosition;

  TopMostVisibleItem({
    required this.type,
    required this.roundId,
    this.gameIndex,
    this.gameId,
    required this.scrollOffset,
    this.relativePosition,
  });
}
