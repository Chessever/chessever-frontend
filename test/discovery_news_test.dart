import 'dart:math' as math;
import 'dart:async';

import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/feed/news/news_cover.dart';
import 'package:chessever2/screens/feed/news/news_hero_cover.dart';
import 'package:chessever2/screens/feed/news/news_reader_pager.dart';
import 'package:chessever2/screens/feed/news/news_reader_screen.dart';
import 'package:chessever2/screens/feed/news/news_reading_access.dart';
import 'package:chessever2/screens/feed/news/news_repository.dart';
import 'package:chessever2/screens/for_you/discovery/news_screen.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Map<String, dynamic> _row(
  int id, {
  int? hour,
  bool partner = false,
  String? imageUrl,
  String? content,
}) => {
  'id': id,
  'title': '${partner ? 'Partner' : 'ChessEver'} story $id',
  'summary': 'The players and results from round $id.',
  'content':
      content ??
      'Round $id included a **decisive** game.\n\n'
          '## The final round\n\nThe championship continues.',
  'image_url': imageUrl,
  'status': 'published',
  'published_at': DateTime.utc(
    2026,
    10,
    1,
  ).add(Duration(hours: hour ?? 100 - id)).toIso8601String(),
  'created_at': DateTime.utc(2026, 10, 1).toIso8601String(),
  if (partner) ...{
    'source_id': 'rookreview',
    'url': 'https://rookreview.com/news/story-$id',
  },
};

class _Rows {
  _Rows(this.rows);
  List<Map<String, dynamic>> rows;
  final List<int> offsets = [];
  bool fail = false;

  Future<List<Map<String, dynamic>>> fetch(int offset, int limit) async {
    offsets.add(offset);
    if (fail) throw StateError('offline');
    return rows.sublist(
      math.min(offset, rows.length),
      math.min(offset + limit, rows.length),
    );
  }
}

NewsCatalogRepository _catalog(
  _Rows own,
  _Rows partners, {
  int pageSize = 12,
}) => NewsCatalogRepository(
  fetchOwn: own.fetch,
  fetchPartners: partners.fetch,
  pageSize: pageSize,
);

Future<void> _pump(
  WidgetTester tester, {
  required NewsCatalogRepository Function() create,
  Widget home = const NewsScreen(),
  Size size = const Size(390, 844),
  double scale = 1,
  bool light = false,
  bool reducedMotion = false,
  bool premium = false,
  Future<bool> Function(BuildContext)? requestPremium,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        newsCatalogFactoryProvider.overrideWithValue(create),
        feedNewsProvider.overrideWith((ref) async => []),
        premiumAccessProvider.overrideWithValue(premium),
        if (requestPremium != null)
          newsPremiumPromptProvider.overrideWithValue(requestPremium),
      ],
      child: MaterialApp(
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        builder: (context, child) {
          ResponsiveHelper.init(context);
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: reducedMotion,
            ),
            child: child!,
          );
        },
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('news catalog', () {
    test(
      'pages merge both publishers globally, including equal dates and ids',
      () async {
        final own = _Rows([for (var i = 1; i <= 9; i++) _row(i)]);
        final partners = _Rows([
          for (var i = 1; i <= 7; i++) _row(i, hour: 94 - i, partner: true),
        ]);
        final catalog = _catalog(own, partners, pageSize: 3);
        final all = <FeedNews>[];
        for (var i = 0; i < 10; i++) {
          final page = await catalog.loadNext();
          all.addAll(page.items);
          if (!page.hasMore) break;
        }
        final expected = mergeFeedNews(
          own.rows.map((row) => normalizeNewsRow(row)!).toList(),
          partners.rows.map((row) => normalizePartnerNewsRow(row)!).toList(),
        );
        expect(all.map((item) => item.key), expected.map((item) => item.key));
        expect(all.map((item) => item.key).toSet(), hasLength(16));
        expect((await catalog.loadNext()).items, isEmpty);
        expect((await catalog.loadNext()).hasMore, isFalse);
      },
    );

    test(
      'failed pages retry from the same cursor without losing buffered articles',
      () async {
        final own = _Rows([for (var i = 1; i <= 5; i++) _row(i)]);
        final partners = _Rows([_row(1, hour: 10, partner: true)]);
        final catalog = _catalog(own, partners, pageSize: 2);
        expect((await catalog.loadNext()).items.map((item) => item.key), [
          '1',
          '2',
        ]);
        own.fail = true;
        await expectLater(catalog.loadNext(), throwsStateError);
        own.fail = false;
        expect((await catalog.loadNext()).items.map((item) => item.key), [
          '3',
          '4',
        ]);
        expect((await catalog.loadNext()).items.map((item) => item.key), [
          '5',
          'rookreview:1',
        ]);
        expect(own.offsets.take(3), [0, 2, 2]);
        expect(partners.offsets, [0]);
      },
    );

    test(
      'invalid rows and a repeated row do not truncate browsing or duplicate cards',
      () async {
        final own = _Rows([
          {..._row(1), 'content': ''},
          {..._row(2), 'content': ''},
          _row(3),
          _row(3),
          _row(4),
        ]);
        final catalog = _catalog(own, _Rows([]), pageSize: 2);
        expect((await catalog.loadNext()).items.map((item) => item.id), [3, 4]);
        expect((await catalog.loadNext()).hasMore, isFalse);
      },
    );

    test('concurrent page requests share one read', () async {
      final own = _Rows([_row(1)]);
      final catalog = _catalog(own, _Rows([]));
      final first = catalog.loadNext();
      final second = catalog.loadNext();
      expect(identical(first, second), isTrue);
      await Future.wait([first, second]);
      expect(own.offsets, [0]);
    });
  });

  group('news browsing', () {
    testWidgets(
      'Next asks after three articles and dismissal keeps the third',
      (tester) async {
        var prompts = 0;
        await _pump(
          tester,
          create: () => _catalog(
            _Rows([for (var i = 1; i <= 8; i++) _row(i)]),
            _Rows([]),
          ),
          requestPremium: (_) async {
            prompts++;
            return false;
          },
        );
        await tester.tap(find.byKey(const ValueKey('news_card_1')));
        await tester.pumpAndSettle();
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.byTooltip('Next article'));
          await tester.pumpAndSettle();
        }
        expect(find.text('3 / 8'), findsOneWidget);
        expect(prompts, 0);
        await tester.tap(find.byTooltip('Next article'));
        await tester.pumpAndSettle();
        expect(prompts, 1);
        expect(find.text('3 / 8'), findsOneWidget);
        expect(find.text('ChessEver story 4'), findsNothing);
        // Going back and returning to a read article never spends a new read.
        await tester.tap(find.byTooltip('Previous article'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Next article'));
        await tester.pumpAndSettle();
        expect(prompts, 1);
        await tester.tap(find.byTooltip('Next article'));
        await tester.pumpAndSettle();
        expect(prompts, 2);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('swiping cannot preview a gated body or stack prompts', (
      tester,
    ) async {
      var prompts = 0;
      final result = Completer<bool>();
      await _pump(
        tester,
        create: () =>
            _catalog(_Rows([for (var i = 1; i <= 5; i++) _row(i)]), _Rows([])),
        requestPremium: (_) {
          prompts++;
          return result.future;
        },
      );
      await tester.tap(find.byKey(const ValueKey('news_card_1')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.drag(find.byType(PageView), const Offset(-340, 0));
        await tester.pumpAndSettle();
      }
      await tester.drag(find.byType(PageView), const Offset(-340, 0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(prompts, 1);
      expect(find.text('ChessEver story 4'), findsNothing);
      expect(
        find.textContaining('Round 4 included', findRichText: true),
        findsNothing,
      );
      await tester.drag(find.byType(PageView), const Offset(-340, 0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(prompts, 1);
      result.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('3 / 5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'accepted prompts resume the article and repeat after another three',
      (tester) async {
        var prompts = 0;
        await _pump(
          tester,
          create: () => _catalog(
            _Rows([for (var i = 1; i <= 8; i++) _row(i)]),
            _Rows([]),
          ),
          requestPremium: (_) async {
            prompts++;
            return true;
          },
        );
        await tester.tap(find.byKey(const ValueKey('news_card_1')));
        await tester.pumpAndSettle();
        for (var i = 2; i <= 7; i++) {
          await tester.tap(find.byTooltip('Next article'));
          await tester.pumpAndSettle();
          expect(find.text('$i / 8'), findsOneWidget);
          expect(
            prompts,
            i < 4
                ? 0
                : i < 7
                ? 1
                : 2,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'closing and reopening the reader does not reset the free allowance',
      (tester) async {
        var prompts = 0;
        await _pump(
          tester,
          create: () => _catalog(
            _Rows([for (var i = 1; i <= 5; i++) _row(i)]),
            _Rows([]),
          ),
          requestPremium: (_) async {
            prompts++;
            return false;
          },
        );
        await tester.tap(find.byKey(const ValueKey('news_card_1')));
        await tester.pumpAndSettle();
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.byTooltip('Next article'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        final fourth = find.byKey(const ValueKey('news_card_4'));
        await tester.scrollUntilVisible(
          fourth,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(fourth);
        await tester.pumpAndSettle();
        expect(prompts, 1);
        expect(find.byType(NewsReaderPager), findsNothing);
        // A previously read card can still be reopened.
        final third = find.byKey(const ValueKey('news_card_3'));
        await tester.scrollUntilVisible(
          third,
          -300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(third);
        await tester.pumpAndSettle();
        expect(find.text('3 / 5'), findsOneWidget);
        expect(prompts, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Premium reads past both free boundaries without a prompt', (
      tester,
    ) async {
      var prompts = 0;
      await _pump(
        tester,
        create: () =>
            _catalog(_Rows([for (var i = 1; i <= 8; i++) _row(i)]), _Rows([])),
        premium: true,
        requestPremium: (_) async {
          prompts++;
          return false;
        },
      );
      await tester.tap(find.byKey(const ValueKey('news_card_1')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 7; i++) {
        await tester.tap(find.byTooltip('Next article'));
        await tester.pumpAndSettle();
      }
      expect(find.text('8 / 8'), findsOneWidget);
      expect(prompts, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'tap flies the same cover into a rich article; swipe and back keep order',
      (tester) async {
        final own = _Rows([
          _row(
            1,
            imageUrl:
                'https://oelbsuggrzyqwzmvidju.supabase.co/storage/v1/object/public/news/cover.jpg',
          ),
          _row(2),
          _row(3),
        ]);
        await _pump(tester, create: () => _catalog(own, _Rows([])));
        final card = find.byKey(const ValueKey('news_card_1'));
        final sourceHero = tester.widget<Hero>(
          find.descendant(of: card, matching: find.byType(Hero)),
        );
        final sourceCover = tester.widget<NewsHeroCover>(
          find.descendant(of: card, matching: find.byType(NewsHeroCover)),
        );
        expect(sourceCover.imageUrl, isNotNull);
        await tester.tap(card);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        // A real Navigator Hero flight is mounted in the overlay.
        expect(find.byType(NewsReaderPager), findsOneWidget);
        expect(find.byType(Hero), findsWidgets);
        expect(
          find.descendant(
            of: find.byType(NewsReaderScreen),
            matching: find.byType(NewsCover),
          ),
          findsNothing,
        );
        expect(
          tester
              .widgetList<NewsCover>(find.byType(NewsCover))
              .where((cover) => cover.imageUrl == sourceCover.imageUrl),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        final reader = tester.widget<NewsReaderScreen>(
          find.byType(NewsReaderScreen),
        );
        expect(reader.news.id, 1);
        expect(reader.heroTag, sourceHero.tag);
        final cover = tester.widget<NewsHeroCover>(
          find.descendant(
            of: find.byType(NewsReaderScreen),
            matching: find.byType(NewsHeroCover),
          ),
        );
        expect(cover.imageUrl, own.rows.first['image_url']);
        expect(cover.imageUrl, sourceCover.imageUrl);
        final readerImage = tester.widget<NewsNetworkImage>(
          find.descendant(
            of: find.byType(NewsReaderScreen),
            matching: find.byType(NewsNetworkImage),
          ),
        );
        expect(readerImage.pixelWidth, 390);
        expect(readerImage.fadeInDuration, Duration.zero);
        expect(
          find.textContaining('decisive', findRichText: true),
          findsOneWidget,
        );

        await tester.drag(find.byType(PageView), const Offset(-340, 0));
        await tester.pumpAndSettle();
        expect(find.text('2 / 3'), findsOneWidget);
        expect(
          tester
              .widget<NewsReaderScreen>(find.byType(NewsReaderScreen))
              .news
              .id,
          2,
        );
        await tester.tap(find.byTooltip('Previous article'));
        await tester.pumpAndSettle();
        expect(find.text('1 / 3'), findsOneWidget);
        await tester.tap(find.byTooltip('Next article'));
        await tester.pumpAndSettle();
        expect(find.text('2 / 3'), findsOneWidget);
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.byType(NewsReaderPager), findsNothing);
        expect(find.byKey(const ValueKey('news_card_2')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'reader opens the selected article, saves scroll positions and pages beyond the grid batch',
      (tester) async {
        final own = _Rows([
          for (var i = 1; i <= 7; i++)
            _row(
              i,
              content: List.filled(
                20,
                'A long paragraph about the championship.',
              ).join('\n\n'),
            ),
        ]);
        await _pump(
          tester,
          create: () => _catalog(own, _Rows([]), pageSize: 2),
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('news_card_2')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(const ValueKey('news_card_2')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NewsReaderScreen>(find.byType(NewsReaderScreen))
              .news
              .id,
          2,
        );
        final articleScroll = find.descendant(
          of: find.byType(NewsReaderScreen),
          matching: find.byType(CustomScrollView),
        );
        await tester.drag(articleScroll, const Offset(0, -400));
        await tester.pumpAndSettle();
        ScrollPosition readingPosition() => tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: articleScroll,
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
        final offset = readingPosition().pixels;
        expect(offset, greaterThan(100));
        await tester.drag(find.byType(PageView), const Offset(-340, 0));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NewsReaderScreen>(find.byType(NewsReaderScreen))
              .news
              .id,
          3,
        );
        await tester.drag(find.byType(PageView), const Offset(340, 0));
        await tester.pumpAndSettle();
        expect(readingPosition().pixels, closeTo(offset, 1));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('screen reader can activate a card and article navigation', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        create: () => _catalog(_Rows([_row(1), _row(2)]), _Rows([])),
      );
      final card = tester.getSemantics(
        find.bySemanticsLabel(RegExp(r'^ChessEver story 1\.')),
      );
      expect(card.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      card.owner!.performAction(card.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(find.byType(NewsReaderPager), findsOneWidget);
      final next = tester.getSemantics(find.byTooltip('Next article'));
      expect(next.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      next.owner!.performAction(next.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets(
      'reader retries a failed older batch without losing the current article',
      (tester) async {
        var attempts = 0;
        var more = true;
        final first = normalizeNewsRow(_row(1))!;
        final second = normalizeNewsRow(_row(2))!;
        await _pump(
          tester,
          create: () => _catalog(_Rows([]), _Rows([])),
          home: NewsReaderPager(
            articles: [first],
            initialIndex: 0,
            heroScope: Object(),
            hasMore: () => more,
            loadMore: () async {
              attempts++;
              if (attempts == 1) throw StateError('offline');
              more = false;
              return [first, second];
            },
          ),
        );
        expect(find.text('1 / 1'), findsOneWidget);
        expect(attempts, 1);
        await tester.tap(find.byTooltip('Retry next article'));
        await tester.pumpAndSettle();
        expect(find.text('2 / 2'), findsOneWidget);
        expect(attempts, 2);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'first-load errors retry and a failed refresh preserves readable cards',
      (tester) async {
        final own = _Rows([_row(1)])..fail = true;
        await _pump(tester, create: () => _catalog(own, _Rows([])));
        expect(find.text("Couldn't load news"), findsOneWidget);
        own.fail = false;
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('news_card_1')), findsOneWidget);
        own.fail = true;
        final refresh = tester.widget<RefreshIndicator>(
          find.byType(RefreshIndicator),
        );
        final refreshed = refresh.onRefresh();
        await tester.pump();
        await refreshed;
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const ValueKey('news_card_1')), findsOneWidget);
        expect(find.text("Couldn't refresh news."), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets('empty news is refreshable', (tester) async {
      final own = _Rows([]);
      await _pump(tester, create: () => _catalog(own, _Rows([])));
      expect(find.text('No news yet'), findsOneWidget);
      own.rows = [_row(1)];
      final refreshed = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      await refreshed;
      expect(find.byKey(const ValueKey('news_card_1')), findsOneWidget);
    });

    testWidgets(
      'reduced motion keeps cover and article visible without Hero flight',
      (tester) async {
        final own = _Rows([_row(1), _row(2)]);
        await _pump(
          tester,
          create: () => _catalog(own, _Rows([])),
          reducedMotion: true,
        );
        expect(find.byType(Hero), findsNothing);
        expect(find.byType(NewsCover), findsWidgets);
        await tester.tap(find.byKey(const ValueKey('news_card_1')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('decisive', findRichText: true),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Next article'));
        await tester.pumpAndSettle();
        expect(find.text('2 / 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    for (final scale in [1.0, 1.24]) {
      testWidgets('a phone shows two aligned grid columns at ${scale}x text', (
        tester,
      ) async {
        final own = _Rows([
          for (var i = 1; i <= 6; i++)
            {
              ..._row(i),
              if (i == 1)
                'title':
                    'Javokhir Sindarov Wins Clutch Chess: Champions Showdown '
                    '2026 in Saint Louis After Three Days of Play',
            },
        ]);
        await _pump(
          tester,
          create: () => _catalog(own, _Rows([])),
          size: const Size(402, 874),
          scale: scale,
        );
        final delegate =
            tester.widget<SliverGrid>(find.byType(SliverGrid)).gridDelegate
                as SliverGridDelegateWithFixedCrossAxisCount;
        expect(delegate.crossAxisCount, 2);
        final first = tester.getRect(find.byKey(const ValueKey('news_card_1')));
        final second = tester.getRect(
          find.byKey(const ValueKey('news_card_2')),
        );
        final third = tester.getRect(find.byKey(const ValueKey('news_card_3')));
        expect(second.top, first.top);
        expect(second.width, moreOrLessEquals(first.width));
        expect(second.height, moreOrLessEquals(first.height));
        expect(third.left, first.left);
        expect(third.top, greaterThan(first.bottom));
        // The summary waits for the reader at grid width.
        expect(
          find.text('The players and results from round 2.'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }

    for (final width in [320.0, 768.0, 1200.0]) {
      for (final light in [false, true]) {
        testWidgets(
          'grid and reader fit $width with large text in ${light ? 'light' : 'dark'}',
          (tester) async {
            final own = _Rows([for (var i = 1; i <= 6; i++) _row(i)]);
            await _pump(
              tester,
              create: () => _catalog(own, _Rows([])),
              size: Size(width, 1000),
              scale: 1.8,
              light: light,
            );
            expect(find.byType(SliverGrid), findsOneWidget);
            final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
            final delegate =
                grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
            expect(
              delegate.crossAxisCount,
              width < 600
                  ? 1
                  : width < 1000
                  ? 2
                  : 3,
            );
            expect(tester.takeException(), isNull);
            await tester.tap(find.byKey(const ValueKey('news_card_1')));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.byType(NewsReaderScreen), findsOneWidget);
          },
        );
      }
    }
  });
}
