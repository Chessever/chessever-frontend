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
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
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
}) => Collection(
  id: 'e-$location',
  slug: 'event-$location',
  kind: CollectionKind.event,
  title: 'Tata Steel Masters',
  location: location,
  dateStart: start ?? DateTime(2024, 1, 13),
  dateEnd: end ?? DateTime(2024, 1, 28),
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
        theme: AppTheme.darkTheme,
        routes: {
          '/tournament_detail_screen': (_) =>
              const Scaffold(body: Text('TOURNAMENT PAGE')),
        },
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
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
  await tester.tap(find.text(tab).first);
  await _settle(tester);
}

/// Game cards leave short timers behind; take the tree down and let them run.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

Finder _rich(String text) => find.textContaining(text, findRichText: true);

const _confirming = 'Confirming your Premium\u2026';
const _confirmFailed = "Couldn't confirm your Premium just now.";

/// Lets [total] of fake time pass a second at a time, so the confirm's
/// backoff timers and the reads they start all run.
Future<void> _wait(WidgetTester tester, Duration total) async {
  for (var t = Duration.zero; t < total; t += const Duration(seconds: 1)) {
    await tester.pump(const Duration(seconds: 1));
  }
  await _settle(tester);
}

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
    _widgetTest('a free viewer gets the preview and never the games', (
      tester,
    ) async {
      final repo = _Repo(detail: _book(contentLocked: true, events: _events));
      await _pump(
        tester,
        repo: repo,
        subscribed: false,
        home: () => CollectionScreen(collection: _book()),
      );

      // The preview opens on About: credits, and the one way in, which
      // carries the count (the facts do not say it again above it).
      expect(find.text('by Garry Kasparov'), findsOneWidget);
      expect(find.byKey(const ValueKey('collection_unlock')), findsOneWidget);
      expect(_rich('Read all 4 games in this book'), findsOneWidget);
      expect(find.text('4 games'), findsNothing);

      // The contents are visible, every entry locked.
      await _showTab(tester, 'Games');
      expect(_rich('The Matches'), findsOneWidget);
      expect(_rich('Moscow 1984'), findsOneWidget);
      // A chapter's title may take two lines, as a part's does.
      expect(tester.widget<RichText>(_rich('Moscow 1984')).maxLines, 2);
      expect(find.text('3 games'), findsOneWidget);
      expect(find.byType(DiscoveryPadlock), findsWidgets);
      expect(find.byType(DiscoveryGameList), findsNothing);

      // A book's tabs: no Players tab; its Events are its credits, open to
      // everyone, locked or not.
      expect(find.text('Players'), findsNothing);
      await _showTab(tester, 'Events');
      expect(find.text('World Championship 1985'), findsOneWidget);
      expect(find.text('Game 16 is the octopus knight.'), findsOneWidget);

      // Nothing behind the paywall was asked for.
      expect(repo.gamesCalls, 0);
      expect(repo.playersCalls, 0);
    });

    _widgetTest('a subscriber reads the games', (tester) async {
      final repo = _Repo(detail: _book(contentLocked: false));
      await _pump(
        tester,
        repo: repo,
        subscribed: true,
        home: () => CollectionScreen(collection: _book()),
      );
      // Opens on its games.
      expect(find.byType(DiscoveryGameList), findsWidgets);
      expect(find.byKey(const ValueKey('collection_unlock')), findsNothing);
      expect(repo.gamesCalls, 1);
    });

    _widgetTest('the server opening a book opens it, subscription or not', (
      tester,
    ) async {
      // A web subscriber the app's store state does not know about.
      final repo = _Repo(detail: _book(contentLocked: false));
      await _pump(
        tester,
        repo: repo,
        subscribed: false,
        home: () => CollectionScreen(collection: _book()),
      );
      await _showTab(tester, 'Games');
      expect(find.byType(DiscoveryGameList), findsWidgets);
      expect(find.byKey(const ValueKey('collection_unlock')), findsNothing);
    });

    _widgetTest('a refusal from the server is the preview, not an error', (
      tester,
    ) async {
      // The store says subscribed; the server has not seen the purchase.
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
        subscribed: true,
        home: () => CollectionScreen(collection: _book()),
      );
      expect(_rich('Moscow 1985'), findsOneWidget);
      expect(find.textContaining('session'), findsNothing);
      // A subscriber is never offered the paywall: the page confirms their
      // Premium with the server instead, and says so.
      expect(find.byKey(const ValueKey('collection_unlock')), findsNothing);
      expect(find.text(_confirming), findsOneWidget);
      // About says the same where its way in would be.
      await _showTab(tester, 'About');
      expect(find.text(_confirming), findsOneWidget);
    });

    _widgetTest(
      'a subscriber the server still locks: confirmed until it opens',
      (tester) async {
        // Just bought: the server still holds its "not Premium" answer.
        final repo = _Repo(detail: _book(contentLocked: true));
        await _pump(
          tester,
          repo: repo,
          subscribed: true,
          home: () => CollectionScreen(collection: _book()),
        );
        expect(find.text(_confirming), findsOneWidget);
        expect(find.byKey(const ValueKey('collection_unlock')), findsNothing);
        // While it confirms, the locked chapters wait with it.
        final asked = repo.detailCalls;
        await tester.tap(_rich('Moscow 1984'));
        await tester.pump();
        expect(repo.detailCalls, asked);

        // It asks again on its own, with a backoff, and only for the verdict:
        // the games wait for the server to open them.
        final gamesAsked = repo.gamesCalls;
        await _wait(tester, const Duration(seconds: 6));
        expect(repo.detailCalls, greaterThan(asked + 1));
        expect(find.text(_confirming), findsOneWidget);
        expect(repo.gamesCalls, gamesAsked);

        // The server sees the purchase: the next ask opens the book.
        repo.detail = _book(contentLocked: false);
        await _wait(tester, const Duration(seconds: 9));
        expect(find.byType(DiscoveryGameList), findsWidgets);
        expect(find.text(_confirming), findsNothing);
        expect(
          find.byKey(const ValueKey('collection_unlock_status')),
          findsNothing,
        );
      },
    );

    _widgetTest('the confirm asks the server anew; the page\'s own reads do '
        'not', (tester) async {
      final repo = _Repo(detail: _book(contentLocked: true));
      await _pump(
        tester,
        repo: repo,
        subscribed: true,
        home: () => CollectionScreen(collection: _book()),
      );
      await _wait(tester, const Duration(seconds: 3));
      // The page's first read is plain; every re-check skips the server's
      // cached "not Premium".
      expect(repo.freshDetailReads.first, isFalse);
      expect(repo.freshDetailReads.skip(1), everyElement(isTrue));
      expect(repo.freshDetailReads.length, greaterThan(1));

      repo.detail = _book(contentLocked: false);
      await _wait(tester, const Duration(seconds: 6));
      expect(find.byType(DiscoveryGameList), findsWidgets);
      // The proof read of the games went out fresh too, and nothing is
      // held once the confirm is over.
      expect(repo.freshGamesReads, contains(isTrue));
      expect(repo.isFreshAccess('kasparov-karpov'), isFalse);
    });

    _widgetTest('a confirm that runs out says so, and Try again asks again', (
      tester,
    ) async {
      final repo = _Repo(detail: _book(contentLocked: true));
      final container = await _pump(
        tester,
        repo: repo,
        subscribed: true,
        home: () => CollectionScreen(collection: _book()),
      );
      await _wait(tester, const Duration(seconds: 40));
      expect(find.text(_confirming), findsNothing);
      expect(find.text(_confirmFailed), findsOneWidget);
      expect(
        find.byKey(const ValueKey('collection_unlock_retry')),
        findsOneWidget,
      );
      expect(container.read(collectionConfirmFailedAtProvider), isNotNull);

      final asked = repo.detailCalls;
      await tester.tap(find.byKey(const ValueKey('collection_unlock_retry')));
      await tester.pump();
      expect(find.text(_confirming), findsOneWidget);
      await _settle(tester);
      expect(repo.detailCalls, greaterThan(asked));

      // It opens this time: the failure is forgotten.
      repo.detail = _book(contentLocked: false);
      await _wait(tester, const Duration(seconds: 3));
      expect(find.byType(DiscoveryGameList), findsWidgets);
      expect(container.read(collectionConfirmFailedAtProvider), isNull);
    });

    _widgetTest('a confirm that ran out a moment ago is said again at once', (
      tester,
    ) async {
      final repo = _Repo(detail: _book(contentLocked: true));
      await _pump(
        tester,
        repo: repo,
        subscribed: true,
        overrides: [
          collectionConfirmFailedAtProvider.overrideWith(
            (ref) => DateTime.now(),
          ),
        ],
        home: () => CollectionScreen(collection: _book()),
      );
      expect(find.text(_confirmFailed), findsOneWidget);
      final asked = repo.detailCalls;
      await _wait(tester, const Duration(seconds: 12));
      // No confirm of its own this time: only a tap asks again.
      expect(repo.detailCalls, asked);
    });

    _widgetTest('the Premium check out of reach reads as a retry', (
      tester,
    ) async {
      final repo = _Repo(
        detail: _book(),
        gamesError: const CollectionsRequestException(
          'Entitlement check unavailable',
          statusCode: 503,
          code: 'access_check_unavailable',
        ),
      );
      await _pump(
        tester,
        repo: repo,
        subscribed: true,
        home: () => CollectionScreen(collection: _book()),
      );
      expect(
        find.text("Couldn't check your Premium access just now."),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
    });

    _widgetTest('the way in opens the paywall; entitled, the page re-asks', (
      tester,
    ) async {
      final unlocks = <_Unlock>[];
      final repo = _Repo(detail: _book(contentLocked: true));
      await _pump(
        tester,
        repo: repo,
        subscribed: false,
        unlocks: unlocks,
        home: () => CollectionScreen(collection: _book()),
      );
      await tester.tap(find.byKey(const ValueKey('collection_unlock')));
      await _settle(tester);
      expect(unlocks, hasLength(1));
      expect(unlocks.single.featureId, 'collection_books');
      expect(unlocks.single.returnTo, 'collections/collection');

      // A locked chapter is a way in too.
      await _showTab(tester, 'Games');
      await tester.tap(_rich('Moscow 1984'));
      await _settle(tester);
      expect(unlocks, hasLength(2));

      // The purchase goes through: the server is asked again, and opens it.
      final before = repo.detailCalls;
      repo.detail = _book(contentLocked: false);
      await unlocks.last.then!();
      await _settle(tester);
      expect(repo.detailCalls, greaterThan(before));
      expect(find.byType(DiscoveryGameList), findsWidgets);
      expect(find.byKey(const ValueKey('collection_unlock')), findsNothing);
    });

    _widgetTest('a purchase the server sees late: the page confirms it', (
      tester,
    ) async {
      final unlocks = <_Unlock>[];
      final repo = _Repo(detail: _book(contentLocked: true));
      await _pump(
        tester,
        repo: repo,
        subscribed: false,
        unlocks: unlocks,
        home: () => CollectionScreen(collection: _book()),
      );
      await tester.tap(find.byKey(const ValueKey('collection_unlock')));
      await _settle(tester);
      // Bought, but the server still holds "not Premium" for a while.
      await unlocks.single.then!();
      await tester.pump();
      expect(find.text(_confirming), findsOneWidget);
      expect(find.byKey(const ValueKey('collection_unlock')), findsNothing);
      await _wait(tester, const Duration(seconds: 12));
      expect(find.text(_confirming), findsOneWidget);
      // No second paywall while it confirms.
      expect(unlocks, hasLength(1));

      repo.detail = _book(contentLocked: false);
      await _wait(tester, const Duration(seconds: 10));
      // Asked for from About's "Read all 4 games": the book opens on them.
      expect(find.byType(DiscoveryGameList), findsWidgets);
      expect(find.text(_confirming), findsNothing);
    });

    for (final opened in [_book(), _book(contentLocked: true)]) {
    _widgetTest('a subscriber the server locks never sees the offer, '
        'not even for a frame (opened ${opened.contentLocked == null ? 'from the list' : 'on About'})', (tester) async {
      final repo = _Repo(detail: _book(contentLocked: true));
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [
          collectionsRepositoryProvider.overrideWithValue(repo),
          subscriptionProvider.overrideWith((ref) => _Subscription(true)),
          spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return CollectionScreen(collection: opened);
              },
            ),
          ),
        ),
      );
      final onAbout = opened.contentLocked == true;
      // Frame by frame, from the first one to the server's verdict and on.
      var confirmingSeen = false;
      for (var i = 0; i < 30; i++) {
        expect(
          find.byKey(const ValueKey('collection_unlock')),
          findsNothing,
          reason: 'frame $i',
        );
        // About's facts keep the count: the line under them never jumps.
        if (onAbout) {
          expect(find.text('4 games'), findsOneWidget, reason: 'frame $i');
        }
        confirmingSeen |= find.text(_confirming).evaluate().isNotEmpty;
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(confirmingSeen, isTrue);
    });
    }

    _widgetTest('the games stay the preview while the page re-checks, '
        'never a skeleton', (tester) async {
      // No verdict from the detail (its check was down), and the games
      // route refuses: the page confirms, re-reading the games each try.
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
        subscribed: true,
        home: () => CollectionScreen(collection: _book()),
      );
      expect(find.text(_confirming), findsOneWidget);
      final asked = repo.gamesCalls;
      for (var i = 0; i < 400; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(SkeletonWidget), findsNothing, reason: 'tick $i');
        expect(_rich('Moscow 1984'), findsOneWidget, reason: 'tick $i');
      }
      expect(repo.gamesCalls, greaterThan(asked + 2));
    });

    _widgetTest('a proof read that breaks is no answer, never the book '
        'opening', (tester) async {
      final repo = _Repo(
        detail: _book(),
        gamesError: const CollectionsRequestException(
          'Premium required',
          statusCode: 403,
          code: 'premium_required',
        ),
      );
      final container = await _pump(
        tester,
        repo: repo,
        subscribed: true,
        home: () => CollectionScreen(collection: _book()),
      );
      expect(find.text(_confirming), findsOneWidget);
      // The server gives no verdict and the games read now breaks outright.
      repo.gamesError = const CollectionsRequestException(
        'Premium access could not be checked right now',
        statusCode: 503,
        code: 'access_check_unavailable',
      );
      final asked = repo.detailCalls;
      await _wait(tester, const Duration(seconds: 40));
      // It kept asking, and ran out as a confirm that did not go through:
      // nothing counted the broken read as the server opening the book.
      expect(repo.detailCalls, greaterThan(asked + 3));
      expect(container.read(collectionConfirmFailedAtProvider), isNotNull);
    });

    _widgetTest('a session the server refuses: sign in again, then it '
        'confirms on the new one', (tester) async {
      final repo = _Repo(
        detail: _book(contentLocked: true, lockReason: 'auth_required'),
      );
      var signIns = 0;
      await _pump(
        tester,
        repo: repo,
        subscribed: true,
        overrides: [
          collectionSignInProvider.overrideWithValue((context) async {
            signIns++;
            return true;
          }),
        ],
        home: () => CollectionScreen(collection: _book()),
      );
      expect(find.text(_confirming), findsOneWidget);
      // Refused twice in a row: no waiting out the whole window.
      await _wait(tester, const Duration(seconds: 3));
      expect(find.text(_confirming), findsNothing);
      expect(find.text('Your sign-in has expired.'), findsOneWidget);
      expect(find.text(_confirmFailed), findsNothing);
      final signIn = find.byKey(const ValueKey('collection_unlock_sign_in'));
      expect(signIn, findsOneWidget);

      // Signed in again: the page asks on the new session, which opens it.
      repo.detail = _book(contentLocked: false);
      await tester.tap(signIn);
      await _settle(tester);
      expect(signIns, 1);
      expect(find.byType(DiscoveryGameList), findsWidgets);
    });

    _widgetTest('a locked book without contents shows who plays in it', (
      tester,
    ) async {
      final bare = Collection(
        id: 'b9',
        slug: 'my-system',
        kind: CollectionKind.book,
        title: 'My System',
        author: 'Aron Nimzowitsch',
        gameCount: 40,
        contentLocked: true,
        players: const ['Nimzowitsch, Aron', 'Capablanca, Jose Raul'],
      );
      await _pump(
        tester,
        repo: _Repo(detail: bare),
        subscribed: false,
        home: () => CollectionScreen(collection: bare),
      );
      await _showTab(tester, 'Games');
      expect(find.byKey(const ValueKey('collection_unlock')), findsWidgets);
      expect(
        find.text('Nimzowitsch, Aron · Capablanca, Jose Raul'),
        findsWidgets,
      );
    });

    _widgetTest('a book\'s About shows its whole jacket, standing', (
      tester,
    ) async {
      final covered = Collection(
        id: 'b1',
        slug: 'kasparov-karpov',
        kind: CollectionKind.book,
        title: 'Kasparov vs Karpov',
        coverUrl: 'https://example.invalid/cover.jpg',
        gameCount: 4,
        contentLocked: true,
      );
      await _pump(
        tester,
        repo: _Repo(detail: covered),
        subscribed: false,
        home: () => CollectionScreen(collection: covered),
      );
      final cover = tester.getSize(find.byType(CachedNetworkImage).first);
      expect(cover.height / cover.width, closeTo(1.5, 0.01));
    });

    _widgetTest('its card carries the padlock for a free viewer only', (
      tester,
    ) async {
      final repo = _Repo(detail: _book());
      await _pump(
        tester,
        repo: repo,
        subscribed: false,
        home: () => Scaffold(body: CollectionCard(collection: _book())),
      );
      expect(find.byType(DiscoveryPadlock), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Kasparov vs Karpov.*Premium')),
        findsOneWidget,
      );
    });

    _widgetTest('a long credit gives way to the padlock, never the reverse', (
      tester,
    ) async {
      final long = Collection(
        id: 'b2',
        slug: 'kasparov-on-kasparov',
        kind: CollectionKind.book,
        title: 'Garry Kasparov on Garry Kasparov',
        author: 'Garry Kasparov and Dmitry Plisetsky',
        gameCount: 55,
      );
      final repo = _Repo(detail: long);
      await _pump(
        tester,
        repo: repo,
        subscribed: false,
        size: const Size(320, 900),
        textScale: 1.3,
        home: () => Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: CollectionCard(collection: long),
          ),
        ),
      );
      final lock = find.byKey(const ValueKey('collection_card_padlock'));
      expect(lock, findsOneWidget);
      final rect = tester.getRect(lock);
      expect(rect.width, greaterThan(0));
      expect(
        tester.getRect(find.byType(CollectionPlateRow)).contains(rect.center),
        isTrue,
      );
      // The credit has a line of its own and the count one of its own, the
      // padlock after it: neither is cut to make room for the other.
      final count = tester.renderObject<RenderParagraph>(
        find.text('55 games'),
      );
      expect(count.didExceedMaxLines, isFalse);
      final credit = tester.renderObject<RenderParagraph>(
        find.text('by Garry Kasparov and Dmitry Plisetsky'),
      );
      expect(credit.didExceedMaxLines, isFalse);
      expect(
        tester.getRect(find.text('55 games')).top,
        greaterThanOrEqualTo(
          tester.getRect(find.text('by Garry Kasparov and Dmitry Plisetsky'))
              .bottom,
        ),
      );
    });

    _widgetTest('a book card stands on a portrait cover, an event on a '
        'landscape picture', (tester) async {
      final repo = _Repo(detail: _book());
      await _pump(
        tester,
        repo: repo,
        subscribed: true,
        home: () => Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CollectionCard(collection: _book()),
              CollectionCard(collection: _event()),
            ],
          ),
        ),
      );
      final plates = find.descendant(
        of: find.byType(CollectionPlateRow),
        matching: find.byType(ClipRRect),
      );
      final book = tester.getSize(plates.at(0));
      final event = tester.getSize(plates.at(1));
      // 2:3, as a book is printed; 5:4 for an event's picture.
      expect(book.height / book.width, closeTo(1.5, 0.01));
      expect(event.width / event.height, closeTo(1.25, 0.01));
    });

    for (final (size, scale) in [
      (const Size(393, 900), 1.0),
      (const Size(375, 900), 1.3),
      (const Size(320, 900), 1.3),
    ]) {
      _widgetTest('an event card keeps its whole date, year and all '
          '(${size.width.toInt()} pt, ${scale}x)', (tester) async {
        final repo = _Repo(detail: _book());
        await _pump(
          tester,
          repo: repo,
          subscribed: false,
          size: size,
          textScale: scale,
          home: () => Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                CollectionCard(collection: _event()),
                CollectionCard(
                  collection: _event(
                    location: 'Saint Louis',
                    start: DateTime(2025, 8, 18),
                    end: DateTime(2025, 8, 30),
                  ),
                ),
                CollectionCard(
                  collection: _event(
                    location: 'Moscow',
                    start: DateTime(1984, 9, 10),
                    end: DateTime(1985, 2, 15),
                  ),
                ),
              ],
            ),
          ),
        );
        for (final dates in [
          'Jan\u00a013-28,\u00a02024',
          'Aug\u00a018-30,\u00a02025',
          'Sep\u00a010,\u00a01984 - Feb\u00a015,\u00a01985',
        ]) {
          final found = find.textContaining(dates);
          final paragraph = tester.renderObject<RenderParagraph>(found);
          expect(paragraph.didExceedMaxLines, isFalse, reason: dates);
          // Broken at the separator, when it breaks: no line ends on a dot.
          expect(
            tester.widget<Text>(found).data,
            isNot(contains(' ·\n')),
            reason: dates,
          );
        }
        // The count stands on its own line, whole.
        expect(
          tester
              .renderObject<RenderParagraph>(find.text('91 games').first)
              .didExceedMaxLines,
          isFalse,
        );
      });
    }

    _widgetTest('a subscriber sees no padlock', (tester) async {
      final repo = _Repo(detail: _book());
      await _pump(
        tester,
        repo: repo,
        subscribed: true,
        home: () => Scaffold(body: CollectionCard(collection: _book())),
      );
      expect(find.byType(DiscoveryPadlock), findsNothing);
    });
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
      expect(find.text('Book'), findsOneWidget);
      expect(find.text('Books'), findsNothing);
      expect(find.text('Kasparov vs Karpov'), findsOneWidget);
      expect(find.text('The 1985 match, move by move.'), findsOneWidget);
      // Premium, and this viewer is not.
      expect(find.byType(DiscoveryPadlock), findsOneWidget);

      // The book opens on its preview.
      await tester.tap(find.text('Kasparov vs Karpov'));
      await _settle(tester);
      expect(find.byType(CollectionScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('collection_unlock')), findsOneWidget);
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
      expect(find.text('Book'), findsOneWidget);
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
      expect(find.text('Books'), findsNothing);
      expect(find.text('Book'), findsNothing);
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
      expect(find.text('Books'), findsOneWidget);
      expect(find.text('Book'), findsNothing);
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

    _widgetTest('an event card: place and dates always, then games and '
        'books', (tester) async {
      final subtitled = Collection.fromJson({
        'id': 'e1',
        'slug': 'tata-2024',
        'kind': 'event',
        'title': 'Tata Steel Masters 2024',
        'subtitle': 'Fourteen players, one round-robin',
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
      // The subtitle never hides where and when it was played.
      expect(
        find.text('Wijk aan Zee · Jan 13-28, 2024'),
        findsOneWidget,
      );
      expect(find.text('Fourteen players, one round-robin'), findsNothing);
      expect(find.text('91 games · 2 books'), findsOneWidget);
      // Neither place nor dates: the subtitle stands in; no books, no count.
      expect(find.text('Played online'), findsOneWidget);
      expect(find.text('1 game'), findsOneWidget);
      expect(find.textContaining('book'), findsOneWidget);
    });

    _widgetTest('a book card: the author, its bound events, a 2:3 plate '
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
      // Every plate is a whole 2:3 book, the placeholder included.
      final plates = find.descendant(
        of: find.byType(CollectionPlateRow),
        matching: find.byType(ClipRRect),
      );
      expect(plates, findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        final size = tester.getSize(plates.at(i));
        expect(size.height / size.width, closeTo(1.5, 0.01));
      }
      // Nothing is cut at 320 pt and 1.3x text.
      for (final text in [
        'by Garry Kasparov',
        '55 games · 2 events',
        'World Championship 1985 and 1 more',
      ]) {
        expect(
          tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines,
          isFalse,
          reason: text,
        );
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
          expect(rect.contains(r.topLeft) && rect.contains(r.bottomRight),
              isTrue, reason: t.data);
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

    _widgetTest('a book reads About · Games · Events; an event About · Games '
        '· Books · Players', (tester) async {
      await _pump(
        tester,
        repo: _Repo(detail: _book(contentLocked: false)),
        subscribed: true,
        home: () => CollectionScreen(collection: _book()),
      );
      expect(tabLabels(tester), ['About', 'Games', 'Events']);
      await _teardown(tester);

      await _pump(
        tester,
        repo: _Repo(detail: _event()),
        subscribed: false,
        home: () => CollectionScreen(collection: _event()),
      );
      expect(tabLabels(tester), ['About', 'Games', 'Books', 'Players']);
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
      expect(find.byKey(const ValueKey('collection_unlock')), findsOneWidget);
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
      expect(find.text('No events for this book yet.'), findsOneWidget);
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
      await _showTab(tester, 'Books');
      expect(repo.bookAnchors.single.collections, ['e-Wijk aan Zee']);
      expect(find.text('Kasparov vs Karpov'), findsOneWidget);
      expect(find.text('by Garry Kasparov'), findsOneWidget);
      expect(find.text('Timman annotates round 7.'), findsOneWidget);
      // A Premium book for a viewer without Premium: the padlock.
      expect(find.byType(DiscoveryPadlock), findsOneWidget);

      repo.detail = _book();
      await tester.tap(find.text('Kasparov vs Karpov'));
      await _settle(tester);
      // The book's own page, on its preview.
      expect(
        find.byType(CollectionScreen, skipOffstage: false),
        findsNWidgets(2),
      );
      expect(find.byKey(const ValueKey('collection_unlock')), findsOneWidget);
    });

    _widgetTest('an event\'s Books tab: none, and a failure with a retry', (
      tester,
    ) async {
      final repo = _Repo(
        detail: _event(),
        booksError: Exception('offline'),
      );
      await _pump(
        tester,
        repo: repo,
        subscribed: true,
        home: () => CollectionScreen(collection: _event()),
      );
      await _showTab(tester, 'Books');
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('No books about this event yet.'), findsNothing);

      repo.booksError = null;
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(repo.bookAnchors, hasLength(2));
      expect(find.text('No books about this event yet.'), findsOneWidget);
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
      await _showTab(tester, 'Books');
      expect(repo.bookAnchors.single.collections, ['e-Wijk aan Zee']);
      expect(find.text('No books about this event yet.'), findsOneWidget);
    });
  });
}
