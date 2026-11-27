import 'package:chessever2/repository/gamebase/collections/collections_models.dart';

typedef CollectionCheckpoint = ({String gameId, int moveIndex});

CollectionCheckpoint? collectionCheckpointFromJson(Object? json) {
  if (json case {'gameId': final String id, 'moveIndex': final int moveIndex}) {
    if (id.isNotEmpty && moveIndex >= -1 && moveIndex <= 4095) {
      return (gameId: id, moveIndex: moveIndex);
    }
  }
  return null;
}

class FeedCollection {
  const FeedCollection(
    this.collection,
    this.resume, {
    this.featuredGameId,
    this.gameIndex,
    this.gameOrderSeed = 0,
    this.anchorGameId,
  });

  final Collection collection;
  final CollectionCheckpoint? resume;
  final String? featuredGameId;
  final int? gameIndex;
  final int gameOrderSeed;
  final String? anchorGameId;

  String get feedKey => gameIndex == null
      ? 'collection:${collection.id}'
      : 'collection-game:${collection.id}:$gameOrderSeed:$gameIndex';

  static FeedCollection? fromJson(Object? json) {
    if (json case {
      'type': 'collection',
      'id': final String id,
      'slug': final String slug,
      'title': final String title,
    }) {
      if (id.isEmpty || slug.isEmpty || title.trim().isEmpty) return null;
      final row = Map<String, dynamic>.from(json as Map);
      return FeedCollection(
        Collection.fromJson(row),
        collectionCheckpointFromJson(row['resume']),
        featuredGameId: _gameId(row['featuredGameId']),
        gameIndex: switch (row['gameIndex']) {
          final int index when index >= 0 => index,
          _ => null,
        },
        gameOrderSeed: switch (row['gameOrderSeed']) {
          final int seed when seed >= 0 => seed,
          _ => 0,
        },
        anchorGameId: _gameId(row['anchorGameId']),
      );
    }
    return null;
  }

  static String? _gameId(Object? value) =>
      value is String && RegExp(r'^[A-Za-z0-9_.:-]{1,128}$').hasMatch(value)
      ? value
      : null;
}
