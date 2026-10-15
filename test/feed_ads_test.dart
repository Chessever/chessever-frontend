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

  group('withFeedAds', () {
    test('an ad after every fifth post, only between two posts', () {
      expect(keys(withFeedAds(posts(11))), [
        'news:1',
        'news:2',
        'news:3',
        'news:4',
        'news:5',
        'ad:news:5',
        'news:6',
        'news:7',
        'news:8',
        'news:9',
        'news:10',
        'ad:news:10',
        'news:11',
      ]);
    });

    test('no ad after the last post: the tail follows it', () {
      expect(withFeedAds(posts(5)).whereType<FeedAdEntry>(), isEmpty);
      expect(keys(withFeedAds(posts(10))), isNot(contains('ad:news:10')));
    });

    test('a growing feed keeps every ad where it stood', () {
      final short = keys(withFeedAds(posts(8)));
      final long = keys(withFeedAds(posts(14)));
      expect(long.sublist(0, short.length), short);
    });

    test('withdrawn ads are left out', () {
      final pages = withFeedAds(posts(11), withdrawn: {'ad:news:5'});
      expect(keys(pages.whereType<FeedAdEntry>().toList()), ['ad:news:10']);
    });
  });

  test('feedPostIndexAt translates pages to posts', () {
    final pages = withFeedAds(posts(11));
    expect(feedPostIndexAt(pages, 0), 0);
    expect(feedPostIndexAt(pages, 4), 4);
    // The ad page reports the post after it.
    expect(feedPostIndexAt(pages, 5), 5);
    expect(feedPostIndexAt(pages, 6), 5);
    expect(feedPostIndexAt(pages, 12), 10);
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
