import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/collections/collection_bindings.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryPadlock;
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event_id.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/about_tour_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart'
    show RoundStatus;
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart'
    show PremiumResume;
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState, Session, User;

/// Books behind Premium, and books bound to events: the app side of the
/// superadmin Collections work. The server is the judge of who reads a
/// Premium book (it sees the session and the entitlement); the app shows
/// the preview and the paywall, never an error, when it says no.

// ------------------------------------------------------------------ http

/// Records every request and answers each with [answer]'s body and status.
class _Recorder implements HttpClientAdapter {
  _Recorder(this.answer);

  final (int, Object) Function(RequestOptions options) answer;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final (status, body) = answer(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _ok(Object? data) => {'status': 'success', 'data': data};

Map<String, Object?> _err(String message, String code) => {
  'status': 'error',
  'error': {'message': message, 'code': code},
};

// ------------------------------------------------------------------ fixtures

const _pgn = '''[Event "Casual"]
[White "Kasparov, Garry"]
[Black "Karpov, Anatoly"]
[Result "1-0"]

1. e4 e5 2. Nf3 Nc6 3. Bb5 1-0''';

CollectionGame _game(String id, String sectionId) => CollectionGame.fromCard(
  CollectionGameCard(
    id: id,
    sectionId: sectionId,
    white: const CollectionPlayerSide(
      name: 'Kasparov, Garry',
      key: 'name:kasparov, garry',
    ),
    black: const CollectionPlayerSide(
      name: 'Karpov, Anatoly',
      key: 'name:karpov, anatoly',
    ),
    pgn: _pgn,
  ),
)!;

const _sections = [
  CollectionSection(
    id: 'p1',
    kind: CollectionSectionKind.part,
    label: 'Part I',
    number: 'I',
    title: 'The Matches',
    orderIndex: 1,
    children: [
      CollectionSection(
        id: 'ch1',
        parentId: 'p1',
        kind: CollectionSectionKind.chapter,
        label: 'Chapter 1',
        number: '1',
        title: 'Moscow 1984',
        orderIndex: 1,
        gameCount: 3,
      ),
      CollectionSection(
        id: 'ch2',
        parentId: 'p1',
        kind: CollectionSectionKind.chapter,
        label: 'Chapter 2',
        number: '2',
        title: 'Moscow 1985',
        orderIndex: 2,
        gameCount: 1,
      ),
    ],
  ),
];

const _events = [
  CollectionEventRef(
    linkId: 'l1',
    title: 'World Championship 1985',
    location: 'Moscow',
    note: 'Game 16 is the octopus knight.',
    open: CollectionEventOpen.database(
      eventName: 'World Championship 1985',
      site: 'Moscow URS',
    ),
  ),
];

Collection _book({
  bool? contentLocked,
  String? lockReason,
  CollectionAccess? access,
  List<CollectionEventRef> events = const [],
}) => Collection(
  id: 'b1',
  slug: 'kasparov-karpov',
  kind: CollectionKind.book,
  title: 'Kasparov vs Karpov',
  author: 'Garry Kasparov',
  gameCount: 4,
  access: access,
  contentLocked: contentLocked,
  lockReason: lockReason,
  sections: _sections,
  events: events,
);

Collection _event({
  String location = 'Wijk aan Zee',
  DateTime? start,
  DateTime? end,
  String? author,
}) => Collection(
  id: 'e-$location',
  slug: 'event-$location',
  kind: CollectionKind.event,
  title: 'Tata Steel Masters',
  location: location,
  dateStart: start ?? DateTime(2024, 1, 13),
  dateEnd: end ?? DateTime(2024, 1, 28),
  author: author,
  gameCount: 91,
);

// ------------------------------------------------------------------ doubles

class _Repo extends CollectionsRepository {
  _Repo({
    required this.detail,
    this.gamesError,
    this.books = const [],
    this.booksError,
  }) : super(GamebaseRepository(Dio(), apiKey: 'test'));

  Collection detail;
  Object? gamesError;

  /// Thrown by [fetchBooksForEvent] while set.
  Object? booksError;
  final List<Collection> books;
  int detailCalls = 0;
  int gamesCalls = 0;
  int playersCalls = 0;
  final bookAnchors = <CollectionEventAnchors>[];

  /// Whether each read went out held fresh (see holdFreshAccess).
  final freshDetailReads = <bool>[];
  final freshGamesReads = <bool>[];

  @override
  Future<Collection> fetchCollection(String slug) async {
    detailCalls++;
    freshDetailReads.add(isFreshAccess(slug));
    return detail;
  }

  @override
  Future<List<CollectionGame>> fetchGames(String slug) async {
    gamesCalls++;
    freshGamesReads.add(isFreshAccess(slug));
    final e = gamesError;
    if (e != null) throw e;
    return [
      _game('g1', 'ch1'),
      _game('g2', 'ch1'),
      _game('g3', 'ch1'),
      _game('g4', 'ch2'),
    ];
  }

  @override
  Future<List<CollectionOpening>> fetchOpenings({String? slug}) async =>
      const [];

  @override
  Future<List<CollectionPlayer>> fetchPlayers(String slug) async {
    playersCalls++;
    final e = gamesError;
    if (e != null) throw e;
    return const [];
  }

  @override
  Future<List<Collection>> fetchBooksForEvent(
    CollectionEventAnchors anchors,
  ) async {
    bookAnchors.add(anchors);
    final e = booksError;
    if (e != null) throw e;
    return books;
  }
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription(bool subscribed)
    : super(SubscriptionState(isSubscribed: subscribed, isLoading: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _EngineSettings extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoSpoilers extends EventNoSpoilersController {
  _NoSpoilers({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

CloudEval _eval(String fen) => CloudEval(
  fen: fen,
  knodes: 0,
  depth: 20,
  pvs: [Pv(moves: 'e2e4', cp: 40)],
  requestedMultiPv: 1,
);

/// One paywall request: what the page asked it to unlock.
typedef _Unlock = ({String? featureId, String? returnTo, PremiumResume? then});

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required _Repo repo,
  required bool subscribed,
  required Widget Function() home,
  List<_Unlock>? unlocks,
  List<Override> overrides = const [],
  Size size = const Size(390, 2400),
  double textScale = 1,
  ThemeData? theme,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      ...overrides,
      collectionsRepositoryProvider.overrideWithValue(repo),
      subscriptionProvider.overrideWith((ref) => _Subscription(subscribed)),
      spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
      boardSettingsProviderNew.overrideWith(_BoardSettings.new),
      engineSettingsProviderNew.overrideWith(_EngineSettings.new),
      eventNoSpoilersProvider.overrideWith(
        (ref, tourId) => _NoSpoilers(ref: ref, tourId: tourId),
      ),
      gameCardEvalWithStockfishFallbackProvider.overrideWith(
        (ref, fen) async => _eval(fen),
      ),
      gameCardEvalCacheOnlyProvider.overrideWith(
        (ref, fen) async => _eval(fen),
      ),
      if (unlocks != null)
        collectionUnlockProvider.overrideWithValue((
          context,
          ref, {
          featureId,
          returnTo,
          onEntitled,
        }) async {
          unlocks.add((
            featureId: featureId,
            returnTo: returnTo,
            then: onEntitled,
          ));
          return false;
        }),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        routes: {
          '/tournament_detail_screen': (_) =>
              const Scaffold(body: Text('TOURNAMENT PAGE')),
        },
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Directionality(textDirection: direction, child: child!),
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return home();
          },
        ),
      ),
    ),
  );
  await _settle(tester);
  return container;
}

/// Game cards and springs keep scheduling frames, so the page is given a
/// fixed run of frames rather than waiting for silence.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _showTab(WidgetTester tester, String tab) async {
  if (const ['Events', 'Collections', 'Players'].contains(tab)) {
    final strip = find.descendant(
      of: find.byType(SegmentedSwitcher),
      matching: find.text('About'),
    );
    await tester.ensureVisible(strip.first);
    await _settle(tester);
    await tester.tap(strip.first);
    await _settle(tester);
    final action = find.widgetWithText(TextButton, tab);
    await tester.ensureVisible(action);
    await tester.tap(action);
    await _settle(tester);
    return;
  }
  await tester.ensureVisible(find.text(tab).first);
  await _settle(tester);
  await tester.tap(find.text(tab).first);
  await _settle(tester);
}

/// Game cards leave short timers behind; take the tree down and let them run.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

Finder _rich(String text) => find.textContaining(text, findRichText: true);

/// A widget test that takes its tree down at the end.
void _widgetTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    await _teardown(tester);
  });
}

// ------------------------------------------------------------------ tests

/// Card lines are measured in Inter; the test font's square glyphs are far
/// wider and would cut dates the app never cuts.
Future<void> _loadInter() async {
  final loader = FontLoader('InterDisplay');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    final bytes = File('assets/fonts/Inter-$weight.otf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadInter);

  group('models', () {
    test('access: books default to Premium, events to free', () {
      Collection parse(Map<String, dynamic> extra) =>
          Collection.fromJson({'id': 'x', 'slug': 'x', ...extra});
      expect(parse({'kind': 'book'}).access, CollectionAccess.premium);
      expect(parse({'kind': 'event'}).access, CollectionAccess.free);
      expect(
        parse({'kind': 'book', 'access': 'free'}).access,
        CollectionAccess.free,
      );
      expect(
        parse({'kind': 'event', 'access': 'premium'}).access,
        CollectionAccess.premium,
      );
      // An unknown value never opens a book.
      expect(
        parse({'kind': 'book', 'access': 'gold'}).access,
        CollectionAccess.premium,
      );
      expect(parse({'kind': 'book'}).contentLocked, isNull);
      expect(
        parse({'kind': 'book', 'contentLocked': true}).contentLocked,
        true,
      );
      expect(
        parse({'kind': 'book', 'contentLocked': false}).contentLocked,
        false,
      );
      final refused = parse({
        'kind': 'book',
        'contentLocked': true,
        'lockReason': 'auth_required',
      });
      expect(refused.lockReason, 'auth_required');
      expect(refused.lockedForSignIn, isTrue);
      expect(
        parse({
          'kind': 'book',
          'contentLocked': true,
          'lockReason': 'premium_required',
        }).lockedForSignIn,
        isFalse,
      );
      expect(parse({'kind': 'book'}).lockReason, isNull);
    });

    test('detail parses the bound events and where each one opens', () {
      final c = Collection.fromJson({
        'id': 'b1',
        'slug': 'wc-matches',
        'kind': 'book',
        'eventCount': 5,
        'events': [
          {
            'linkId': 'l1',
            'title': 'World Championship 2024',
            'location': 'Singapore',
            'dateStart': '2024-11-25',
            'dateEnd': '2024-12-13',
            'note': 'Game 14 decided it.',
            'open': {
              'kind': 'broadcast',
              'groupBroadcastId': 'gb_abcd1234',
              'tourId': 'abcd1234',
            },
          },
          {
            'linkId': 'l2',
            'title': 'Candidates 2024',
            'open': {'kind': 'broadcast_slug', 'slug': 'candidates-2024'},
          },
          {
            'linkId': 'l3',
            'title': 'Linares 1994',
            'open': {
              'kind': 'database',
              'eventName': 'Linares',
              'site': 'Linares ESP',
            },
          },
          {
            'linkId': 'l4',
            'title': 'US Championship 2025',
            'open': {'kind': 'collection', 'slug': 'us-2025'},
          },
          {
            'linkId': 'l5',
            'title': 'Somewhere',
            'open': {'kind': 'hologram'},
          },
          {'linkId': 'l6'},
          'not a map',
        ],
      });
      expect(c.eventCount, 5);
      expect(c.events.map((e) => e.linkId), ['l1', 'l2', 'l3', 'l4', 'l5']);
      final wc = c.events[0];
      expect(wc.note, 'Game 14 decided it.');
      expect(wc.dateStart, DateTime(2024, 11, 25));
      expect(wc.open!.kind, CollectionEventOpenKind.broadcast);
      expect(wc.open!.groupBroadcastId, 'gb_abcd1234');
      expect(wc.open!.tourId, 'abcd1234');
      expect(c.events[1].open!.kind, CollectionEventOpenKind.broadcastSlug);
      expect(c.events[1].open!.slug, 'candidates-2024');
      expect(c.events[2].open!.eventName, 'Linares');
      expect(c.events[2].open!.site, 'Linares ESP');
      expect(c.events[3].open!.kind, CollectionEventOpenKind.collection);
      // Shown, but with nowhere to go.
      expect(c.events[4].open, isNull);
    });

    test('for-event rows carry the note and the link', () {
      final books = collectionsForEventFromJson({
        'books': [
          {
            'id': 'b1',
            'slug': 'kasparov-karpov',
            'kind': 'book',
            'title': 'Kasparov vs Karpov',
            'access': 'premium',
            'note': 'Chapter 3 is this match.',
            'linkId': 'l1',
          },
          {'title': 'no id: dropped'},
        ],
      });
      expect(books, hasLength(1));
      expect(books.single.note, 'Chapter 3 is this match.');
      expect(books.single.linkId, 'l1');
      expect(books.single.isPremium, isTrue);
    });

    test('an error envelope keeps its code', () {
      CollectionsRequestException thrown(String code) {
        try {
          unwrapCollectionsEnvelope(_err('No', code), statusCode: 403);
        } on CollectionsRequestException catch (e) {
          return e;
        }
        fail('did not throw');
      }

      expect(thrown('premium_required').isPremiumGate, isTrue);
      expect(thrown('auth_required').isPremiumGate, isTrue);
      expect(thrown('access_check_unavailable').isPremiumGate, isFalse);
      expect(
        thrown('access_check_unavailable').isAccessCheckUnavailable,
        isTrue,
      );
      expect(thrown('not_found').isPremiumGate, isFalse);
      expect(isCollectionPremiumGate(thrown('premium_required')), isTrue);
      expect(isCollectionPremiumGate(Exception('403')), isFalse);
    });

    test('anchors are trimmed, deduplicated, sorted and capped', () {
      final a = CollectionEventAnchors(
        groups: [' gb_b ', 'gb_a', 'gb_b', '', null],
        tours: ['t2', 't1'],
        slugs: ['Sinquefield-Cup-2026', 'sinquefield-cup-2026'],
        events: ['x' * 300],
        site: '  Saint Louis USA ',
      );
      expect(a.groups, ['gb_a', 'gb_b']);
      expect(a.tours, ['t1', 't2']);
      expect(a.slugs, ['sinquefield-cup-2026']);
      expect(a.events.single.length, CollectionEventAnchors.maxLength);
      expect(a.site, 'Saint Louis USA');
      final many = CollectionEventAnchors(
        tours: [
          for (var i = 0; i < 40; i++) 't${i.toString().padLeft(2, '0')}',
        ],
      );
      expect(many.tours, hasLength(CollectionEventAnchors.maxValues));

      // Two pages naming the same event share one cache entry.
      final b = CollectionEventAnchors(
        groups: ['gb_a', 'gb_b'],
        tours: ['t1', 't2'],
        slugs: ['sinquefield-cup-2026'],
        events: ['x' * 300],
        site: 'Saint Louis USA',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      expect(a.toQuery(), {
        'group': ['gb_a', 'gb_b'],
        'tour': ['t1', 't2'],
        'slug': ['sinquefield-cup-2026'],
        'event': ['x' * CollectionEventAnchors.maxLength],
        'site': ['Saint Louis USA'],
        'kind': ['book'],
      });
      // A Site alone narrows nothing and is not sent.
      expect(CollectionEventAnchors(groups: ['g'], site: 'Moscow').toQuery(), {
        'group': ['g'],
        'kind': ['book'],
      });
      expect(CollectionEventAnchors(site: 'Moscow').isEmpty, isTrue);
    });

    test(
      'the server verdict decides; the app guesses only until it has it',
      () {
        bool locked(
          Collection c, {
          bool subscribed = false,
          bool loading = false,
        }) => isCollectionLocked(
          c,
          isSubscribed: subscribed,
          subscriptionLoading: loading,
        );

        // A free collection is never locked.
        expect(locked(_book(access: CollectionAccess.free)), isFalse);
        // No verdict yet: locked for a viewer known not to subscribe, open for
        // a subscriber and while the subscription loads (no lock flash).
        expect(locked(_book()), isTrue);
        expect(locked(_book(), subscribed: true), isFalse);
        expect(locked(_book(), loading: true), isFalse);
        // The verdict wins either way.
        expect(locked(_book(contentLocked: false)), isFalse);
        expect(locked(_book(contentLocked: true), subscribed: true), isTrue);
      },
    );
  });

  group('repository', () {
    test('sends the session as a bearer on the gated reads only', () async {
      final http = _Recorder((o) {
        if (o.path.endsWith('/games')) {
          return (
            200,
            _ok({'items': [], 'total': 0, 'limit': 200, 'offset': 0}),
          );
        }
        if (o.path.endsWith('/players')) return (200, _ok({'items': []}));
        return (200, _ok({'id': 'b1', 'slug': 'b1', 'kind': 'book'}));
      });
      final repo = CollectionsRepository(
        GamebaseRepository(Dio()..httpClientAdapter = http, apiKey: 'test'),
        accessToken: () => 'session-jwt',
      );
      await repo.fetchCollection('b1');
      await repo.fetchGames('b1');
      await repo.fetchPlayers('b1');
      expect(http.requests, hasLength(3));
      for (final r in http.requests) {
        expect(r.headers['Authorization'], 'Bearer session-jwt');
        expect(r.headers['X-API-Key'], 'test');
      }

      final guest = _Recorder(
        (o) => (200, _ok({'id': 'b1', 'slug': 'b1', 'kind': 'book'})),
      );
      await CollectionsRepository(
        GamebaseRepository(Dio()..httpClientAdapter = guest, apiKey: 'test'),
        accessToken: () => null,
      ).fetchCollection('b1');
      expect(guest.requests.single.headers.containsKey('Authorization'), false);
    });

    test('a fresh hold asks the server to judge Premium anew, until it is '
        'released', () async {
      final http = _Recorder((o) {
        if (o.path.endsWith('/games')) {
          return (
            200,
            _ok({'items': [], 'total': 0, 'limit': 200, 'offset': 0}),
          );
        }
        if (o.path.endsWith('/players')) return (200, _ok({'items': []}));
        return (200, _ok({'id': 'b1', 'slug': 'b1', 'kind': 'book'}));
      });
      final repo = CollectionsRepository(
        GamebaseRepository(Dio()..httpClientAdapter = http, apiKey: 'test'),
        accessToken: () => 'jwt',
      );
      await repo.fetchCollection('b1');
      final release = repo.holdFreshAccess('b1');
      await repo.fetchCollection('b1');
      await repo.fetchGames('b1');
      await repo.fetchPlayers('b1');
      // Another book's reads are not affected.
      await repo.fetchCollection('b2');
      release();
      release(); // a second release does nothing
      await repo.fetchCollection('b1');

      String? cacheControl(RequestOptions r) => r.headers['Cache-Control'];
      expect(http.requests.map(cacheControl), [
        null,
        'no-cache',
        'no-cache',
        'no-cache',
        null,
        null,
      ]);
      expect(http.requests[1].headers['Pragma'], 'no-cache');
      expect(repo.isFreshAccess('b1'), isFalse);
    });

    test('a Premium refusal surfaces as the paywall gate', () async {
      final http = _Recorder(
        (o) => (403, _err('Premium required', 'premium_required')),
      );
      final repo = CollectionsRepository(
        GamebaseRepository(Dio()..httpClientAdapter = http, apiKey: 'test'),
        accessToken: () => 'jwt',
      );
      await expectLater(
        repo.fetchGames('b1'),
        throwsA(
          isA<CollectionsRequestException>()
              .having((e) => e.isPremiumGate, 'isPremiumGate', isTrue)
              .having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('books for an event: every anchor repeats its key', () async {
      final http = _Recorder(
        (o) => (
          200,
          _ok({
            'books': [
              {
                'id': 'b1',
                'slug': 'kasparov-karpov',
                'kind': 'book',
                'title': 'Kasparov vs Karpov',
                'note': 'The 1985 match.',
                'linkId': 'l1',
              },
            ],
          }),
        ),
      );
      final repo = CollectionsRepository(
        GamebaseRepository(Dio()..httpClientAdapter = http, apiKey: 'test'),
        accessToken: () => null,
      );
      final books = await repo.fetchBooksForEvent(
        CollectionEventAnchors(
          groups: ['gb_abcd1234'],
          tours: ['abcd1234', 'efgh5678'],
          slugs: ['world-championship-1985'],
        ),
      );
      expect(books.single.note, 'The 1985 match.');
      final uri = http.requests.single.uri;
      expect(uri.path, '/api/collections/for-event');
      expect(uri.queryParametersAll['tour'], ['abcd1234', 'efgh5678']);
      expect(uri.queryParametersAll['group'], ['gb_abcd1234']);
      expect(uri.queryParametersAll['slug'], ['world-championship-1985']);
      expect(uri.queryParametersAll['kind'], ['book']);

      // Nothing to look for: no request at all.
      expect(await repo.fetchBooksForEvent(CollectionEventAnchors()), isEmpty);
      expect(http.requests, hasLength(1));
    });

    group('the session token', () {
      final now = DateTime.utc(2026, 9, 26, 12);
      Session session(String token, {required Duration expiresIn}) => Session(
        accessToken: token,
        tokenType: 'bearer',
        user: const User(
          id: 'u1',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      )..expiresAt = now.add(expiresIn).millisecondsSinceEpoch ~/ 1000;

      test('a live token goes as it is, at once', () async {
        final live = session('live', expiresIn: const Duration(minutes: 30));
        final changes = StreamController<AuthState>.broadcast();
        addTearDown(changes.close);
        expect(
          await freshSessionToken(
            current: () => live,
            changes: changes.stream,
            now: () => now,
          ),
          'live',
        );
      });

      test('a spent token waits for the SDK to refresh it', () async {
        var current = session('spent', expiresIn: const Duration(seconds: 2));
        final changes = StreamController<AuthState>.broadcast();
        addTearDown(changes.close);
        final token = freshSessionToken(
          current: () => current,
          changes: changes.stream,
          now: () => now,
        );
        await Future<void>.delayed(Duration.zero);
        // A replayed state that is spent too does not end the wait.
        changes.add(AuthState(AuthChangeEvent.initialSession, current));
        await Future<void>.delayed(Duration.zero);
        current = session('fresh', expiresIn: const Duration(hours: 1));
        changes.add(AuthState(AuthChangeEvent.tokenRefreshed, current));
        expect(await token, 'fresh');
      });

      test('no refresh in time: the token it holds goes', () async {
        final spent = session('spent', expiresIn: -const Duration(minutes: 1));
        final changes = StreamController<AuthState>.broadcast();
        addTearDown(changes.close);
        expect(
          await freshSessionToken(
            current: () => spent,
            changes: changes.stream,
            now: () => now,
            wait: const Duration(milliseconds: 20),
          ),
          'spent',
        );
      });

      test('signed out: no token', () async {
        final changes = StreamController<AuthState>.broadcast();
        addTearDown(changes.close);
        expect(
          await freshSessionToken(current: () => null, changes: changes.stream),
          isNull,
        );
      });
    });

    test('an event page names its group, its tours and their slugs', () {
      Tour tour(String id, String slug) =>
          Tour.virtual(id: id, name: slug, slug: slug, dates: [], players: []);
      final broadcast = GroupBroadcast(
        id: 'gb_abcd1234',
        createdAt: DateTime(2026),
        name: 'Sinquefield Cup 2026',
        search: const [],
      );
      final anchors = collectionAnchorsForEvent(
        broadcast: broadcast,
        tours: [
          tour('abcd1234', 'sinquefield-cup-2026'),
          tour('efgh5678', 'sinquefield-cup-2026--rapid'),
        ],
      );
      expect(anchors.groups, ['gb_abcd1234']);
      expect(anchors.tours, ['abcd1234', 'efgh5678']);
      expect(anchors.slugs, [
        'sinquefield-cup-2026',
        'sinquefield-cup-2026--rapid',
      ]);

      // A database event on the same page: its PGN Event name and Site.
      final virtual = GroupBroadcast(
        id: virtualBroadcastId('Linares', site: 'Linares ESP'),
        createdAt: DateTime(2026),
        name: 'Linares',
        search: const [],
      );
      final db = collectionAnchorsForEvent(
        broadcast: virtual,
        tours: [tour(virtual.id, 'Linares')],
      );
      expect(db.events, ['Linares']);
      expect(db.site, 'Linares ESP');
      expect(db.groups, isEmpty);
      expect(db.tours, isEmpty);

      expect(collectionAnchorsForEvent(broadcast: null).isEmpty, isTrue);
    });
  });

  group('a Premium book', () {
    for (final subscribed in [false, true]) {
      _widgetTest(
        'same shared game preview, no browse-time unlock paid=$subscribed',
        (tester) async {
          final repo = _Repo(
            detail: _book(contentLocked: !subscribed, events: _events),
          );
          await _pump(
            tester,
            repo: repo,
            subscribed: subscribed,
            home: () => CollectionScreen(collection: _book()),
          );
          expect(find.byType(DiscoveryGameList), findsWidgets);
          expect(find.byType(DiscoveryPadlock), findsNothing);
          expect(find.byKey(const ValueKey('collection_unlock')), findsNothing);
          expect(find.textContaining('Read all'), findsNothing);
          expect(repo.gamesCalls, 1);
          await _showTab(tester, 'About');
          expect(find.text('by Garry Kasparov'), findsOneWidget);
          expect(find.text('4 games'), findsOneWidget);
          expect(find.byKey(const ValueKey('collection_unlock')), findsNothing);
        },
      );
    }
    _widgetTest(
      'denied metadata is an honest retry, not substitute event rows',
      (tester) async {
        final repo = _Repo(
          detail: _book(),
          gamesError: const CollectionsRequestException(
            'Premium required',
            statusCode: 403,
            code: 'premium_required',
          ),
        );
        await _pump(
          tester,
          repo: repo,
          subscribed: false,
          home: () => CollectionScreen(collection: _book()),
        );
        expect(
          find.text("Game previews aren't available from this server yet."),
          findsOneWidget,
        );
        expect(find.text('Try again'), findsOneWidget);
        expect(find.byType(DiscoveryPadlock), findsNothing);
        expect(find.byKey(const ValueKey('collection_unlock')), findsNothing);
        expect(_rich('Moscow 1984'), findsNothing);
      },
    );
  });

  group('bindings', () {
    _widgetTest('a book lists its events on its Events tab; one opens', (
      tester,
    ) async {
      final repo = _Repo(detail: _book(contentLocked: false, events: _events));
      final container = await _pump(
        tester,
        repo: repo,
        subscribed: true,
        home: () => CollectionScreen(collection: _book()),
      );
      // On their own tab now, not under the About text.
      await _showTab(tester, 'About');
      expect(find.text('World Championship 1985'), findsNothing);
      await _showTab(tester, 'Events');
      expect(find.text('World Championship 1985'), findsOneWidget);
      expect(find.text('Game 16 is the octopus knight.'), findsOneWidget);

      await tester.tap(find.text('World Championship 1985'));
      await _settle(tester);
      // A database event opens on the tournament page, backed by the
      // game database under its Event name and Site.
      expect(find.text('TOURNAMENT PAGE'), findsOneWidget);
      final opened = container.read(selectedBroadcastModelProvider)!;
      final key = virtualEventKeyFromId(opened.id)!;
      expect(key.eventName, 'World Championship 1985');
      expect(key.site, 'Moscow URS');
    });

    _widgetTest('an event page shows the books bound to it', (tester) async {
      final repo = _Repo(
        detail: _book(),
        books: [
          Collection.fromJson({
            'id': 'b1',
            'slug': 'kasparov-karpov',
            'kind': 'book',
            'title': 'Kasparov vs Karpov',
            'author': 'Garry Kasparov',
            'gameCount': 4,
            'note': 'The 1985 match, move by move.',
            'linkId': 'l1',
          }),
        ],
      );
      final anchors = CollectionEventAnchors(
        groups: ['gb_abcd1234'],
        tours: ['abcd1234'],
      );
      await _pump(
        tester,
        repo: repo,
        subscribed: false,
        home: () => Scaffold(
          body: ListView(
            children: [
              CollectionBooksSection(
                anchors: anchors,
                titleStyle: const TextStyle(),
              ),
            ],
          ),
        ),
      );
      expect(repo.bookAnchors, [anchors]);
      // One book: its heading says so, as a book's page says "Event".
      expect(find.text('Collection'), findsOneWidget);
      expect(find.text('Collections'), findsNothing);
      expect(find.text('Kasparov vs Karpov'), findsOneWidget);
      expect(find.text('The 1985 match, move by move.'), findsOneWidget);
      // Premium, and this viewer is not.
      expect(find.byType(DiscoveryPadlock), findsNothing);

      // The book opens on its preview.
      await tester.tap(find.text('Kasparov vs Karpov'));
      await _settle(tester);
      expect(find.byType(CollectionScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('collection_unlock')), findsNothing);
    });

    _widgetTest('the event About tab lists its books under its facts', (
      tester,
    ) async {
      final broadcast = GroupBroadcast(
        id: 'gb_abcd1234',
        createdAt: DateTime(2026),
        name: 'World Championship 1985',
        search: const [],
      );
      Tour tour(String id, String slug) =>
          Tour.virtual(id: id, name: slug, slug: slug, dates: [], players: []);
      final repo = _Repo(
        detail: _book(),
        books: [
          Collection.fromJson({
            'id': 'b1',
            'slug': 'kasparov-karpov',
            'kind': 'book',
            'title': 'Kasparov vs Karpov',
            'author': 'Garry Kasparov',
            'gameCount': 4,
            'note': 'The 1985 match, move by move.',
          }),
        ],
      );
      await _pump(
        tester,
        repo: repo,
        subscribed: true,
        overrides: [
          selectedBroadcastModelProvider.overrideWith((ref) => broadcast),
          canonicalSelectedBroadcastProvider.overrideWith(
            (ref) async => broadcast,
          ),
          tourDetailScreenProviderOverride(
            TourDetailViewModel(
              aboutTourModel: const AboutTourModel(
                id: 'abcd1234',
                slug: 'world-championship-1985',
                name: 'World Championship 1985',
                description: '',
                imageUrl: '',
                players: [],
                timeControl: '120 min',
                date: 'Sep 3 - Nov 9, 1985',
                location: 'Moscow',
                websiteUrl: '',
                standingsUrl: '',
                tourUrl: '',
                groupBroadcastId: 'gb_abcd1234',
              ),
              liveTourIds: const [],
              tours: [
                TourModel(
                  tour: tour('abcd1234', 'world-championship-1985'),
                  roundStatus: RoundStatus.completed,
                ),
              ],
            ),
          ),
        ],
        home: () => const AboutTourScreen(),
      );
      expect(repo.bookAnchors.single.groups, ['gb_abcd1234']);
      expect(repo.bookAnchors.single.tours, ['abcd1234']);
      expect(repo.bookAnchors.single.slugs, ['world-championship-1985']);
      expect(find.text('Collection'), findsOneWidget);
      expect(find.text('Kasparov vs Karpov'), findsOneWidget);
      expect(find.text('The 1985 match, move by move.'), findsOneWidget);
      // A subscriber's book wears no padlock.
      expect(find.byType(DiscoveryPadlock), findsNothing);
    });

    _widgetTest('an event with no books looks as it always did', (
      tester,
    ) async {
      final repo = _Repo(detail: _book());
      await _pump(
        tester,
        repo: repo,
        subscribed: false,
        home: () => Scaffold(
          body: CollectionBooksSection(
            anchors: CollectionEventAnchors(groups: ['gb_x']),
            titleStyle: const TextStyle(),
          ),
        ),
      );
      expect(find.text('Collections'), findsNothing);
      expect(find.text('Collection'), findsNothing);
      expect(
        find.byKey(const ValueKey('collection_books_section')),
        findsNothing,
      );
    });

    _widgetTest('two books are headed Books', (tester) async {
      Collection book(String id) => Collection.fromJson({
        'id': id,
        'slug': id,
        'kind': 'book',
        'title': 'Book $id',
        'gameCount': 4,
      });
      final repo = _Repo(detail: _book(), books: [book('b1'), book('b2')]);
      await _pump(
        tester,
        repo: repo,
        subscribed: true,
        home: () => Scaffold(
          body: ListView(
            children: [
              CollectionBooksSection(
                anchors: CollectionEventAnchors(groups: ['gb_x']),
                titleStyle: const TextStyle(),
              ),
            ],
          ),
        ),
      );
      expect(find.text('Collections'), findsOneWidget);
      expect(find.text('Collection'), findsNothing);
    });
  });

  group('cards, tabs and missing fields', () {
    test('foreword and bookCount parse when present, null when not', () {
      Collection parse(Map<String, dynamic> extra) =>
          Collection.fromJson({'id': 'x', 'slug': 'x', ...extra});
      final full = parse({
        'kind': 'book',
        'foreword': '  I wrote this book for you.\n\nRead it slowly.  ',
      });
      expect(full.foreword, 'I wrote this book for you.\n\nRead it slowly.');
      expect(parse({'kind': 'book'}).foreword, isNull);
      expect(parse({'kind': 'book', 'foreword': null}).foreword, isNull);
      expect(parse({'kind': 'book', 'foreword': '   '}).foreword, isNull);

      expect(parse({'kind': 'event', 'bookCount': 3}).bookCount, 3);
      expect(parse({'kind': 'event', 'bookCount': '2'}).bookCount, 2);
      // Not said is unknown, never "no books".
      expect(parse({'kind': 'event'}).bookCount, isNull);
      expect(parse({'kind': 'event', 'bookCount': null}).bookCount, isNull);
      expect(parse({'kind': 'event', 'bookCount': 'many'}).bookCount, isNull);

      // A row with nothing but its identity still reads.
      final bare = Collection.fromJson({'id': 'y'});
      expect(bare.slug, 'y');
      expect(bare.title, 'Untitled');
      expect(bare.author, isNull);
      expect(bare.coverUrl, isNull);
      expect(bare.bookCount, isNull);
      expect(bare.foreword, isNull);
      expect(bare.events, isEmpty);
    });

    _widgetTest('an event card: author and year, then games and '
        'books', (tester) async {
      final subtitled = Collection.fromJson({
        'id': 'e1',
        'slug': 'tata-2024',
        'kind': 'event',
        'title': 'Tata Steel Masters 2024',
        'subtitle': 'Fourteen players, one round-robin',
        'author': 'GM Durarbayli',
        'location': 'Wijk aan Zee',
        'dateStart': '2024-01-13',
        'dateEnd': '2024-01-28',
        'gameCount': 91,
        'bookCount': 2,
      });
      final bare = Collection.fromJson({
        'id': 'e2',
        'slug': 'unknown',
        'kind': 'event',
        'title': 'An event with no place or dates',
        'subtitle': 'Played online',
        'gameCount': 1,
        'bookCount': 0,
      });
      await _pump(
        tester,
        repo: _Repo(detail: _book()),
        subscribed: false,
        home: () => Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CollectionCard(collection: subtitled),
              CollectionCard(collection: bare),
            ],
          ),
        ),
      );
      // The subtitle never hides who wrote it, which year, or where.
      // (The identity may wrap at the separator, so match its parts.)
      expect(find.textContaining('Durarbayli'), findsOneWidget);
      // The year: once in the title, once in the identity line.
      expect(find.textContaining('2024'), findsNWidgets(2));
      expect(find.textContaining('Wijk aan Zee'), findsOneWidget);
      expect(find.textContaining('13-28'), findsNothing);
      expect(find.text('Fourteen players, one round-robin'), findsNothing);
      expect(find.text('91 games · 2 collections'), findsOneWidget);
      // Neither author, place nor dates: the subtitle stands in; no count.
      expect(find.text('Played online'), findsOneWidget);
      expect(find.text('1 game'), findsOneWidget);
      expect(find.textContaining('collection'), findsOneWidget);
    });

    _widgetTest('a book card: the author, its bound events, an event plate '
        'whatever it lacks', (tester) async {
      final counted = Collection.fromJson({
        'id': 'b1',
        'slug': 'kk',
        'kind': 'book',
        'title': 'Kasparov vs Karpov',
        'author': 'Garry Kasparov',
        'gameCount': 55,
        'eventCount': 2,
      });
      final named = Collection.fromJson({
        'id': 'b2',
        'slug': 'kk2',
        'kind': 'book',
        'title': 'The Match',
        'author': 'Anatoly Karpov',
        'gameCount': 24,
        'events': [
          {'linkId': 'l1', 'title': 'World Championship 1985'},
          {'linkId': 'l2', 'title': 'World Championship 1986'},
        ],
      });
      // No author, no cover, no events: title and count only.
      final bare = Collection.fromJson({
        'id': 'b3',
        'slug': 'bare',
        'kind': 'book',
        'title': 'Anonymous notes',
        'gameCount': 1,
      });
      await _pump(
        tester,
        repo: _Repo(detail: _book()),
        subscribed: true,
        size: const Size(320, 1200),
        textScale: 1.3,
        home: () => Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CollectionCard(collection: counted),
              CollectionCard(collection: named),
              CollectionCard(collection: bare),
            ],
          ),
        ),
      );
      expect(find.text('by Garry Kasparov'), findsOneWidget);
      expect(find.text('55 games · 2 events'), findsOneWidget);
      expect(find.text('by Anatoly Karpov'), findsOneWidget);
      // Named when the row carries them, and then not counted as well.
      expect(find.text('World Championship 1985 and 1 more'), findsOneWidget);
      expect(find.text('24 games'), findsOneWidget);
      expect(find.text('1 game'), findsOneWidget);
      expect(find.textContaining('by '), findsNWidgets(2));
      // Every plate uses the event proportions, including the pixel placeholder.
      final plates = find.descendant(
        of: find.byType(CollectionPlateRow),
        matching: find.byType(ClipRRect),
      );
      expect(plates, findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        final size = tester.getSize(plates.at(i));
        expect(size.width / size.height, closeTo(1.25, 0.01));
      }
      for (final card in tester.widgetList<CollectionPlateRow>(
        find.byType(CollectionPlateRow),
      )) {
        final row = find.byWidget(card);
        final rect = tester.getRect(row);
        for (final t in tester.widgetList<Text>(
          find.descendant(of: row, matching: find.byType(Text)),
        )) {
          final r = tester.getRect(find.byWidget(t));
          expect(
            rect.contains(r.topLeft) && rect.contains(r.bottomRight),
            isTrue,
            reason: t.data,
          );
        }
      }
    });

    List<String> tabLabels(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(
        find.descendant(
          of: find.byType(SegmentedSwitcher),
          matching: find.byType(Text),
        ),
      ))
        t.data!,
    ];

    _widgetTest('books and events share About, Games and Players tabs', (
      tester,
    ) async {
      await _pump(
        tester,
        repo: _Repo(detail: _book(contentLocked: false)),
        subscribed: true,
        home: () => CollectionScreen(collection: _book()),
      );
      // expect(tabLabels(tester), ['About', 'Openings', 'Games', 'Players']);
      expect(tabLabels(tester), ['About', 'Games', 'Players']);
      await _teardown(tester);

      await _pump(
        tester,
        repo: _Repo(detail: _event()),
        subscribed: false,
        home: () => CollectionScreen(collection: _event()),
      );
      expect(tabLabels(tester), ['About', 'Games', 'Players']);
      // A free event opens on its games, as it always did.
      expect(find.byType(DiscoveryGameList), findsWidgets);
      await _showTab(tester, 'Players');
      expect(find.text('No players in this collection yet.'), findsOneWidget);
    });

    _widgetTest('a book\'s About: every credit, the description, then the '
        'foreword', (tester) async {
      final book = Collection(
        id: 'b1',
        slug: 'kasparov-karpov',
        kind: CollectionKind.book,
        title: 'Kasparov vs Karpov',
        author: 'Garry Kasparov',
        annotator: 'Dmitry Plisetsky',
        publisher: 'Everyman Chess',
        publishedYear: 2008,
        // The team's own publish time is never the book's printed date.
        publishedAt: DateTime.utc(2026, 9, 1),
        gameCount: 4,
        contentLocked: true,
        about: 'The first two matches.',
        foreword: 'I owe this book to my trainers.\n\nAnd to Anatoly.',
        sections: _sections,
      );
      await _pump(
        tester,
        repo: _Repo(detail: book),
        subscribed: false,
        home: () => CollectionScreen(collection: book),
      );
      await _showTab(tester, 'About');
      expect(find.text('by Garry Kasparov'), findsOneWidget);
      expect(find.text('Annotated by Dmitry Plisetsky'), findsOneWidget);
      expect(find.text('Everyman Chess · 2008'), findsOneWidget);
      expect(find.textContaining('2026'), findsNothing);
      expect(find.text('Foreword'), findsOneWidget);
      expect(find.text('I owe this book to my trainers.'), findsOneWidget);
      expect(find.text('And to Anatoly.'), findsOneWidget);
      // The description leads; the foreword follows it.
      expect(
        tester.getTopLeft(find.text('The first two matches.')).dy,
        lessThan(tester.getTopLeft(find.text('Foreword')).dy),
      );
      // The preview is free: About, foreword and all, with the way in.
      expect(find.byKey(const ValueKey('collection_unlock')), findsNothing);
    });

    _widgetTest('a book with none of the optional fields: About shows what '
        'there is, Events says there are none', (tester) async {
      const bare = Collection(
        id: 'b9',
        slug: 'bare',
        kind: CollectionKind.book,
        title: 'Anonymous notes',
        contentLocked: false,
      );
      await _pump(
        tester,
        repo: _Repo(detail: bare),
        subscribed: true,
        home: () => CollectionScreen(collection: bare),
      );
      await _showTab(tester, 'About');
      expect(find.text('Anonymous notes'), findsWidgets);
      expect(find.text('Foreword'), findsNothing);
      expect(find.textContaining('by '), findsNothing);
      expect(find.byKey(const ValueKey('collection_foreword')), findsNothing);
      await _showTab(tester, 'Events');
      expect(find.text('No events for this collection yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _widgetTest('an event\'s Books tab lists its books with their notes; '
        'one opens on its page', (tester) async {
      final repo = _Repo(
        detail: _event(),
        books: [
          Collection.fromJson({
            'id': 'b1',
            'slug': 'kasparov-karpov',
            'kind': 'book',
            'title': 'Kasparov vs Karpov',
            'author': 'Garry Kasparov',
            'gameCount': 4,
            'note': 'Timman annotates round 7.',
          }),
        ],
      );
      await _pump(
        tester,
        repo: repo,
        subscribed: false,
        home: () => CollectionScreen(collection: _event()),
      );
      await _showTab(tester, 'Collections');
      expect(repo.bookAnchors.single.collections, ['e-Wijk aan Zee']);
      expect(find.text('Kasparov vs Karpov'), findsOneWidget);
      expect(find.text('by Garry Kasparov'), findsOneWidget);
      expect(find.text('Timman annotates round 7.'), findsOneWidget);
      // A Premium book for a viewer without Premium: the padlock.
      expect(find.byType(DiscoveryPadlock), findsNothing);

      repo.detail = _book();
      await tester.tap(find.text('Kasparov vs Karpov'));
      await _settle(tester);
      // The book's own page, on its preview.
      expect(
        find.byType(CollectionScreen, skipOffstage: false),
        findsNWidgets(2),
      );
      expect(find.byKey(const ValueKey('collection_unlock')), findsNothing);
    });

    _widgetTest('an event\'s Books tab: none, and a failure with a retry', (
      tester,
    ) async {
      final repo = _Repo(detail: _event(), booksError: Exception('offline'));
      await _pump(
        tester,
        repo: repo,
        subscribed: true,
        home: () => CollectionScreen(collection: _event()),
      );
      await _showTab(tester, 'Collections');
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('No collections about this event yet.'), findsNothing);

      repo.booksError = null;
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(repo.bookAnchors, hasLength(2));
      expect(find.text('No collections about this event yet.'), findsOneWidget);
    });

    _widgetTest('an event opened from a book waits for its id, then asks '
        'for its books', (tester) async {
      final repo = _Repo(detail: _event());
      // As a book's event link opens it: by slug, the id still to come.
      final bySlug = Collection(
        id: '',
        slug: 'event-Wijk aan Zee',
        kind: CollectionKind.event,
        title: 'Tata Steel Masters',
      );
      await _pump(
        tester,
        repo: repo,
        subscribed: true,
        home: () => CollectionScreen(collection: bySlug),
      );
      await _showTab(tester, 'Collections');
      expect(repo.bookAnchors.single.collections, ['e-Wijk aan Zee']);
      expect(find.text('No collections about this event yet.'), findsOneWidget);
    });
  });
}
