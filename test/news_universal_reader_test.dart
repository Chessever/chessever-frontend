import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/feed/news/news_link_screen.dart';
import 'package:chessever2/screens/feed/news/news_links.dart';
import 'package:chessever2/screens/feed/news/news_reader_pager.dart';
import 'package:chessever2/screens/feed/news/news_reader_screen.dart';
import 'package:chessever2/screens/feed/news/news_reading_access.dart';
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
  testWidgets(
    'Feed visibility, Read and News navigation share one three-article allowance',
    (tester) async {
      var prompts = 0;
      final articles = [for (var id = 1; id <= 5; id++) _article(id)];
      final container = ProviderContainer(
        overrides: [
          premiumAccessProvider.overrideWithValue(false),
          feedNewsProvider.overrideWith((ref) async => articles),
          newsPremiumPromptProvider.overrideWithValue((_) async {
            prompts++;
            return false;
          }),
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
      for (var i = 0; i < 2; i++) {
        await _swipeArticle(tester);
      }
      expect(
        prompts,
        0,
        reason:
            'Opening a Feed post again in the reader must not count it twice.',
      );
      await _swipeArticle(tester);
      expect(prompts, 1);
      expect(_readingId(tester), 3);
      expect(find.text('Championship story 4'), findsNothing);
    },
  );

  testWidgets(
    'background Feed previews spend no reads; visible fourth post prompts once',
    (tester) async {
      var prompts = 0;
      var id = 1;
      var visible = false;
      late StateSetter update;
      final container = ProviderContainer(
        overrides: [
          premiumAccessProvider.overrideWithValue(false),
          newsPremiumPromptProvider.overrideWithValue((_) async {
            prompts++;
            return false;
          }),
        ],
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
        expect(prompts, next == 4 ? 1 : 0);
      }
      // A modal hiding and revealing Feed must not reopen a dismissed prompt.
      update(() => visible = false);
      await tester.pumpAndSettle();
      update(() => visible = true);
      await tester.pumpAndSettle();
      expect(prompts, 1);
    },
  );

  testWidgets(
    'a shared article outside the Feed batch resolves and uses the same gate',
    (tester) async {
      var attempts = 0;
      var prompts = 0;
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
            newsPremiumPromptProvider.overrideWithValue((_) async {
              prompts++;
              return false;
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
      expect(prompts, 0);
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
