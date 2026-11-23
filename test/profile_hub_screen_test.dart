import 'dart:async';
import 'dart:convert';

import 'package:chessever2/providers/app_version_provider.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/screens/my_profile/my_profile_screen.dart';
import 'package:chessever2/screens/my_profile/profile_hub_screen.dart';
import 'package:chessever2/screens/settings/settings_page.dart';
import 'package:chessever2/services/attention_policy.dart';
import 'package:chessever2/services/discovery_dots/discovery_dots_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/adaptive_window.dart';
import 'package:chessever2/widgets/discovery_dot.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'inbox_fakes.dart';

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription(bool subscribed)
    : super(SubscriptionState(isSubscribed: subscribed));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DotsSource implements DiscoveryDotsSource {
  _DotsSource(this.cached);

  final String cached;

  @override
  Future<String> initialize() async => cached;

  @override
  Future<String> fetch() async => cached;

  @override
  Stream<String> get updates => const Stream.empty();
}

class _MemoryStore implements DiscoveryDotsSeenStore {
  Map<String, int> seen = {};

  @override
  Map<String, int> read() => seen;

  @override
  Future<void> write(Map<String, int> value) async => seen = value;
}

/// Every route the navigator lost, by name.
class _Losses extends NavigatorObserver {
  final List<String?> names = [];

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      names.add(route.settings.name);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      names.add(route.settings.name);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      names.add(oldRoute?.settings.name);
}

Future<void> _pump(
  WidgetTester tester, {
  bool light = false,
  bool premium = false,
  List<Map<String, Object?>> dots = const [],
  double statusBar = 0,
  NavigatorObserver? observer,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: statusBar);
  tester.view.viewPadding = FakeViewPadding(top: statusBar);
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => AppUser(
          id: inboxOwnerA,
          createdAt: DateTime.utc(2026),
          isAnonymous: true,
        ),
      ),
      subscriptionProvider.overrideWith((ref) => _Subscription(premium)),
      appVersionProvider.overrideWith((ref) async => '35.25.4'),
      attentionClockProvider.overrideWithValue(inboxFixtureNow),
      inboxSourceProvider.overrideWithValue(FakeInboxSource()),
      inboxCacheProvider.overrideWithValue(FakeInboxCache()),
      botvinnikTabAvailableProvider.overrideWithValue(true),
      myProfileIdentityProvider.overrideWith(
        (ref) => (displayName: 'Fixture Reader', email: null, isGuest: true),
      ),
      discoveryDotsSourceProvider.overrideWithValue(
        _DotsSource(jsonEncode({'dots': dots})),
      ),
      discoveryDotsSeenStoreProvider.overrideWithValue(_MemoryStore()),
      discoveryDotsDeliveryStoreProvider.overrideWithValue(_MemoryStore()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        themeAnimationDuration: Duration.zero,
        // A lit dot breathes forever; held still, pumpAndSettle can finish.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: AdaptiveWindowScope(child: child!),
        ),
        navigatorObservers: [?observer],
        // As in the app: Home is the one route, named as the app names it.
        onGenerateRoute: (_) => null,
        onGenerateInitialRoutes: (_) => [
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/home_screen'),
            builder: (_) => const Scaffold(body: ProfileHubScreen()),
          ),
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final fonts = FontLoader('InterDisplay')
      ..addFont(rootBundle.load('assets/fonts/Inter-Regular.otf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Medium.otf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Bold.otf'));
    await fonts.load();
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      publishableKey: 'LOCAL-FIXTURE-ANON-KEY',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (_) async => throw StateError('Unexpected LOCAL FIXTURE request'),
      ),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets('Settings opens over Home and goes back to it: Home is never '
      'popped', (tester) async {
    final losses = _Losses();
    await _pump(tester, observer: losses);
    await tester.ensureVisible(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(losses.names, isNot(contains('/home_screen')));
    final page = find.byType(SettingsPage);
    expect(page, findsOneWidget);
    // A way back, and a route to go back to (the swipe and Android back
    // both have somewhere to land).
    expect(Navigator.of(tester.element(page)).canPop(), isTrue);
    expect(find.byType(PageBackButton), findsOneWidget);
    await tester.tap(find.byType(PageBackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.byType(ProfileHubScreen), findsOneWidget);
    expect(losses.names, isNot(contains('/home_screen')));
    await _close(tester);
    // Settings' bodies opened the local store, which gives up after two
    // timed-out tries in a test.
    await tester.pump(const Duration(seconds: 20));
  });

  testWidgets('Feedback opens its form over Home: Home is never popped', (
    tester,
  ) async {
    final losses = _Losses();
    await _pump(tester, observer: losses);
    await tester.ensureVisible(find.text('Feedback'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feedback'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Your Feedback'), findsOneWidget);
    expect(losses.names, isNot(contains('/home_screen')));
    // Closed, the form leaves Home where it was.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Your Feedback'), findsNothing);
    expect(find.byType(ProfileHubScreen), findsOneWidget);
    expect(losses.names, isNot(contains('/home_screen')));
    await _close(tester);
  });

  testWidgets('the last row clears the dock the page runs under', (
    tester,
  ) async {
    await _pump(tester);
    final list = find.byType(Scrollable);
    final context = tester.element(list);
    final padding = tester.widget<ListView>(find.byType(ListView)).padding!;
    expect(
      padding.resolve(TextDirection.ltr).bottom,
      greaterThanOrEqualTo(MediaQuery.paddingOf(context).bottom),
    );
    await _close(tester);
  });

  testWidgets('each row is read once, with its trailing state', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(tester.getSemantics(find.text('Calendar')).label, 'Calendar');
    // Board's mark names itself too; the row still says it once.
    expect(tester.getSemantics(find.text('Board')).label, 'Board');
    expect(
      tester.getSemantics(find.text('Free plan')).label,
      'Free plan, See what Premium adds\nUpgrade',
    );
    expect(
      tester.getSemantics(find.text('Inbox')).label,
      'Inbox\nUnread Inbox message',
    );
    expect(
      tester.getSemantics(find.text('Fixture Reader')).label,
      'Fixture Reader, Not signed in, open your profile',
    );
    await _close(tester);
    handle.dispose();
  });

  testWidgets('Upgrade and the Premium mark clear contrast on paper', (
    tester,
  ) async {
    await _pump(tester, light: true);
    final upgrade = tester.widget<Text>(find.text('Upgrade'));
    expect(upgrade.style?.color, AppColors.light.accentText);
    await _close(tester);

    await _pump(tester, light: true, premium: true);
    final mark = tester.widget<Icon>(
      find.byIcon(Icons.workspace_premium_rounded),
    );
    expect(mark.color, AppColors.light.accentText);
    await _close(tester);
  });

  testWidgets('rows start under the root bar and never scroll under the '
      'status bar', (tester) async {
    const inset = 47.0;
    await _pump(tester, statusBar: inset);
    final list = find.byType(Scrollable);
    final context = tester.element(list);
    // The page starts where every root's page starts: under the bar every
    // root wears, its name set as every root's is.
    expect(
      tester.getTopLeft(list).dy,
      closeTo(HomeTopBarMetrics.headerExtent(context), 0.5),
    );
    expect(find.byType(HomeTopBarFrame), findsOneWidget);
    expect(find.widgetWithText(HomeTopBarTitle, 'Profile'), findsOneWidget);
    await tester.drag(list, const Offset(0, -240));
    await tester.pumpAndSettle();
    // The viewport (and so its clip) still starts under the inset.
    expect(tester.getTopLeft(list).dy, greaterThanOrEqualTo(inset));
    await _close(tester);
  });

  testWidgets('dots published at the sidebar and old tabs still land', (
    tester,
  ) async {
    await _pump(
      tester,
      dots: const [
        {
          'id': 'calendar-launch',
          'rev': 1,
          'target': 'drawer.calendar',
          'trail': ['home.menu'],
        },
      ],
    );
    Finder dotIn(String title) => find.descendant(
      of: find.ancestor(
        of: find.text(title),
        matching: find.byType(DiscoveryDotAnchor),
      ),
      matching: find.byType(DiscoveryDotMark),
    );
    expect(dotIn('Calendar'), findsOneWidget);
    expect(find.byType(DiscoveryDotMark), findsOneWidget);
    await _close(tester);

    // Events has its dock slot again (2026-11-23): Profile holds no Events
    // row, and a Nudge trailed through the Events slot lights nothing here.
    await _pump(
      tester,
      dots: const [
        {
          'id': 'past-events',
          'rev': 1,
          'target': 'events.tab.past',
          'trail': ['home.nav.events'],
        },
      ],
    );
    expect(find.text('Events'), findsNothing);
    expect(find.byType(DiscoveryDotMark), findsNothing);
    await _close(tester);
  });
}
