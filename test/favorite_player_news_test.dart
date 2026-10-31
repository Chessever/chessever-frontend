// Test-only in-memory implementation of the installed preferences backend.
// ignore_for_file: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:chessever2/providers/favorite_player_news_preference_provider.dart';
import 'package:chessever2/providers/notification_preferences_provider.dart';
import 'package:chessever2/providers/notification_permission_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/screens/settings/widgets/notification_settings_body.dart';
import 'package:chessever2/screens/feed/news/news_repository.dart';
import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/screens/feed/news/news_reader_screen.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/services/favorite_player_news_destination.dart';
import 'package:chessever2/services/favorite_player_news_preference_store.dart';
import 'package:chessever2/services/direct_push_registration_controller.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/notification_settings/notif_toggle_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Board extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _GamePrefs extends NotificationPreferencesNotifier {
  @override
  Future<NotificationPreferences> build() async =>
      NotificationPreferences.defaults;
}

class _Permission extends StateNotifier<AsyncValue<bool>>
    implements NotificationPermissionNotifier {
  _Permission([bool enabled = true]) : super(AsyncData(enabled));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget _theme(Widget child, {GlobalKey<NavigatorState>? navigatorKey}) =>
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: AppTheme.darkTheme,
      builder: (context, child) {
        ResponsiveHelper.init(context);
        return child!;
      },
      routes: {
        '/home_screen': (_) => const Scaffold(body: Text('LOCAL FIXTURE Home')),
      },
      home: child,
    );
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  test(
    'default, persistence and provider restoration are device-local',
    () async {
      var synced = 0;
      ProviderContainer container() => ProviderContainer(
        overrides: [
          favoritePlayerNewsSyncProvider.overrideWithValue(() async {
            synced++;
          }),
        ],
      );
      final a = container();
      expect(await a.read(favoritePlayerNewsPreferenceProvider.future), true);
      await a
          .read(favoritePlayerNewsPreferenceProvider.notifier)
          .setEnabled(false);
      expect(await FavoritePlayerNewsPreferenceStore().read(), false);
      a.dispose();
      final restored = container();
      expect(
        await restored.read(favoritePlayerNewsPreferenceProvider.future),
        false,
      );
      expect(synced, 1);
      expect(NotificationPreferences.defaults.favoritePlayerAlerts, true);
      expect(NotificationPreferences.defaults.favoriteEventAlerts, true);
      final stored = await SharedPreferences.getInstance();
      expect(stored.getKeys(), {FavoritePlayerNewsPreferenceStore.stateKey});
      restored.dispose();
    },
  );
  test(
    'failed server sync retains local opt-out and reports pending instead of undoing it',
    () async {
      var attempts = 0;
      final c = ProviderContainer(
        overrides: [
          favoritePlayerNewsSyncProvider.overrideWithValue(() async {
            if (++attempts == 1) {
              throw StateError('Synthetic local sync pending');
            }
          }),
        ],
      );
      await c.read(favoritePlayerNewsPreferenceProvider.future);
      final notifier = c.read(favoritePlayerNewsPreferenceProvider.notifier);
      await expectLater(notifier.setEnabled(false), throwsStateError);
      expect(await FavoritePlayerNewsPreferenceStore().read(), false);
      expect(c.read(favoritePlayerNewsPreferenceProvider).requireValue, false);
      await notifier.setEnabled(false);
      expect(attempts, 2);
      c.dispose();
    },
  );
  test(
    'rapid toggle writes serialize; final opt-out survives restore',
    () async {
      final c = ProviderContainer(
        overrides: [
          favoritePlayerNewsSyncProvider.overrideWithValue(() async {}),
        ],
      );
      await c.read(favoritePlayerNewsPreferenceProvider.future);
      final n = c.read(favoritePlayerNewsPreferenceProvider.notifier);
      await Future.wait([
        n.setEnabled(false),
        n.setEnabled(true),
        n.setEnabled(false),
      ]);
      expect(c.read(favoritePlayerNewsPreferenceProvider).requireValue, false);
      expect(await FavoritePlayerNewsPreferenceStore().read(), false);
      c.dispose();
    },
  );
  test(
    'tap destination validates article identity and ignores competing player/event route',
    () {
      final route = favoritePlayerNewsDestination({
        'type': 'favorite_player_news',
        'news_id': '42',
        'route': '/app/events',
        'url': 'https://attacker.example',
      });
      expect(route?.id, '42');
      expect(route?.uri.path, '/app/news/42');
      for (final value in [
        null,
        '',
        '0',
        '01',
        '-1',
        '1e2',
        '42/other',
        1.5,
        {},
        '9007199254740992',
      ]) {
        expect(
          favoritePlayerNewsDestination({
            'type': 'favorite_player_news',
            'news_id': value,
            'route': '/app/news/42',
          }),
          isNull,
        );
      }
    },
  );
  for (final width in [320.0, 390.0]) {
    testWidgets(
      'actual settings render at $width; News opt-out preserves game and event settings',
      (tester) async {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var syncs = 0;
        final writes = <Future<void>>[];
        final c = ProviderContainer(
          overrides: [
            boardSettingsProviderNew.overrideWith(_Board.new),
            notificationPreferencesProvider.overrideWith(_GamePrefs.new),
            notificationPermissionProvider.overrideWith((_) => _Permission()),
            favoritePlayerNewsSyncProvider.overrideWithValue(() async {
              syncs++;
            }),
          ],
        );
        addTearDown(c.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: _theme(
              Scaffold(
                body: SingleChildScrollView(
                  child: NotificationSettingsBody(trackPersist: writes.add),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('News about favorite players'), findsOneWidget);
        final tile = find.ancestor(
          of: find.text('News about favorite players'),
          matching: find.byType(NotifToggleTile),
        );
        expect(tester.widget<NotifToggleTile>(tile).value, true);
        final games = c.read(notificationPreferencesProvider).requireValue;
        await tester.ensureVisible(tile);
        await tester.tap(
          find.descendant(of: tile, matching: find.byType(Switch)),
        );
        await tester.pumpAndSettle();
        await Future.wait(writes);
        await tester.pumpAndSettle();
        expect(tester.widget<NotifToggleTile>(tile).value, false);
        expect(syncs, 1);
        expect(
          c.read(notificationPreferencesProvider).requireValue,
          same(games),
        );
        expect(games.favoriteEventAlerts, true);
        expect(games.favoritePlayerAlerts, true);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'persistent pending status survives settings remount and clears only on remote acknowledgement',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        FavoritePlayerNewsPreferenceStore.key: false,
      });
      final status = ValueNotifier(
        const FavoritePlayerNewsSyncStatus(enabled: false),
      );
      addTearDown(status.dispose);
      final c = ProviderContainer(
        overrides: [
          boardSettingsProviderNew.overrideWith(_Board.new),
          notificationPreferencesProvider.overrideWith(_GamePrefs.new),
          notificationPermissionProvider.overrideWith(
            (_) => _Permission(false),
          ),
          favoritePlayerNewsStatusProvider.overrideWithValue(status),
          favoritePlayerNewsSyncProvider.overrideWithValue(
            () async => throw StateError('Synthetic offline'),
          ),
        ],
      );
      addTearDown(c.dispose);
      Widget settings() => UncontrolledProviderScope(
        container: c,
        child: _theme(
          Scaffold(
            body: SingleChildScrollView(
              child: NotificationSettingsBody(trackPersist: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpWidget(settings());
      await tester.pumpAndSettle();
      final tile = find.ancestor(
        of: find.text('News about favorite players'),
        matching: find.byType(NotifToggleTile),
      );
      expect(tester.widget<NotifToggleTile>(tile).value, false);
      expect(
        tester.widget<NotifToggleTile>(tile).onChanged,
        isNotNull,
        reason: 'Category opt-out must not depend on OS/provider readiness',
      );
      expect(find.textContaining('Sync pending.'), findsOneWidget);
      expect(
        find.textContaining(
          'Alerts already accepted or in flight may still arrive.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(settings());
      await tester.pumpAndSettle();
      expect(find.textContaining('Sync pending.'), findsOneWidget);
      // An acknowledgement for an older desired value must not clear pending.
      status.value = const FavoritePlayerNewsSyncStatus(
        enabled: true,
        confirmed: true,
      );
      await tester.pump();
      expect(find.textContaining('Sync pending.'), findsOneWidget);
      status.value = const FavoritePlayerNewsSyncStatus(
        enabled: false,
        confirmed: true,
      );
      await tester.pump();
      expect(find.textContaining('Sync pending.'), findsNothing);
      expect(find.textContaining('Synced on this device'), findsOneWidget);
      expect(tester.widget<NotifToggleTile>(tile).value, false);
      expect(
        c
            .read(notificationPreferencesProvider)
            .requireValue
            .favoriteEventAlerts,
        true,
      );
      expect(
        c
            .read(notificationPreferencesProvider)
            .requireValue
            .favoritePlayerAlerts,
        true,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final cold in [false, true]) {
    testWidgets(
      'actual notification router opens exact article ${cold ? 'after cold startup' : 'warm'}',
      (tester) async {
        DeepLinkService.instance.dispose();
        addTearDown(DeepLinkService.instance.dispose);
        final nav = GlobalKey<NavigatorState>();
        late WidgetRef captured;
        final loaded = <int?>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentUserProvider.overrideWith(
                (_) => AppUser(
                  id: '00000000-0000-4000-8000-000000000001',
                  createdAt: DateTime.utc(2026),
                  isAnonymous: true,
                ),
              ),
              premiumAccessProvider.overrideWithValue(false),
              newsArticleLoaderProvider.overrideWithValue((link) async {
                loaded.add(link.id);
                return FeedNews(
                  id: link.id!,
                  title: 'LOCAL FIXTURE exact article ${link.id}',
                  summary: '',
                  content:
                      'Players involved: [Alpha Player](/player/101)\n\nInterview body.',
                  publishedAt: DateTime.utc(2026),
                );
              }),
            ],
            child: Consumer(
              builder: (context, ref, _) {
                captured = ref;
                return _theme(
                  const Scaffold(body: Text('LOCAL FIXTURE startup')),
                  navigatorKey: nav,
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        DeepLinkService.instance.attachNotificationRouter(nav, captured);
        if (!cold) DeepLinkService.notifyAppReady();
        DeepLinkService.instance.ingestNotificationData({
          'type': 'favorite_player_news',
          'news_id': '42',
          'route': '/app/events',
        });
        await tester.pump();
        if (cold) {
          expect(loaded, isEmpty);
          DeepLinkService.notifyAppReady();
        }
        await tester.pumpAndSettle();
        expect(loaded, [42]);
        expect(find.byType(NewsReaderScreen), findsOneWidget);
        expect(find.text('LOCAL FIXTURE exact article 42'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
