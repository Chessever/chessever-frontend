import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/feed/models/feed_collection.dart';
import 'package:chessever2/screens/feed/providers/board_feed_client.dart';
import 'package:chessever2/screens/feed/widgets/feed_collection_page.dart';
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:chessever2/screens/stories/story_pages.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'support/story_parity_harness.dart';

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
          {'type': 'ad', 'id': 'ad:page:8'},
          {'type': 'ad', 'id': 'bad-slot'},
          {'type': 'board', 'id': 'second'},
        ],
      }).cards,
      [
        (
          id: 'first',
          isAd: false,
          articleCount: null,
          short: null,
          collection: null,
        ),
        (id: '42', isAd: false, articleCount: 3, short: null, collection: null),
        (
          id: 'ad:page:8',
          isAd: true,
          articleCount: null,
          short: null,
          collection: null,
        ),
        (
          id: 'second',
          isAd: false,
          articleCount: null,
          short: null,
          collection: null,
        ),
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
          'featuredGameId': 'game-17',
          'resume': {'gameId': 'game-2', 'moveIndex': 12},
        },
        {'type': 'news', 'id': '42', 'articleCount': 2},
      ],
    }).cards;
    expect(cards.map((card) => card.id), ['first', 'book-1', '42']);
    expect(cards[1].collection?.collection.slug, 'my-book');
    expect(cards[1].collection?.featuredGameId, 'game-17');
    expect(cards[1].collection?.resume, (gameId: 'game-2', moveIndex: 12));
  });

  testWidgets('browse all collection games on one Feed card', (tester) async {
    final collection = Collection(
      id: 'collection',
      slug: 'collection',
      kind: CollectionKind.book,
      title: 'Twenty games',
      gameCount: 20,
      access: CollectionAccess.premium,
      contentLocked: true,
    );
    final server = _FeedCollectionServer(collection);
    final impressions = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectionsRepositoryProvider.overrideWithValue(server),
          boardSettingsProviderNew.overrideWith(DefaultBoard.new),
          premiumAccessProvider.overrideWithValue(false),
          storyAnalyzerProvider.overrideWithValue((_) async => {}),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: FeedCollectionPage(
                  card: FeedCollection(
                    collection,
                    null,
                    featuredGameId: 'game-17',
                  ),
                  active: true,
                  onGameVisible: impressions.add,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    String visibleGame() => tester
        .widget<StoryFrameView>(find.byType(StoryFrameView))
        .frame
        .game
        .id;
    expect(visibleGame(), 'game-17');
    for (var step = 1; step < 20; step++) {
      final number = (16 + step) % 20 + 1;
      await tester.tap(find.byTooltip('Next collection game'));
      await tester.pumpAndSettle();
      expect(visibleGame(), 'game-$number');
      expect(find.text('Game $number of 20'), findsOneWidget);
    }
    await tester.tap(find.byTooltip('Next collection game'));
    await tester.pumpAndSettle();
    expect(visibleGame(), 'game-17');
    await tester.tap(find.byTooltip('Previous collection game'));
    await tester.pumpAndSettle();
    expect(visibleGame(), 'game-16');
    expect(server.browseReads, 2);
    expect(server.playableReads, 0);
    expect(impressions.take(20), [
      for (var step = 0; step < 20; step++) 'game-${(16 + step) % 20 + 1}',
    ]);
    expect(find.text('Upgrade'), findsOneWidget);
  });

  test(
    'keeps board-only compatibility but respects an empty mixed response',
    () {
      expect(
        page({
          'gameIds': ['first'],
        }).cards,
        [
          (
            id: 'first',
            isAd: false,
            articleCount: null,
            short: null,
            collection: null,
          ),
        ],
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

class _FeedCollectionServer extends StoryServer {
  _FeedCollectionServer(Collection collection)
    : super(collection: collection, entitled: () => false);

  final cards = [
    for (var number = 1; number <= 20; number++)
      storyCard('game-$number', 'White $number', botvinnikPgn),
  ];
  int browseReads = 0;

  @override
  Future<List<CollectionGameCard>?> fetchStoryGames(
    String slug, {
    required String day,
  }) async => cards.take(1).toList();

  @override
  Future<List<CollectionGame>> fetchGames(String slug) async {
    browseReads++;
    return [for (final card in cards) CollectionGame.fromPreviewCard(card)!];
  }
}
