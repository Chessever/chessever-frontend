import 'package:chessever2/repository/gamebase/collections/collections_models.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:chessever2/widgets/hub_tile_captions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

SavedAnalysis _like(
  String id,
  DateTime createdAt, {
  List<String> tags = const [],
}) {
  return SavedAnalysis(
    id: id,
    userId: 'user',
    title: id,
    chessGame: ChessGame.fromPgn(id, '1. e4 e5 *'),
    analysisState: const {},
    variationComments: const {},
    lastViewedPosition: -1,
    tags: tags,
    isFavorite: false,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

FeedItem _feed(String white, String black) {
  PlayerCard player(String name) => PlayerCard(
    name: name,
    federation: 'IND',
    title: 'GM',
    rating: 2700,
    countryCode: 'IN',
    team: null,
  );
  return FeedItem(
    game: GamesTourModel(
      gameId: 'g',
      whitePlayer: player(white),
      blackPlayer: player(black),
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.whiteWins,
      roundId: 'r',
      tourId: 't',
    ),
    plies: const [
      FeedPly(fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'),
    ],
    reason: 'Brilliant finish',
  );
}

Collection _collection(String id, CollectionKind kind) =>
    Collection(id: id, slug: id, kind: kind, title: id);

List<Collection> _shelf({int events = 0, int books = 0}) => [
  for (var i = 0; i < events; i++) _collection('e$i', CollectionKind.event),
  for (var i = 0; i < books; i++) _collection('b$i', CollectionKind.book),
];

void main() {
  group('likesSummary', () {
    final now = DateTime(2026, 9, 25, 15, 30);

    test('counts every like and the ones made on the local day', () {
      final summary = likesSummary(
        AsyncData([
          _like('a', DateTime(2026, 9, 25, 0, 1)),
          _like('b', DateTime(2026, 9, 25, 23, 59)),
          _like('c', DateTime(2026, 9, 24, 23, 59)),
          _like('d', DateTime(2025, 9, 25, 12)),
        ]),
        now: now,
      );
      expect(summary, const AsyncData<(int, int)>((4, 2)));
    });

    test('loading and failure pass through untouched', () {
      expect(
        likesSummary(const AsyncLoading<List<SavedAnalysis>>(), now: now),
        isA<AsyncLoading<(int, int)>>(),
      );
      final failed = likesSummary(
        AsyncError<List<SavedAnalysis>>(Exception('offline'), StackTrace.empty),
        now: now,
      );
      expect(failed.hasError, isTrue);
      expect(failed.valueOrNull, isNull);
    });

    test('a tag written on a like leaves the summary equal, so a '
        'select() does not rebuild the tile', () {
      final before = likesSummary(
        AsyncData([_like('a', now), _like('b', now)]),
        now: now,
      );
      final after = likesSummary(
        AsyncData([
          _like('a', now, tags: ['Endgame']),
          _like('b', now),
        ]),
        now: now,
      );
      expect(after, before);
    });

    test('works as the selector of a provider of likes', () {
      final likes = StateProvider<AsyncValue<List<SavedAnalysis>>>(
        (ref) => AsyncData([_like('a', DateTime.now())]),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // The tear-off itself, as the tile watches it.
      final summary = container.read(likes.select(likesSummary));
      expect(summary.valueOrNull?.$1, 1);
    });
  });

  group('hubLikesCaption', () {
    test('counts, with today only when there is one', () {
      expect(hubLikesCaption(const AsyncData((128, 2))), '128 games · 2 today');
      expect(hubLikesCaption(const AsyncData((128, 0))), '128 games');
      expect(hubLikesCaption(const AsyncData((1, 0))), '1 game');
      expect(hubLikesCaption(const AsyncData((1, 1))), '1 game · 1 today');
      expect(hubLikesCaption(const AsyncData((2, 1))), '2 games · 1 today');
    });

    test('a thousand or more reads grouped', () {
      expect(
        hubLikesCaption(const AsyncData((1284, 3))),
        '1,284 games · 3 today',
      );
    });

    test('no likes invites the first one', () {
      expect(
        hubLikesCaption(const AsyncData((0, 0))),
        'No likes yet',
      );
    });

    test('loading and failure keep the tile fallback', () {
      expect(hubLikesCaption(const AsyncLoading()), kHubTileCaption);
      expect(
        hubLikesCaption(AsyncError(Exception('offline'), StackTrace.empty)),
        kHubTileCaption,
      );
      expect(kHubTileCaption, 'Tap to view');
    });
  });

  group('hubPrepCaption', () {
    const master = AsyncData(9800000);

    test('a signed-in viewer with databases reads their count', () {
      expect(
        hubPrepCaption(guest: false, settled: true, databases: 3),
        '3 databases',
      );
      expect(
        hubPrepCaption(
          guest: false,
          settled: true,
          databases: 1,
          masterTotal: master,
        ),
        '1 database',
      );
    });

    test('no databases, or a guest, reads the master database', () {
      expect(
        hubPrepCaption(
          guest: false,
          settled: true,
          databases: 0,
          masterTotal: master,
        ),
        '9.8M master games',
      );
      expect(
        hubPrepCaption(
          guest: true,
          settled: true,
          databases: 4,
          masterTotal: master,
        ),
        '9.8M master games',
      );
      expect(
        hubPrepCaption(
          guest: true,
          settled: false,
          databases: 0,
          masterTotal: master,
        ),
        '9.8M master games',
      );
    });

    test('an unknown total, or folders still being read, say '
        '"Your databases"', () {
      for (final total in <AsyncValue<int>?>[
        null,
        const AsyncLoading<int>(),
        AsyncError<int>(Exception('offline'), StackTrace.empty),
        const AsyncData(0),
      ]) {
        expect(
          hubPrepCaption(
            guest: false,
            settled: true,
            databases: 0,
            masterTotal: total,
          ),
          'Your databases',
        );
        expect(
          hubPrepCaption(
            guest: true,
            settled: true,
            databases: 0,
            masterTotal: total,
          ),
          'Your databases',
        );
      }
      expect(
        hubPrepCaption(
          guest: false,
          settled: false,
          databases: 0,
          masterTotal: master,
        ),
        'Your databases',
      );
    });
  });

  group('hubFeedCaption', () {
    test('the players of the first game, by surname', () {
      expect(
        hubFeedCaption(_feed('Gukesh, D', 'Nakamura, Hikaru')),
        'Gukesh vs Nakamura',
      );
      expect(
        hubFeedCaption(_feed('Magnus Carlsen', 'Ding, Liren')),
        'Carlsen vs Ding',
      );
    });

    test('a trailing initial never stands for the name', () {
      expect(
        hubFeedCaption(_feed('Gukesh D', 'Praggnanandhaa R')),
        'Gukesh vs Praggnanandhaa',
      );
      expect(
        hubFeedCaption(_feed('Ramesh R.B.', 'Wesley So')),
        'Ramesh vs So',
      );
    });

    test('no cached first page, or a nameless side, falls back', () {
      expect(hubFeedCaption(null), 'Games and news');
      expect(hubFeedCaption(_feed('  ', 'Ding, Liren')), 'Games and news');
    });
  });

  group('hubCollectionsCaption', () {
    test('events and books, by kind and number', () {
      expect(
        hubCollectionsCaption(AsyncData(_shelf(events: 6, books: 2))),
        '6 events · 2 books',
      );
      expect(
        hubCollectionsCaption(AsyncData(_shelf(events: 1, books: 1))),
        '1 event · 1 book',
      );
      expect(
        hubCollectionsCaption(AsyncData(_shelf(events: 6))),
        '6 annotated events',
      );
      expect(
        hubCollectionsCaption(AsyncData(_shelf(events: 1))),
        '1 annotated event',
      );
      expect(hubCollectionsCaption(AsyncData(_shelf(books: 2))), '2 books');
      expect(hubCollectionsCaption(AsyncData(_shelf(books: 1))), '1 book');
    });

    test('an empty shelf says so', () {
      expect(
        hubCollectionsCaption(const AsyncData(<Collection>[])),
        'Nothing published yet',
      );
    });

    test('loading and failure keep the tile fallback', () {
      expect(
        hubCollectionsCaption(const AsyncLoading<List<Collection>>()),
        kHubTileCaption,
      );
      expect(
        hubCollectionsCaption(
          AsyncError<List<Collection>>(Exception('offline'), StackTrace.empty),
        ),
        kHubTileCaption,
      );
    });
  });
}
