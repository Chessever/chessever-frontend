import 'package:chessever2/screens/for_you/discovery/discovery_share.dart';
import 'package:chessever2/screens/my_space/actions/space_component_share.dart';
import 'package:chessever2/services/app_destination.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every /app link the app shares must open somewhere for the person it is
/// sent to: an app route (parseAppDestination), and on the web either a page
/// chessever.com serves or a path the iOS associated domains claim. A path
/// with neither 404s for every iPhone and desktop recipient.
///
/// What chessever.com serves under /app (chessever_web_frontend origin/main,
/// src/app/app/** and next.config.ts redirects) and what its
/// apple-app-site-association claims, as of 2026-11-22. Update it with the
/// web change that adds a page or a claim.
const _webServedAppPaths = {
  '/app', // redirect
  '/app/feed',
  '/app/likes',
  '/app/miniatures',
  '/app/reports',
  '/app/news', // redirect, and claimed by the AASA
};

/// Shares the web cannot open yet: they need hand-off pages
/// (src/app/app/collections, src/app/app/my-space/[component]) and AASA
/// claims on the web. Listed so the gap is visible and no new share joins
/// it silently; remove each entry when its page ships.
const _knownWebGaps = {
  '/app/collections',
  '/app/my-space/prep',
  '/app/my-space/library',
  '/app/my-space/likes',
};

void main() {
  final shared = <String, Uri>{
    for (final c in DiscoveryShareDestination.values)
      'Discovery ${c.name}': discoveryShareUri(c),
    for (final c in SpaceComponent.values)
      'My Space ${c.name}': spaceComponentShareUri(c),
  };

  for (final entry in shared.entries) {
    test('${entry.key} (${entry.value.path}) opens in the app', () {
      expect(parseAppDestination(entry.value.toString()), isNotNull);
    });

    test('${entry.key} (${entry.value.path}) opens on the web', () {
      final path = entry.value.path;
      expect(
        _webServedAppPaths.contains(path) || _knownWebGaps.contains(path),
        isTrue,
        reason:
            '$path is no page chessever.com serves: add the web page and '
            'AASA claim first, or list it in _knownWebGaps with an owner',
      );
    });
  }

  test('a known gap that the web has closed is removed from the list', () {
    expect(_knownWebGaps.intersection(_webServedAppPaths), isEmpty);
  });
}
