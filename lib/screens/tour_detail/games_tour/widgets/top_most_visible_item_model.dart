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

enum TopMostItemType { game, header }
