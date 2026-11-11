import 'dart:async';
import 'dart:convert';

import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/feed/news/news_group_card.dart';
import 'package:chessever2/screens/feed/news/news_group_repository.dart';
import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/screens/feed/news/news_reader_pager.dart';
import 'package:chessever2/screens/feed/news/news_reader_screen.dart';
import 'package:chessever2/screens/feed/news/news_related_articles.dart';
import 'package:chessever2/screens/feed/news/news_repository.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _row(int count) => {
  'id': 7,
  'title': 'Original story',
  'content': 'Original body',
  'published_at': '2026-11-11T12:00:00Z',
  'group_article_count': count,
};
FeedNews _article(int id) => FeedNews(
  id: id,
  title: 'Article $id',
  summary: '',
  content: 'Full body $id',
  publishedAt: DateTime.utc(2026, 11, 11),
);

class _Cache implements NewsCacheStore {
  @override
  Future<NewsCacheEntry?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

class _Groups extends NewsGroupRepository {
  int calls = 0;
  bool fail = false;
  final offsets = <int>[];
  @override
  Future<NewsGroupPage> load(int articleId, {int offset = 0}) async {
    calls++;
    offsets.add(offset);
    if (fail) throw StateError('offline');
    return NewsGroupPage([
      NewsGroupArticle(
        id: offset + 2,
        title: 'Sibling ${offset + 2}',
        publishedAt: DateTime.utc(2026, 11, 11),
      ),
    ], hasMore: offset == 0);
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Groups groups,
  Widget home, {
  Future<FeedNews?> Function(int)? loader,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        newsGroupRepositoryProvider.overrideWithValue(groups),
        newsArticleLoaderProvider.overrideWithValue(
          (link) async =>
              loader == null ? _article(link.id!) : loader(link.id!),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) {
          ResponsiveHelper.init(context);
          return child!;
        },
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('group counts normalize, cache, and participate in equality', () {
    final grouped = normalizeNewsRow(_row(17))!;
    final single = normalizeNewsRow(_row(1))!;
    expect(grouped.groupArticleCount, 17);
    expect(FeedNews.fromJson(grouped.toJson()), grouped);
    expect(grouped, isNot(single));
    final legacy = grouped.toJson()..remove('groupArticleCount');
    expect(FeedNews.fromJson(legacy)!.groupArticleCount, 1);
    expect(normalizeNewsRow(_row(0))!.groupArticleCount, 1);
  });

  test('count-only changes refresh bodies and cached model', () async {
    var count = 2;
    var fullReads = 0;
    final repo = FeedNewsRepository(
      cache: _Cache(),
      fetchRows: (_) async {
        fullReads++;
        return [_row(count)];
      },
      fetchStamps: (_) async => [_row(count)..remove('content')],
    );
    expect((await repo.refresh())!.items.single.groupArticleCount, 2);
    await repo.refresh();
    expect(fullReads, 1);
    count = 3;
    expect((await repo.refresh())!.items.single.groupArticleCount, 3);
    expect(fullReads, 2);
  });

  test(
    'member queries use published anchor, exact scope, exclusion and stable pagination',
    () async {
      final requests = <Uri>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'public-test-key',
        httpClient: MockClient((request) async {
          requests.add(request.url);
          if (request.url.queryParameters['select'] == 'group_day,group_key') {
            return http.Response(
              jsonEncode([
                {'group_day': '2026-11-11', 'group_key': 'tour:abc'},
              ]),
              200,
              request: request,
            );
          }
          return http.Response(
            jsonEncode([
              for (var i = 0; i < 21; i++)
                {
                  'id': 100 - i,
                  'title': 'Story $i',
                  'feed_published_at': '2026-11-11T12:00:00Z',
                },
            ]),
            200,
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final repo = NewsGroupRepository(client: client);
      final page = await repo.load(7);
      expect(page.items, hasLength(20));
      expect(page.hasMore, isTrue);
      expect(page.items.first.id, 100);
      expect(requests.first.path, '/rest/v1/news_group_articles');
      expect(requests.first.queryParameters['source'], 'eq.news');
      expect(requests.first.queryParameters['id'], 'eq.7');
      final query = requests[1].queryParameters;
      expect(query['source'], 'eq.news');
      expect(query['group_day'], 'eq.2026-11-11');
      expect(query['group_key'], 'eq.tour:abc');
      expect(query['id'], 'neq.7');
      expect(query['select'], 'id,title,feed_published_at');
      expect(
        query['order'],
        'feed_published_at.desc.nullslast,created_at.desc.nullslast,id.desc.nullslast',
      );
      expect(query['limit'], '21');
      await repo.load(7, offset: 20);
      expect(requests.last.queryParameters['offset'], '20');
    },
  );

  test(
    'missing anchors and singleton groups have no siblings; errors propagate',
    () async {
      var mode = 'missing';
      final client = SupabaseClient(
        'https://example.supabase.co',
        'public-test-key',
        httpClient: MockClient((request) async {
          if (mode == 'error') {
            return http.Response(
              '{"message":"offline"}',
              503,
              request: request,
            );
          }
          final anchor =
              request.url.queryParameters['select'] == 'group_day,group_key';
          return http.Response(
            jsonEncode(
              anchor && mode == 'singleton'
                  ? [
                      {'group_day': '2026-11-11', 'group_key': 'article:7'},
                    ]
                  : [],
            ),
            200,
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final repo = NewsGroupRepository(client: client);
      expect((await repo.load(7)).items, isEmpty);
      mode = 'singleton';
      expect((await repo.load(7)).hasMore, isFalse);
      mode = 'error';
      await expectLater(repo.load(7), throwsA(isA<PostgrestException>()));
    },
  );

  testWidgets(
    'related article opens alone; Back restores scroll and loaded siblings',
    (tester) async {
      final groups = _Groups();
      final original = FeedNews(
        id: 1,
        title: 'Original',
        summary: '',
        content: List.filled(45, 'Long original paragraph.').join('\n\n'),
        publishedAt: DateTime.utc(2026, 11, 11),
      );
      await _pump(tester, groups, NewsReaderScreen(news: original));
      await tester.scrollUntilVisible(
        find.text('Sibling 2'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final before = scroll.pixels;
      await tester.tap(find.text('Sibling 2'));
      await tester.pumpAndSettle();
      final reader = tester.widget<NewsReaderScreen>(
        find.byType(NewsReaderScreen),
      );
      expect(reader.news.id, 2);
      expect(reader.showRelatedArticles, isFalse);
      expect(reader.onNext, isNull);
      expect(reader.onPrevious, isNull);
      expect(find.byType(NewsReaderPager), findsNothing);
      expect(find.byType(NewsRelatedArticles), findsNothing);
      expect(find.text('Full body 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(scroll.pixels, before);
      expect(groups.calls, 1);
      await tester.ensureVisible(find.text('Show more'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();
      expect(groups.offsets, [0, 1]);
      await tester.ensureVisible(find.text('Sibling 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sibling 3'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NewsReaderScreen>(find.byType(NewsReaderScreen)).news.id,
        3,
      );
    },
  );

  testWidgets(
    'related loading and article failures allow retry without leaving reader',
    (tester) async {
      final groups = _Groups()..fail = true;
      var articleFails = true;
      await _pump(
        tester,
        groups,
        NewsReaderScreen(news: _article(1)),
        loader: (id) async => articleFails ? null : _article(id),
      );
      await tester.ensureVisible(
        find.text("Couldn't load related articles. Retry"),
      );
      groups.fail = false;
      await tester.tap(find.text("Couldn't load related articles. Retry"));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sibling 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sibling 2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text("Couldn't open article. Try again."), findsOneWidget);
      articleFails = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NewsReaderScreen>(find.byType(NewsReaderScreen)).news.id,
        2,
      );
    },
  );

  testWidgets('repeated sibling taps start only one load', (tester) async {
    final pending = Completer<FeedNews?>();
    var reads = 0;
    await _pump(
      tester,
      _Groups(),
      NewsReaderScreen(news: _article(1)),
      loader: (_) {
        reads++;
        return pending.future;
      },
    );
    await tester.ensureVisible(find.text('Sibling 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sibling 2'));
    await tester.tap(find.text('Sibling 2'));
    expect(reads, 1);
    pending.complete(_article(2));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NewsReaderScreen>(find.byType(NewsReaderScreen)).news.id,
      2,
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NewsReaderScreen>(find.byType(NewsReaderScreen)).news.id,
      1,
    );
  });

  testWidgets('group card shows count with bounded decoration in both themes', (
    tester,
  ) async {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SizedBox(
              width: 180,
              height: 280,
              child: NewsGroupCard(
                news: normalizeNewsRow(_row(17))!,
                child: const ColoredBox(color: Colors.grey),
              ),
            ),
          ),
        ),
      );
      expect(find.text('17 articles · Latest'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
