import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/feed/providers/feed_entries_provider.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/feed/models/feed_entry.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<FeedEntry> posts(int count) => [
    for (var i = 1; i <= count; i++) FeedNewsEntry(_news(i)),
  ];
  List<String> keys(List<FeedEntry> pages) => [
    for (final page in pages) page.key,
  ];

  test('only paid subscriptions hide ads, after the initial check', () {
    final subscription = _Subscription(SubscriptionState(isLoading: true));
    final container = ProviderContainer(
      overrides: [
        feedAdsAvailableProvider.overrideWithValue(true),
        subscriptionProvider.overrideWith((ref) => subscription),
        // Temporary rewarded access makes effective Premium true, while the
        // paid subscription remains false.
        premiumAccessProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(feedAdsVisibleProvider), isFalse);
    subscription.update(SubscriptionState(isLoading: false));
    expect(container.read(feedAdsVisibleProvider), isTrue);
    subscription.update(SubscriptionState(isLoading: true));
    expect(container.read(feedAdsVisibleProvider), isTrue);
    subscription.update(SubscriptionState(isSubscribed: true));
    expect(container.read(feedAdsVisibleProvider), isFalse);
    subscription.update(SubscriptionState(isSubscribed: false));
    expect(container.read(feedAdsVisibleProvider), isTrue);
  });

  test('unavailable placements never show ads', () {
    final container = ProviderContainer(
      overrides: [feedAdsAvailableProvider.overrideWithValue(false)],
    );
    addTearDown(container.dispose);
    expect(container.read(feedAdsVisibleProvider), isFalse);
  });

  group('withFeedAds', () {
    test('ads occupy positions 3, 8, 13, 18 counting all pages', () {
      final pages = withFeedAds(posts(16));
      expect(
        [
          for (var i = 0; i < pages.length; i++)
            if (pages[i] is FeedAdEntry) i + 1,
        ],
        [3, 8, 13, 18],
      );
      expect(keys(pages.whereType<FeedNewsEntry>().toList()), keys(posts(16)));
    });

    test('short feeds and the final post have no trailing ad', () {
      for (final count in [0, 1, 2]) {
        expect(withFeedAds(posts(count)).whereType<FeedAdEntry>(), isEmpty);
      }
      expect(keys(withFeedAds(posts(3))), [
        'news:1',
        'news:2',
        'ad:news:2',
        'news:3',
      ]);
      expect(keys(withFeedAds(posts(6))), isNot(contains('ad:news:6')));
    });

    test('a growing feed keeps every ad where it stood', () {
      final short = keys(withFeedAds(posts(8)));
      final long = keys(withFeedAds(posts(14)));
      expect(long.sublist(0, short.length), short);
    });

    test('withdrawn ads are left out', () {
      final pages = withFeedAds(posts(11), withdrawn: {'ad:news:2'});
      expect(keys(pages.whereType<FeedAdEntry>().toList()), [
        'ad:news:6',
        'ad:news:10',
      ]);
    });
  });

  test('feedPostIndexAt translates pages to posts', () {
    final pages = withFeedAds(posts(11));
    expect(feedPostIndexAt(pages, 0), 0);
    expect(feedPostIndexAt(pages, 1), 1);
    // The ad page reports the post after it.
    expect(feedPostIndexAt(pages, 2), 2);
    expect(feedPostIndexAt(pages, 3), 2);
    expect(feedPostIndexAt(pages, 7), 6);
    expect(feedPostIndexAt(pages, 8), 6);
    expect(feedPostIndexAt(pages, 13), 10);
    // The tail sits just past the last post.
    expect(feedPostIndexAt(pages, pages.length), 11);
  });
}

FeedNews _news(int id) => FeedNews(
  id: id,
  title: 'News $id',
  summary: 'Summary',
  content: 'Body',
  publishedAt: DateTime(2026, 9, 20),
);

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription(super.state);

  void update(SubscriptionState value) => state = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
