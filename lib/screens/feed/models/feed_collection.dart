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
  const FeedCollection(this.collection, this.resume, {this.featuredGameId});

  final Collection collection;
  final CollectionCheckpoint? resume;
  final String? featuredGameId;

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
        featuredGameId: switch (row['featuredGameId']) {
          final String id
              when RegExp(r'^[A-Za-z0-9_.:-]{1,128}$').hasMatch(id) =>
            id,
          _ => null,
        },
      );
    }
    return null;
  }
}
