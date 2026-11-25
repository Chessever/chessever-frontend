// Botvinnik as a home tab: Home keeps the page alive out of sight (Offstage
// with its tickers muted) on the same route as the tab in view. Nothing the
// hidden page holds may answer Back or read the Inbox for that tab.
import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/chat/chat_screen.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/services/attention_policy.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../inbox_fakes.dart';

class _Guest extends AuthController {
  @override
  Future<AppAuthState> build() async => AppAuthState.authenticated(
    AppUser(id: inboxOwnerA, createdAt: DateTime.utc(2026), isAnonymous: true),
  );
}

/// The tab's place in Home, as `BottomNavBarView` keeps it.
class _Harness {
  _Harness(this.source);

  final FakeInboxSource source;
  late ProviderContainer container;
  final navigator = GlobalKey<NavigatorState>();
  final inView = ValueNotifier(true);

  Widget host() => ProviderScope(
    overrides: [
      authStateProvider.overrideWith(_Guest.new),
      attentionClockProvider.overrideWithValue(inboxFixtureNow),
      inboxSourceProvider.overrideWithValue(source),
      inboxCacheProvider.overrideWithValue(FakeInboxCache()),
    ],
    child: MaterialApp(
      navigatorKey: navigator,
      theme: AppTheme.darkTheme,
      // The empty chat's mark loops; still, the page can settle.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context, listen: false);
          ResponsiveHelper.init(context);
          return ValueListenableBuilder<bool>(
            valueListenable: inView,
            builder: (context, inView, _) => Stack(
              fit: StackFit.expand,
              children: [
                Offstage(
                  offstage: !inView,
                  child: TickerMode(
                    enabled: inView,
                    child: const ChatScreen(
                      embedded: true,
                      screenContext: ChatScreenContext(screen: 'home'),
                    ),
                  ),
                ),
                if (!inView) const Scaffold(body: Text('Another tab')),
              ],
            ),
          );
        },
      ),
    ),
  );
}

Future<_Harness> _pump(WidgetTester tester, FakeInboxSource source) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  // Resuming starts the placeholder client's token refresh timer.
  Supabase.instance.client.auth.stopAutoRefresh();
  final harness = _Harness(source);
  addTearDown(harness.inView.dispose);
  await tester.pumpWidget(harness.host());
  await tester.pumpAndSettle();
  return harness;
}

ScaffoldState _chatScaffold(WidgetTester tester) => tester.firstState(
  find.descendant(
    of: find.byType(ChatScreen, skipOffstage: false),
    matching: find.byType(Scaffold, skipOffstage: false),
  ),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder-publishable-key',
    );
  });

  testWidgets('a chats drawer left open does not take Back from another tab', (
    tester,
  ) async {
    final harness = await _pump(tester, FakeInboxSource()..rows.clear());
    final navigator = harness.navigator.currentState!;

    await tester.tap(find.byTooltip('Chats'));
    await tester.pumpAndSettle();
    expect(_chatScaffold(tester).isDrawerOpen, isTrue);
    expect(navigator.canPop(), isTrue, reason: 'Back closes the open drawer');

    harness.inView.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Another tab'), findsOneWidget);
    expect(_chatScaffold(tester).isDrawerOpen, isFalse);
    expect(navigator.canPop(), isFalse, reason: 'Back belongs to Home again');

    harness.inView.value = true;
    await tester.pumpAndSettle();
    expect(_chatScaffold(tester).isDrawerOpen, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('out of sight, a notice that arrives is not read until shown', (
    tester,
  ) async {
    final source = FakeInboxSource()..rows.clear();
    final harness = await _pump(tester, source);

    harness.inView.value = false;
    await tester.pumpAndSettle();
    source.rows[inboxOwnerA] = [inboxFixture(inboxIdA)];
    await harness.container.read(inboxProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(source.marks, isEmpty);
    expect(harness.container.read(inboxUnreadCountProvider), 1);

    harness.inView.value = true;
    await tester.pumpAndSettle();
    expect(source.marks, [(inboxOwnerA, inboxIdA)]);
  });
}
