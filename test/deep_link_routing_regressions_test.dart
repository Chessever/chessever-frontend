// Regression cover for the 39.x deep-link and push routing audit. Every test
// drives the real DeepLinkService (handleDeepLink, the notification router,
// drainPendingDestination) to its destination under the current routing
// tree: a home shell that registers itself as HomeScreen does
// (registerHomeShellRoute), the dock's selected section, and the surfaces
// the overhaul put over it (a pushed page such as Search, a full-screen
// modal route such as the stories viewer, a popup such as the glass menus).
// Only repositories are faked; pages the router pushes are captured through
// the service's test seams instead of being built.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/event_video_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/memorial_player_local_search.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/news/news_reader_screen.dart';
import 'package:chessever2/screens/for_you/discovery/likes_screen.dart';
import 'package:chessever2/screens/for_you/discovery/reports_screen.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/my_prep_home_screen.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/settings/settings_page.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_repo_provider.dart';
import 'package:chessever2/screens/webview/app_webview_screen.dart';
import 'package:chessever2/services/app_destination_service.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/services/editorial_link_service.dart';
import 'package:chessever2/services/onesignal_push_payload.dart';
import 'package:chessever2/utils/own_web_page.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/guest_session_gate_listener.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

/// The reader's session, switchable mid-test (sign-in after a held link).
bool _signedIn = true;

class _SwitchableAuth extends AuthController {
  @override
  Future<AppAuthState> build() async => AppAuthState(
    status: _signedIn
        ? AppAuthStatus.authenticated
        : AppAuthStatus.unauthenticated,
  );

  /// Google or Apple being asked: the controller says loading, as data,
  /// until the answer lands (AuthController.signInWithGoogle).
  void startSignIn() => state = const AsyncData(AppAuthState.loading());

  void finishSignIn() {
    _signedIn = true;
    state = const AsyncData(AppAuthState(status: AppAuthStatus.authenticated));
  }

  /// Google's or Apple's sheet dismissed (AuthController): error for a
  /// guest's upgrade, unauthenticated for a plain sign-in.
  void cancelSignIn(AppAuthState ended) => state = AsyncData(ended);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The bundled Memorial catalog is memoized: load it here, outside any
    // test's clock, or the second test awaits a future of the first's zone.
    await findBundledMemorialPlayerByRouteId('memorial-e03cdf6af47b368c');
    // GameRepository (the real getGameByAnyId runs) needs the client to exist.
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder-publishable-key',
    );
  });

  late GlobalKey<NavigatorState> navigatorKey;
  late List<String> generated;
  late _Stack stack;
  late List<Widget> pages;
  late List<(Uri, LaunchMode)> launched;
  late OwnWebPageLauncher previousLauncher;

  setUp(() {
    _signedIn = true;
    DeepLinkService.instance.detachNotificationRouter();
    DeepLinkService.instance.dispose();
    navigatorKey = GlobalKey<NavigatorState>();
    generated = [];
    stack = _Stack();
    pages = [];
    launched = [];
    previousLauncher = ownWebPageLauncher;
    ownWebPageLauncher = (uri, mode) async {
      launched.add((uri, mode));
      return true;
    };
    GuestGateRouteObserver.instance.topRouteName.value = null;
  });

  tearDown(() {
    ownWebPageLauncher = previousLauncher;
    GuestGateRouteObserver.instance.topRouteName.value = null;
    DeepLinkService.instance.detachNotificationRouter();
    DeepLinkService.instance.dispose();
  });

  /// The app: Home (a shell registered like HomeScreen) as the first route,
  /// named routes for the rest. Returns the app root's ref, as main.dart
  /// hands the router.
  Future<WidgetRef> pumpApp(
    WidgetTester tester, {
    List<Override> overrides = const [],
    bool attach = true,
  }) async {
    late WidgetRef rootRef;
    final service = DeepLinkService.instance;
    // Inside the test's zone, so the app-ready gate opens in it too.
    service.dispose();
    service.debugBoardPageBuilder = (game) => Text('board ${game.gameId}');
    service.debugPageOverride = (page) {
      pages.add(page);
      return Scaffold(body: Text('page ${page.runtimeType}'));
    };
    Route<void> route(RouteSettings settings) => MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => settings.name == '/home_screen'
          ? const _HomeShell()
          : Scaffold(body: Text('route ${settings.name}')),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(_SwitchableAuth.new),
          currentUserProvider.overrideWith(
            (ref) => _signedIn
                ? AppUser(id: 'reader', createdAt: DateTime.utc(2026))
                : null,
          ),
          eventVideoConfigurationProvider.overrideWithValue(null),
          ...overrides,
        ],
        child: Consumer(
          builder: (_, ref, child) {
            rootRef = ref;
            return child!;
          },
          child: MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: [stack],
            builder: (context, child) {
              ResponsiveHelper.init(context);
              return child!;
            },
            onGenerateRoute: (settings) {
              generated.add(settings.name ?? '');
              return route(settings);
            },
            onGenerateInitialRoutes: (_) => [
              route(const RouteSettings(name: '/home_screen')),
            ],
          ),
        ),
      ),
    );
    // authStateProvider auto-disposes: hold it as the app's listeners do.
    final auth = ProviderScope.containerOf(
      navigatorKey.currentContext!,
    ).listen(authStateProvider, (_, _) {});
    addTearDown(auth.close);
    await tester.pump();
    if (attach) service.attachNotificationRouter(navigatorKey, rootRef);
    return rootRef;
  }

  /// Player links check the bundled Memorial catalog first, read from the
  /// asset bundle outside the test clock.
  Future<void> loadMemorialCatalog(
    WidgetTester tester, {
    required bool Function() until,
  }) async {
    for (var i = 0; i < 40 && !until(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Onboarding (or sign-in) alone on screen, Home gone, as on a new
  /// reader's first launch.
  Future<void> showAlone(WidgetTester tester, String route) async {
    unawaited(
      navigatorKey.currentState!.pushNamedAndRemoveUntil(route, (_) => false),
    );
    GuestGateRouteObserver.instance.topRouteName.value = route;
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    generated.clear();
  }

  /// Onboarding finished: Home alone (markOnboardingComplete).
  Future<void> finishOnboarding(WidgetTester tester) async {
    unawaited(
      navigatorKey.currentState!.pushNamedAndRemoveUntil(
        '/home_screen',
        (_) => false,
      ),
    );
    GuestGateRouteObserver.instance.topRouteName.value = '/home_screen';
  }

  ProviderContainer container() =>
      ProviderScope.containerOf(navigatorKey.currentContext!);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The overhaul's surfaces over Home: a pushed page (Search), a
  /// full-screen non-opaque modal route on the root navigator (the stories
  /// viewer) and a popup (a glass menu or sheet).
  Future<void> coverHome(WidgetTester tester) async {
    final navigator = navigatorKey.currentState!;
    unawaited(navigator.pushNamed('/search'));
    await tester.pump(const Duration(milliseconds: 400));
    unawaited(navigator.push(_StoriesStandIn()));
    await tester.pump(const Duration(milliseconds: 400));
    unawaited(navigator.push(_PopupStandIn()));
    await tester.pump(const Duration(milliseconds: 400));
    expect(stack.names, [
      '/home_screen',
      '/search',
      'collection_stories',
      'glass_popup',
    ]);
    generated.clear();
  }

  // ---------------------------------------------------------------------------
  group('a game resolves by games.id first (issue 9)', () {
    for (final cold in [true, false]) {
      testWidgets('game_started for games.id XBnzfSW7, lichess q83KAyaw '
          '(cold=$cold)', (tester) async {
        final games = _Games({'XBnzfSW7'});
        final ref = await pumpApp(
          tester,
          attach: !cold,
          overrides: [
            gameRepositoryProvider.overrideWithValue(games),
            roundRepositoryProvider.overrideWithValue(_Rounds()),
          ],
        );
        if (!cold) DeepLinkService.notifyAppReady();
        // Cold: the tap arrives before the router is attached (main()).
        DeepLinkService.instance.ingestNotificationData({
          'type': 'game_started',
          'game_id': 'XBnzfSW7',
        });
        if (cold) {
          DeepLinkService.instance.attachNotificationRouter(navigatorKey, ref);
          DeepLinkService.notifyAppReady();
        }
        await settle(tester);
        expect(find.text('board XBnzfSW7'), findsOneWidget);
        expect(games.byId, ['XBnzfSW7']);
        expect(games.byLichessId, isEmpty);
        expect(stack.names.first, '/home_screen');
        expect(stack.names, hasLength(2));
        expect(generated, isNot(contains('/home_screen')));
      });
    }

    testWidgets('a shared /games/<lichess id> still falls back to lichess_id', (
      tester,
    ) async {
      final games = _Games({}, lichess: {'q83KAyaw': 'XBnzfSW7'});
      final ref = await pumpApp(
        tester,
        overrides: [
          gameRepositoryProvider.overrideWithValue(games),
          roundRepositoryProvider.overrideWithValue(_Rounds()),
        ],
      );
      DeepLinkService.notifyAppReady();
      DeepLinkService.instance.handleDeepLink(
        Uri.parse('https://chessever.com/games/q83KAyaw'),
        navigatorKey,
        ref,
      );
      await settle(tester);
      expect(games.byId, ['q83KAyaw']);
      expect(games.byLichessId, ['q83KAyaw']);
      expect(find.text('board XBnzfSW7'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  group('player profile links with a view (issue 21)', () {
    test('identity and view parse as the web parses them', () {
      final cases = <List<String>, (String, PlayerProfileTab?)?>{
        ['1503014']: ('1503014', null),
        ['1503014', 'games']: ('1503014', PlayerProfileTab.games),
        ['magnus-carlsen', '1503014']: ('1503014', null),
        ['magnus-carlsen', '1503014', 'events']: (
          '1503014',
          PlayerProfileTab.events,
        ),
        ['magnus-carlsen', '1503014', 'about']: (
          '1503014',
          PlayerProfileTab.about,
        ),
        ['magnus-carlsen', '1503014', 'news']: (
          '1503014',
          PlayerProfileTab.about,
        ),
        ['x', 'memorial-e03cdf6af47b368c', 'news']: (
          'memorial-e03cdf6af47b368c',
          PlayerProfileTab.about,
        ),
        ['5000017-63']: ('5000017', null),
        ['old-name', '900826-reused']: ('900826-reused', null),
        ['games']: null,
        ['magnus-carlsen']: null,
      };
      for (final entry in cases.entries) {
        final target = playerProfileLinkTarget(entry.key);
        final expected = entry.value;
        if (expected == null) {
          expect(target, isNull, reason: '${entry.key}');
        } else {
          expect(target?.routeId, expected.$1, reason: '${entry.key}');
          expect(target?.tab, expected.$2, reason: '${entry.key}');
        }
      }
    });

    for (final entry in {
      'https://chessever.com/player/1503014/games': PlayerProfileTab.games,
      'https://chessever.com/player/magnus-carlsen/1503014/events':
          PlayerProfileTab.events,
      'com.chessever.app://player/1503014/games': PlayerProfileTab.games,
      'https://chessever.com/player/magnus-carlsen/1503014': null,
    }.entries) {
      testWidgets('${entry.key} opens 1503014 on ${entry.value}', (
        tester,
      ) async {
        final players = _Players();
        final ref = await pumpApp(
          tester,
          overrides: [chessPlayerRepositoryProvider.overrideWithValue(players)],
        );
        DeepLinkService.notifyAppReady();
        DeepLinkService.instance.handleDeepLink(
          Uri.parse(entry.key),
          navigatorKey,
          ref,
        );
        await loadMemorialCatalog(tester, until: () => pages.isNotEmpty);
        expect(players.requested, [1503014]);
        final profile = pages.single as PlayerProfileScreen;
        expect(profile.fideId, 1503014);
        expect(profile.initialTab, entry.value);
        expect(stack.names, ['/home_screen', isNull]);
        expect(generated, isNot(contains('/home_screen')));
      });
    }

    testWidgets('a Memorial profile link with a view opens that profile', (
      tester,
    ) async {
      final ref = await pumpApp(
        tester,
        overrides: [
          chessPlayerRepositoryProvider.overrideWithValue(_Players()),
        ],
      );
      DeepLinkService.notifyAppReady();
      DeepLinkService.instance.handleDeepLink(
        Uri.parse(
          'https://chessever.com/player/someone/memorial-e03cdf6af47b368c/news',
        ),
        navigatorKey,
        ref,
      );
      await loadMemorialCatalog(tester, until: () => pages.isNotEmpty);
      final profile = pages.single as PlayerProfileScreen;
      expect(profile.memorialRouteId, 'memorial-e03cdf6af47b368c');
      // The app has no News tab: a /news view opens About.
      expect(profile.initialTab, PlayerProfileTab.about);
    });

    testWidgets('an unknown player on a warm start keeps the reader in place', (
      tester,
    ) async {
      final ref = await pumpApp(
        tester,
        overrides: [
          chessPlayerRepositoryProvider.overrideWithValue(_Players()),
        ],
      );
      DeepLinkService.notifyAppReady();
      unawaited(navigatorKey.currentState!.pushNamed('/board-being-read'));
      await tester.pump(const Duration(milliseconds: 400));
      generated.clear();
      DeepLinkService.instance.handleDeepLink(
        Uri.parse('https://chessever.com/player/someone/999999999/games'),
        navigatorKey,
        ref,
      );
      await loadMemorialCatalog(
        tester,
        until: () =>
            find.text("Couldn't open that link.").evaluate().isNotEmpty,
      );
      expect(stack.names, ['/home_screen', '/board-being-read']);
      expect(generated, isEmpty);
      expect(find.text("Couldn't open that link."), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  group('broadcast and games paths (issues 4 and 23)', () {
    List<Override> eventRepos(_Tours tours, _Groups groups, _Rounds rounds) => [
      tourRepositoryProvider.overrideWithValue(tours),
      groupBroadcastRepositoryProvider.overrideWithValue(groups),
      roundRepositoryProvider.overrideWithValue(rounds),
      tourDetailRepoProvider.overrideWithValue(_Selection()),
    ];

    for (final entry in {
      // The web's round page: the event opens on that round.
      'https://chessever.com/broadcast/titled-tuesday/mKgqPByN/round/R0000001':
          (tours: ['mKgqPByN'], round: 'R0000001'),
      // A PGN BroadcastURL rebranded from Lichess carries the ROUND id.
      'https://chessever.com/broadcast/superfinal-2025-men/R0000001': (
        tours: ['R0000001', 'mKgqPByN'],
        round: 'R0000001',
      ),
      // A Lichess round path a host-only rebrand put on chessever.com.
      'https://chessever.com/broadcast/superfinal-2025-men/round-4/R0000001': (
        tours: ['mKgqPByN'],
        round: 'R0000001',
      ),
    }.entries) {
      testWidgets('${entry.key} opens the event on its round', (tester) async {
        final tours = _Tours();
        final groups = _Groups();
        final rounds = _Rounds();
        final ref = await pumpApp(
          tester,
          overrides: eventRepos(tours, groups, rounds),
        );
        DeepLinkService.notifyAppReady();
        DeepLinkService.instance.handleDeepLink(
          Uri.parse(entry.key),
          navigatorKey,
          ref,
        );
        await settle(tester);
        expect(tours.requested, entry.value.tours);
        expect(groups.requested, 'gb_mKgqPByN');
        expect(
          container().read(userSelectedRoundProvider)?.id,
          entry.value.round,
        );
        expect(
          container().read(pendingRoundNavigationProvider),
          entry.value.round,
        );
        expect(generated, ['/tournament_detail_screen']);
      });
    }

    testWidgets('a Lichess broadcast game path opens the game', (tester) async {
      final games = _Games({'K4cjG7Tz'});
      final ref = await pumpApp(
        tester,
        overrides: [
          gameRepositoryProvider.overrideWithValue(games),
          roundRepositoryProvider.overrideWithValue(_Rounds()),
        ],
      );
      DeepLinkService.notifyAppReady();
      DeepLinkService.instance.handleDeepLink(
        Uri.parse(
          'https://chessever.com/broadcast/x/round-7/efqWGqz4/K4cjG7Tz',
        ),
        navigatorKey,
        ref,
      );
      await settle(tester);
      expect(find.text('board K4cjG7Tz'), findsOneWidget);
    });

    for (final path in [
      '/broadcast/signin',
      '/broadcast/editor',
      '/broadcast/settings',
      '/broadcast/hubs',
      '/broadcast/fide-world-cup-2026',
      '/broadcast/olympiad-2026/teams',
      '/games/search',
      // Not routed at all: account and legal pages reach a build that still
      // claims every chessever.com path.
      '/account',
      '/privacy-policy',
    ]) {
      testWidgets('$path opens on the web, over the app', (tester) async {
        final tours = _Tours();
        final ref = await pumpApp(
          tester,
          overrides: eventRepos(tours, _Groups(), _Rounds()),
        );
        DeepLinkService.notifyAppReady();
        DeepLinkService.instance.handleDeepLink(
          Uri.parse('https://chessever.com$path'),
          navigatorKey,
          ref,
        );
        await settle(tester);
        expect(launched, [
          (
            Uri.parse('https://chessever.com$path'),
            LaunchMode.inAppBrowserView,
          ),
        ]);
        expect(tours.requested, isNull, reason: 'no bogus id is resolved');
        expect(stack.names, ['/home_screen']);
        expect(generated, isEmpty);
      });
    }

    testWidgets('an event that cannot be found leaves a warm stack alone', (
      tester,
    ) async {
      final ref = await pumpApp(
        tester,
        overrides: eventRepos(_Tours(known: false), _Groups(), _Rounds()),
      );
      DeepLinkService.notifyAppReady();
      await coverHome(tester);
      DeepLinkService.instance.handleDeepLink(
        Uri.parse('https://chessever.com/broadcast/gone/ZZZZZZZZ'),
        navigatorKey,
        ref,
      );
      await settle(tester);
      expect(generated, isEmpty, reason: 'Home was not rebuilt');
      expect(stack.names, [
        '/home_screen',
        '/search',
        'collection_stories',
        'glass_popup',
      ]);
    });
  });

  // ---------------------------------------------------------------------------
  testWidgets('a round push whose ids arrived as the string "null" (FCM) '
      'resolves the round (issue 14)', (tester) async {
    final tours = _Tours();
    final rounds = _Rounds();
    await pumpApp(
      tester,
      overrides: [
        tourRepositoryProvider.overrideWithValue(tours),
        groupBroadcastRepositoryProvider.overrideWithValue(_Groups()),
        roundRepositoryProvider.overrideWithValue(rounds),
        tourDetailRepoProvider.overrideWithValue(_Selection()),
      ],
    );
    DeepLinkService.notifyAppReady();
    DeepLinkService.instance.ingestNotificationData({
      'type': 'round_heads_up',
      'round_id': 'R0000001',
      'tour_id': 'null',
      'group_broadcast_id': 'null',
    });
    await settle(tester);
    expect(rounds.requested, ['R0000001']);
    expect(tours.requested, ['mKgqPByN']);
    expect(generated, ['/tournament_detail_screen']);
  });

  // ---------------------------------------------------------------------------
  group('links and pushes wait for a session (issue 12)', () {
    const book = Collection(
      id: 'book-1',
      slug: 'us-chess-championships',
      kind: CollectionKind.book,
      title: 'US Chess Championships',
      access: CollectionAccess.free,
    );

    testWidgets('a collection link signed out waits for sign-in, then opens', (
      tester,
    ) async {
      _signedIn = false;
      final ref = await pumpApp(
        tester,
        overrides: [
          collectionsRepositoryProvider.overrideWithValue(_OneCollection(book)),
        ],
      );
      DeepLinkService.notifyAppReady();
      DeepLinkService.instance.handleDeepLink(
        Uri.parse('https://chessever.com/collections/us-chess-championships'),
        navigatorKey,
        ref,
      );
      await settle(tester);
      expect(generated, ['/auth_screen'], reason: 'never a session-less Home');
      expect(pages, isEmpty);
      expect(DeepLinkService.instance.hasPendingDestination, isTrue);

      // Signed in: Home comes up and routes the held link.
      // Signed in: AuthStateListener puts Home up, which routes the link.
      _signedIn = true;
      container().invalidate(authStateProvider);
      await settle(tester);
      await finishOnboarding(tester);
      await settle(tester);
      expect((pages.single as CollectionScreen).collection.slug, book.slug);
      expect(stack.names, ['/home_screen', isNull]);
      expect(DeepLinkService.instance.hasPendingDestination, isFalse);
    });

    testWidgets('a link while onboarding is on screen is held, nothing moves', (
      tester,
    ) async {
      final ref = await pumpApp(
        tester,
        overrides: [
          collectionsRepositoryProvider.overrideWithValue(_OneCollection(book)),
        ],
      );
      DeepLinkService.notifyAppReady();
      await showAlone(tester, '/onboarding');
      DeepLinkService.instance.handleDeepLink(
        Uri.parse('https://chessever.com/collections/us-chess-championships'),
        navigatorKey,
        ref,
      );
      await settle(tester);
      expect(generated, isEmpty);
      expect(pages, isEmpty);
      expect(DeepLinkService.instance.hasPendingDestination, isTrue);

      // Onboarding ends on Home, which routes the held link.
      await finishOnboarding(tester);
      await settle(tester);
      expect(pages.single, isA<CollectionScreen>());
      expect(stack.names, ['/home_screen', isNull]);
      expect(DeepLinkService.instance.hasPendingDestination, isFalse);
    });

    testWidgets('a guest\'s Sign up over Home does not hold links', (
      tester,
    ) async {
      final ref = await pumpApp(
        tester,
        overrides: [
          collectionsRepositoryProvider.overrideWithValue(_OneCollection(book)),
        ],
      );
      DeepLinkService.notifyAppReady();
      unawaited(navigatorKey.currentState!.pushNamed('/auth_screen'));
      GuestGateRouteObserver.instance.topRouteName.value = '/auth_screen';
      await tester.pump(const Duration(milliseconds: 400));
      DeepLinkService.instance.handleDeepLink(
        Uri.parse('https://chessever.com/collections/us-chess-championships'),
        navigatorKey,
        ref,
      );
      await settle(tester);
      expect(pages.single, isA<CollectionScreen>());
      expect(DeepLinkService.instance.hasPendingDestination, isFalse);
    });

    for (final push in <Map<String, dynamic>>[
      {
        'type': 'collection_games_added',
        'collection_slug': 'us-chess-championships',
      },
      {
        'type': 'smart_event_games',
        'smart_event_id': 'smart_event:sicilian-2600',
        'smart_event_name': 'Sicilian 2600+',
        'formats': 'blitz,live',
        'eco_code': 'B20',
      },
      {'type': 'prep_games_added', 'prep_profile_id': 'vasif'},
    ]) {
      testWidgets('${push['type']} signed out opens sign-in, not Home', (
        tester,
      ) async {
        _signedIn = false;
        await pumpApp(
          tester,
          overrides: [
            collectionsRepositoryProvider.overrideWithValue(
              _OneCollection(book),
            ),
          ],
        );
        DeepLinkService.notifyAppReady();
        DeepLinkService.instance.ingestNotificationData(push);
        await settle(tester);
        expect(generated, isNot(contains('/home_screen')));
        expect(pages, isEmpty);
      });
    }

    testWidgets('a configured route push signed out opens after sign-in', (
      tester,
    ) async {
      _signedIn = false;
      final opened = <Widget>[];
      await pumpApp(
        tester,
        overrides: [
          // Signed in later: read the switch on every rebuild.
          currentUserProvider.overrideWith((ref) {
            ref.watch(authStateProvider);
            return _signedIn
                ? AppUser(id: 'reader', createdAt: DateTime.utc(2026))
                : null;
          }),
          appDestinationPageNavigationProvider.overrideWithValue(
            (_, page, __) => opened.add(page),
          ),
        ],
      );
      DeepLinkService.notifyAppReady();
      await showAlone(tester, '/auth_screen');
      DeepLinkService.instance.ingestNotificationData({
        'route': '/app/settings/notifications',
      });
      await settle(tester);
      expect(opened, isEmpty);
      expect(DeepLinkService.instance.hasPendingDestination, isTrue);

      _signedIn = true;
      container().invalidate(authStateProvider);
      await settle(tester);
      await finishOnboarding(tester);
      await settle(tester);
      expect(opened.single, isA<SettingsPage>());
    });

    testWidgets('a game link signed out opens the board after sign-in', (
      tester,
    ) async {
      _signedIn = false;
      final ref = await pumpApp(
        tester,
        overrides: [
          gameRepositoryProvider.overrideWithValue(_Games({'XBnzfSW7'})),
          roundRepositoryProvider.overrideWithValue(_Rounds()),
        ],
      );
      DeepLinkService.notifyAppReady();
      DeepLinkService.instance.handleDeepLink(
        Uri.parse('https://chessever.com/games/XBnzfSW7'),
        navigatorKey,
        ref,
      );
      // The session restore wait (kAuthRestoreTimeout, a wall-clock
      // deadline) runs out first; its polling timer fires on the next pump.
      await tester.runAsync(
        () => Future<void>.delayed(
          kAuthRestoreTimeout + const Duration(milliseconds: 200),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      expect(generated, ['/auth_screen']);
      expect(find.text('board XBnzfSW7'), findsNothing);

      _signedIn = true;
      container().invalidate(authStateProvider);
      await settle(tester);
      await finishOnboarding(tester);
      await settle(tester);
      expect(find.text('board XBnzfSW7'), findsOneWidget);
    });
  });

  testWidgets('a game link while onboarding is held, then opens on Home '
      '(issue 12)', (tester) async {
    final ref = await pumpApp(
      tester,
      overrides: [
        gameRepositoryProvider.overrideWithValue(_Games({'XBnzfSW7'})),
        roundRepositoryProvider.overrideWithValue(_Rounds()),
      ],
    );
    DeepLinkService.notifyAppReady();
    await showAlone(tester, '/onboarding');
    DeepLinkService.instance.handleDeepLink(
      Uri.parse('https://chessever.com/games/XBnzfSW7'),
      navigatorKey,
      ref,
    );
    await settle(tester);
    expect(find.text('board XBnzfSW7'), findsNothing);
    expect(generated, isEmpty);
    await finishOnboarding(tester);
    await settle(tester);
    expect(find.text('board XBnzfSW7'), findsOneWidget);
    expect(stack.names, ['/home_screen', isNull]);
  });

  // ---------------------------------------------------------------------------
  group('taps over the overhaul surfaces keep one Home (issues 5, 16)', () {
    testWidgets('a push that names nothing returns to the same Home', (
      tester,
    ) async {
      await pumpApp(tester);
      DeepLinkService.notifyAppReady();
      await coverHome(tester);
      final shell = tester.state(find.byType(_HomeShell, skipOffstage: false));
      DeepLinkService.instance.ingestNotificationData({
        'type': 'call_to_action',
      });
      await settle(tester);
      expect(stack.names, ['/home_screen']);
      expect(generated, isEmpty, reason: 'Home is kept, not built anew');
      expect(tester.state(find.byType(_HomeShell)), same(shell));
    });

    testWidgets('a collection push lands over Home; Back returns to it', (
      tester,
    ) async {
      await pumpApp(
        tester,
        overrides: [
          collectionsRepositoryProvider.overrideWithValue(
            _OneCollection(
              const Collection(
                id: 'book-1',
                slug: 'us-chess-championships',
                kind: CollectionKind.book,
                title: 'US Chess Championships',
                access: CollectionAccess.free,
              ),
            ),
          ),
        ],
      );
      DeepLinkService.notifyAppReady();
      await coverHome(tester);
      DeepLinkService.instance.ingestNotificationData({
        'type': 'collection_games_added',
        'collection_slug': 'us-chess-championships',
      });
      await settle(tester);
      expect(stack.names, ['/home_screen', isNull]);
      expect(pages.single, isA<CollectionScreen>());
      expect(generated, isEmpty);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(stack.names, ['/home_screen']);
    });

    testWidgets('a game push replaces the surfaces with the board', (
      tester,
    ) async {
      await pumpApp(
        tester,
        overrides: [
          gameRepositoryProvider.overrideWithValue(_Games({'XBnzfSW7'})),
          roundRepositoryProvider.overrideWithValue(_Rounds()),
        ],
      );
      DeepLinkService.notifyAppReady();
      await coverHome(tester);
      DeepLinkService.instance.ingestNotificationData({
        'type': 'game_started',
        'game_id': 'XBnzfSW7',
      });
      await settle(tester);
      expect(stack.names, ['/home_screen', isNull]);
      expect(find.text('board XBnzfSW7'), findsOneWidget);
    });

    for (final entry in {
      // Events is a dock section again (2026-11-23): never a second Events
      // page pushed over Home.
      'https://chessever.com/app/events': BottomNavBarItem.tournaments,
      'https://chessever.com/app/feed': BottomNavBarItem.feed,
      'https://chessever.com/app/home/today': BottomNavBarItem.forYou,
    }.entries) {
      testWidgets('route ${entry.key} lands on its dock section with the dock '
          'in view', (tester) async {
        await pumpApp(tester);
        DeepLinkService.notifyAppReady();
        await coverHome(tester);
        final reveal = container().read(homeChromeRevealRequestProvider);
        DeepLinkService.instance.ingestNotificationData({'route': entry.key});
        await settle(tester);
        expect(stack.names, ['/home_screen']);
        expect(generated, isEmpty);
        expect(container().read(selectedBottomNavBarItemProvider), entry.value);
        expect(
          container().read(homeChromeRevealRequestProvider),
          greaterThan(reveal),
          reason: 'Home already open still shows its dock',
        );
      });
    }

    testWidgets('route /app/collections pushes the Collections page over '
        'Home, the dock section unchanged', (tester) async {
      final opened = <Widget>[];
      await pumpApp(
        tester,
        overrides: [
          // The page the link asks for, pushed under its route name as the
          // app does; a stand-in is drawn, so the catalog reads nothing.
          appDestinationPageNavigationProvider.overrideWithValue((
            context,
            page,
            name,
          ) {
            opened.add(page);
            unawaited(
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  settings: RouteSettings(name: name),
                  builder: (_) => Text('page $name'),
                ),
              ),
            );
          }),
        ],
      );
      DeepLinkService.notifyAppReady();
      await coverHome(tester);
      DeepLinkService.instance.ingestNotificationData({
        'route': 'https://chessever.com/app/collections',
      });
      await settle(tester);
      // Collections has no dock slot: its page, with its back, over Home.
      expect(stack.names, ['/home_screen', '/app/collections']);
      expect(opened.single, isA<CollectionsScreen>());
      expect(generated, isEmpty);
      expect(
        container().read(selectedBottomNavBarItemProvider),
        BottomNavBarItem.forYou,
      );
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(stack.names, ['/home_screen']);
    });
  });

  // ---------------------------------------------------------------------------
  testWidgets('the newest tap wins over a slower older one (issue 28)', (
    tester,
  ) async {
    final held = Completer<void>();
    final games = _Games({'AAAAAAAA', 'BBBBBBBB'}, hold: {'AAAAAAAA': held});
    await pumpApp(
      tester,
      overrides: [
        gameRepositoryProvider.overrideWithValue(games),
        roundRepositoryProvider.overrideWithValue(_Rounds()),
      ],
    );
    DeepLinkService.notifyAppReady();
    DeepLinkService.instance.ingestNotificationData({
      'type': 'game_finished',
      'game_id': 'AAAAAAAA',
    });
    await tester.pump(const Duration(milliseconds: 100));
    DeepLinkService.instance.ingestNotificationData({
      'type': 'game_started',
      'game_id': 'BBBBBBBB',
    });
    await settle(tester);
    expect(find.text('board BBBBBBBB'), findsOneWidget);
    held.complete();
    await settle(tester);
    expect(find.text('board AAAAAAAA'), findsNothing);
    expect(find.text('board BBBBBBBB'), findsOneWidget);
    expect(stack.names, hasLength(2));
  });

  // ---------------------------------------------------------------------------
  group('Inbox and Nudge links open the whole catalog in place (issues 11, '
      '15)', () {
    Future<void> tapLink(WidgetTester tester, String link) async {
      final context = navigatorKey.currentContext!;
      // The message the link sits in, over Home.
      unawaited(navigatorKey.currentState!.pushNamed('/app/inbox/message'));
      await tester.pump(const Duration(milliseconds: 400));
      generated.clear();
      await container().read(editorialLinkOpenerProvider)(
        navigatorKey.currentState!.overlay!.context,
        Uri.parse(link),
      );
      expect(context.mounted, isTrue);
      await settle(tester);
    }

    testWidgets('/app/players/<id>/games opens over the message', (
      tester,
    ) async {
      final opened = <Widget>[];
      await pumpApp(
        tester,
        overrides: [
          appDestinationPageNavigationProvider.overrideWithValue(
            (_, page, __) => opened.add(page),
          ),
        ],
      );
      DeepLinkService.notifyAppReady();
      await tapLink(tester, 'https://chessever.com/app/players/1503014/games');
      final profile = opened.single as PlayerProfileScreen;
      expect(profile.fideId, 1503014);
      expect(profile.initialTab, PlayerProfileTab.games);
      expect(stack.names, ['/home_screen', '/app/inbox/message']);
      expect(launched, isEmpty);
    });

    testWidgets('/app/settings/notifications opens over the message', (
      tester,
    ) async {
      final opened = <Widget>[];
      await pumpApp(
        tester,
        overrides: [
          appDestinationPageNavigationProvider.overrideWithValue(
            (_, page, __) => opened.add(page),
          ),
        ],
      );
      DeepLinkService.notifyAppReady();
      await tapLink(tester, 'https://chessever.com/app/settings/notifications');
      expect(opened.single, isA<SettingsPage>());
      expect(stack.names, ['/home_screen', '/app/inbox/message']);
    });

    testWidgets('/app/collections/<id> opens the collection over the message', (
      tester,
    ) async {
      final opened = <Widget>[];
      await pumpApp(
        tester,
        overrides: [
          collectionsRepositoryProvider.overrideWithValue(
            _OneCollection(
              const Collection(
                id: 'book-1',
                slug: 'us-chess-championships',
                kind: CollectionKind.book,
                title: 'US Chess Championships',
                access: CollectionAccess.premium,
                contentLocked: true,
              ),
            ),
          ),
          appDestinationPageNavigationProvider.overrideWithValue(
            (_, page, __) => opened.add(page),
          ),
        ],
      );
      DeepLinkService.notifyAppReady();
      await tapLink(
        tester,
        'https://chessever.com/app/collections/us-chess-championships',
      );
      expect(opened.single, isA<CollectionScreen>());
      expect(stack.names, ['/home_screen', '/app/inbox/message']);
    });

    testWidgets('/app/webview?url= opens the page in the app', (tester) async {
      final opened = <Widget>[];
      await pumpApp(
        tester,
        overrides: [
          appDestinationPageNavigationProvider.overrideWithValue(
            (_, page, __) => opened.add(page),
          ),
        ],
      );
      DeepLinkService.notifyAppReady();
      await tapLink(
        tester,
        'https://chessever.com/app/webview?url=https%3A%2F%2Fexample.com%2Fa',
      );
      expect(
        (opened.single as AppWebViewScreen).url,
        Uri.parse('https://example.com/a'),
      );
      expect(launched, isEmpty);
    });

    testWidgets('/app/feed selects the dock Feed tab, pushing nothing', (
      tester,
    ) async {
      // The real editorial navigation: with Home under the message it opens
      // the dock's tab and builds no second FeedScreen.
      await pumpApp(tester);
      DeepLinkService.notifyAppReady();
      await tapLink(tester, 'https://chessever.com/app/feed');
      expect(
        container().read(selectedBottomNavBarItemProvider),
        BottomNavBarItem.feed,
      );
      expect(stack.names, ['/home_screen']);
      expect(generated, isEmpty);
      // Analytics for the section change leaves a timer behind.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('an account page opens in a browser over the app', (
      tester,
    ) async {
      await pumpApp(tester);
      DeepLinkService.notifyAppReady();
      await tapLink(tester, 'https://chessever.com/account');
      expect(launched.single.$1, Uri.parse('https://chessever.com/account'));
    });

    // O7: the shapes the news router also reads (My Space's pages, Likes,
    // Reports, legacy content paths) used to reset Home and close the
    // message; Back now returns to it.
    for (final entry in <String, bool Function(Widget)>{
      'https://chessever.com/app/my-space/prep': (page) =>
          page is MyPrepHomeScreen,
      'https://chessever.com/app/likes/week': (page) =>
          page is ProviderScope && page.child is LikesScreen,
    }.entries) {
      testWidgets('${entry.key} opens over the message (O7)', (tester) async {
        final opened = <Widget>[];
        await pumpApp(
          tester,
          overrides: [
            appDestinationPageNavigationProvider.overrideWithValue(
              (_, page, __) => opened.add(page),
            ),
          ],
        );
        DeepLinkService.notifyAppReady();
        await tapLink(tester, entry.key);
        expect(opened, hasLength(1));
        expect(entry.value(opened.single), isTrue, reason: '${opened.single}');
        expect(stack.names, ['/home_screen', '/app/inbox/message']);
        expect(generated, isEmpty);
      });
    }

    testWidgets('/app/reports/<type> asks for Reports, then opens over the '
        'message (O7)', (tester) async {
      final opened = <Widget>[];
      final asked = <String>[];
      await pumpApp(
        tester,
        overrides: [
          appDestinationPageNavigationProvider.overrideWithValue(
            (_, page, __) => opened.add(page),
          ),
          appDestinationAccessRequestProvider.overrideWithValue((
            _,
            feature,
          ) async {
            asked.add(feature);
            return true;
          }),
        ],
      );
      DeepLinkService.notifyAppReady();
      await tapLink(tester, 'https://chessever.com/app/reports/missed_chance');
      expect(asked, ['game_reports'], reason: 'the Reports gate is kept');
      expect((opened.single as ProviderScope).child, isA<ReportsScreen>());
      expect(stack.names, ['/home_screen', '/app/inbox/message']);
    });

    for (final link in [
      'https://chessever.com/games/XBnzfSW7',
      'https://chessever.com/app/games/XBnzfSW7',
    ]) {
      testWidgets('$link opens the board over the message; Back returns to '
          'it (O7)', (tester) async {
        await pumpApp(
          tester,
          overrides: [
            gameRepositoryProvider.overrideWithValue(_Games({'XBnzfSW7'})),
            roundRepositoryProvider.overrideWithValue(_Rounds()),
          ],
        );
        DeepLinkService.notifyAppReady();
        await tapLink(tester, link);
        expect(find.text('board XBnzfSW7'), findsOneWidget);
        expect(stack.names, ['/home_screen', '/app/inbox/message', isNull]);
        navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        expect(stack.names, ['/home_screen', '/app/inbox/message']);
      });
    }

    testWidgets('a broadcast link opens the event over the message (O7)', (
      tester,
    ) async {
      await pumpApp(
        tester,
        overrides: [
          tourRepositoryProvider.overrideWithValue(_Tours()),
          groupBroadcastRepositoryProvider.overrideWithValue(_Groups()),
          roundRepositoryProvider.overrideWithValue(_Rounds()),
          tourDetailRepoProvider.overrideWithValue(_Selection()),
        ],
      );
      DeepLinkService.notifyAppReady();
      await tapLink(tester, 'https://chessever.com/broadcast/tt/mKgqPByN');
      expect(generated, ['/tournament_detail_screen']);
      expect(stack.names, [
        '/home_screen',
        '/app/inbox/message',
        '/tournament_detail_screen',
      ]);
    });

    testWidgets('a game that cannot be found leaves the message open, with a '
        'snack (O7)', (tester) async {
      await pumpApp(
        tester,
        overrides: [
          gameRepositoryProvider.overrideWithValue(_Games(const {})),
          roundRepositoryProvider.overrideWithValue(_Rounds()),
        ],
      );
      DeepLinkService.notifyAppReady();
      await tapLink(tester, 'https://chessever.com/games/ZZZZZZZZ');
      expect(stack.names, ['/home_screen', '/app/inbox/message']);
      expect(generated, isEmpty);
      expect(find.text(kLinkFailedMessage), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  group('a collection link that cannot open keeps the reader in place '
      '(O14)', () {
    const other = Collection(
      id: 'book-2',
      slug: 'another-book',
      kind: CollectionKind.book,
      title: 'Another book',
      access: CollectionAccess.free,
    );

    for (final entry in <String, (CollectionsRepository Function(), String)>{
      'unpublished': (
        () => _OneCollection(other),
        "Couldn't open that collection.",
      ),
      'offline': (
        _OfflineCollections.new,
        'No internet connection. Please check your network and try again.',
      ),
    }.entries) {
      testWidgets('${entry.key}: nothing closes and a snack says why', (
        tester,
      ) async {
        final ref = await pumpApp(
          tester,
          overrides: [
            collectionsRepositoryProvider.overrideWithValue(entry.value.$1()),
          ],
        );
        DeepLinkService.notifyAppReady();
        await coverHome(tester);
        DeepLinkService.instance.handleDeepLink(
          Uri.parse('https://chessever.com/collections/us-chess-championships'),
          navigatorKey,
          ref,
        );
        await settle(tester);
        expect(stack.names, [
          '/home_screen',
          '/search',
          'collection_stories',
          'glass_popup',
        ]);
        expect(generated, isEmpty);
        expect(pages, isEmpty);
        expect(find.text(entry.value.$2), findsOneWidget);
      });
    }

    testWidgets('on a cold start with no Home it falls back to Home', (
      tester,
    ) async {
      final ref = await pumpApp(
        tester,
        overrides: [
          collectionsRepositoryProvider.overrideWithValue(
            _OneCollection(other),
          ),
        ],
      );
      DeepLinkService.notifyAppReady();
      await showAlone(tester, '/splash');
      DeepLinkService.instance.handleDeepLink(
        Uri.parse('https://chessever.com/collections/us-chess-championships'),
        navigatorKey,
        ref,
      );
      await settle(tester);
      expect(generated, ['/home_screen']);
      expect(stack.names, ['/home_screen']);
    });
  });

  // ---------------------------------------------------------------------------
  group("a push during a guest's Google or Apple sign-in waits for the Home "
      'sign-in builds (O17)', () {
    const book = Collection(
      id: 'book-1',
      slug: 'us-chess-championships',
      kind: CollectionKind.book,
      title: 'US Chess Championships',
      access: CollectionAccess.free,
    );

    final cases = <String, (Map<String, dynamic>, Matcher)>{
      'collection_games_added': (
        {
          'type': 'collection_games_added',
          'collection_slug': 'us-chess-championships',
        },
        isA<CollectionScreen>(),
      ),
      'round_started': (
        {
          'type': 'round_started',
          'round_id': 'R0000001',
          'tour_id': 'mKgqPByN',
          'group_broadcast_id': 'gb_mKgqPByN',
        },
        isNull,
      ),
      'smart_event_games': (
        {
          'type': 'smart_event_games',
          'smart_event_id': 'smart_event:sicilian-2600',
          'smart_event_name': 'Sicilian 2600+',
          'formats': 'blitz,live',
          'eco_code': 'B20',
        },
        isA<SmartEventScreen>(),
      ),
      'prep_games_added': (
        {'type': 'prep_games_added', 'prep_profile_id': 'vasif'},
        isA<MyPrepHomeScreen>(),
      ),
    };

    for (final entry in cases.entries) {
      testWidgets('${entry.key}: held, Home kept, no sign-in over it; then '
          'opens over the new Home', (tester) async {
        await pumpApp(
          tester,
          overrides: [
            collectionsRepositoryProvider.overrideWithValue(
              _OneCollection(book),
            ),
            tourRepositoryProvider.overrideWithValue(_Tours()),
            groupBroadcastRepositoryProvider.overrideWithValue(_Groups()),
            roundRepositoryProvider.overrideWithValue(_Rounds()),
            tourDetailRepoProvider.overrideWithValue(_Selection()),
            favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
            prepProfilesProvider.overrideWith((ref) => _NoPrepProfiles()),
          ],
        );
        DeepLinkService.notifyAppReady();
        // A guest's Sign up over Home; Google is being asked.
        unawaited(navigatorKey.currentState!.pushNamed('/auth_screen'));
        GuestGateRouteObserver.instance.topRouteName.value = '/auth_screen';
        await tester.pump(const Duration(milliseconds: 400));
        generated.clear();
        final auth =
            container().read(authStateProvider.notifier) as _SwitchableAuth;
        auth.startSignIn();
        await tester.pump();

        DeepLinkService.instance.ingestNotificationData(entry.value.$1);
        await settle(tester);
        expect(stack.names, ['/home_screen', '/auth_screen']);
        expect(generated, isEmpty, reason: 'never sign-in rebuilt over Home');
        expect(pages, isEmpty, reason: 'nothing opened over the sign-in');
        expect(DeepLinkService.instance.hasPendingDestination, isTrue);

        // Signed in: the auth screen puts Home up anew, alone; it routes the
        // held push.
        auth.finishSignIn();
        await finishOnboarding(tester);
        await settle(tester);
        expect(DeepLinkService.instance.hasPendingDestination, isFalse);
        if (entry.key == 'round_started') {
          expect(generated.last, '/tournament_detail_screen');
          expect(stack.names, ['/home_screen', '/tournament_detail_screen']);
        } else {
          expect(pages.single, entry.value.$2);
          expect(stack.names, ['/home_screen', isNull]);
        }
      });
    }
  });

  // ---------------------------------------------------------------------------
  group('a news article\'s links open over the article (O21)', () {
    FeedNews article(String source) => FeedNews(
      id: 4242,
      title: 'Gukesh wins the opener',
      summary: 'Round 1',
      content: 'The full report of round 1.',
      publishedAt: DateTime.utc(2026, 11, 20),
      sourceUrl: source,
    );

    /// The real reader over Home, as Discovery's News opens it.
    Future<void> openArticle(WidgetTester tester, FeedNews news) async {
      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/news/4242'),
            builder: (_) =>
                NewsReaderScreen(news: news, showRelatedArticles: false),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      generated.clear();
    }

    Future<void> tapSource(WidgetTester tester, String label) async {
      // The reader's list builds the row before it scrolls into view.
      await tester.ensureVisible(find.text(label, skipOffstage: false));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(label));
      await settle(tester);
    }

    testWidgets('a game opens over the article; Back returns to it', (
      tester,
    ) async {
      await pumpApp(
        tester,
        overrides: [
          feedNewsProvider.overrideWith((ref) async => const <FeedNews>[]),
          gameRepositoryProvider.overrideWithValue(_Games({'XBnzfSW7'})),
          roundRepositoryProvider.overrideWithValue(_Rounds()),
        ],
      );
      DeepLinkService.notifyAppReady();
      await openArticle(tester, article('/games/XBnzfSW7'));
      await tapSource(tester, 'Open Game');
      expect(find.text('board XBnzfSW7'), findsOneWidget);
      expect(stack.names, ['/home_screen', '/news/4242', isNull]);
      expect(launched, isEmpty);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(stack.names, ['/home_screen', '/news/4242']);
      expect(find.text('Gukesh wins the opener'), findsOneWidget);
    });

    testWidgets('an event opens over the article', (tester) async {
      await pumpApp(
        tester,
        overrides: [
          feedNewsProvider.overrideWith((ref) async => const <FeedNews>[]),
          tourRepositoryProvider.overrideWithValue(_Tours()),
          groupBroadcastRepositoryProvider.overrideWithValue(_Groups()),
          roundRepositoryProvider.overrideWithValue(_Rounds()),
          tourDetailRepoProvider.overrideWithValue(_Selection()),
        ],
      );
      DeepLinkService.notifyAppReady();
      await openArticle(tester, article('/broadcast/tt/mKgqPByN'));
      await tapSource(tester, 'Open Event');
      expect(generated, ['/tournament_detail_screen']);
      expect(stack.names, [
        '/home_screen',
        '/news/4242',
        '/tournament_detail_screen',
      ]);
    });

    testWidgets('a game that cannot be found leaves the article open, with a '
        'snack', (tester) async {
      await pumpApp(
        tester,
        overrides: [
          feedNewsProvider.overrideWith((ref) async => const <FeedNews>[]),
          gameRepositoryProvider.overrideWithValue(_Games(const {})),
          roundRepositoryProvider.overrideWithValue(_Rounds()),
        ],
      );
      DeepLinkService.notifyAppReady();
      await openArticle(tester, article('/games/ZZZZZZZZ'));
      await tapSource(tester, 'Open Game');
      expect(stack.names, ['/home_screen', '/news/4242']);
      expect(generated, isEmpty);
      expect(find.text(kLinkFailedMessage), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  group('a WebView link or push waits like every other destination (O22)', () {
    Future<_SwitchableAuth> signUpUnderWay(WidgetTester tester) async {
      unawaited(navigatorKey.currentState!.pushNamed('/auth_screen'));
      GuestGateRouteObserver.instance.topRouteName.value = '/auth_screen';
      await tester.pump(const Duration(milliseconds: 400));
      generated.clear();
      final auth =
          container().read(authStateProvider.notifier) as _SwitchableAuth;
      auth.startSignIn();
      await tester.pump();
      return auth;
    }

    for (final entry in <String, void Function(WidgetRef)>{
      'a push route': (_) => DeepLinkService.instance.ingestNotificationData({
        'route':
            'https://chessever.com/webview?url=https%3A%2F%2Fexample.com%2Fa',
      }),
      'a push url wrapper': (_) =>
          DeepLinkService.instance.ingestNotificationData({
            'url':
                'https://chessever.com/webview?url=https%3A%2F%2Fexample.com%2Fa',
          }),
    }.entries) {
      testWidgets('${entry.key} during a guest\'s sign-in is held, then opens '
          'over the Home sign-in builds', (tester) async {
        final opened = <Widget>[];
        final ref = await pumpApp(
          tester,
          overrides: [
            appDestinationPageNavigationProvider.overrideWithValue(
              (_, page, __) => opened.add(page),
            ),
          ],
        );
        DeepLinkService.notifyAppReady();
        final auth = await signUpUnderWay(tester);
        entry.value(ref);
        await settle(tester);
        expect(opened, isEmpty, reason: 'never over the Sign up page');
        expect(stack.names, ['/home_screen', '/auth_screen']);
        expect(DeepLinkService.instance.hasPendingDestination, isTrue);

        auth.finishSignIn();
        await finishOnboarding(tester);
        await settle(tester);
        expect(
          (opened.single as AppWebViewScreen).url,
          Uri.parse('https://example.com/a'),
        );
        expect(DeepLinkService.instance.hasPendingDestination, isFalse);
      });
    }

    testWidgets('an outside /webview link while onboarding is alone on screen '
        'waits for Home', (tester) async {
      final opened = <Widget>[];
      final ref = await pumpApp(
        tester,
        overrides: [
          appDestinationPageNavigationProvider.overrideWithValue(
            (_, page, __) => opened.add(page),
          ),
        ],
      );
      DeepLinkService.notifyAppReady();
      await showAlone(tester, '/onboarding');
      DeepLinkService.instance.handleDeepLink(
        Uri.parse(
          'https://chessever.com/webview?url=https%3A%2F%2Fchessever.com%2Fpremium',
        ),
        navigatorKey,
        ref,
      );
      await settle(tester);
      expect(opened, isEmpty);
      expect(DeepLinkService.instance.hasPendingDestination, isTrue);

      await finishOnboarding(tester);
      await settle(tester);
      expect(
        (opened.single as AppWebViewScreen).url,
        Uri.parse('https://chessever.com/premium'),
      );
    });

    // Links tapped inside the app are never held: the reader is in the app,
    // and an in-place tap is never kept for a Home to replay (it would be
    // lost), whatever the auth state or the screen behind says.
    for (final entry in <String, Future<void> Function(WidgetTester)>{
      'while a sign-in is under way': (tester) async {
        unawaited(navigatorKey.currentState!.pushNamed('/app/inbox/message'));
        await tester.pump(const Duration(milliseconds: 400));
        (container().read(authStateProvider.notifier) as _SwitchableAuth)
            .startSignIn();
        await tester.pump();
      },
      'with onboarding alone on screen': (tester) =>
          showAlone(tester, '/onboarding'),
    }.entries) {
      testWidgets('a WebView link tapped in the app opens at once '
          '${entry.key}', (tester) async {
        final opened = <Widget>[];
        await pumpApp(
          tester,
          overrides: [
            appDestinationPageNavigationProvider.overrideWithValue(
              (_, page, __) => opened.add(page),
            ),
          ],
        );
        DeepLinkService.notifyAppReady();
        await entry.value(tester);
        final routes = List<String?>.of(stack.names);
        await container().read(editorialLinkOpenerProvider)(
          navigatorKey.currentState!.overlay!.context,
          Uri.parse(
            'https://chessever.com/webview?url=https%3A%2F%2Fexample.com%2Fa',
          ),
        );
        await settle(tester);
        expect(
          (opened.single as AppWebViewScreen).url,
          Uri.parse('https://example.com/a'),
        );
        expect(DeepLinkService.instance.hasPendingDestination, isFalse);
        expect(stack.names, routes, reason: 'over the page it was tapped on');
      });
    }

    testWidgets('a WebView link with Home in front still opens at once', (
      tester,
    ) async {
      final opened = <Widget>[];
      final ref = await pumpApp(
        tester,
        overrides: [
          appDestinationPageNavigationProvider.overrideWithValue(
            (_, page, __) => opened.add(page),
          ),
        ],
      );
      DeepLinkService.notifyAppReady();
      DeepLinkService.instance.handleDeepLink(
        Uri.parse(
          'https://chessever.com/webview?url=https%3A%2F%2Fchessever.com%2Fpremium',
        ),
        navigatorKey,
        ref,
      );
      await settle(tester);
      expect(opened.single, isA<AppWebViewScreen>());
      expect(DeepLinkService.instance.hasPendingDestination, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('a sign-in cancelled with no session to open the held push for '
      '(O20)', () {
    const book = Collection(
      id: 'book-1',
      slug: 'us-chess-championships',
      kind: CollectionKind.book,
      title: 'US Chess Championships',
      access: CollectionAccess.free,
    );

    for (final ended in const [
      ('error', AppAuthState.error('Sign in was cancelled')),
      ('unauthenticated', AppAuthState.unauthenticated()),
    ]) {
      testWidgets('(${ended.$1}) lets it go with a quiet word; nothing moves, '
          'no sign-in over Home', (tester) async {
        await pumpApp(
          tester,
          overrides: [
            collectionsRepositoryProvider.overrideWithValue(
              _OneCollection(book),
            ),
          ],
        );
        DeepLinkService.notifyAppReady();
        unawaited(navigatorKey.currentState!.pushNamed('/auth_screen'));
        GuestGateRouteObserver.instance.topRouteName.value = '/auth_screen';
        await tester.pump(const Duration(milliseconds: 400));
        generated.clear();
        final auth =
            container().read(authStateProvider.notifier) as _SwitchableAuth;
        auth.startSignIn();
        await tester.pump();
        DeepLinkService.instance.ingestNotificationData({
          'type': 'collection_games_added',
          'collection_slug': 'us-chess-championships',
        });
        await settle(tester);
        expect(DeepLinkService.instance.hasPendingDestination, isTrue);

        // This harness has no Supabase session: nothing survives the
        // cancelled sign-in to open the push for.
        _signedIn = false;
        auth.cancelSignIn(ended.$2);
        await settle(tester);
        // A moment for a sign-in page the app may still put up.
        expect(DeepLinkService.instance.hasPendingDestination, isTrue);
        await tester.pump(const Duration(seconds: 3));
        await settle(tester);
        expect(DeepLinkService.instance.hasPendingDestination, isFalse);
        expect(find.text(kHeldLinkNeedsSignInMessage), findsOneWidget);
        expect(stack.names, ['/home_screen', '/auth_screen']);
        expect(generated, isEmpty);
        expect(pages, isEmpty);
      });
    }

    testWidgets('a sign-out that ends on sign-in alone keeps the push for the '
        'Home the next sign-in builds', (tester) async {
      await pumpApp(
        tester,
        overrides: [
          collectionsRepositoryProvider.overrideWithValue(_OneCollection(book)),
        ],
      );
      DeepLinkService.notifyAppReady();
      final auth =
          container().read(authStateProvider.notifier) as _SwitchableAuth;
      // Signing out: the controller says loading until it lands.
      auth.startSignIn();
      await tester.pump();
      DeepLinkService.instance.ingestNotificationData({
        'type': 'collection_games_added',
        'collection_slug': 'us-chess-championships',
      });
      await settle(tester);
      expect(DeepLinkService.instance.hasPendingDestination, isTrue);

      _signedIn = false;
      auth.cancelSignIn(const AppAuthState.unauthenticated());
      await settle(tester);
      // AuthStateListener clears the reader's caches, then puts sign-in up
      // alone.
      await showAlone(tester, '/auth_screen');
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(DeepLinkService.instance.hasPendingDestination, isTrue);
      expect(find.text(kHeldLinkNeedsSignInMessage), findsNothing);

      auth.finishSignIn();
      await finishOnboarding(tester);
      await settle(tester);
      expect(pages.single, isA<CollectionScreen>());
    });

    testWidgets('with sign-in alone on screen it keeps waiting for the Home '
        'sign-in builds', (tester) async {
      await pumpApp(
        tester,
        overrides: [
          collectionsRepositoryProvider.overrideWithValue(_OneCollection(book)),
        ],
      );
      DeepLinkService.notifyAppReady();
      await showAlone(tester, '/auth_screen');
      final auth =
          container().read(authStateProvider.notifier) as _SwitchableAuth;
      auth.startSignIn();
      await tester.pump();
      DeepLinkService.instance.ingestNotificationData({
        'type': 'collection_games_added',
        'collection_slug': 'us-chess-championships',
      });
      await settle(tester);
      _signedIn = false;
      auth.cancelSignIn(const AppAuthState.unauthenticated());
      await settle(tester);
      expect(DeepLinkService.instance.hasPendingDestination, isTrue);
      expect(find.text(kHeldLinkNeedsSignInMessage), findsNothing);
      expect(generated, isEmpty);

      // Tried again, and signed in this time: the Home it builds routes it.
      auth.startSignIn();
      await tester.pump();
      auth.finishSignIn();
      await finishOnboarding(tester);
      await settle(tester);
      expect(pages.single, isA<CollectionScreen>());
      expect(DeepLinkService.instance.hasPendingDestination, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('a push in OneSignal\'s envelope routes like the same push sent '
      'directly (O6)', () {
    const id = '7f2c1a9e-4b1d-4f0e-9c3a-2d6b8e1f0a55';
    const book = Collection(
      id: 'book-1',
      slug: 'us-chess-championships',
      kind: CollectionKind.book,
      title: 'US Chess Championships',
      access: CollectionAccess.free,
    );

    testWidgets('an iOS tap (custom.a, no gcm.message_id) opens the board', (
      tester,
    ) async {
      await pumpApp(
        tester,
        overrides: [
          gameRepositoryProvider.overrideWithValue(_Games({'XBnzfSW7'})),
          roundRepositoryProvider.overrideWithValue(_Rounds()),
        ],
      );
      DeepLinkService.notifyAppReady();
      DeepLinkService.instance.ingestNotificationData({
        'custom': {
          'i': id,
          'a': {'type': 'game_started', 'game_id': 'XBnzfSW7'},
        },
      });
      await settle(tester);
      expect(find.text('board XBnzfSW7'), findsOneWidget);
      expect(stack.names, ['/home_screen', isNull]);
    });

    testWidgets('the Android notification the app drew routes from its '
        'payload', (tester) async {
      await pumpApp(
        tester,
        overrides: [
          collectionsRepositoryProvider.overrideWithValue(_OneCollection(book)),
        ],
      );
      DeepLinkService.notifyAppReady();
      // What DirectPushService.presentOneSignalPush puts in the payload, read
      // back as its tap hands it over.
      final drawn = parseOneSignalPush({
        'custom': jsonEncode({
          'i': id,
          'a': {
            'type': 'collection_games_added',
            'collection_slug': 'us-chess-championships',
            'added': 3,
          },
        }),
        'title': 'US Chess Championships',
        'alert': '3 new games just landed.',
      })!;
      DeepLinkService.instance.ingestNotificationData(
        Map<String, dynamic>.from(
          jsonDecode(jsonEncode(drawn.data)) as Map<String, dynamic>,
        ),
      );
      await settle(tester);
      expect((pages.single as CollectionScreen).collection.slug, book.slug);
      // `added` arrived as JSON 3 and reads as FCM's "3".
      expect(
        find.text('3 new games just landed in US Chess Championships.'),
        findsOneWidget,
      );
    });

    testWidgets('a chessever.com launch URL opens in the app when the data '
        'names nothing', (tester) async {
      await pumpApp(
        tester,
        overrides: [
          collectionsRepositoryProvider.overrideWithValue(_OneCollection(book)),
        ],
      );
      DeepLinkService.notifyAppReady();
      DeepLinkService.instance.ingestNotificationData({
        'custom': {
          'i': id,
          'u': 'https://chessever.com/collections/us-chess-championships',
        },
      });
      await settle(tester);
      expect(pages.single, isA<CollectionScreen>());
    });

    testWidgets('a browser launch URL is ignored: no WebView, Home stays', (
      tester,
    ) async {
      final opened = <Widget>[];
      await pumpApp(
        tester,
        overrides: [
          appDestinationPageNavigationProvider.overrideWithValue(
            (_, page, __) => opened.add(page),
          ),
        ],
      );
      DeepLinkService.notifyAppReady();
      DeepLinkService.instance.ingestNotificationData({
        'custom': {'i': id, 'u': 'https://example.com/promo'},
      });
      await settle(tester);
      expect(opened, isEmpty);
      expect(launched, isEmpty);
      expect(stack.names, ['/home_screen']);
    });
  });

  // ---------------------------------------------------------------------------
  // The iPhone simulator run (2026-11-23): every universal link opened from
  // outside reached Dart twice, and a /webview link stacked two WebViews
  // (one Back left the second). Each delivery arrives as its own platform
  // message, so the first has opened its page before the second comes.
  group('one tap delivered twice opens once', () {
    const premium =
        'https://chessever.com/webview?url=https%3A%2F%2Fchessever.com%2Fpremium';
    const pricing =
        'https://chessever.com/webview?url=https%3A%2F%2Fchessever.com%2Fpricing';

    Future<(WidgetRef, List<Widget>)> pumpWithPages(WidgetTester tester) async {
      final opened = <Widget>[];
      final ref = await pumpApp(
        tester,
        overrides: [
          appDestinationPageNavigationProvider.overrideWithValue(
            (_, page, __) => opened.add(page),
          ),
        ],
      );
      DeepLinkService.notifyAppReady();
      return (ref, opened);
    }

    List<Uri> webViews(List<Widget> opened) => [
      for (final page in opened) (page as AppWebViewScreen).url,
    ];

    testWidgets('the same /webview link delivered twice opens one WebView', (
      tester,
    ) async {
      final (ref, opened) = await pumpWithPages(tester);
      DeepLinkService.instance.handleDeepLink(
        Uri.parse(premium),
        navigatorKey,
        ref,
      );
      await tester.pump();
      expect(webViews(opened), [Uri.parse('https://chessever.com/premium')]);

      DeepLinkService.instance.handleDeepLink(
        Uri.parse(premium),
        navigatorKey,
        ref,
      );
      await settle(tester);
      expect(webViews(opened), [Uri.parse('https://chessever.com/premium')]);
    });

    testWidgets('another link inside the window, and the same link after '
        'it, still open', (tester) async {
      final (ref, opened) = await pumpWithPages(tester);
      var now = DateTime.utc(2026, 11, 23, 12);
      DeepLinkService.instance.debugClock = () => now;
      void tap(String link) => DeepLinkService.instance.handleDeepLink(
        Uri.parse(link),
        navigatorKey,
        ref,
      );

      tap(premium);
      await tester.pump();
      now = now.add(const Duration(milliseconds: 300));
      tap('$premium#again'); // the same link: the fragment never routes
      await tester.pump();
      tap(pricing);
      await tester.pump();
      now = now.add(DeepLinkService.outsideLinkRepeatWindow);
      tap(pricing);
      await settle(tester);

      expect(webViews(opened), [
        Uri.parse('https://chessever.com/premium'),
        Uri.parse('https://chessever.com/pricing'),
        Uri.parse('https://chessever.com/pricing'),
      ]);
    });

    testWidgets('a game link and a collection link delivered twice open once '
        'each', (tester) async {
      final ref = await pumpApp(
        tester,
        overrides: [
          gameRepositoryProvider.overrideWithValue(_Games({'XBnzfSW7'})),
          collectionsRepositoryProvider.overrideWithValue(
            _OneCollection(
              const Collection(
                id: 'book-1',
                slug: 'us-chess-championships',
                kind: CollectionKind.book,
                title: 'US Chess Championships',
                access: CollectionAccess.free,
              ),
            ),
          ),
        ],
      );
      DeepLinkService.notifyAppReady();
      Future<void> deliverTwice(String link) async {
        DeepLinkService.instance.handleDeepLink(
          Uri.parse(link),
          navigatorKey,
          ref,
        );
        await tester.pump();
        DeepLinkService.instance.handleDeepLink(
          Uri.parse(link),
          navigatorKey,
          ref,
        );
        await settle(tester);
      }

      await deliverTwice('https://chessever.com/games/XBnzfSW7');
      expect(stack.names, ['/home_screen', isNull]);
      expect(find.text('board XBnzfSW7'), findsOneWidget);

      await deliverTwice(
        'https://chessever.com/collections/us-chess-championships',
      );
      expect(stack.names, ['/home_screen', isNull]);
      expect(pages.whereType<CollectionScreen>(), hasLength(1));
    });

    testWidgets('a cold start routes the launch link once; a replay right '
        'after is dropped, the same link tapped later opens', (tester) async {
      final (ref, opened) = await pumpWithPages(tester);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const methods = MethodChannel('com.llfbandit.app_links/messages');
      const events = EventChannel('com.llfbandit.app_links/events');
      // app_links' native side: getInitialLink answers the launch link, and
      // the stream's first listener gets it again (never marked sent).
      messenger.setMockMethodCallHandler(
        methods,
        (call) async => call.method == 'getInitialLink' ? premium : null,
      );
      // The stream is app_links' one broadcast stream (Supabase may already
      // listen to it): a link arrives as a message on its channel.
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(onListen: (_, _) {}),
      );
      // Its controllers were made outside this test's clock: let the real
      // event loop hand the message on.
      Future<void> deliver(String link) => tester.runAsync(() async {
        await messenger.handlePlatformMessage(
          events.name,
          const StandardMethodCodec().encodeSuccessEnvelope(link),
          (_) {},
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(methods, null);
        messenger.setMockStreamHandler(events, null);
      });
      final launch = DateTime.utc(2026, 11, 23, 12);
      var now = launch;
      DeepLinkService.instance.debugClock = () => now;

      await DeepLinkService.instance.initialize(navigatorKey, ref);
      await tester.pump();
      expect(webViews(opened), [Uri.parse('https://chessever.com/premium')]);

      // A replay right after subscribing (when this listener, not Supabase's,
      // is the one app_links replays to) falls in the repeat window.
      now = launch.add(const Duration(seconds: 1));
      await deliver(premium);
      await settle(tester);
      expect(webViews(opened), [Uri.parse('https://chessever.com/premium')]);

      // The same link tapped minutes later is a tap again, even when the
      // replay never reached this listener (Supabase subscribed first).
      now = launch.add(const Duration(minutes: 3));
      await deliver(premium);
      await settle(tester);
      expect(webViews(opened), [
        Uri.parse('https://chessever.com/premium'),
        Uri.parse('https://chessever.com/premium'),
      ]);
    });
  });
}

/// Home as the router sees it: a page that registers its route as the home
/// shell, exactly as HomeScreen does, and a Scaffold so snacks can show.
class _HomeShell extends ConsumerStatefulWidget {
  const _HomeShell();

  @override
  ConsumerState<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<_HomeShell> {
  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    // As HomeScreen: a link held while the reader signed in or onboarded is
    // routed once Home is up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) DeepLinkService.instance.drainPendingDestination();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!identical(route, _route)) {
      unregisterHomeShellRoute(_route);
      _route = route;
    }
    registerHomeShellRoute(route);
  }

  @override
  void dispose() {
    unregisterHomeShellRoute(_route);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hold the section as the dock does.
    ref.watch(selectedBottomNavBarItemProvider);
    return const Scaffold(body: Text('home'));
  }
}

/// The stories viewer's kind of route: full screen, not opaque, on the root
/// navigator.
class _StoriesStandIn extends ModalRoute<void> {
  _StoriesStandIn()
    : super(settings: const RouteSettings(name: 'collection_stories'));

  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => false;
  @override
  String? get barrierLabel => null;
  @override
  bool get maintainState => true;
  @override
  bool get opaque => false;
  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => const ColoredBox(color: Colors.black, child: Text('stories'));
}

/// A glass menu or sheet: a popup route.
class _PopupStandIn extends PopupRoute<void> {
  _PopupStandIn() : super(settings: const RouteSettings(name: 'glass_popup'));

  @override
  Color? get barrierColor => Colors.black26;
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => 'Dismiss';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => const Center(child: Text('menu'));
}

/// The navigator's routes, bottom to top, by name.
class _Stack extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  List<String?> get names => [for (final r in routes) r.settings.name];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : routes.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) routes[index] = newRoute;
  }
}

Games _game(String id) => Games(
  id: id,
  roundId: 'R0000001',
  roundSlug: 'round-1',
  tourId: 'mKgqPByN',
  tourSlug: 'titled-tuesday',
  players: [
    Player(
      name: 'White',
      title: 'GM',
      rating: 2700,
      fideId: 1,
      fed: 'USA',
      clock: 0,
      team: '',
    ),
    Player(
      name: 'Black',
      title: 'GM',
      rating: 2690,
      fideId: 2,
      fed: 'NOR',
      clock: 0,
      team: '',
    ),
  ],
);

/// The real GameRepository resolver over a fake table: [ids] are games.id
/// values, [lichess] maps a lichess_id to its games.id.
class _Games extends GameRepository {
  _Games(this.ids, {this.lichess = const {}, this.hold = const {}});

  final Set<String> ids;
  final Map<String, String> lichess;
  final Map<String, Completer<void>> hold;
  final byId = <String>[];
  final byLichessId = <String>[];

  @override
  Future<Games?> findGameById(String id) async {
    byId.add(id);
    await hold[id]?.future;
    return ids.contains(id) ? _game(id) : null;
  }

  @override
  Future<Games> getGameByLichessId(String lichessId) async {
    byLichessId.add(lichessId);
    final id = lichess[lichessId];
    if (id == null) throw Exception('No rows found');
    return _game(id);
  }

  @override
  Future<Games> getGameById(String id) async {
    final game = await findGameById(id);
    if (game == null) throw Exception('No rows found');
    return game;
  }

  @override
  Future<List<Games>> getGamesByRoundId(String roundId) async => const [];
}

class _Rounds implements RoundRepository {
  final requested = <String>[];

  @override
  Future<Round> getRoundById(String id) async {
    requested.add(id);
    if (id != 'R0000001') throw Exception('No rows found');
    return Round(
      id: id,
      slug: 'round-4',
      tourId: 'mKgqPByN',
      tourSlug: 'titled-tuesday',
      name: 'Round 4',
      createdAt: DateTime.utc(2026, 9, 29),
      url: '',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Tours implements TourRepository {
  _Tours({this.known = true});

  final bool known;
  List<String>? requested;

  @override
  Future<List<Tour>> getToursByIds(List<String> ids) async {
    requested = [...?requested, ...ids];
    if (!known || !ids.contains('mKgqPByN')) return const [];
    return [
      Tour(
        id: 'mKgqPByN',
        name: 'Titled Tuesday',
        slug: 'titled-tuesday',
        info: TourInfo(),
        createdAt: DateTime(2026, 9, 29),
        url: '',
        tier: 0,
        dates: [],
        players: [],
        groupBroadcastId: 'gb_mKgqPByN',
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Groups implements GroupBroadcastRepository {
  String? requested;

  @override
  Future<GroupBroadcast> getGroupBroadcastById(String id) async {
    requested = id;
    if (id != 'gb_mKgqPByN') throw Exception('No rows found');
    return GroupBroadcast(
      id: id,
      createdAt: DateTime(2026, 9, 29),
      name: 'Titled Tuesday',
      search: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Selection implements TourDetailRepo {
  @override
  Future<void> saveSelectedTourId({
    required String groupEventId,
    required String tourId,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Players implements ChessPlayerRepository {
  final requested = <int>[];

  @override
  Future<ChessPlayer?> getPlayerByFideId(int fideId) async {
    requested.add(fideId);
    if (fideId != 1503014) return null;
    return const ChessPlayer(
      fideid: 1503014,
      name: 'Carlsen, Magnus',
      title: 'GM',
      rating: 2830,
      country: 'NOR',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OneCollection extends CollectionsRepository {
  _OneCollection(this.collection)
    : super(GamebaseRepository(Dio(), apiKey: 'test'));

  final Collection collection;

  @override
  Future<Collection> fetchCollection(String slug) async {
    if (slug != collection.slug) throw Exception('not published');
    return collection;
  }
}

/// A catalog that cannot be reached: the device is offline.
class _OfflineCollections extends CollectionsRepository {
  _OfflineCollections() : super(GamebaseRepository(Dio(), apiKey: 'test'));

  @override
  Future<Collection> fetchCollection(String slug) async =>
      throw const SocketException('Failed host lookup: gamebase');
}

class _NoFavoriteEvents extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const <FavoriteEvent>[];
}

/// No Prep profile on this device (the push was starred on another).
class _NoPrepProfiles extends StateNotifier<AsyncValue<List<PrepProfile>>>
    implements PrepProfilesNotifier {
  _NoPrepProfiles() : super(const AsyncData(<PrepProfile>[]));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
