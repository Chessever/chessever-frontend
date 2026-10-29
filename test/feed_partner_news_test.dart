import 'package:chessever2/screens/feed/models/feed_entry.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/screens/feed/news/news_reader_screen.dart';
import 'package:chessever2/screens/feed/news/news_repository.dart';
import 'package:chessever2/screens/feed/news/news_rich_blocks.dart';
import 'package:chessever2/screens/feed/providers/feed_entries_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// RookReview articles in the Feed: rows from `partner_news` (filled by the
// partner-news-sync Edge Function), merged with ChessEver's own news under
// RookReview's name and mark.

/// What partner-news-sync stores for RookReview's Sindarov piece: the
/// summary is the first paragraph, with straight quotes where the body has
/// curly ones.
const String _quoteBody =
    'Timur Turlov shared his opinion on the FIDE World Championship 2026. '
    'Timur notes Sindarov’s success at the Candidates.\n\n'
    '> “I think the match will be really interesting.\n'
    '>\n'
    '> Yes, he is the favorite right now.”\n'
    '>\n'
    '> *Timur Turlov — Kazakh businessman*\n\n'
    'Sindarov [won](https://rookreview.com/news/sindarov-wins-candidates) the '
    'Candidates\\. Prize: \$400\\.\n\n'
    '| Place | Player |\n| --- | --- |\n| 1\\. | Sindarov |\n\n'
    'Credit: FIDE';

Map<String, dynamic> _partnerRow({
  Object? id = 7,
  Object? sourceId = 'rookreview',
  Object? url = 'https://rookreview.com/news/sindarov-is-the-favorite',
  Object? title = '"Sindarov is the favorite right now" — Timur Turlov',
  Object? summary =
      'Timur Turlov shared his opinion on the FIDE World Championship 2026. '
      "Timur notes Sindarov's success at the Candidates.",
  Object? content = _quoteBody,
  Object? imageUrl = 'https://rookreview.b-cdn.net/Turlov/turlov.jpeg',
  Object? publishedAt = '2026-10-23T19:53:00Z',
  Object? updatedAt = '2026-10-23T19:55:00Z',
}) => {
  'id': id,
  'source_id': sourceId,
  'url': url,
  'title': title,
  'summary': summary,
  'content': content,
  'image_url': imageUrl,
  'published_at': publishedAt,
  'updated_at': updatedAt,
};

Map<String, dynamic> _ownRow({
  int id = 7,
  String title = 'Carlsen wins Norway Chess 2026',
  String publishedAt = '2026-10-23T20:00:00Z',
}) => {
  'id': id,
  'title': title,
  'summary': 'A clean sweep in Stavanger.',
  'content': 'Magnus Carlsen won again.',
  'source_url': null,
  'image_url': null,
  'status': 'published',
  'published_at': publishedAt,
  'created_at': publishedAt,
  'updated_at': publishedAt,
};

FeedNews _partner([Map<String, dynamic>? row]) =>
    normalizePartnerNewsRow(row ?? _partnerRow())!;

FeedNews _own({int id = 7, String publishedAt = '2026-10-23T20:00:00Z'}) =>
    normalizeNewsRow(_ownRow(id: id, publishedAt: publishedAt))!;

class _Fetcher {
  _Fetcher(this.rows);

  List<Map<String, dynamic>> rows;
  Object? error;
  int calls = 0;

  Future<List<Map<String, dynamic>>> call(int limit) async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return rows;
  }
}

class _MemoryCache implements NewsCacheStore {
  NewsCacheEntry? entry;

  @override
  Future<NewsCacheEntry?> read(String key) async => entry;

  @override
  Future<void> write(String key, String value) async {
    entry = (value: value, storedAt: DateTime.now());
  }
}

void main() {
  group('normalizePartnerNewsRow', () {
    test('a RookReview row is a RookReview article', () {
      final news = _partner();
      expect(news.publisher, NewsPublisher.rookReview);
      expect(news.id, 7);
      expect(news.key, 'rookreview:7');
      expect(
        news.webUrl,
        'https://rookreview.com/news/sindarov-is-the-favorite',
      );
      expect(news.imageUrl, 'https://rookreview.b-cdn.net/Turlov/turlov.jpeg');
      expect(news.sourceUrl, isNull);
      expect(news.publishedAt, DateTime.utc(2026, 10, 23, 19, 53));
      expect(news.updatedAt, DateTime.utc(2026, 10, 23, 19, 55));
      expect(news.content, contains('| Place | Player |\n| --- | --- |'));
    });

    test('drops rows this build cannot credit or show', () {
      expect(normalizePartnerNewsRow(_partnerRow(sourceId: 'unknown')), isNull);
      expect(normalizePartnerNewsRow(_partnerRow(sourceId: null)), isNull);
      for (final url in [
        'https://evil.example/news/a',
        'https://rookreview.com.evil.example/a',
        'http://rookreview.com/news/a',
        'javascript:alert(1)',
        null,
      ]) {
        expect(
          normalizePartnerNewsRow(_partnerRow(url: url)),
          isNull,
          reason: '$url',
        );
      }
      expect(normalizePartnerNewsRow(_partnerRow(title: ' ')), isNull);
      expect(normalizePartnerNewsRow(_partnerRow(content: '')), isNull);
      expect(normalizePartnerNewsRow(_partnerRow(publishedAt: null)), isNull);
      expect(normalizePartnerNewsRow(_partnerRow(id: 0)), isNull);
      expect(
        normalizePartnerNewsRow(
          _partnerRow(url: 'https://www.rookreview.com/news/a'),
        ),
        isNotNull,
      );
    });

    test('a cover off the partner\'s hosts is dropped, the article kept', () {
      final news = normalizePartnerNewsRow(
        _partnerRow(imageUrl: 'https://tracker.example/pixel.gif'),
      )!;
      expect(news.imageUrl, isNull);
      expect(_partner(_partnerRow(imageUrl: null)).imageUrl, isNull);
    });
  });

  group('cache', () {
    test('keeps the publisher; older entries are ChessEver\'s', () {
      final items = [_own(), _partner()];
      final decoded = decodeFeedNewsCache(encodeFeedNewsCache(items))!;
      expect(decoded, items);
      expect(decoded[1].publisher, NewsPublisher.rookReview);

      final legacy = _own().toJson()..remove('publisher');
      expect(FeedNews.fromJson(legacy)!.publisher, NewsPublisher.chessever);
      final unknown = _partner().toJson()..['publisher'] = 'gone';
      expect(FeedNews.fromJson(unknown), isNull);
    });
  });

  group('merge and keys', () {
    test('newest first across publishers; ChessEver leads on a tie', () {
      final early = _own(id: 1, publishedAt: '2026-10-22T10:00:00Z');
      final tie = _own(id: 2, publishedAt: '2026-10-23T19:53:00Z');
      final partner = _partner();
      final latest = _partner(
        _partnerRow(
          id: 9,
          url: 'https://rookreview.com/news/b',
          publishedAt: '2026-10-24T10:00:00Z',
        ),
      );
      expect(mergeFeedNews([tie, early], [latest, partner]).map((n) => n.key), [
        'rookreview:9',
        '2',
        'rookreview:7',
        '1',
      ]);
    });

    test('ChessEver 7 and RookReview 7 are two articles', () {
      final own = _own();
      final partner = _partner();
      expect(own.key, '7');
      expect(partner.key, 'rookreview:7');
      expect(FeedNewsEntry(own).key, 'news:7');
      expect(FeedNewsEntry(partner).key, 'news:rookreview:7');

      expect(
        feedNewsUnseenFirst([own, partner], const {'7'}).map((n) => n.key),
        ['rookreview:7', '7'],
      );
    });
  });

  group('plain text', () {
    test('quotes unwrap into paragraphs; markup, tables and links go', () {
      expect(newsPlainParagraphs(_quoteBody), [
        'Timur Turlov shared his opinion on the FIDE World Championship 2026. '
            'Timur notes Sindarov’s success at the Candidates.',
        '“I think the match will be really interesting.',
        'Yes, he is the favorite right now.”',
        'Timur Turlov — Kazakh businessman',
        r'Sindarov won the Candidates. Prize: $400.',
        'Credit: FIDE',
      ]);
      expect(
        newsPlainParagraphs(
          '<!-- news-youtube: dQw4w9WgXcQ -->\n\n![a](https://x/y.jpg)\n\n## Head\n\nline one\\\nline two',
        ),
        ['line one line two'],
      );
    });

    test('a summary that only repeats the opening is spotted', () {
      final news = _partner();
      expect(newsSummaryRepeatsBody(news.summary, news.content), isTrue);
      expect(
        newsSummaryRepeatsBody(
          'Timur Turlov shared his opinion…',
          news.content,
        ),
        isTrue,
      );
      expect(
        newsSummaryRepeatsBody('Something else entirely.', news.content),
        isFalse,
      );
      expect(newsSummaryRepeatsBody('', news.content), isFalse);
    });
  });

  group('links', () {
    test('a link to a RookReview article in the Feed finds it', () {
      final partner = _partner();
      final own = _own();
      expect(
        newsArticleAt(
          Uri.parse('https://rookreview.com/news/sindarov-is-the-favorite/'),
          [own, partner],
        ),
        partner,
      );
      expect(
        newsArticleAt(
          Uri.parse(
            'https://www.rookreview.com/news/sindarov-is-the-favorite?ref=x',
          ),
          [partner],
        ),
        partner,
      );
      expect(
        newsArticleAt(Uri.parse('https://rookreview.com/news/other'), [
          partner,
        ]),
        isNull,
      );
      expect(
        newsArticleAt(Uri.parse('https://chessever.com/news/7/carlsen'), [
          partner,
          own,
        ]),
        own,
      );
      expect(
        newsArticleAt(Uri.parse('https://chessever.com/news/7/carlsen'), [
          partner,
        ]),
        isNull,
      );
    });

    test('RookReview pictures load inline; strangers stay links', () {
      expect(
        isNewsImageSourceAllowed(
          Uri.parse('https://rookreview.b-cdn.net/a.jpeg'),
        ),
        isTrue,
      );
      expect(
        isNewsImageSourceAllowed(Uri.parse('https://evil.example/a.jpeg')),
        isFalse,
      );
    });
  });

  group('FeedNewsRepository with partners', () {
    test(
      'merges partner articles in and checks both for changes cheaply',
      () async {
        var clock = DateTime(2026, 10, 26, 12);
        final own = _Fetcher([_ownRow()]);
        final ownStamps = _Fetcher([Map.of(_ownRow())..remove('content')]);
        final partner = _Fetcher([_partnerRow()]);
        final partnerStamps = _Fetcher([
          Map.of(_partnerRow())..remove('content'),
        ]);
        final repo = FeedNewsRepository(
          fetchRows: own.call,
          fetchStamps: ownStamps.call,
          fetchPartnerRows: partner.call,
          fetchPartnerStamps: partnerStamps.call,
          cache: _MemoryCache(),
          clock: () => clock,
        );

        final first = (await repo.refresh())!;
        expect(first.items.map((n) => n.key), ['7', 'rookreview:7']);

        clock = clock.add(const Duration(minutes: 31));
        final same = (await repo.refresh())!;
        expect(identical(same.items, first.items), isTrue);
        expect(own.calls, 1);
        expect(partner.calls, 1);
        expect(partnerStamps.calls, 1);

        // A new RookReview article moves the partner stamps only.
        partner.rows = [
          _partnerRow(
            id: 8,
            url: 'https://rookreview.com/news/new',
            publishedAt: '2026-10-26T11:00:00Z',
          ),
          _partnerRow(),
        ];
        partnerStamps.rows = [
          for (final row in partner.rows) Map.of(row)..remove('content'),
        ];
        clock = clock.add(const Duration(minutes: 31));
        final fresh = (await repo.refresh())!;
        expect(fresh.items.map((n) => n.key), [
          'rookreview:8',
          '7',
          'rookreview:7',
        ]);
        expect(identical(fresh.items[1], first.items[0]), isTrue);
        expect(identical(fresh.items[2], first.items[1]), isTrue);
      },
    );

    test('a partner outage keeps the partner articles already shown', () async {
      final partner = _Fetcher([_partnerRow()]);
      final repo = FeedNewsRepository(
        fetchRows: _Fetcher([_ownRow()]).call,
        fetchPartnerRows: partner.call,
        cache: _MemoryCache(),
      );
      expect((await repo.refresh())!.items, hasLength(2));

      partner.error = const PostgrestException(
        message: 'timeout',
        code: '57014',
      );
      final during = (await repo.refresh())!;
      expect(during.items.map((n) => n.key), ['7', 'rookreview:7']);

      partner.error = const PostgrestException(
        message: 'Could not find the table public.partner_news',
        code: 'PGRST205',
      );
      expect((await repo.refresh())!.items.map((n) => n.key), ['7']);
    });

    test('a ChessEver failure still fails the refresh', () async {
      final own = _Fetcher(const [])
        ..error = const PostgrestException(message: 'boom', code: '500');
      final repo = FeedNewsRepository(
        fetchRows: own.call,
        fetchPartnerRows: _Fetcher([_partnerRow()]).call,
        cache: _MemoryCache(),
      );
      expect(await repo.refresh(), isNull);
    });
  });

  group('widgets', () {
    Future<void> pump(
      WidgetTester tester,
      Widget child,
      List<FeedNews> items,
    ) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(393 * 3, 852 * 3);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            premiumAccessProvider.overrideWithValue(false),
            feedNewsProvider.overrideWith((ref) async => items),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return child;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('a RookReview page carries its mark, name and opening words', (
      tester,
    ) async {
      final news = _partner();
      await pump(
        tester,
        Scaffold(
          body: SizedBox(
            height: 700,
            child: FeedNewsPage(
              news: news,
              isCurrent: true,
              isVisible: true,
              onRequestNext: () {},
            ),
          ),
        ),
        [news],
      );

      expect(
        find.textContaining('RookReview', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('ChessEver News', findRichText: true),
        findsNothing,
      );
      expect(
        find.image(const AssetImage(PngAsset.rookReviewMark)),
        findsOneWidget,
      );

      final title = tester.widget<Text>(find.text(news.title));
      expect(title.maxLines, 2);
      // The opening words fill the page, the summary not printed twice.
      final excerpt = tester.widget<Text>(
        find.textContaining('Timur Turlov shared his opinion'),
      );
      expect(excerpt.data!.split('Timur Turlov shared').length, 2);
      expect(
        excerpt.data,
        contains('I think the match will be really interesting.'),
      );
      expect(excerpt.maxLines, greaterThanOrEqualTo(2));
      expect(excerpt.overflow, TextOverflow.fade);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Read'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(NewsReaderScreen), findsOneWidget);
    });

    testWidgets('a short page drops the excerpt rather than cutting it', (
      tester,
    ) async {
      final news = _partner();
      await pump(
        tester,
        Scaffold(
          body: SizedBox(
            height: 280,
            child: FeedNewsPage(
              news: news,
              isCurrent: true,
              isVisible: true,
              onRequestNext: () {},
            ),
          ),
        ),
        [news],
      );
      expect(
        find.textContaining('Timur Turlov shared his opinion'),
        findsNothing,
      );
      expect(find.text('Read'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the reader credits RookReview and always links the original', (
      tester,
    ) async {
      final news = _partner();
      await pump(tester, NewsReaderScreen(news: news), [news]);

      expect(
        find.textContaining('RookReview  \u00b7', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('ChessEver News', findRichText: true),
        findsNothing,
      );
      // The summary is the first paragraph: shown once, in the body.
      expect(find.text(news.summary), findsNothing);
      expect(
        find.textContaining(
          'Timur Turlov shared his opinion',
          findRichText: true,
        ),
        findsOneWidget,
      );

      // The whole article, and the original one tap away from the top...
      expect(
        find.textContaining('Timur Turlov', findRichText: true),
        findsWidgets,
      );
      expect(find.text('Read original article on RookReview'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Read original article on RookReview')).dy,
        lessThan(tester.getTopLeft(find.text(news.title)).dy + 200),
      );
      // ...and at the end.
      await tester.scrollUntilVisible(
        find.text('Read original article'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Read original article'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Read original article on RookReview'),
        findsNWidgets(2),
      );
      expect(find.text('Read on RookReview'), findsNothing);
      expect(find.text('Open on chessever.com'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ChessEver articles carry no partner link', (tester) async {
      final news = FeedNews(
        id: 41,
        title: 'Our own story',
        summary: '',
        content: 'Every word of it.\n\nThe last paragraph.',
        publishedAt: DateTime.utc(2026, 10, 25),
      );
      await pump(tester, NewsReaderScreen(news: news), [news]);

      expect(
        find.textContaining('The last paragraph.', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Read original article'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
