import 'package:chessever2/screens/feed/providers/board_feed_client.dart';
import 'package:flutter_test/flutter_test.dart';

BoardFeedPage page(Map<String, Object> fields) =>
    BoardFeedPage({'sessionId': 'session', 'pageId': 'page', ...fields});

void main() {
  test('mixed feed keeps the server order and grouped article count', () {
    expect(
      page({
        'gameIds': ['first', 'second'],
        'items': [
          {'type': 'board', 'id': 'first'},
          {'type': 'news', 'id': '42', 'articleCount': 3},
          {'type': 'unsupported', 'id': 'other'},
          {'type': 'board', 'id': 'second'},
        ],
      }).cards,
      [
        (id: 'first', articleCount: null, short: null, collection: null),
        (id: '42', articleCount: 3, short: null, collection: null),
        (id: 'second', articleCount: null, short: null, collection: null),
      ],
    );
  });

  test('validates Short URLs and preserves its place in the feed', () {
    final cards = page({
      'items': [
        {'type': 'board', 'id': 'first'},
        {
          'type': 'short',
          'id': 'ShortTest01',
          'title': 'Opening Short',
          'channelName': 'Chess channel',
          'thumbnailUrl': 'https://untrusted.example/short.jpg',
        },
        {'type': 'news', 'id': '42', 'articleCount': 2},
        {
          'type': 'short',
          'id': '../other',
          'title': 'Invalid',
          'channelName': 'Chess channel',
        },
      ],
    }).cards;
    expect(cards.map((card) => card.id), ['first', 'ShortTest01', '42']);
    expect(
      cards[1].short!.watchUrl.toString(),
      'https://www.youtube.com/shorts/ShortTest01',
    );
    expect(cards[1].short!.thumbnail, isNull);
  });

  test('collection cards preserve the exact saved game and move', () {
    final cards = page({
      'items': [
        {'type': 'board', 'id': 'first'},
        {
          'type': 'collection',
          'id': 'book-1',
          'slug': 'my-book',
          'title': 'Annotated games',
          'kind': 'book',
          'resume': {'gameId': 'game-2', 'moveIndex': 12},
        },
        {'type': 'news', 'id': '42', 'articleCount': 2},
      ],
    }).cards;
    expect(cards.map((card) => card.id), ['first', 'book-1', '42']);
    expect(cards[1].collection?.collection.slug, 'my-book');
    expect(cards[1].collection?.resume, (gameId: 'game-2', moveIndex: 12));
  });

  test(
    'keeps board-only compatibility but respects an empty mixed response',
    () {
      expect(
        page({
          'gameIds': ['first'],
        }).cards,
        [(id: 'first', articleCount: null, short: null, collection: null)],
      );
      expect(
        page({
          'gameIds': ['first'],
          'items': [],
        }).cards,
        isEmpty,
      );
    },
  );
}
