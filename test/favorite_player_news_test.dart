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

  @override
  Future<void> setFavoritePlayerNewsAlerts(bool value) async {
    state = AsyncData(
      state.requireValue.copyWith(favoritePlayerNewsAlerts: value),
    );
  }
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
  });
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
        final writes = <Future<void>>[];
        final c = ProviderContainer(
          overrides: [
            boardSettingsProviderNew.overrideWith(_Board.new),
            notificationPreferencesProvider.overrideWith(_GamePrefs.new),
            notificationPermissionProvider.overrideWith((_) => _Permission()),
            currentUserProvider.overrideWith(
              (_) => AppUser(
                id: 'fixture-account',
                createdAt: DateTime.utc(2026),
                isAnonymous: true,
              ),
            ),
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
        expect(
          c
              .read(notificationPreferencesProvider)
              .requireValue
              .favoritePlayerNewsAlerts,
          false,
        );
        expect(
          find.textContaining('all devices on your account'),
          findsOneWidget,
        );
        expect(games.favoriteEventAlerts, true);
        expect(games.favoritePlayerAlerts, true);
        expect(tester.takeException(), isNull);
      },
    );
  }
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
