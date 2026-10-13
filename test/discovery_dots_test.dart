import 'dart:async';
import 'dart:convert';

import 'package:chessever2/services/discovery_dots/discovery_dot.dart';
import 'package:chessever2/services/discovery_dots/discovery_dots_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/discovery_dot.dart';
import 'package:chessever2/services/editorial_link_service.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _FakeSource implements DiscoveryDotsSource {
  _FakeSource(this.cached);

  String cached;
  final controller = StreamController<String>.broadcast();

  @override
  Future<String> initialize() async => cached;

  @override
  Future<String> fetch() async => cached;

  @override
  Stream<String> get updates => controller.stream;
}

class _MemoryStore implements DiscoveryDotsSeenStore {
  _MemoryStore([Map<String, int>? initial]) : seen = {...?initial};

  Map<String, int> seen;

  @override
  Map<String, int> read() => seen;

  @override
  Future<void> write(Map<String, int> value) async => seen = value;
}

String _config(List<Map<String, Object?>> dots) => jsonEncode({'dots': dots});

const _feed = {
  'id': 'feed',
  'rev': 1,
  'target': 'home.tab.discovery',
  'trail': ['home.nav.home'],
  'message': 'Swipe through the best games here.',
};

void main() {
  group('parseDiscoveryDots', () {
    test('reads a published dot', () {
      final dots = parseDiscoveryDots(_config([_feed]));
      expect(dots, hasLength(1));
      expect(dots.single.target, 'home.tab.discovery');
      expect(dots.single.trail, ['home.nav.home']);
      expect(dots.single.message, 'Swipe through the best games here.');
    });

    test('drops bad rows without losing good ones', () {
      final dots = parseDiscoveryDots(
        _config([
          {'id': 'no-target', 'rev': 1},
          {'id': 'zero-rev', 'rev': 0, 'target': 'a'},
          {'id': 'has@sign', 'rev': 1, 'target': 'a'},
          {'id': 'paused', 'rev': 1, 'target': 'a', 'enabled': false},
          _feed,
          {..._feed, 'message': 'duplicate id'},
        ]),
      );
      expect(dots.map((d) => d.id), ['feed']);
    });

    test('treats garbage as no dots', () {
      expect(parseDiscoveryDots(''), isEmpty);
      expect(parseDiscoveryDots('not json'), isEmpty);
      expect(parseDiscoveryDots('[]'), isEmpty);
      expect(parseDiscoveryDots('{"dots":"nope"}'), isEmpty);
    });

    test('a blank message means a silent dot', () {
      final dots = parseDiscoveryDots(
        _config([
          {..._feed, 'message': '   '},
        ]),
      );
      expect(dots.single.message, isNull);
    });
    test(
      'reads marker words and tooltip links; bad links do not become actions',
      () {
        final dot = parseDiscoveryDots(
          _config([
            {
              ..._feed,
              'label': 'NEW',
              'messages': [
                {
                  'body': 'See your game reports.',
                  'action_url': 'https://chessever.com/reports',
                },
                {'body': 'Unsafe link.', 'action_url': 'javascript:alert(1)'},
              ],
            },
          ]),
        ).single;
        expect(dot.label, 'NEW');
        expect(
          dot.tooltipMessages[0].actionUrl.toString(),
          'https://chessever.com/reports',
        );
        expect(dot.tooltipMessages[1].actionUrl, isNull);
        expect(discoveryNudgeLabel('TOO-LONG-WORD'), isNull);
        expect(discoveryNudgeLabel('Two words'), isNull);
        expect(discoveryNudgeLabel('New'), 'New');
      },
    );
  });

  group('visibility', () {
    final dot = parseDiscoveryDots(_config([_feed])).single;

    test('lights the target and its trail, nothing else', () {
      expect(litDiscoveryAnchors([dot], const {}), {
        'home.tab.discovery',
        'home.nav.home',
      });
    });

    test('passing a hop retires only that hop', () {
      final result = acknowledgeDiscoveryAnchor([dot], 'home.nav.home', {});
      expect(result.message, isNull);
      expect(litDiscoveryAnchors([dot], result.seen), {'home.tab.discovery'});
    });

    test('reaching the target retires the trail and returns the message', () {
      final result = acknowledgeDiscoveryAnchor(
        [dot],
        'home.tab.discovery',
        {},
      );
      expect(result.message, 'Swipe through the best games here.');
      expect(litDiscoveryAnchors([dot], result.seen), isEmpty);
    });

    test('a higher revision shows a dismissed dot again', () {
      final seen = acknowledgeDiscoveryAnchor(
        [dot],
        'home.tab.discovery',
        {},
      ).seen;
      final again = parseDiscoveryDots(
        _config([
          {..._feed, 'rev': 2},
        ]),
      ).single;
      expect(litDiscoveryAnchors([again], seen), {
        'home.tab.discovery',
        'home.nav.home',
      });
    });
    test('all messages at one target stack, while trail hops show none', () {
      final dots = parseDiscoveryDots(
        _config([
          {
            ..._feed,
            'messages': [
              {'body': 'First'},
              {'body': 'Second'},
            ],
          },
          {..._feed, 'id': 'another', 'message': 'Third'},
        ]),
      );
      expect(
        acknowledgeDiscoveryAnchor(dots, 'home.nav.home', {}).messages,
        isEmpty,
      );
      final result = acknowledgeDiscoveryAnchor(dots, 'home.tab.discovery', {});
      expect(result.messages.map((m) => m.body), ['First', 'Second', 'Third']);
      expect(litDiscoveryAnchors(dots, result.seen), isEmpty);
    });
  });

  test('discoveryDotId slugs a label inside its scope', () {
    expect(discoveryDotId('home.tab', 'My Space'), 'home.tab.my_space');
    expect(discoveryDotId('drawer', ' Rate us! '), 'drawer.rate_us');
  });

  group('DiscoveryDotAnchor', () {
    Future<(_FakeSource, _MemoryStore)> pumpTabs(
      WidgetTester tester, {
      List<Map<String, Object?>> dots = const [_feed],
      Map<String, int>? seen,
      EditorialLinkOpener? openLink,
    }) async {
      final source = _FakeSource(_config(dots));
      final store = _MemoryStore(seen);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discoveryDotsSourceProvider.overrideWithValue(source),
            discoveryDotsSeenStoreProvider.overrideWithValue(store),
            if (openLink != null)
              editorialLinkOpenerProvider.overrideWithValue(openLink),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 360,
                      child: SegmentedSwitcher(
                        dotScope: 'home.tab',
                        options: const ['My Space', 'Today', 'Discovery'],
                        initialSelection: 1,
                        onSelectionChanged: (_) {},
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      // Let the fake source's futures deliver the published dots.
      await tester.pump();
      await tester.pump();
      return (source, store);
    }

    Finder dotIn(String label) => find.descendant(
      of: find.ancestor(
        of: find.text(label),
        matching: find.byType(DiscoveryDotAnchor),
      ),
      matching: find.byType(DiscoveryDotMark),
    );

    testWidgets('shows a dot only on the published tab', (tester) async {
      await pumpTabs(tester);
      expect(dotIn('Discovery'), findsOneWidget);
      expect(dotIn('Today'), findsNothing);
      expect(dotIn('My Space'), findsNothing);
    });
    testWidgets(
      'NEW marker opens a paged tooltip and See routes its current link',
      (tester) async {
        final links = <Uri>[];
        await pumpTabs(
          tester,
          openLink: (context, uri) async {
            links.add(uri);
          },
          dots: [
            {
              ..._feed,
              'label': 'NEW',
              'messages': [
                {
                  'body': 'First tip',
                  'action_url': 'https://chessever.com/feed',
                },
                {
                  'body': 'Second tip',
                  'action_url': 'https://chessever.com/reports',
                },
              ],
            },
          ],
        );
        expect(find.text('NEW'), findsOneWidget);
        await tester.tap(find.text('Discovery'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('1/2'), findsOneWidget);
        expect(find.text('First tip'), findsOneWidget);
        await tester.tap(find.byTooltip('Next message'));
        await tester.pump();
        expect(find.text('2/2'), findsOneWidget);
        expect(find.text('Second tip'), findsOneWidget);
        await tester.tap(find.text('See'));
        await tester.pump(const Duration(milliseconds: 350));
        expect(links.map((uri) => uri.toString()), [
          'https://chessever.com/reports',
        ]);
        expect(find.text('2/2'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'the longest marker is whole, readable and inside the viewport',
      (tester) async {
        await pumpTabs(
          tester,
          dots: [
            {..._feed, 'label': 'UPCOMING'},
          ],
        );
        final marker = tester.getRect(find.text('UPCOMING'));
        final viewport =
            tester.view.physicalSize / tester.view.devicePixelRatio;
        expect(marker.left, greaterThanOrEqualTo(0));
        expect(marker.right, lessThanOrEqualTo(viewport.width));
        expect(marker.top, greaterThanOrEqualTo(0));
        expect(marker.bottom, lessThanOrEqualTo(viewport.height));
        final fade = tester.widget<FadeTransition>(
          find.descendant(
            of: find.byType(DiscoveryDotMark),
            matching: find.byType(FadeTransition),
          ),
        );
        expect(fade.opacity.value, 1);
      },
    );

    testWidgets(
      'an icon-sized control uses a circle instead of cropping the word',
      (tester) async {
        final source = _FakeSource(
          _config([
            {..._feed, 'label': 'UPCOMING'},
          ]),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              discoveryDotsSourceProvider.overrideWithValue(source),
              discoveryDotsSeenStoreProvider.overrideWithValue(_MemoryStore()),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  return Scaffold(
                    body: Center(
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: DiscoveryDotAnchor(
                          id: 'home.tab.discovery',
                          child: IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.info_outline),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        final marker = tester.widget<DiscoveryDotMark>(
          find.byType(DiscoveryDotMark),
        );
        expect(marker.label, isNull);
        expect(marker.semanticsLabel, 'UPCOMING');
        expect(tester.getSize(find.byType(DiscoveryDotMark)), const Size(8, 8));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('tapping the tab retires the dot and shows its message', (
      tester,
    ) async {
      final (_, store) = await pumpTabs(tester);
      await tester.tap(find.text('Discovery'));
      await tester.pump();

      expect(find.byType(DiscoveryDotMark), findsNothing);
      expect(find.text('Swipe through the best games here.'), findsOneWidget);
      expect(store.seen, {'feed': 1});

      // Touching anywhere dismisses the bubble.
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      expect(find.text('Swipe through the best games here.'), findsNothing);
    });

    testWidgets('the bubble leaves on its own', (tester) async {
      await pumpTabs(tester);
      await tester.tap(find.text('Discovery'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 7));
      expect(find.text('Swipe through the best games here.'), findsNothing);
    });

    testWidgets('a dot without a message just goes away', (tester) async {
      await pumpTabs(
        tester,
        dots: [
          {'id': 'quiet', 'rev': 1, 'target': 'home.tab.my_space'},
        ],
      );
      expect(dotIn('My Space'), findsOneWidget);
      await tester.tap(find.text('My Space'));
      await tester.pump();
      expect(find.byType(DiscoveryDotMark), findsNothing);
    });

    testWidgets('a dismissed dot stays gone until its revision is raised', (
      tester,
    ) async {
      final (source, _) = await pumpTabs(tester, seen: {'feed': 1});
      expect(find.byType(DiscoveryDotMark), findsNothing);

      source.controller.add(
        _config([
          {..._feed, 'rev': 2},
        ]),
      );
      await tester.pump();
      await tester.pump();
      expect(dotIn('Discovery'), findsOneWidget);
    });

    testWidgets('a dot never changes the layout of its surface', (
      tester,
    ) async {
      await pumpTabs(tester, dots: const []);
      final bare = tester.getRect(find.text('Discovery'));
      await pumpTabs(tester);
      expect(tester.getRect(find.text('Discovery')), bare);
    });
  });
}
