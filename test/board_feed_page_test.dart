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

  testWidgets('collection games have separate vertical cards', (tester) async {
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
    final pages = PageController();
    addTearDown(pages.dispose);
    final cards = [
      FeedCollection(
        collection,
        (gameId: 'game-17', moveIndex: 2),
        gameIndex: 0,
        anchorGameId: 'game-17',
      ),
      FeedCollection(collection, null, gameIndex: 1, anchorGameId: 'game-17'),
    ];
    expect(cards[0].feedKey, isNot(cards[1].feedKey));

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
                body: PageView.builder(
                  controller: pages,
                  scrollDirection: Axis.vertical,
                  itemCount: cards.length,
                  itemBuilder: (context, index) => FeedCollectionPage(
                    key: ValueKey(cards[index].feedKey),
                    card: cards[index],
                    active: true,
                    onGameVisible: impressions.add,
                  ),
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
    expect(find.byTooltip('Next collection game'), findsNothing);
    expect(find.byTooltip('Previous collection game'), findsNothing);
    expect(find.text('Upgrade'), findsOneWidget);
    expect(find.text('View collection'), findsOneWidget);

    pages.jumpToPage(1);
    await tester.pumpAndSettle();
    expect(visibleGame(), 'game-1');
    expect(impressions, ['game-17', 'game-1']);
    expect(server.browseReads, 1);
    expect(server.playableReads, 0);
  });

  // A phone: the annotation's room runs from under the move down to the
  // card's two buttons, the part of the card a thumb reaches for.
  Future<PageController> pumpAnnotated(
    WidgetTester tester,
    String comment,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final collection = Collection(
      id: 'collection',
      slug: 'collection',
      kind: CollectionKind.book,
      title: 'Twenty games',
      gameCount: 20,
      access: CollectionAccess.premium,
      contentLocked: true,
    );
    final server = _FeedCollectionServer(collection)
      ..cards[0] = storyCard(
        'game-1',
        'White 1',
        '[Result "*"]\n\n1. e4 {$comment} e5 2. Nf3 Nc6 *',
      );
    final pages = PageController();
    addTearDown(pages.dispose);
    final cards = [
      for (var index = 0; index < 2; index++)
        FeedCollection(collection, null, gameIndex: index),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectionsRepositoryProvider.overrideWithValue(server),
          boardSettingsProviderNew.overrideWith(DefaultBoard.new),
          premiumAccessProvider.overrideWithValue(false),
          storyAnalyzerProvider.overrideWithValue(
            (jobs) async => analyzeStoryJobs(jobs),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: PageView.builder(
                  controller: pages,
                  scrollDirection: Axis.vertical,
                  itemCount: cards.length,
                  itemBuilder: (context, index) => FeedCollectionPage(
                    key: ValueKey(cards[index].feedKey),
                    card: cards[index],
                    active: true,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return pages;
  }

  // A slow drag, let go at rest: the page turns only when it was carried
  // past its middle, never on a fling.
  Future<void> swipeUp(WidgetTester tester, Offset from, double by) async {
    final gesture = await tester.startGesture(from);
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(Offset(0, -by / 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a swipe that starts on a collection card\'s annotation turns '
      'the Feed', (tester) async {
    final pages = await pumpAnnotated(tester, 'A quiet move.');
    final annotation = find.byKey(const ValueKey('story_annotation_scroll'));
    expect(find.text('A quiet move.'), findsOneWidget);
    // The words fit their room: there is nothing to scroll there.
    final room = tester.state<ScrollableState>(
      find.descendant(of: annotation, matching: find.byType(Scrollable)),
    );
    expect(room.position.maxScrollExtent, 0);

    // The lower right of the room, in the empty space under the words.
    final corner = tester.getBottomRight(annotation) - const Offset(24, 12);
    await swipeUp(tester, corner, 560);
    expect(pages.page, closeTo(1, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long annotation on a collection card scrolls first, then '
      'its end turns the Feed', (tester) async {
    final comment = List.filled(90, 'The pawn controls the centre.').join(' ');
    final pages = await pumpAnnotated(tester, comment);
    final annotation = find.byKey(const ValueKey('story_annotation_scroll'));
    final room = tester
        .state<ScrollableState>(
          find.descendant(of: annotation, matching: find.byType(Scrollable)),
        )
        .position;
    expect(room.maxScrollExtent, greaterThan(200));

    await swipeUp(tester, tester.getCenter(annotation), 120);
    expect(room.pixels, greaterThan(60));
    expect(pages.page, closeTo(0, 0.01));

    room.jumpTo(room.maxScrollExtent);
    await tester.pump();
    await swipeUp(tester, tester.getCenter(annotation), 560);
    expect(pages.page, closeTo(1, 0.01));
    expect(tester.takeException(), isNull);
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
