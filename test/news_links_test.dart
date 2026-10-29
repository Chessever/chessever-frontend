import 'dart:convert';
import 'dart:io';

import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/feed/news/news_links.dart';
import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/services/app_destination.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixtures =
      jsonDecode(File('test/fixtures/news-links.json').readAsStringSync())
          as List;
  for (final fixture in fixtures) {
    test(
      'native and web share contract: ${fixture['publisher']}:${fixture['id']}',
      () {
        final publisher =
            NewsPublisher.ofSource(fixture['publisher']) ??
            NewsPublisher.chessever;
        final article = FeedNews(
          id: fixture['id'],
          title: fixture['title'],
          summary: '',
          content: 'Article body',
          publishedAt: DateTime.utc(2026),
          publisher: publisher,
        );
        final path = fixture['path'] as String;
        expect(newsShareUrl(article), 'https://chessever.com$path');
        for (final url in [
          'https://chessever.com$path?utm_source=social',
          'https://www.chessever.com$path',
          'com.chessever.app:/$path',
          'https://chessever.com/app$path',
        ]) {
          final link = NewsLink.parse(Uri.parse(url));
          expect(link?.key, article.key);
          expect(newsArticleAt(Uri.parse(url), [article]), article);
          expect(newsInAppRoute(Uri.parse(url)), isNotNull);
        }
        final destination = parseAppDestination('/app$path');
        expect(destination?.kind, AppDestinationKind.news);
        expect(destination?.id, '${article.id}');
        expect(destination?.section, publisher.sourceId);
      },
    );
  }

  test(
    'old or absent slugs resolve by publisher and id; hub links stay hubs',
    () {
      for (final url in [
        'https://chessever.com/news/7',
        'com.chessever.app://news/7/old-title',
      ]) {
        expect(NewsLink.parse(Uri.parse(url))?.key, '7');
      }
      for (final path in ['/news', '/news/', '/news/page/2', '/app/news']) {
        final link = NewsLink.parse(Uri.parse('https://chessever.com$path'));
        expect(link, isNotNull);
        expect(link!.id, isNull);
      }
    },
  );

  test(
    'foreign origins, unknown publishers and malformed identities fail closed',
    () {
      for (final url in [
        'https://attacker.example/news/7/story',
        'http://chessever.com/news/7/story',
        'https://user@chessever.com/news/7/story',
        'https://chessever.com:444/news/7/story',
        'https://chessever.com/news/0/story',
        'https://chessever.com/news/-1/story',
        'https://chessever.com/news/1e2/story',
        'https://chessever.com/news/9007199254740992/story',
        'https://chessever.com/news/7/title/extra',
        'https://chessever.com/news/7/a%2fb',
        'https://chessever.com/news/partners/unknown/7/story',
      ]) {
        expect(NewsLink.parse(Uri.parse(url)), isNull, reason: url);
      }
    },
  );
}
