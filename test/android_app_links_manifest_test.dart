import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The chessever.com App Link filters claim only what the app routes.
///
/// Up to 39.2.x both filters were host-only (`https://chessever.com`, every
/// path) and verified, so a plain VIEW intent for /account, /privacy-policy,
/// /terms-of-use or /desktop, which the app itself launches, resolved to
/// ChessEver, which has no route for those pages, and nothing opened.
void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final filters = RegExp(
    r'<intent-filter android:autoVerify="true">([\s\S]*?)</intent-filter>',
  ).allMatches(manifest).map((m) => m.group(1)!).toList();

  List<String> filtersFor(String host) => [
    for (final filter in filters)
      if (filter.contains('android:host="$host"')) filter,
  ];

  /// What a filter's path data matches, as Android reads `path` (exact) and
  /// `pathPrefix`.
  bool claims(String filter, String path) {
    final exact = RegExp(
      r'android:path="([^"]+)"',
    ).allMatches(filter).map((m) => m.group(1)!);
    final prefixes = RegExp(
      r'android:pathPrefix="([^"]+)"',
    ).allMatches(filter).map((m) => m.group(1)!);
    final patterns = RegExp(
      r'android:pathPattern="([^"]+)"',
    ).allMatches(filter).map((m) => m.group(1)!);
    expect(patterns, isEmpty, reason: 'keep the claims readable');
    return exact.contains(path) || prefixes.any(path.startsWith);
  }

  for (final host in ['chessever.com', 'www.chessever.com']) {
    group(host, () {
      test('has exactly one verified filter, scoped by path', () {
        final hostFilters = filtersFor(host);
        expect(hostFilters, hasLength(1));
        final filter = hostFilters.single;
        expect(filter, contains('android:scheme="https"'));
        expect(
          RegExp(r'android:path(Prefix)?="').hasMatch(filter),
          isTrue,
          reason: 'a host-only filter claims every chessever.com page',
        );
      });

      // Every shape DeepLinkService.handleDeepLink routes.
      for (final path in [
        '/games/XBnzfSW7',
        '/broadcast/titled-tuesday/mKgqPByN',
        '/broadcast/x/mKgqPByN/player/1503014',
        '/books/share-token',
        '/databases/folder-id',
        '/folders/folder-id',
        '/player/magnus-carlsen/1503014/games',
        '/collections/us-chess-championships',
        '/news',
        '/news/7/title',
        '/news/partners/rookreview/7/title',
        '/app',
        '/app/home/today',
        '/app/collections',
        '/webview',
      ]) {
        test('claims $path', () {
          expect(claims(filtersFor(host).single, path), isTrue);
        });
      }

      // Own pages the app opens itself, and other web-only pages.
      for (final path in [
        '/',
        '/account',
        '/privacy-policy',
        '/terms-of-use',
        '/desktop',
        '/download',
        '/premium',
        '/pricing',
        '/thank-you',
        '/updates/desktop/downloads/Chessever.dmg',
        '/apple-app-site-association',
        '/newsletter',
        '/application',
        '/auxnews/1/title',
      ]) {
        test('does not claim $path', () {
          expect(claims(filtersFor(host).single, path), isFalse);
        });
      }
    });
  }
}
