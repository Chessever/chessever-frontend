import 'dart:async';

import 'package:chessever2/providers/app_version_provider.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/inbox/inbox_message.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/screens/inbox/inbox_screen.dart';
import 'package:chessever2/screens/inbox/inbox_unread_dot.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/hamburger_menu/hamburger_menu.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'inbox_fakes.dart';

final _identity = StateProvider<String?>((ref) => inboxOwnerA);
ProviderContainer? _testContainer;
void _disposeContainer() {
  _testContainer?.dispose();
  _testContainer = null;
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription() : super(SubscriptionState(isSubscribed: false));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeInboxSource source, {
  bool shell = false,
  bool light = false,
  double scale = 1,
  bool anonymous = true,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWith((ref) {
        final id = ref.watch(_identity);
        return id == null
            ? null
            : AppUser(
                id: id,
                createdAt: DateTime.utc(2026),
                isAnonymous: anonymous,
              );
      }),
      subscriptionProvider.overrideWith((ref) => _Subscription()),
      appVersionProvider.overrideWith((ref) async => '35.25.4'),
      inboxSourceProvider.overrideWithValue(source),
      inboxCacheProvider.overrideWithValue(FakeInboxCache()),
    ],
  );
  _testContainer = container;
  addTearDown(_disposeContainer);
  final scaffoldKey = GlobalKey<ScaffoldState>();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            if (!shell) return const InboxScreen();
            return Scaffold(
              key: scaffoldKey,
              drawer: HamburgerMenu(
                callbacks: HamburgerMenuCallbacks(
                  onPlayersPressed: () {},
                  onBoardPressed: () {},
                  onFavoritesPressed: () {},
                  onSupportPressed: () {},
                  onPremiumPressed: () {},
                  onLogoutPressed: () {},
                ),
              ),
              body: Center(
                child: HomeTopBarAvatar(
                  onTap: () => scaffoldKey.currentState!.openDrawer(),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  _disposeContainer();
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

  testWidgets(
    'drawer avatar keeps its editor inside the Inbox unread wrapper',
    (tester) async {
      final source = FakeInboxSource();
      final container = await _pump(
        tester,
        source,
        shell: true,
        anonymous: false,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(HomeTopBarAvatar));
      await tester.pumpAndSettle();
      final avatar = find.descendant(
        of: find.byType(HamburgerMenu),
        matching: find.byType(UserAvatar),
      );
      expect(avatar, findsOneWidget);
      expect(
        find.ancestor(of: avatar, matching: find.byType(InboxAvatarBadge)),
        findsOneWidget,
      );
      expect(tester.widget<UserAvatar>(avatar).onTap, isNotNull);
      await tester.tap(avatar);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close profile photo'), findsOneWidget);
      expect(find.text('Upload'), findsOneWidget);
      expect(container.read(inboxProvider).hasUnread, true);
      expect(source.marks, isEmpty);
      await tester.tap(find.byTooltip('Close profile photo'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('drawer-inbox-dot')), findsOneWidget);
      await _close(tester);
    },
  );

  testWidgets(
    'drawer/list do not mark; Inbox directly above Board, feedback kept',
    (tester) async {
      final source = FakeInboxSource();
      final container = await _pump(tester, source, shell: true);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('inbox-avatar-dot')), findsOneWidget);
      await tester.tap(find.byType(HomeTopBarAvatar));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('drawer-inbox-dot')), findsOneWidget);
      final inboxY = tester.getCenter(find.text('Inbox')).dy;
      final boardY = tester.getCenter(find.text('Board')).dy;
      final calendarY = tester.getCenter(find.text('Calendar')).dy;
      expect(inboxY, lessThan(boardY));
      expect(boardY - inboxY, closeTo(calendarY - boardY, 1));
      expect(find.text('Feedback'), findsOneWidget);
      expect(source.marks, isEmpty);
      await tester.tap(find.byKey(const ValueKey('drawer-inbox')));
      await tester.pumpAndSettle();
      expect(find.byType(InboxScreen), findsOneWidget);
      expect(source.marks, isEmpty);
      expect(container.read(inboxProvider).hasUnread, true);
      expect(
        find.byKey(const ValueKey('inbox-row-dot-$inboxIdA')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('inbox-row-dot-$inboxIdB')),
        findsOneWidget,
      );
      await _close(tester);
    },
  );

  testWidgets(
    'exact full text alone marks specific row, plain secure rendering',
    (tester) async {
      final source = FakeInboxSource();
      final container = await _pump(tester, source);
      await tester.pumpAndSettle();
      expect(source.marks, isEmpty);
      await tester.tap(find.byKey(const ValueKey('inbox-row-$inboxIdA')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('inbox-full-text')), findsOneWidget);
      final body = tester.widget<SelectableText>(
        find.byKey(const ValueKey('inbox-full-text')),
      );
      expect(body.data, inboxFixture(inboxIdA).body);
      expect(find.text('Sep 30, 2026'), findsOneWidget);
      expect(source.marks, [(inboxOwnerA, inboxIdA)]);
      expect(container.read(inboxProvider).message(inboxIdB)!.isUnread, true);
      expect(container.read(inboxProvider).hasUnread, true);
      expect(find.text('Reply'), findsNothing);
      expect(find.text('Message us'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('inbox-row-dot-$inboxIdA')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('inbox-row-dot-$inboxIdB')),
        findsOneWidget,
      );
      await _close(tester);
    },
  );
  testWidgets(
    'read failure keeps cyan and text; explicit Retry confirms read',
    (tester) async {
      final source = FakeInboxSource()..failMark = true;
      final container = await _pump(tester, source);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('inbox-row-$inboxIdA')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('inbox-full-text')), findsOneWidget);
      expect(find.textContaining('Could not save this read'), findsOneWidget);
      expect(container.read(inboxProvider).message(inboxIdA)!.isUnread, true);
      source.failMark = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(container.read(inboxProvider).message(inboxIdA)!.isUnread, false);
      expect(container.read(inboxProvider).message(inboxIdB)!.isUnread, true);
      expect(find.text('Retry'), findsNothing);
      await _close(tester);
    },
  );
  testWidgets(
    'account switch on detail removes old body and performs no B mark',
    (tester) async {
      final source = FakeInboxSource();
      final gate = Completer<DateTime>();
      source.markOverride = (_, _) => gate.future;
      final container = await _pump(tester, source);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('inbox-row-$inboxIdA')));
      await tester.pumpAndSettle();
      container.read(_identity.notifier).state = inboxOwnerB;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('inbox-full-text')), findsNothing);
      expect(
        find.text('This message is unavailable for this account.'),
        findsOneWidget,
      );
      gate.complete(inboxReadTime);
      await tester.pumpAndSettle();
      expect(source.marks, [(inboxOwnerA, inboxIdA)]);
      expect(container.read(inboxProvider).messages.single.id, inboxIdB);
      expect(container.read(inboxProvider).messages.single.isUnread, true);
      await _close(tester);
    },
  );
  testWidgets('loading, empty, fetch-error and retry states are distinct', (
    tester,
  ) async {
    final source = FakeInboxSource();
    final gate = Completer<List<InboxMessage>>();
    source.fetchOverride = (_) => gate.future;
    final container = await _pump(tester, source);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    gate.completeError(StateError('LOCAL FIXTURE offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not refresh Inbox'), findsOneWidget);
    expect(find.textContaining('Your Inbox is empty'), findsNothing);
    source.fetchOverride = (_) async => [];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your Inbox is empty'), findsOneWidget);
    expect(container.read(inboxProvider).syncError, isNull);
    await _close(tester);
  });
  testWidgets('all avatar and drawer dots clear only after the final read', (
    tester,
  ) async {
    final source = FakeInboxSource();
    final container = await _pump(tester, source, shell: true);
    await tester.pumpAndSettle();
    await container.read(inboxProvider.notifier).markOpened(inboxIdA);
    await tester.pumpAndSettle();
    expect(find.byType(InboxUnreadDot), findsOneWidget);
    await tester.tap(find.byType(HomeTopBarAvatar));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('drawer-inbox-dot')), findsOneWidget);
    await container.read(inboxProvider.notifier).markOpened(inboxIdB);
    await tester.pumpAndSettle();
    expect(find.byType(InboxUnreadDot), findsNothing);
    await _close(tester);
  });
  for (final light in [false, true]) {
    testWidgets(
      'Inbox and detail fit large text in ${light ? 'light' : 'dark'} theme',
      (tester) async {
        final source = FakeInboxSource();
        await _pump(tester, source, light: light, scale: 2);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('inbox-row-$inboxIdA')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('inbox-full-text')), findsOneWidget);
        await _close(tester);
      },
    );
  }
}
