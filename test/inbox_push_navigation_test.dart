import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/inbox/inbox_message.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/screens/inbox/inbox_screen.dart';
import 'package:chessever2/services/app_destination_service.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'inbox_fakes.dart';

final _identity = StateProvider<String?>((ref) => inboxOwnerA);

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription() : super(SubscriptionState(isSubscribed: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RestoringAuth extends AuthController {
  _RestoringAuth(this.restored);

  final Future<AppAuthState> restored;

  @override
  Future<AppAuthState> build() => restored;
}

class _NavigationObserver extends NavigatorObserver {
  final pushed = <String?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route.settings.name);
  }
}

class _Host {
  _Host(this.container, this.navigatorKey, this.ref, this.observer);

  final ProviderContainer container;
  final GlobalKey<NavigatorState> navigatorKey;
  final WidgetRef ref;
  final _NavigationObserver observer;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
  }

  void attach() =>
      DeepLinkService.instance.attachNotificationRouter(navigatorKey, ref);

  Future<void> close(WidgetTester tester) async {
    DeepLinkService.instance.detachNotificationRouter();
    await tester.pumpWidget(const SizedBox.shrink());
    dispose();
  }
}

Future<_Host> _pumpHost(
  WidgetTester tester,
  FakeInboxSource source, {
  List<Override> overrides = const [],
  bool useAuthUser = false,
}) async {
  // The ready completer belongs to this test's fake-async zone.
  DeepLinkService.instance.dispose();
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      if (!useAuthUser)
        currentUserProvider.overrideWith((ref) {
          final id = ref.watch(_identity);
          return id == null
              ? null
              : AppUser(
                  id: id,
                  createdAt: DateTime.utc(2026),
                  isAnonymous: true,
                );
        }),
      subscriptionProvider.overrideWith((ref) => _Subscription()),
      inboxSourceProvider.overrideWithValue(source),
      inboxCacheProvider.overrideWithValue(FakeInboxCache()),
      ...overrides,
    ],
  );
  final navigatorKey = GlobalKey<NavigatorState>();
  final observer = _NavigationObserver();
  late WidgetRef captured;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) {
          captured = ref;
          return MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: [observer],
            theme: AppTheme.darkTheme,
            themeAnimationDuration: Duration.zero,
            builder: (context, child) {
              ResponsiveHelper.init(context);
              return child!;
            },
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(
                body: Center(child: Text('LOCAL FIXTURE: Home')),
              ),
            ),
          );
        },
      ),
    ),
  );
  final host = _Host(container, navigatorKey, captured, observer);
  addTearDown(host.dispose);
  return host;
}

const _payload = <String, dynamic>{
  'type': 'call_to_action',
  'inbox_message_id': inboxIdA,
};

InboxMessage _message(String id, String title, String body) => InboxMessage(
  id: id,
  title: title,
  body: body,
  publishedAt: DateTime.utc(2026, 9, 30),
);

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

  setUp(() {
    DeepLinkService.instance.detachNotificationRouter();
    DeepLinkService.instance.dispose();
  });
  tearDown(() {
    DeepLinkService.instance.detachNotificationRouter();
    DeepLinkService.instance.dispose();
  });

  testWidgets(
    'cold Inbox tap waits for ready and reads only its exact message',
    (tester) async {
      final gate = Completer<List<InboxMessage>>();
      final source = FakeInboxSource()..fetchOverride = (_) => gate.future;
      final host = await _pumpHost(tester, source);
      DeepLinkService.instance.ingestNotificationData(_payload);
      host.attach();
      await tester.pump();

      expect(find.text('LOCAL FIXTURE: Home'), findsOneWidget);
      expect(find.byType(InboxMessageScreen), findsNothing);
      expect(source.fetches, isEmpty);
      expect(source.marks, isEmpty);

      DeepLinkService.notifyAppReady();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.byType(InboxMessageScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(InboxMessageScreen),
          matching: find.byType(SkeletonWidget),
        ),
        findsOneWidget,
      );
      expect(find.byType(GenericErrorWidget), findsNothing);
      expect(source.marks, isEmpty);

      gate.complete(source.rows[inboxOwnerA]!);
      await tester.pumpAndSettle();
      expect(find.text('Fixture: study a position'), findsOneWidget);
      expect(find.byKey(const ValueKey('inbox-full-text')), findsOneWidget);
      expect(
        tester
            .widget<InboxMessageScreen>(find.byType(InboxMessageScreen))
            .messageId,
        inboxIdA,
      );
      expect(source.marks, [(inboxOwnerA, inboxIdA)]);
      expect(
        host.container.read(inboxProvider).message(inboxIdB)!.isUnread,
        true,
      );
      expect(host.observer.pushed.skip(1), [
        '/home_screen',
        '/app/inbox',
        '/app/inbox/$inboxIdA',
      ]);
      await host.close(tester);
    },
  );

  testWidgets('Inbox message survives auth restore after the app is ready', (
    tester,
  ) async {
    final restored = Completer<AppAuthState>();
    final source = FakeInboxSource();
    final host = await _pumpHost(
      tester,
      source,
      useAuthUser: true,
      overrides: [
        authStateProvider.overrideWith(() => _RestoringAuth(restored.future)),
      ],
    );
    host.attach();
    expect(host.container.read(currentUserProvider), isNull);
    DeepLinkService.instance.ingestNotificationData(_payload);
    DeepLinkService.notifyAppReady();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(host.container.read(authStateProvider).isLoading, true);
    expect(find.text('LOCAL FIXTURE: Home'), findsOneWidget);
    expect(find.byType(InboxMessageScreen), findsNothing);
    expect(source.fetches, isEmpty);
    expect(source.marks, isEmpty);

    restored.complete(
      AppAuthState.authenticated(
        AppUser(
          id: inboxOwnerA,
          createdAt: DateTime.utc(2026),
          isAnonymous: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fixture: study a position'), findsOneWidget);
    final detail = tester.widget<InboxMessageScreen>(
      find.byType(InboxMessageScreen),
    );
    expect(detail.ownerId, inboxOwnerA);
    expect(detail.messageId, inboxIdA);
    expect(source.marks, [(inboxOwnerA, inboxIdA)]);
    expect(
      host.container.read(inboxProvider).message(inboxIdB)!.isUnread,
      true,
    );
    await host.close(tester);
  });

  for (final route in [null, '/app/settings/notifications']) {
    testWidgets('a tap preserves the auth screen without a session ($route)', (
      tester,
    ) async {
      final source = FakeInboxSource();
      final host = await _pumpHost(
        tester,
        source,
        useAuthUser: true,
        overrides: [
          authStateProvider.overrideWith(
            () => _RestoringAuth(
              Future.value(const AppAuthState.unauthenticated()),
            ),
          ),
        ],
      );
      await tester.pumpAndSettle();
      host.attach();
      DeepLinkService.notifyAppReady();
      DeepLinkService.instance.ingestNotificationData({
        ..._payload,
        if (route != null) 'route': route,
      });
      await tester.pumpAndSettle();

      expect(host.observer.pushed, ['/']);
      expect(find.byType(InboxMessageScreen), findsNothing);
      expect(source.fetches, isEmpty);
      expect(source.marks, isEmpty);
      await host.close(tester);
    });
  }

  testWidgets('only the newest tap waiting for app readiness can open', (
    tester,
  ) async {
    final source = FakeInboxSource();
    final host = await _pumpHost(tester, source);
    host.attach();
    DeepLinkService.instance.ingestNotificationData(_payload);
    DeepLinkService.instance.ingestNotificationData({
      ..._payload,
      'inbox_message_id': inboxIdB,
    });
    DeepLinkService.notifyAppReady();
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<InboxMessageScreen>(find.byType(InboxMessageScreen))
          .messageId,
      inboxIdB,
    );
    expect(source.marks, [(inboxOwnerA, inboxIdB)]);
    expect(host.observer.pushed, [
      '/',
      '/home_screen',
      '/app/inbox',
      '/app/inbox/$inboxIdB',
    ]);
    await host.close(tester);
  });

  testWidgets('warm Inbox tap keeps the Inbox and Home back stack', (
    tester,
  ) async {
    final source = FakeInboxSource();
    final host = await _pumpHost(tester, source);
    host.attach();
    DeepLinkService.notifyAppReady();
    DeepLinkService.instance.ingestNotificationData(_payload);
    await tester.pumpAndSettle();
    expect(find.byType(InboxMessageScreen), findsOneWidget);
    expect(source.marks, [(inboxOwnerA, inboxIdA)]);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(InboxMessageScreen), findsNothing);
    expect(find.byType(InboxScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-row-dot-$inboxIdA')), findsNothing);
    expect(
      find.byKey(const ValueKey('inbox-row-dot-$inboxIdB')),
      findsOneWidget,
    );
    expect(source.marks, [(inboxOwnerA, inboxIdA)]);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('LOCAL FIXTURE: Home'), findsOneWidget);
    expect(host.navigatorKey.currentState!.canPop(), false);
    await host.close(tester);
  });

  testWidgets('Inbox id takes precedence over legacy game and URL hints', (
    tester,
  ) async {
    final source = FakeInboxSource();
    final host = await _pumpHost(tester, source);
    host.attach();
    DeepLinkService.notifyAppReady();
    DeepLinkService.instance.ingestNotificationData({
      ..._payload,
      'type': 'game_started',
      'game_id': 'LOCAL-FIXTURE-GAME',
      'url': 'https://chessever.com/game/LOCAL-FIXTURE-GAME',
    });
    await tester.pumpAndSettle();
    expect(find.text('Fixture: study a position'), findsOneWidget);
    expect(find.byType(InboxMessageScreen), findsOneWidget);
    expect(source.marks, [(inboxOwnerA, inboxIdA)]);
    await host.close(tester);
  });

  testWidgets('explicit app route overrides the attached Inbox message', (
    tester,
  ) async {
    final source = FakeInboxSource();
    final opened = <String>[];
    final host = await _pumpHost(
      tester,
      source,
      overrides: [
        appDestinationPageNavigationProvider.overrideWithValue(
          (_, page, routeName) => opened.add(routeName),
        ),
      ],
    );
    host.attach();
    DeepLinkService.instance.ingestNotificationData({
      ..._payload,
      'route': '/app/settings/notifications',
    });
    await tester.pump();
    expect(opened, isEmpty);
    DeepLinkService.notifyAppReady();
    await tester.pumpAndSettle();

    expect(opened, ['/app/settings/notifications']);
    expect(find.byType(InboxMessageScreen), findsNothing);
    expect(source.marks, isEmpty);
    await host.close(tester);
  });

  testWidgets('invalid app route falls back to the attached Inbox message', (
    tester,
  ) async {
    final source = FakeInboxSource();
    final host = await _pumpHost(tester, source);
    host.attach();
    DeepLinkService.notifyAppReady();
    DeepLinkService.instance.ingestNotificationData({
      ..._payload,
      'route': 'https://example.invalid/app/settings',
    });
    await tester.pumpAndSettle();

    expect(find.text('Fixture: study a position'), findsOneWidget);
    expect(find.byType(InboxMessageScreen), findsOneWidget);
    expect(source.marks, [(inboxOwnerA, inboxIdA)]);
    await host.close(tester);
  });

  testWidgets('failed Inbox fetch retries into the requested message', (
    tester,
  ) async {
    final source = FakeInboxSource()..failFetch = true;
    final host = await _pumpHost(tester, source);
    host.attach();
    DeepLinkService.notifyAppReady();
    DeepLinkService.instance.ingestNotificationData(_payload);
    await tester.pumpAndSettle();
    expect(find.byType(InboxMessageScreen), findsOneWidget);
    expect(find.byType(GenericErrorWidget), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(source.marks, isEmpty);

    source.failFetch = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Fixture: study a position'), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-full-text')), findsOneWidget);
    expect(source.marks, [(inboxOwnerA, inboxIdA)]);
    await host.close(tester);
  });

  testWidgets('missing Inbox id never opens or marks another message', (
    tester,
  ) async {
    final source = FakeInboxSource()
      ..rows[inboxOwnerA] = [inboxFixture(inboxIdB)];
    final host = await _pumpHost(tester, source);
    host.attach();
    DeepLinkService.notifyAppReady();
    DeepLinkService.instance.ingestNotificationData(_payload);
    await tester.pumpAndSettle();
    expect(find.byType(InboxMessageScreen), findsOneWidget);
    expect(
      find.text('This message is unavailable for this account.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('inbox-full-text')), findsNothing);
    expect(source.marks, isEmpty);
    await host.close(tester);
  });

  testWidgets('account switch during loading cannot leak or mark either body', (
    tester,
  ) async {
    final oldAccountFetch = Completer<List<InboxMessage>>();
    final source = FakeInboxSource();
    final oldMessage = _message(
      inboxIdA,
      'LOCAL FIXTURE: account A title',
      'LOCAL FIXTURE: private account A body',
    );
    source.rows[inboxOwnerB] = [
      _message(
        inboxIdA,
        'LOCAL FIXTURE: account B title',
        'LOCAL FIXTURE: private account B body',
      ),
    ];
    source.fetchOverride = (owner) => owner == inboxOwnerA
        ? oldAccountFetch.future
        : Future.value(source.rows[owner]!);
    final host = await _pumpHost(tester, source);
    host.attach();
    DeepLinkService.notifyAppReady();
    DeepLinkService.instance.ingestNotificationData(_payload);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(InboxMessageScreen), findsOneWidget);
    expect(source.marks, isEmpty);

    host.container.read(_identity.notifier).state = inboxOwnerB;
    await tester.pump();
    oldAccountFetch.complete([oldMessage]);
    await tester.pumpAndSettle();
    expect(host.container.read(inboxProvider).ownerId, inboxOwnerB);
    expect(find.byKey(const ValueKey('inbox-full-text')), findsNothing);
    expect(find.textContaining('private account'), findsNothing);
    expect(
      find.text('This message is unavailable for this account.'),
      findsOneWidget,
    );
    expect(source.marks, isEmpty);
    await host.close(tester);
  });
}
