import 'dart:async';
import 'dart:convert';

import 'package:chessever2/services/attention_policy.dart';
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

String _config(
  List<Map<String, Object?>> dots, [
  List<Map<String, Object?>> targeted = const [],
]) => jsonEncode({'dots': dots, if (targeted.isNotEmpty) 'targeted': targeted});

class _FakeMatcher implements DiscoveryAudienceMatcher {
  _FakeMatcher(this.answer);

  Set<String> Function(Map<String, String> audiences) answer;
  final asked = <Map<String, String>>[];

  @override
  Future<Set<String>> match(Map<String, String> audiences) async {
    asked.add(audiences);
    return answer(audiences);
  }
}

/// An account long past its quiet first week, with a fresh delivery memory.
List<Override> _settledAccount() => [
  accountCreatedAtProvider.overrideWithValue(DateTime.utc(2020)),
  discoveryDotsDeliveryStoreProvider.overrideWithValue(_MemoryStore()),
];

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

    test('standing on a hop retires every hop before it', () {
      // The published Prep nudge: Home (bottom bar) → My Space → My Prep → tab.
      final prep = parseDiscoveryDots(
        _config([
          {
            'id': 'prep',
            'rev': 1,
            'target': 'prep.tab.games',
            'trail': [
              'home.nav.home',
              'home.tab.my_space',
              'my_space.tile.my_prep',
            ],
          },
        ]),
      ).single;
      final result = acknowledgeDiscoveryAnchor(
        [prep],
        'my_space.tile.my_prep',
        {},
      );
      expect(litDiscoveryAnchors([prep], result.seen), {'prep.tab.games'});
    });

    test('the live Prep nudge clears the bottom bar once Prep is tapped', () {
      // Remote Config discovery_dots v12, verbatim.
      const live =
          '{"dots":[{"id":"prep","rev":1792285788580,'
          '"target":"my_space.tile.my_prep",'
          '"trail":["home.nav.home","home.tab.my_space"],'
          '"message":"","label":"","messages":[],"enabled":true,'
          '"name":"Prep"}]}';
      final dots = parseDiscoveryDots(live);
      expect(litDiscoveryAnchors(dots, const {}), {
        'home.nav.home',
        'home.tab.my_space',
        'my_space.tile.my_prep',
      });
      final result = acknowledgeDiscoveryAnchor(
        dots,
        'my_space.tile.my_prep',
        const {},
      );
      expect(litDiscoveryAnchors(dots, result.seen), isEmpty);
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
      bool onScreen = true,
    }) async {
      final source = _FakeSource(_config(dots));
      final store = _MemoryStore(seen);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discoveryDotsSourceProvider.overrideWithValue(source),
            discoveryDotsSeenStoreProvider.overrideWithValue(store),
            ..._settledAccount(),
            if (openLink != null)
              editorialLinkOpenerProvider.overrideWithValue(openLink),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: Center(
                    child: TickerMode(
                      enabled: onScreen,
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
              ..._settledAccount(),
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

    testWidgets('a tab the page opened on is reached without a tap', (
      tester,
    ) async {
      final (_, store) = await pumpTabs(
        tester,
        dots: const [
          {
            'id': 'today',
            'rev': 1,
            'target': 'home.tab.today',
            'trail': ['home.nav.home'],
            'message': 'Fresh games every morning.',
          },
        ],
      );
      await tester.pump();
      expect(dotIn('Today'), findsNothing);
      expect(store.seen['today'], 1);
      expect(find.text('Fresh games every morning.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('a selected tab behind another page is not reached', (
      tester,
    ) async {
      final (_, store) = await pumpTabs(
        tester,
        onScreen: false,
        dots: const [
          {'id': 'today', 'rev': 1, 'target': 'home.tab.today'},
        ],
      );
      await tester.pump();
      expect(dotIn('Today'), findsOneWidget);
      expect(store.seen, isEmpty);
    });

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

    testWidgets('a marker word never moves a baseline-aligned row', (
      tester,
    ) async {
      Future<_FakeSource> pumpRow(List<Map<String, Object?>> dots) async {
        final source = _FakeSource(_config(dots));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              discoveryDotsSourceProvider.overrideWithValue(source),
              discoveryDotsSeenStoreProvider.overrideWithValue(_MemoryStore()),
              ..._settledAccount(),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  return const Scaffold(
                    body: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('Before', style: TextStyle(fontSize: 24)),
                          DiscoveryDotAnchor(
                            id: 'home.tab.discovery',
                            child: Text('Discovery'),
                          ),
                          Text('After'),
                        ],
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
        return source;
      }

      List<Rect> rects() => [
        for (final label in ['Before', 'Discovery', 'After'])
          tester.getRect(find.text(label)),
      ];

      await pumpRow(const []);
      final bare = rects();

      final marked = {..._feed, 'label': 'NEW'};
      final source = await pumpRow([marked]);
      expect(find.text('NEW'), findsOneWidget);
      expect(rects(), bare);

      for (final dots in [
        [
          {...marked, 'enabled': false},
        ],
        <Map<String, Object?>>[],
        [marked],
      ]) {
        source.controller.add(_config(dots));
        await tester.pump();
        await tester.pump();
        expect(
          find.text('NEW'),
          dots.isEmpty || dots.single['enabled'] == false
              ? findsNothing
              : findsOneWidget,
        );
        expect(rects(), bare);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('audiences', () {
    final premiumAudience = 'a' * 64;
    final androidAudience = 'b' * 64;
    final premium = {
      'id': 'premium-reports',
      'rev': 1,
      'target': 'discovery.tile.reports',
      'audience_id': premiumAudience,
    };
    final android = {
      'id': 'android-prep',
      'rev': 1,
      'target': 'my_space.tile.my_prep',
      'audience_id': androidAudience,
    };

    test('targeted rows carry their audience id; damaged ones are dropped', () {
      final dots = parseDiscoveryDots(
        _config(
          [_feed],
          [
            premium,
            {...android, 'audience_id': ''},
            {...android, 'id': 'no-audience', 'audience_id': null},
            {...android, 'id': 'short-id', 'audience_id': 'premium'},
            {
              ...android,
              'id': 'inline-filters',
              'audience_id': null,
              'audience': {'platform': 'android'},
            },
            {...premium, 'target': 'duplicate.id'},
          ],
        ),
      );
      expect(dots.map((d) => d.id), ['feed', 'premium-reports']);
      expect(dots.first.targeted, isFalse);
      expect(dots.last.audienceId, premiumAudience);
    });

    test('a targeted dot shows only once the server matched it', () {
      final dots = parseDiscoveryDots(_config([_feed], [premium, android]));
      ids(Set<String>? matched) =>
          visibleDiscoveryDots(dots, matched).map((d) => d.id);
      expect(ids(null), ['feed']);
      expect(ids({}), ['feed']);
      expect(ids({'premium-reports'}), ['feed', 'premium-reports']);
    });

    Future<(ProviderContainer, _FakeSource, _FakeMatcher)> load({
      required String? viewer,
      required Set<String> Function(Map<String, String>) answer,
      List<Map<String, Object?>>? targeted,
      List<Map<String, Object?>> everyone = const [_feed],
    }) async {
      targeted ??= [premium, android];
      final source = _FakeSource(_config(everyone, targeted));
      final matcher = _FakeMatcher(answer);
      final container = ProviderContainer(
        overrides: [
          discoveryDotsSourceProvider.overrideWithValue(source),
          discoveryDotsSeenStoreProvider.overrideWithValue(_MemoryStore()),
          discoveryAudienceMatcherProvider.overrideWithValue(matcher),
          discoveryAudienceViewerProvider.overrideWith((ref) => viewer),
          ..._settledAccount(),
        ],
      );
      addTearDown(container.dispose);
      container.listen(discoveryDotsProvider, (_, _) {});
      await pumpEventQueue();
      return (container, source, matcher);
    }

    test(
      'lights the targeted dots the server matched for this person',
      () async {
        final (container, _, matcher) = await load(
          viewer: 'user-1',
          answer: (_) => {'premium-reports'},
          everyone: const [],
        );
        final lit = container.read(discoveryDotsProvider).lit;
        expect(lit, contains('discovery.tile.reports'));
        expect(lit, isNot(contains('my_space.tile.my_prep')));
        expect(matcher.asked.last, {
          'premium-reports': premiumAudience,
          'android-prep': androidAudience,
        });
        // The cached and fetched config are the same: one question, not two.
        expect(matcher.asked, hasLength(1));
      },
    );

    test('hides targeted dots with no account or a failed check', () async {
      final signedOut = await load(
        viewer: null,
        answer: (_) => {'premium-reports'},
      );
      expect(signedOut.$3.asked, isEmpty);
      expect(
        signedOut.$1.read(discoveryDotsProvider).lit,
        isNot(contains('discovery.tile.reports')),
      );
      final failing = await load(
        viewer: 'user-1',
        answer: (_) => throw StateError('offline'),
      );
      expect(failing.$1.read(discoveryDotsProvider).lit, {
        'home.tab.discovery',
        'home.nav.home',
      });
    });

    test('asks again when the published audiences change', () async {
      final (container, source, matcher) = await load(
        viewer: 'user-1',
        answer: (audiences) => audiences.keys.toSet(),
        everyone: const [],
      );
      // Both match; one campaign lights at a time, in publication order.
      expect(container.read(discoveryDotsProvider).lit, {
        'discovery.tile.reports',
      });
      matcher.answer = (_) => {};
      source.controller.add(
        _config(
          [_feed],
          [
            {...premium, 'audience_id': 'c' * 64},
          ],
        ),
      );
      await pumpEventQueue();
      expect(matcher.asked, hasLength(2));
      expect(
        container.read(discoveryDotsProvider).lit,
        isNot(contains('discovery.tile.reports')),
      );
    });
  });

  group('attention rules', () {
    const today = {'id': 'today', 'rev': 1, 'target': 'home.tab.today'};
    const prep = {'id': 'prep', 'rev': 1, 'target': 'my_space.tile.my_prep'};
    final now = DateTime.utc(2026, 10, 28, 12);
    final nowMs = now.millisecondsSinceEpoch;
    final day = const Duration(days: 1).inMilliseconds;

    /// One app launch: a fresh notifier over the device's [seen] and
    /// [delivered] memory.
    Future<(ProviderContainer, StateProvider<DateTime?>)> launch(
      List<Map<String, Object?>> dots, {
      required DateTime? createdAt,
      _MemoryStore? seen,
      _MemoryStore? delivered,
    }) async {
      final account = StateProvider<DateTime?>((ref) => createdAt);
      final container = ProviderContainer(
        overrides: [
          discoveryDotsSourceProvider.overrideWithValue(
            _FakeSource(_config(dots)),
          ),
          discoveryDotsSeenStoreProvider.overrideWithValue(
            seen ?? _MemoryStore(),
          ),
          discoveryDotsDeliveryStoreProvider.overrideWithValue(
            delivered ?? _MemoryStore(),
          ),
          attentionClockProvider.overrideWithValue(() => now),
          accountCreatedAtProvider.overrideWith((ref) => ref.watch(account)),
        ],
      );
      addTearDown(container.dispose);
      container.listen(discoveryDotsProvider, (_, _) {});
      await pumpEventQueue();
      return (container, account);
    }

    test(
      'a new account absorbs its first week; only later dots light',
      () async {
        final seen = _MemoryStore();
        final (first, _) = await launch(
          [_feed, today],
          createdAt: now.subtract(const Duration(days: 2)),
          seen: seen,
        );
        expect(first.read(discoveryDotsProvider).lit, isEmpty);
        expect(seen.seen, {'feed': 1, 'today': 1});

        final (later, _) = await launch(
          [_feed, today, prep],
          createdAt: now.subtract(const Duration(days: 8)),
          seen: seen,
        );
        expect(later.read(discoveryDotsProvider).lit, {
          'my_space.tile.my_prep',
        });
      },
    );

    test('dots wait for an account instead of guessing its age', () async {
      final seen = _MemoryStore();
      final (container, account) = await launch(
        [_feed],
        createdAt: null,
        seen: seen,
      );
      expect(container.read(discoveryDotsProvider).lit, isEmpty);
      expect(seen.seen, isEmpty);

      container.read(account.notifier).state = DateTime.utc(2020);
      await pumpEventQueue();
      expect(container.read(discoveryDotsProvider).lit, {
        'home.tab.discovery',
        'home.nav.home',
      });
    });

    test(
      'one campaign at a time; the next waits for the next launch',
      () async {
        final seen = _MemoryStore();
        final delivered = _MemoryStore();
        final (first, _) = await launch(
          [today, prep],
          createdAt: DateTime.utc(2020),
          seen: seen,
          delivered: delivered,
        );
        expect(first.read(discoveryDotsProvider).lit, {'home.tab.today'});
        first
            .read(discoveryDotsProvider.notifier)
            .acknowledge('home.tab.today');
        expect(first.read(discoveryDotsProvider).lit, isEmpty);

        final (next, _) = await launch(
          [today, prep],
          createdAt: DateTime.utc(2020),
          seen: seen,
          delivered: delivered,
        );
        expect(next.read(discoveryDotsProvider).lit, {'my_space.tile.my_prep'});
      },
    );

    test(
      'the first received campaign leads; a month unseen retires it',
      () async {
        final delivered = _MemoryStore({
          '1:today': nowMs - 2 * day,
          '1:prep': nowMs - 5 * day,
          '1:unpublished': nowMs - day,
        });
        final (container, _) = await launch(
          [today, prep],
          createdAt: DateTime.utc(2020),
          delivered: delivered,
        );
        expect(container.read(discoveryDotsProvider).lit, {
          'my_space.tile.my_prep',
        });
        expect(delivered.seen.keys, unorderedEquals(['1:today', '1:prep']));

        delivered.seen = {
          '1:today': nowMs - 2 * day,
          '1:prep': nowMs - 31 * day,
        };
        final (later, _) = await launch(
          [today, prep],
          createdAt: DateTime.utc(2020),
          delivered: delivered,
        );
        expect(later.read(discoveryDotsProvider).lit, {'home.tab.today'});
      },
    );

    test('a raised revision is received anew', () {
      final dots = parseDiscoveryDots(
        _config([
          {...today, 'rev': 2},
        ]),
      );
      expect(
        nextDiscoveryDot(
          dots,
          seen: const {'today': 1},
          delivered: {'1:today': nowMs - 40 * day},
          now: now,
          shelfLife: announcementShelfLife,
        )?.id,
        'today',
      );
    });
  });
}
