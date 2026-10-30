import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/feed/news/news_link_screen.dart';
import 'package:chessever2/screens/feed/news/news_links.dart';
import 'package:chessever2/screens/feed/news/news_reader_pager.dart';
import 'package:chessever2/screens/feed/news/news_reader_screen.dart';
import 'package:chessever2/screens/feed/news/news_repository.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

FeedNews _article(int id) => FeedNews(
  id: id,
  title: 'Championship story $id',
  summary: 'Round $id',
  content: 'The full article for round $id.',
  publishedAt: DateTime.utc(2026, 10, 30 - id),
);

void main() {
  testWidgets('Feed Read opens the same unrestricted article reader', (
    tester,
  ) async {
    final articles = [for (var id = 1; id <= 5; id++) _article(id)];
    final container = ProviderContainer(
      overrides: [
        premiumAccessProvider.overrideWithValue(false),
        feedNewsProvider.overrideWith((ref) async => articles),
      ],
    );
    addTearDown(container.dispose);
    await container.read(feedNewsProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          builder: (context, child) {
            ResponsiveHelper.init(context);
            return child!;
          },
          home: Scaffold(
            body: FeedNewsPage(
              news: articles.first,
              isCurrent: true,
              isVisible: true,
              onRequestNext: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();
    expect(find.byType(NewsReaderPager), findsOneWidget);
    expect(
      ModalRoute.of(
        tester.element(find.byType(NewsReaderPager)),
      )?.settings.name,
      Uri.parse(newsShareUrl(articles.first)).path,
    );
    for (var i = 2; i <= 5; i++) {
      await _swipeArticle(tester);
      expect(_readingId(tester), i);
    }
    expect(find.text('Watch ad'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'visible and background Feed news never interrupt with an access prompt',
    (tester) async {
      var id = 1;
      var visible = false;
      late StateSetter update;
      final container = ProviderContainer(
        overrides: [premiumAccessProvider.overrideWithValue(false)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            builder: (context, child) {
              ResponsiveHelper.init(context);
              return child!;
            },
            home: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return Scaffold(
                  body: FeedNewsPage(
                    news: _article(id),
                    isCurrent: true,
                    isVisible: visible,
                    onRequestNext: () {},
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var next = 1; next <= 4; next++) {
        update(() {
          id = next;
          visible = true;
        });
        await tester.pumpAndSettle();
        expect(find.text('Watch ad'), findsNothing);
      }
      // Returning to Feed stays uninterrupted.
      update(() => visible = false);
      await tester.pumpAndSettle();
      update(() => visible = true);
      await tester.pumpAndSettle();
      expect(find.text('Watch ad'), findsNothing);
    },
  );

  testWidgets(
    'a shared article outside the Feed batch retries and opens directly',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            premiumAccessProvider.overrideWithValue(false),
            newsArticleLoaderProvider.overrideWithValue((link) async {
              attempts++;
              if (attempts == 1) throw StateError('offline');
              expect(link.id, 900);
              return _article(900);
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            builder: (context, child) {
              ResponsiveHelper.init(context);
              return child!;
            },
            home: const NewsLinkScreen(link: NewsLink(id: 900)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load this article."), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byType(NewsReaderScreen), findsOneWidget);
      expect(find.text('Championship story 900'), findsOneWidget);
      expect(attempts, 2);
      expect(find.text('Watch ad'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _swipeArticle(WidgetTester tester, {bool back = false}) async {
  await tester.fling(find.byType(PageView), Offset(back ? 300 : -300, 0), 1500);
  await tester.pumpAndSettle();
}

int _readingId(WidgetTester tester) =>
    tester.widget<NewsReaderScreen>(find.byType(NewsReaderScreen)).news.id;
