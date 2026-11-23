// Links and pushes landing on the REAL HomeScreen. Every test pumps the
// app's own home shell (HomeScreen: its dock, or on a tablet its rail; its
// shell registration; the held-link drain when it mounts; the dock reveal a
// link asks for; its floating buttons) and routes a push or a link through
// the real DeepLinkService while the reader is on a page over Home, the
// Search page above all.
//
// What is stood in, and why: the five section pages
// (homeSectionPageOverrideProvider), which read the network; the providers
// those sections and the shell's background syncs read (favorites, Prep
// sync, Inbox, subscription); the repositories a route reads; and the pages
// the router pushes (DeepLinkService's test seams), which are captured
// rather than built. Search is a page with Search's route name. The reader
// is a guest with a real Supabase session in memory (no network), as a
// guest's session is what links and the game route read.

import 'dart:async';
import 'dart:convert';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/event_video_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/for_you/for_you_screen.dart'
    show
        kDiscoverySearchButtonKey,
        kForYouSearchButtonKey,
        kMySpaceSearchButtonKey;
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/group_event/providers/home_live_first_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/home/home_screen.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/home/widget/home_nav_dock.dart';
import 'package:chessever2/screens/home/widget/tablet_nav_rail.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/screens/inbox/inbox_screen.dart';
import 'package:chessever2/screens/my_prep/my_prep_home_screen.dart';
import 'package:chessever2/screens/my_prep/prep_profiles_cloud.dart';
import 'package:chessever2/screens/my_prep/prep_space_shortcut.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_space/widgets/space_add_fab.dart';
import 'package:chessever2/screens/onboarding/player_selection_screen.dart'
    show markOnboardingComplete;
import 'package:chessever2/screens/search/search_tab_screen.dart'
    show searchRouteName;
import 'package:chessever2/screens/tour_detail/provider/tour_detail_repo_provider.dart';
import 'package:chessever2/screens/webview/app_webview_screen.dart';
import 'package:chessever2/services/app_destination_service.dart';
import 'package:chessever2/services/attention_policy.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/services/editorial_link_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/guest_session_gate_listener.dart';
import 'package:chessever2/widgets/ink_fab.dart' show SearchInkFab;
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite/sqflite.dart' show SqflitePlugin;
import 'package:supabase_flutter/supabase_flutter.dart'
    hide AuthState, AuthException;

import 'inbox_fakes.dart';

const _phone = Size(393, 852);

/// The guest reader: a real anonymous session, held in memory only.
Map<String, dynamic> _guestSession() {
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 24 * 3600;
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {
    'access_token':
        '${encode({'alg': 'none', 'typ': 'JWT'})}.'
        '${encode({'sub': inboxOwnerA, 'exp': expiry})}.LOCAL-FIXTURE',
    'refresh_token': 'LOCAL-FIXTURE-REFRESH',
    'token_type': 'bearer',
    'expires_in': 24 * 3600,
    'expires_at': expiry,
    'user': User(
      id: inboxOwnerA,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-09-30T00:00:00Z',
      isAnonymous: true,
    ).toJson(),
  };
}

final _guest = AppUser(
  id: inboxOwnerA,
  createdAt: DateTime.utc(2026, 9, 30),
  isAnonymous: true,
);

class _GuestAuth extends AuthController {
  @override
  Future<AppAuthState> build() async => AppAuthState.authenticated(_guest);

  /// Google or Apple being asked: the controller says loading, as data,
  /// until the answer lands (AuthController.signInWithGoogle).
  void startSignIn() => state = const AsyncData(AppAuthState.loading());

  void finishSignIn() => state = AsyncData(
    AppAuthState.authenticated(_guest.copyWith(isAnonymous: false)),
  );

  /// Google's or Apple's sheet dismissed: a guest's upgrade lands on
  /// `error`, a plain sign-in on `unauthenticated`
  /// (AuthController.signInWithGoogle / signInWithApple), while the guest's
  /// anonymous session lives on.
  void cancelSignIn(AppAuthState ended) => state = AsyncData(ended);
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription() : super(SubscriptionState(isSubscribed: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoFavoriteEvents extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const <FavoriteEvent>[];
}

class _NoFavoritePlayers extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => const <FavoritePlayer>[];
}

/// Onboarding's last page, as far as finishing it goes: the real
/// [markOnboardingComplete].
class _Onboarding extends StatelessWidget {
  const _Onboarding();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => markOnboardingComplete(context),
        child: const Text('Finish onboarding'),
      ),
    ),
  );
}

/// A section page: a long list, so a scroll can take the dock away.
class _Section extends StatelessWidget {
  const _Section(this.item);

  final BottomNavBarItem item;

  @override
  Widget build(BuildContext context) => ListView.builder(
    key: ValueKey('section-${item.name}'),
    itemCount: 60,
    itemBuilder: (_, i) => SizedBox(height: 72, child: Text('${item.name} $i')),
  );
}

/// Answers the app database's SQLite calls in memory (HomeScreen counts the
/// session there), so no native plugin is needed: the pattern of
/// returning_sign_in_notification_permission_test.dart.
Future<Object?> _sqlite(MethodCall call) async {
  switch (call.method) {
    case 'getDatabasesPath':
      return '/test-home-screen-links';
    case 'openDatabase':
      return <String, Object>{'id': 1};
    case 'query':
      final sql = (call.arguments as Map)['sql'] as String;
      if (sql.contains('user_version')) {
        return <Map<String, Object>>[
          {'user_version': 1},
        ];
      }
      return <Map<String, Object>>[];
    case 'insert':
      return 1;
    default:
      return null;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.tekartik.sqflite'),
          _sqlite,
        );
    SqflitePlugin.registerWith();
    await AppDatabase.instance.database;
    // The guest's one-off favorites cleanup already ran (onboarding's end
    // reads it).
    SharedPreferences.setMockInitialValues({
      'favorites_cleanup_v1_$inboxOwnerA': true,
    });
    await SharedPreferencesService.instance.initialize();
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      publishableKey: 'LOCAL-FIXTURE-ANON-KEY',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((_) async => http.Response('[]', 404)),
    );
    await Supabase.instance.client.auth.setInitialSession(
      jsonEncode(_guestSession()),
    );
  });

  late GlobalKey<NavigatorState> navigatorKey;
  late List<String> generated;
  late List<Widget> pages;
  late _Stack stack;
  late WidgetRef appRef;

  setUp(() {
    DeepLinkService.instance.detachNotificationRouter();
    DeepLinkService.instance.dispose();
    navigatorKey = GlobalKey<NavigatorState>();
    generated = [];
    pages = [];
    stack = _Stack();
    GuestGateRouteObserver.instance.topRouteName.value = null;
  });

  tearDown(() {
    DeepLinkService.instance.detachNotificationRouter();
    DeepLinkService.instance.dispose();
  });

  List<Override> shell() => [
    authStateProvider.overrideWith(_GuestAuth.new),
    homeSectionPageOverrideProvider.overrideWithValue(_Section.new),
    botvinnikTabAvailableProvider.overrideWithValue(true),
    profileAvatarUrlProvider.overrideWithValue(null),
    inboxHasUnreadProvider.overrideWithValue(false),
    subscriptionProvider.overrideWith((ref) => _Subscription()),
    prepKeepFreshProvider.overrideWith((ref) {}),
    prepSpaceSyncProvider.overrideWith((ref) {}),
    prepCloudSyncProvider.overrideWith((ref) {}),
    favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
    favoritePlayersProviderNew.overrideWith(_NoFavoritePlayers.new),
    todayLiveEventCountProvider.overrideWith((ref) => 0),
    eventVideoConfigurationProvider.overrideWithValue(null),
  ];

  Future<void> pumpHome(
    WidgetTester tester, {
    Size size = _phone,
    List<Override> overrides = const [],
    String firstRoute = '/home_screen',
  }) async {
    tester.view
      ..physicalSize = size * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    late WidgetRef rootRef;
    final service = DeepLinkService.instance;
    service.dispose();
    service.debugBoardPageBuilder = (game) =>
        Scaffold(body: Text('board ${game.gameId}'));
    service.debugPageOverride = (page) {
      pages.add(page);
      return Scaffold(body: Text('page ${page.runtimeType}'));
    };
    Route<void> route(RouteSettings settings) => MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => switch (settings.name) {
        '/home_screen' => const HomeScreen(),
        '/onboarding' => const _Onboarding(),
        _ => Scaffold(body: Text('route ${settings.name}')),
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...shell(), ...overrides],
        child: Consumer(
          builder: (_, ref, child) {
            rootRef = ref;
            return child!;
          },
          child: MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: [stack, GuestGateRouteObserver.instance],
            theme: AppTheme.darkTheme,
            themeAnimationDuration: Duration.zero,
            builder: (context, child) {
              ResponsiveHelper.init(context);
              return child!;
            },
            onGenerateRoute: (settings) {
              generated.add(settings.name ?? '');
              return route(settings);
            },
            onGenerateInitialRoutes: (_) => [
              route(RouteSettings(name: firstRoute)),
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
    appRef = rootRef;
    service.attachNotificationRouter(navigatorKey, rootRef);
  }

  ProviderContainer container() =>
      ProviderScope.containerOf(navigatorKey.currentContext!);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The Search page, as Today's button pushes it over Home.
  Future<void> openSearch(WidgetTester tester) async {
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: searchRouteName),
          builder: (_) => const Scaffold(body: Text('search page')),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(stack.names, ['/home_screen', searchRouteName]);
    generated.clear();
  }

  /// The home shell's own state: the same object before and after a tap
  /// means Home was kept, not built anew.
  State<HomeScreen> home(WidgetTester tester) =>
      tester.state(find.byType(HomeScreen, skipOffstage: false));

  /// How much of the dock is shown: 1 in place, 0 gone.
  double dock(WidgetTester tester) =>
      tester.widget<HomeNavDock>(find.byType(HomeNavDock)).chrome!.value;

  BottomNavBarItem section() =>
      container().read(selectedBottomNavBarItemProvider);

  Future<void> back(WidgetTester tester) async {
    navigatorKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// HomeScreen's eight-second review timer and the analytics a section
  /// change leaves run out before the test ends.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  }

  // ---------------------------------------------------------------------------
  group(
    'a tap while the reader is on the Search page lands on the same Home',
    () {
      testWidgets('a game push opens the board over Home; Back returns to it', (
        tester,
      ) async {
        await pumpHome(
          tester,
          overrides: [
            gameRepositoryProvider.overrideWithValue(_Games({'XBnzfSW7'})),
            roundRepositoryProvider.overrideWithValue(_Rounds()),
          ],
        );
        DeepLinkService.notifyAppReady();
        await openSearch(tester);
        final shell = home(tester);
        DeepLinkService.instance.ingestNotificationData({
          'type': 'game_started',
          'game_id': 'XBnzfSW7',
        });
        await settle(tester);
        expect(find.text('board XBnzfSW7'), findsOneWidget);
        expect(stack.names, ['/home_screen', isNull]);
        expect(generated, isEmpty, reason: 'Home kept, not built anew');
        expect(home(tester), same(shell));

        await back(tester);
        expect(stack.names, ['/home_screen']);
        expect(find.text('forYou 0'), findsOneWidget);
        expect(dock(tester), 1);
        await finish(tester);
      });

      testWidgets('an event push opens the event over Home', (tester) async {
        await pumpHome(tester, overrides: _eventRepos());
        DeepLinkService.notifyAppReady();
        await openSearch(tester);
        final shell = home(tester);
        DeepLinkService.instance.ingestNotificationData({
          'type': 'round_started',
          'round_id': 'R0000001',
          'tour_id': 'mKgqPByN',
          'group_broadcast_id': 'gb_mKgqPByN',
        });
        await settle(tester);
        expect(generated, ['/tournament_detail_screen']);
        expect(stack.names, ['/home_screen', '/tournament_detail_screen']);
        expect(home(tester), same(shell));
        await finish(tester);
      });

      testWidgets('a collection push opens the collection over the Collections '
          'tab; Back returns to that tab', (tester) async {
        await pumpHome(
          tester,
          overrides: [
            collectionsRepositoryProvider.overrideWithValue(_OneCollection()),
          ],
        );
        DeepLinkService.notifyAppReady();
        // The reader is on the Collections tab (a tap on the dock), then
        // opens Search.
        await tester.tap(
          find.byKey(bottomNavBarItemKey(BottomNavBarItem.collections)),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('collections 0'), findsOneWidget);
        await openSearch(tester);
        DeepLinkService.instance.ingestNotificationData({
          'type': 'collection_games_added',
          'collection_slug': 'us-chess-championships',
          'added': '3',
        });
        await settle(tester);
        expect(pages.single, isA<CollectionScreen>());
        expect(stack.names, ['/home_screen', isNull]);
        expect(generated, isEmpty);

        await back(tester);
        expect(section(), BottomNavBarItem.collections);
        expect(find.text('collections 0'), findsOneWidget);
        expect(dock(tester), 1);
        await finish(tester);
      });

      testWidgets('/app/collections lands on the Collections dock tab', (
        tester,
      ) async {
        await pumpHome(tester);
        DeepLinkService.notifyAppReady();
        await openSearch(tester);
        final shell = home(tester);
        DeepLinkService.instance.ingestNotificationData({
          'route': '/app/collections',
        });
        await settle(tester);
        expect(stack.names, ['/home_screen']);
        expect(generated, isEmpty);
        expect(section(), BottomNavBarItem.collections);
        expect(find.text('collections 0'), findsOneWidget);
        expect(home(tester), same(shell));
        expect(dock(tester), 1);
        await finish(tester);
      });

      testWidgets('/app/my-space lands on Home, My Space, from another tab', (
        tester,
      ) async {
        await pumpHome(tester);
        DeepLinkService.notifyAppReady();
        await tester.tap(
          find.byKey(bottomNavBarItemKey(BottomNavBarItem.feed)),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(section(), BottomNavBarItem.feed);
        await openSearch(tester);
        DeepLinkService.instance.ingestNotificationData({
          'route': '/app/my-space',
        });
        await settle(tester);
        expect(stack.names, ['/home_screen']);
        expect(section(), BottomNavBarItem.forYou);
        expect(container().read(selectedForYouTabProvider), ForYouTab.mySpace);
        // The shell shows My Space's own button, as it does for the page.
        expect(find.byType(SpaceAddFab), findsOneWidget);
        expect(find.text('forYou 0'), findsOneWidget);
        expect(dock(tester), 1);
        await finish(tester);
      });

      testWidgets('a smart event push opens the smart event over Home', (
        tester,
      ) async {
        await pumpHome(tester);
        DeepLinkService.notifyAppReady();
        await openSearch(tester);
        DeepLinkService.instance.ingestNotificationData({
          'type': 'smart_event_games',
          'smart_event_id': 'smart_event:sicilian-2600',
          'smart_event_name': 'Sicilian 2600+',
          'formats': 'blitz,live',
          'eco_code': 'B20',
        });
        await settle(tester);
        expect(pages.single, isA<SmartEventScreen>());
        expect(stack.names, ['/home_screen', isNull]);
        expect(generated, isEmpty);
        await finish(tester);
      });

      testWidgets('an Inbox nudge route opens its message over the Inbox; a '
          'link in it opens over the message', (tester) async {
        final opened = <Widget>[];
        await pumpHome(
          tester,
          overrides: [
            ..._inbox(),
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
                    builder: (_) => Scaffold(body: Text('opened $name')),
                  ),
                ),
              );
            }),
          ],
        );
        DeepLinkService.notifyAppReady();
        await openSearch(tester);
        DeepLinkService.instance.ingestNotificationData({
          'type': 'call_to_action',
          'inbox_message_id': inboxIdA,
          'route': '/app/inbox/$inboxIdA',
        });
        await settle(tester);
        expect(stack.names, [
          '/home_screen',
          '/app/inbox',
          '/app/inbox/$inboxIdA',
        ]);
        expect(find.byType(InboxMessageScreen), findsOneWidget);

        // A My Space link in the message (O7): over the message, and Back
        // returns to it.
        await container().read(editorialLinkOpenerProvider)(
          tester.element(find.byType(InboxMessageScreen)),
          Uri.parse('https://chessever.com/app/my-space/prep'),
        );
        await settle(tester);
        expect(opened.single, isA<MyPrepHomeScreen>());
        expect(stack.names.last, '/app/my-space/prep');
        expect(stack.names, hasLength(4));
        await back(tester);
        expect(stack.names.last, '/app/inbox/$inboxIdA');
        await finish(tester);
      });
    },
  );

  // ---------------------------------------------------------------------------
  group('the tablet rail routes as the phone dock does', () {
    const iPad = Size(1024, 1366);

    testWidgets('/app/collections selects Collections on the rail', (
      tester,
    ) async {
      await pumpHome(tester, size: iPad);
      DeepLinkService.notifyAppReady();
      expect(find.byType(TabletNavRail), findsOneWidget);
      expect(find.byType(HomeNavDock), findsNothing);
      await openSearch(tester);
      DeepLinkService.instance.ingestNotificationData({
        'route': '/app/collections',
      });
      await settle(tester);
      expect(stack.names, ['/home_screen']);
      expect(section(), BottomNavBarItem.collections);
      expect(find.text('collections 0'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a game push opens the board over the tablet Home', (
      tester,
    ) async {
      await pumpHome(
        tester,
        size: iPad,
        overrides: [
          gameRepositoryProvider.overrideWithValue(_Games({'XBnzfSW7'})),
          roundRepositoryProvider.overrideWithValue(_Rounds()),
        ],
      );
      DeepLinkService.notifyAppReady();
      await openSearch(tester);
      final shell = home(tester);
      DeepLinkService.instance.ingestNotificationData({
        'type': 'game_finished',
        'game_id': 'XBnzfSW7',
      });
      await settle(tester);
      expect(find.text('board XBnzfSW7'), findsOneWidget);
      expect(stack.names, ['/home_screen', isNull]);
      expect(home(tester), same(shell));
      await finish(tester);
    });
  });

  // ---------------------------------------------------------------------------
  group(
    'a link held while onboarding opens on the Home onboarding ends on',
    () {
      for (final entry in <String, void Function(WidgetTester)>{
        'a shared game link': (tester) =>
            DeepLinkService.instance.handleDeepLink(
              Uri.parse('https://chessever.com/games/XBnzfSW7'),
              navigatorKey,
              appRef,
            ),
        'a collection push': (_) =>
            DeepLinkService.instance.ingestNotificationData({
              'type': 'collection_games_added',
              'collection_slug': 'us-chess-championships',
            }),
      }.entries) {
        testWidgets(entry.key, (tester) async {
          await pumpHome(
            tester,
            firstRoute: '/onboarding',
            overrides: [
              gameRepositoryProvider.overrideWithValue(_Games({'XBnzfSW7'})),
              roundRepositoryProvider.overrideWithValue(_Rounds()),
              collectionsRepositoryProvider.overrideWithValue(_OneCollection()),
            ],
          );
          DeepLinkService.notifyAppReady();
          await tester.pump(const Duration(milliseconds: 300));
          expect(stack.names, ['/onboarding']);
          expect(
            GuestGateRouteObserver.instance.topRouteName.value,
            '/onboarding',
          );

          entry.value(tester);
          await settle(tester);
          expect(DeepLinkService.instance.hasPendingDestination, isTrue);
          expect(stack.names, ['/onboarding'], reason: 'nothing moves');
          expect(generated, isEmpty);

          // The real end of onboarding: favorites flushed, the step recorded,
          // Home alone. Home routes the held link once it is up.
          await tester.tap(find.text('Finish onboarding'));
          await settle(tester);
          expect(DeepLinkService.instance.hasPendingDestination, isFalse);
          expect(stack.names, ['/home_screen', isNull]);
          if (entry.key == 'a shared game link') {
            expect(find.text('board XBnzfSW7'), findsOneWidget);
          } else {
            expect(pages.single, isA<CollectionScreen>());
          }
          await finish(tester);
        });
      }
    },
  );

  // ---------------------------------------------------------------------------
  // 38.17 had the app-wide search field over all three Home tabs; the
  // overhaul left it on Today's button only (found 2026-11-22). The same
  // button stands in the same corner on My Space, Today and Discovery.
  testWidgets('Home\'s Search button: the same corner on My Space, Today and '
      'Discovery, each opening Search over Home', (tester) async {
    await pumpHome(tester);
    DeepLinkService.notifyAppReady();
    final corners = <ForYouTab, Rect>{};
    for (final (tab, key) in [
      (ForYouTab.today, kForYouSearchButtonKey),
      (ForYouTab.mySpace, kMySpaceSearchButtonKey),
      (ForYouTab.discovery, kDiscoverySearchButtonKey),
    ]) {
      container().read(selectedForYouTabProvider.notifier).state = tab;
      await settle(tester);
      final button = find.byKey(ValueKey(key));
      expect(button.hitTestable(), findsOneWidget, reason: tab.name);
      expect(tester.widget(button), isA<SearchInkFab>());
      corners[tab] = tester.getRect(button);
      if (tab == ForYouTab.mySpace) {
        // My Space keeps its add button, over Search.
        final add = tester.getRect(find.byType(SpaceAddFab));
        expect(find.byType(SpaceAddFab).hitTestable(), findsOneWidget);
        expect(add.bottom, lessThan(corners[tab]!.top));
        expect(add.right, closeTo(corners[tab]!.right, 1));
      }

      await tester.tap(button);
      await settle(tester);
      expect(stack.names, ['/home_screen', searchRouteName], reason: tab.name);
      await back(tester);
      expect(stack.names, ['/home_screen']);
    }
    expect(corners[ForYouTab.mySpace], corners[ForYouTab.today]);
    expect(corners[ForYouTab.discovery], corners[ForYouTab.today]);
    await finish(tester);
    // Search's landing reads leave a retry of up to a minute behind.
    await tester.pump(const Duration(seconds: 61));
  });

  // ---------------------------------------------------------------------------
  testWidgets('a route to the section already open brings the dock back', (
    tester,
  ) async {
    await pumpHome(tester);
    DeepLinkService.notifyAppReady();
    // The reader read down Today: the dock stepped away. (The stand-in
    // page has no top bar for a scroll to carry, so the section's own
    // chrome, the one the dock follows, is put where a scroll leaves it.)
    (tester.widget<HomeNavDock>(find.byType(HomeNavDock)).chrome!
            as ScrollChromeController)
        .hide(animate: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(dock(tester), 0);

    final shell = home(tester);
    DeepLinkService.instance.ingestNotificationData({
      'route': '/app/home/today',
    });
    await settle(tester);
    expect(section(), BottomNavBarItem.forYou, reason: 'no section changed');
    expect(home(tester), same(shell));
    expect(dock(tester), 1, reason: 'the reader never lands with no dock');
    await finish(tester);
  });

  // ---------------------------------------------------------------------------
  // The iPhone simulator run (2026-11-23): the reader read down Today, the
  // dock, buttons and header stepped away, and a push opened the board (or
  // a collection) while the list still coasted. Back found Home with its
  // bars still away, and the list moved on: the coast, paused under the
  // page, ran on once it closed.
  for (final entry in <String, (void Function(), Finder)>{
    'a game push': (
      () => DeepLinkService.instance.ingestNotificationData({
        'type': 'game_started',
        'game_id': 'XBnzfSW7',
      }),
      find.text('board XBnzfSW7'),
    ),
    'a collection push': (
      () => DeepLinkService.instance.ingestNotificationData({
        'type': 'collection_games_added',
        'collection_slug': 'us-chess-championships',
      }),
      find.text('page CollectionScreen'),
    ),
    // A link from outside the app (a shared game link tapped in Messages):
    // the same bar request as a push.
    'an outside game link': (
      () => DeepLinkService.instance.handleDeepLink(
        Uri.parse('https://chessever.com/games/XBnzfSW7'),
        navigatorKey,
        appRef,
      ),
      find.text('board XBnzfSW7'),
    ),
  }.entries) {
    testWidgets('Back from the page ${entry.key} opened over Home finds its '
        'bars, at the place the reader left', (tester) async {
      await pumpHome(
        tester,
        overrides: [
          gameRepositoryProvider.overrideWithValue(_Games({'XBnzfSW7'})),
          roundRepositoryProvider.overrideWithValue(_Rounds()),
          collectionsRepositoryProvider.overrideWithValue(_OneCollection()),
        ],
      );
      DeepLinkService.notifyAppReady();
      final today = find.byKey(const ValueKey('section-forYou'));
      final list = tester
          .state<ScrollableState>(
            find.descendant(of: today, matching: find.byType(Scrollable)),
          )
          .position;

      // The reader flicks down Today and lets go: the list coasts on, and
      // the bars have stepped away. (The stand-in page has no top bar for
      // the scroll to carry, so the section's chrome is put where reading
      // down leaves it.)
      await tester.fling(today, const Offset(0, -400), 2400);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      (tester.widget<HomeNavDock>(find.byType(HomeNavDock)).chrome!
              as ScrollChromeController)
          .hide(animate: false);
      await tester.pump();
      expect(dock(tester), 0);
      expect(list.isScrollingNotifier.value, isTrue, reason: 'still coasting');
      final left = list.pixels;

      entry.value.$1();
      await settle(tester);
      expect(entry.value.$2, findsOneWidget);

      await back(tester);
      // Long past where the coast would have ended had it run on.
      await tester.pump(const Duration(seconds: 3));
      expect(stack.names, ['/home_screen']);
      expect(dock(tester), 1, reason: 'Home comes back with its dock');
      expect(
        tester.widget<SlidingFabs>(find.byType(SlidingFabs)).controller!.value,
        1,
        reason: 'and its buttons',
      );
      expect(list.pixels, left, reason: 'the list is where the reader left');
      await finish(tester);
    });
  }

  // ---------------------------------------------------------------------------
  testWidgets("a game push during a guest's Google sign-in waits for the Home "
      'sign-in builds (O17)', (tester) async {
    await pumpHome(
      tester,
      overrides: [
        gameRepositoryProvider.overrideWithValue(_Games({'XBnzfSW7'})),
        roundRepositoryProvider.overrideWithValue(_Rounds()),
      ],
    );
    DeepLinkService.notifyAppReady();
    // The guest's Sign up over Home; Google is being asked. The guest's
    // session stays in place meanwhile.
    unawaited(navigatorKey.currentState!.pushNamed('/auth_screen'));
    await tester.pump(const Duration(milliseconds: 500));
    generated.clear();
    final auth = container().read(authStateProvider.notifier) as _GuestAuth;
    auth.startSignIn();
    await tester.pump();

    DeepLinkService.instance.ingestNotificationData({
      'type': 'game_started',
      'game_id': 'XBnzfSW7',
    });
    await settle(tester);
    expect(find.text('board XBnzfSW7'), findsNothing);
    expect(stack.names, ['/home_screen', '/auth_screen']);
    expect(generated, isEmpty);
    expect(DeepLinkService.instance.hasPendingDestination, isTrue);

    // Signed in: the auth screen puts Home up anew, alone (AuthScreen),
    // and that Home routes the held push.
    auth.finishSignIn();
    unawaited(
      navigatorKey.currentState!.pushNamedAndRemoveUntil(
        '/home_screen',
        (_) => false,
      ),
    );
    await settle(tester);
    expect(find.text('board XBnzfSW7'), findsOneWidget);
    expect(stack.names, ['/home_screen', isNull]);
    expect(DeepLinkService.instance.hasPendingDestination, isFalse);
    await finish(tester);
  });

  // ---------------------------------------------------------------------------
  // O20: Google's or Apple's sheet dismissed. The auth state lands on error
  // or unauthenticated while the guest's session lives on, and no new Home
  // mounts to route what the sign-in held.
  group("a guest's cancelled sign-in", () {
    for (final ended in const [
      ('error', AppAuthState.error('Sign in was cancelled')),
      ('unauthenticated', AppAuthState.unauthenticated()),
    ]) {
      testWidgets('(${ended.$1}) opens the push it held, as the guest, on the '
          'same Home', (tester) async {
        final opened = <Widget>[];
        await pumpHome(
          tester,
          overrides: [
            collectionsRepositoryProvider.overrideWithValue(_OneCollection()),
            appDestinationPageNavigationProvider.overrideWithValue(
              (_, page, __) => opened.add(page),
            ),
          ],
        );
        DeepLinkService.notifyAppReady();
        final shell = home(tester);
        unawaited(navigatorKey.currentState!.pushNamed('/auth_screen'));
        await tester.pump(const Duration(milliseconds: 500));
        generated.clear();
        final auth = container().read(authStateProvider.notifier) as _GuestAuth;
        auth.startSignIn();
        await tester.pump();

        DeepLinkService.instance.ingestNotificationData({
          'type': 'collection_games_added',
          'collection_slug': 'us-chess-championships',
          'added': '3',
        });
        await settle(tester);
        expect(pages, isEmpty);
        expect(DeepLinkService.instance.hasPendingDestination, isTrue);
        expect(stack.names, ['/home_screen', '/auth_screen']);

        auth.cancelSignIn(ended.$2);
        await settle(tester);
        expect(pages.single, isA<CollectionScreen>());
        expect(DeepLinkService.instance.hasPendingDestination, isFalse);
        expect(stack.names, ['/home_screen', isNull]);
        expect(generated, isEmpty, reason: 'no sign-in, no second Home');
        expect(home(tester), same(shell));
        expect(opened, isEmpty);
        await finish(tester);
      });

      testWidgets('(${ended.$1}) a link that arrives afterwards opens as the '
          'guest, never sign-in over Home', (tester) async {
        await pumpHome(
          tester,
          overrides: [
            collectionsRepositoryProvider.overrideWithValue(_OneCollection()),
          ],
        );
        DeepLinkService.notifyAppReady();
        final shell = home(tester);
        unawaited(navigatorKey.currentState!.pushNamed('/auth_screen'));
        await tester.pump(const Duration(milliseconds: 500));
        final auth = container().read(authStateProvider.notifier) as _GuestAuth;
        auth.startSignIn();
        await tester.pump();
        auth.cancelSignIn(ended.$2);
        await settle(tester);
        generated.clear();

        DeepLinkService.instance.handleDeepLink(
          Uri.parse('https://chessever.com/collections/us-chess-championships'),
          navigatorKey,
          appRef,
        );
        await settle(tester);
        expect(generated, isNot(contains('/auth_screen')));
        expect(pages.single, isA<CollectionScreen>());
        expect(stack.names, ['/home_screen', isNull]);
        expect(home(tester), same(shell));
        await finish(tester);
      });

      // The /app catalog and the Inbox read the session in
      // _awaitDestinationSession, not _readyToOpen: the guest's live session
      // has to count there too.
      testWidgets('(${ended.$1}) opens the /app route push it held, as the '
          'guest, on the same Home', (tester) async {
        final opened = <Widget>[];
        await pumpHome(
          tester,
          overrides: [
            appDestinationPageNavigationProvider.overrideWithValue(
              (_, page, __) => opened.add(page),
            ),
          ],
        );
        DeepLinkService.notifyAppReady();
        final shell = home(tester);
        unawaited(navigatorKey.currentState!.pushNamed('/auth_screen'));
        await tester.pump(const Duration(milliseconds: 500));
        generated.clear();
        final auth = container().read(authStateProvider.notifier) as _GuestAuth;
        auth.startSignIn();
        await tester.pump();

        DeepLinkService.instance.ingestNotificationData({
          'type': 'call_to_action',
          'route': '/app/my-space/prep',
        });
        await settle(tester);
        expect(opened, isEmpty);
        expect(DeepLinkService.instance.hasPendingDestination, isTrue);

        auth.cancelSignIn(ended.$2);
        await settle(tester);
        expect(opened.single, isA<MyPrepHomeScreen>());
        expect(DeepLinkService.instance.hasPendingDestination, isFalse);
        expect(stack.names, ['/home_screen']);
        expect(generated, isEmpty, reason: 'no sign-in, no second Home');
        expect(home(tester), same(shell));
        await finish(tester);
      });

      testWidgets('(${ended.$1}) an Inbox push that arrives afterwards opens '
          'the Inbox as the guest, never sign-in over Home', (tester) async {
        await pumpHome(tester, overrides: _inbox());
        DeepLinkService.notifyAppReady();
        final shell = home(tester);
        unawaited(navigatorKey.currentState!.pushNamed('/auth_screen'));
        await tester.pump(const Duration(milliseconds: 500));
        final auth = container().read(authStateProvider.notifier) as _GuestAuth;
        auth.startSignIn();
        await tester.pump();
        auth.cancelSignIn(ended.$2);
        await settle(tester);
        generated.clear();

        DeepLinkService.instance.ingestNotificationData({
          'type': 'call_to_action',
          'inbox_message_id': inboxIdA,
        });
        await settle(tester);
        // The Inbox opens over Home. The message itself also needs the
        // app-wide account, which stays empty in this window until a token
        // refresh (O20, the auth owner's item), so only the list is pinned.
        expect(stack.names.take(2), ['/home_screen', '/app/inbox']);
        expect(find.byType(InboxScreen), findsOneWidget);
        expect(generated, isNot(contains('/auth_screen')));
        expect(DeepLinkService.instance.hasPendingDestination, isFalse);
        expect(home(tester), same(shell));
        await finish(tester);
      });
    }

    testWidgets('a WebView push held during the sign-in opens once it is '
        'cancelled (O22)', (tester) async {
      final opened = <Widget>[];
      await pumpHome(
        tester,
        overrides: [
          appDestinationPageNavigationProvider.overrideWithValue(
            (_, page, __) => opened.add(page),
          ),
        ],
      );
      DeepLinkService.notifyAppReady();
      unawaited(navigatorKey.currentState!.pushNamed('/auth_screen'));
      await tester.pump(const Duration(milliseconds: 500));
      final auth = container().read(authStateProvider.notifier) as _GuestAuth;
      auth.startSignIn();
      await tester.pump();

      DeepLinkService.instance.ingestNotificationData({
        'route':
            'https://chessever.com/webview?url=https%3A%2F%2Fexample.com%2Fa',
      });
      await settle(tester);
      expect(
        opened,
        isEmpty,
        reason: 'never over the Sign up page mid sign-in',
      );
      expect(DeepLinkService.instance.hasPendingDestination, isTrue);

      auth.cancelSignIn(const AppAuthState.error('Sign in was cancelled'));
      await settle(tester);
      expect(
        (opened.single as AppWebViewScreen).url,
        Uri.parse('https://example.com/a'),
      );
      expect(DeepLinkService.instance.hasPendingDestination, isFalse);
      await finish(tester);
    });
  });
}

// -----------------------------------------------------------------------------

List<Override> _eventRepos() => [
  tourRepositoryProvider.overrideWithValue(_Tours()),
  groupBroadcastRepositoryProvider.overrideWithValue(_Groups()),
  roundRepositoryProvider.overrideWithValue(_Rounds()),
  tourDetailRepoProvider.overrideWithValue(_Selection()),
];

List<Override> _inbox() => [
  attentionClockProvider.overrideWithValue(inboxFixtureNow),
  inboxSourceProvider.overrideWithValue(FakeInboxSource()),
  inboxCacheProvider.overrideWithValue(FakeInboxCache()),
];

/// The navigator's routes, bottom to top, by name.
class _Stack extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  List<String?> get names => [
    for (final r in routes)
      if (r is PageRoute) r.settings.name,
  ];

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

class _Games extends GameRepository {
  _Games(this.ids);

  final Set<String> ids;

  @override
  Future<Games?> findGameById(String id) async =>
      ids.contains(id) ? _game(id) : null;

  @override
  Future<Games> getGameByLichessId(String lichessId) async =>
      throw Exception('No rows found');

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
  @override
  Future<Round> getRoundById(String id) async {
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
  @override
  Future<List<Tour>> getToursByIds(List<String> ids) async {
    if (!ids.contains('mKgqPByN')) return const [];
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
  @override
  Future<GroupBroadcast> getGroupBroadcastById(String id) async {
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

class _OneCollection extends CollectionsRepository {
  _OneCollection() : super(GamebaseRepository(Dio(), apiKey: 'test'));

  static const book = Collection(
    id: 'book-1',
    slug: 'us-chess-championships',
    kind: CollectionKind.book,
    title: 'US Chess Championships',
    access: CollectionAccess.free,
  );

  @override
  Future<Collection> fetchCollection(String slug) async {
    if (slug != book.slug) throw Exception('not published');
    return book;
  }
}
