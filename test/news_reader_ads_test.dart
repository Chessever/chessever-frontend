import 'dart:async';

import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/news/news_reader_pager.dart';
import 'package:chessever2/screens/feed/news/news_reader_screen.dart';
import 'package:chessever2/screens/feed/providers/feed_entries_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_ad_page.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/ads/ad_disclosure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

FeedNews _news(int id) => FeedNews(
  id: id,
  title: 'Story $id',
  summary: 'Round $id',
  content: List.filled(
    20,
    'The championship continued with a decisive game.',
  ).join('\n\n'),
  publishedAt: DateTime.utc(2026, 10, 30 - id),
);

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription(bool paid) : super(SubscriptionState(isSubscribed: paid));

  void paid(bool value) => state = SubscriptionState(isSubscribed: value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  bool paid = false,
  int initialIndex = 0,
  _Subscription? subscription,
  ValueChanged<FeedNews>? onArticleChanged,
  List<FeedNews>? articles,
  bool Function()? hasMore,
  Future<List<FeedNews>> Function()? loadMore,
  bool reducedMotion = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      feedAdsAvailableProvider.overrideWithValue(true),
      subscriptionProvider.overrideWith(
        (ref) => subscription ?? _Subscription(paid),
      ),
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
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reducedMotion),
            child: child!,
          );
        },
        home: NewsReaderPager(
          articles: articles ?? [for (var i = 1; i <= 8; i++) _news(i)],
          initialIndex: initialIndex,
          heroScope: Object(),
          onArticleChanged: onArticleChanged,
          hasMore: hasMore,
          loadMore: loadMore,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _swipe(WidgetTester tester, {bool back = false}) async {
  await tester.fling(find.byType(PageView), Offset(back ? 320 : -320, 0), 1200);
  await tester.pumpAndSettle();
}

int _readingId(WidgetTester tester) =>
    tester.widget<NewsReaderScreen>(find.byType(NewsReaderScreen)).news.id;

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(NewsReaderScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

void main() {
  testWidgets('footer next brings the following article up from below', (
    tester,
  ) async {
    await _pump(tester, paid: true, articles: [_news(1), _news(2)]);
    _position(tester).jumpTo(_position(tester).maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('news_next')));
    await tester.pump(); // Lay out the vertical pager.
    await tester.pump(); // Start the page animation's ticker.
    await tester.pump(const Duration(milliseconds: 120));
    final incoming = find.byWidgetPredicate(
      (widget) => widget is NewsReaderScreen && widget.news.id == 2,
    );
    final outgoing = find.byWidgetPredicate(
      (widget) => widget is NewsReaderScreen && widget.news.id == 1,
    );
    final next = tester.getTopLeft(incoming);
    final previous = tester.getTopLeft(outgoing);
    expect(next.dx, closeTo(0, 0.1));
    expect(next.dy, greaterThan(0));
    expect(next.dy, lessThan(844));
    expect(previous.dx, closeTo(0, 0.1));
    expect(previous.dy, lessThan(0));
    await tester.pumpAndSettle();
    expect(_readingId(tester), 2);
  });

  testWidgets(
    'reader uses Feed ad cadence with no trailing ad or access gate',
    (tester) async {
      await _pump(tester);
      for (final expected in <int?>[1, 2, null, 3, 4, 5, 6, null, 7, 8]) {
        if (expected == null) {
          expect(find.byType(FeedAdPage), findsOneWidget);
          expect(find.text(AdDisclosureLine.text), findsOneWidget);
          expect(
            tester
                .widget<RemoveAdsButton>(find.byType(RemoveAdsButton))
                .returnTo,
            'news/reader',
          );
        } else {
          expect(_readingId(tester), expected);
        }
        expect(find.text('Watch ad'), findsNothing);
        if (expected != 8) await _swipe(tester);
      }
      expect(
        tester
            .widget<PageView>(find.byType(PageView))
            .childrenDelegate
            .estimatedChildCount,
        10,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selected grid article opens directly even with earlier ad slots',
    (tester) async {
      await _pump(tester, initialIndex: 5);
      expect(_readingId(tester), 6);
      expect(find.byType(FeedAdPage), findsNothing);
      await _swipe(tester);
      expect(find.byType(FeedAdPage), findsOneWidget);
      await _swipe(tester);
      expect(_readingId(tester), 7);
    },
  );

  testWidgets(
    'subscription changes retain the current article and vertical position',
    (tester) async {
      final subscription = _Subscription(false);
      final reported = <int>[];
      await _pump(
        tester,
        initialIndex: 2,
        subscription: subscription,
        onArticleChanged: (news) => reported.add(news.id),
      );
      _position(tester).jumpTo(300);
      await tester.pumpAndSettle();
      subscription.paid(true);
      await tester.pumpAndSettle();
      expect(_readingId(tester), 3);
      expect(_position(tester).pixels, closeTo(300, 1));
      subscription.paid(false);
      await tester.pumpAndSettle();
      expect(_readingId(tester), 3);
      expect(_position(tester).pixels, closeTo(300, 1));
      expect(reported, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed current ad yields the next article without changing Feed slots',
    (tester) async {
      final container = await _pump(tester, initialIndex: 1);
      await _swipe(tester);
      final ad = tester.widget<FeedAdPage>(find.byType(FeedAdPage));
      ad.onUnavailable!();
      await tester.pumpAndSettle();
      expect(_readingId(tester), 3);
      expect(container.read(feedAdWithdrawnProvider), isEmpty);
      await _swipe(tester, back: true);
      expect(_readingId(tester), 2);
      await _swipe(tester);
      expect(_readingId(tester), 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('paid reader has only articles', (tester) async {
    await _pump(tester, paid: true);
    for (var i = 2; i <= 8; i++) {
      await _swipe(tester);
      expect(_readingId(tester), i);
    }
    expect(
      tester
          .widget<PageView>(find.byType(PageView))
          .childrenDelegate
          .estimatedChildCount,
      8,
    );
  });

  testWidgets(
    'bottom pull advances to the scheduled ad, which swipes to the next story',
    (tester) async {
      await _pump(tester, initialIndex: 1);
      _position(tester).jumpTo(_position(tester).maxScrollExtent);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(const Offset(190, 600));
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('Release for next ad'), findsOneWidget);
      expect(
        _readingId(tester),
        2,
        reason: 'Only release commits the page turn.',
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(FeedAdPage), findsOneWidget);
      await _swipe(tester);
      expect(_readingId(tester), 3);
    },
  );

  testWidgets(
    'next waits for an in-flight batch and includes its newly due ad',
    (tester) async {
      final batch = Completer<List<FeedNews>>();
      var more = true;
      var requests = 0;
      await _pump(
        tester,
        articles: [_news(1), _news(2)],
        initialIndex: 1,
        hasMore: () => more,
        loadMore: () {
          requests++;
          return batch.future;
        },
      );
      _position(tester).jumpTo(_position(tester).maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('news_next')));
      await tester.pump();
      expect(find.text('Opening next article…'), findsOneWidget);
      expect(requests, 1);
      more = false;
      batch.complete([_news(1), _news(2), _news(3)]);
      await tester.pumpAndSettle();
      expect(find.byType(FeedAdPage), findsOneWidget);
      await _swipe(tester);
      expect(_readingId(tester), 3);
      expect(find.byKey(const ValueKey('news_next')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a failed next batch keeps the story and can be retried from its footer',
    (tester) async {
      var requests = 0;
      var more = true;
      await _pump(
        tester,
        articles: [_news(1)],
        paid: true,
        hasMore: () => more,
        loadMore: () async {
          requests++;
          if (requests < 3) throw StateError('offline');
          more = false;
          return [_news(1), _news(2)];
        },
      );
      expect(requests, 1);
      _position(tester).jumpTo(_position(tester).maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('news_next')));
      await tester.pumpAndSettle();
      expect(_readingId(tester), 1);
      expect(requests, 2);
      await tester.tap(find.byKey(const ValueKey('news_next')));
      await tester.pumpAndSettle();
      expect(_readingId(tester), 2);
      expect(requests, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion next uses the same sequence and preserves the previous bottom position',
    (tester) async {
      await _pump(tester, paid: true, reducedMotion: true);
      _position(tester).jumpTo(_position(tester).maxScrollExtent);
      await tester.pumpAndSettle();
      final bottom = _position(tester).pixels;
      await tester.tap(find.byKey(const ValueKey('news_next')));
      await tester.pumpAndSettle();
      expect(_readingId(tester), 2);
      await _swipe(tester, back: true);
      expect(_readingId(tester), 1);
      expect(_position(tester).pixels, closeTo(bottom, 1));
      expect(tester.takeException(), isNull);
    },
  );
}
