import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:chessever2/screens/for_you/discovery/providers/reports_provider.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_mode_provider.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/services/app_destination_service.dart';
import 'package:chessever2/screens/for_you/discovery/likes_screen.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_repo_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/screens/feed/news/news_link_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A notification tap can reach Dart before the widget tree that owns a
/// [WidgetRef] exists. On a cold start the native SDK replays the tapped
/// notification as soon as a click listener is registered — which now happens in
/// `main()`, long before `MyApp` paints — so the payload has to survive that gap
/// instead of being dropped on the floor. Dropping it is what left a
/// terminated-app tap sitting on Home while the same tap worked fine when the
/// app was merely backgrounded.
///
/// Covers early tap buffering and the portal broadcast URL with fake auth and
/// repositories, including tour-to-group resolution and category selection.
void main() {
  const noHintsPayload = <String, dynamic>{'type': 'call_to_action'};

  late GlobalKey<NavigatorState> navigatorKey;
  late List<String> pushedRoutes;

  setUp(() {
    // dispose() clears the router binding's sibling state (nav guards, the
    // app-ready gate) so each test starts from a cold-boot shape.
    DeepLinkService.instance.detachNotificationRouter();
    DeepLinkService.instance.dispose();
    navigatorKey = GlobalKey<NavigatorState>();
    pushedRoutes = <String>[];
  });

  tearDown(() {
    DeepLinkService.instance.detachNotificationRouter();
    DeepLinkService.instance.dispose();
  });

  Future<WidgetRef> pumpHost(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          onGenerateRoute: (settings) {
            pushedRoutes.add(settings.name ?? '');
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => Consumer(
                builder: (_, ref, __) {
                  captured = ref;
                  return const SizedBox.shrink();
                },
              ),
            );
          },
          initialRoute: '/',
        ),
      ),
    );
    return captured;
  }

  for (final cold in [true, false]) {
    for (final key in ['url', 'route']) {
      for (final component in ['prep', 'library', 'likes']) {
        testWidgets('My Space $component from $key (cold=$cold)', (
          tester,
        ) async {
          DeepLinkService.instance.dispose();
          final opened = <Widget>[];
          final ref = await pumpHost(
            tester,
            overrides: [
              currentUserProvider.overrideWithValue(
                AppUser(id: 'space-user', createdAt: DateTime(2026)),
              ),
              appDestinationPageNavigationProvider.overrideWithValue(
                (_, page, __) => opened.add(page),
              ),
            ],
          );
          if (!cold) {
            DeepLinkService.instance.attachNotificationRouter(
              navigatorKey,
              ref,
            );
          }
          DeepLinkService.instance.ingestNotificationData({
            key: 'https://chessever.com/app/my-space/$component',
          });
          if (cold) {
            DeepLinkService.instance.attachNotificationRouter(
              navigatorKey,
              ref,
            );
          }
          DeepLinkService.notifyAppReady();
          await tester.pumpAndSettle();
          expect(opened, hasLength(1));
        });
      }
    }
  }

  for (final coldStart in [true, false]) {
    for (final key in ['url', 'route']) {
      for (final type in <ReportGameType?>[null, ...ReportGameType.values]) {
        testWidgets(
          'Reports ${type?.key ?? 'all'} opens from $key (cold=$coldStart)',
          (tester) async {
            DeepLinkService.instance.dispose();
            final opened = <Widget>[];
            final ref = await pumpHost(
              tester,
              overrides: [
                currentUserProvider.overrideWithValue(
                  AppUser(id: 'reports-user', createdAt: DateTime(2026)),
                ),
                appDestinationAccessRequestProvider.overrideWithValue(
                  (_, __) async => true,
                ),
                appDestinationPageNavigationProvider.overrideWithValue(
                  (_, page, __) => opened.add(page),
                ),
              ],
            );
            if (!coldStart) {
              DeepLinkService.instance.attachNotificationRouter(
                navigatorKey,
                ref,
              );
            }
            DeepLinkService.instance.ingestNotificationData({
              key:
                  'https://chessever.com/app/reports/${type?.key ?? 'all'}?date=2026-10-28',
            });
            if (coldStart) {
              DeepLinkService.instance.attachNotificationRouter(
                navigatorKey,
                ref,
              );
            }
            DeepLinkService.notifyAppReady();
            await tester.pumpAndSettle();
            final scope = opened.single as ProviderScope;
            final container = ProviderContainer(overrides: scope.overrides);
            expect(container.read(reportsGameTypeProvider), type);
            expect(
              container.read(reportsDateProvider),
              DateTime.utc(2026, 10, 28),
            );
            container.dispose();
            await tester.pump(const Duration(milliseconds: 1));
          },
        );
      }
    }
  }

  for (final coldStart in [true, false]) {
    for (final key in ['url', 'route']) {
      for (final tab in MiniaturesScreenMode.values) {
        testWidgets('Miniatures $tab opens from $key (cold=$coldStart)', (
          tester,
        ) async {
          DeepLinkService.instance.dispose();
          final opened = <Widget>[];
          final ref = await pumpHost(
            tester,
            overrides: [
              currentUserProvider.overrideWithValue(
                AppUser(id: 'miniatures-user', createdAt: DateTime(2026)),
              ),
              appDestinationPageNavigationProvider.overrideWithValue(
                (_, page, __) => opened.add(page),
              ),
            ],
          );
          if (!coldStart) {
            DeepLinkService.instance.attachNotificationRouter(
              navigatorKey,
              ref,
            );
          }
          final date = tab == MiniaturesScreenMode.games ? '2026-10-28' : null;
          DeepLinkService.instance.ingestNotificationData({
            key:
                'https://chessever.com/app/miniatures/${tab.name}${date == null ? '' : '?date=$date'}',
          });
          if (coldStart) {
            DeepLinkService.instance.attachNotificationRouter(
              navigatorKey,
              ref,
            );
          }
          DeepLinkService.notifyAppReady();
          await tester.pumpAndSettle();
          final scope = opened.single as ProviderScope;
          final container = ProviderContainer(overrides: scope.overrides);
          expect(container.read(selectedMiniaturesModeProvider), tab);
          expect(container.read(miniaturesFilterProvider).dateFrom, date);
          expect(container.read(miniaturesFilterProvider).dateTo, date);
          container.dispose();
          await tester.pump(const Duration(milliseconds: 1));
        });
      }
    }
  }

  for (final coldStart in [true, false]) {
    for (final key in ['url', 'route']) {
      testWidgets(
        'Likes notification restores section and range via $key (cold=$coldStart)',
        (tester) async {
          DeepLinkService.instance.dispose();
          final opened = <Widget>[];
          final ref = await pumpHost(
            tester,
            overrides: [
              authStateProvider.overrideWith(_Authenticated.new),
              currentUserProvider.overrideWithValue(
                AppUser(id: 'likes-user', createdAt: DateTime(2026)),
              ),
              appDestinationPageNavigationProvider.overrideWithValue(
                (_, page, __) => opened.add(page),
              ),
            ],
          );
          if (!coldStart) {
            DeepLinkService.instance.attachNotificationRouter(
              navigatorKey,
              ref,
            );
          }
          DeepLinkService.instance.ingestNotificationData({
            key:
                'https://chessever.com/app/likes/week?date=2026-09-21&view=players',
          });
          if (coldStart) {
            DeepLinkService.instance.attachNotificationRouter(
              navigatorKey,
              ref,
            );
          }
          DeepLinkService.notifyAppReady();
          await tester.pumpAndSettle();
          final scope = opened.single as ProviderScope;
          final container = ProviderContainer(overrides: scope.overrides);
          addTearDown(container.dispose);
          expect(container.read(mostLikedPeriodProvider), MostLikedPeriod.week);
          expect(container.read(mostLikedDayProvider), DateTime(2026, 9, 21));
          expect(
            (scope.child as LikesScreen).initialView,
            MostLikedView.players,
          );
        },
      );
    }
  }

  for (final coldStart in [true, false]) {
    for (final source in ['chessever', 'rookreview']) {
      testWidgets(
        'shared news opens the exact reader (cold=$coldStart, source=$source)',
        (tester) async {
          final pages = <Widget>[];
          final ref = await pumpHost(
            tester,
            overrides: [
              authStateProvider.overrideWith(_Authenticated.new),
              currentUserProvider.overrideWithValue(
                AppUser(
                  id: 'news-reader',
                  createdAt: DateTime.utc(2026),
                  isAnonymous: true,
                ),
              ),
              appDestinationPageNavigationProvider.overrideWithValue(
                (_, page, __) => pages.add(page),
              ),
            ],
          );
          final auth = ProviderScope.containerOf(
            navigatorKey.currentContext!,
          ).listen(authStateProvider, (_, __) {});
          addTearDown(auth.close);
          await tester.pump();
          if (!coldStart) DeepLinkService.notifyAppReady();
          pushedRoutes.clear();
          final path = source == 'chessever'
              ? '/news/7/stale-title'
              : '/news/partners/rookreview/7/stale-title';
          DeepLinkService.instance.handleDeepLink(
            Uri.parse('https://chessever.com$path'),
            navigatorKey,
            ref,
          );
          if (coldStart) {
            await tester.pump();
            expect(pages, isEmpty);
            DeepLinkService.notifyAppReady();
          }
          // The readiness completer belongs to the startup zone, outside
          // WidgetTester's frame clock. Drain its session hand-off too.
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pumpAndSettle();
          final page = pages.single as NewsLinkScreen;
          expect(page.link.id, 7);
          expect(
            page.link.publisher.sourceId,
            source == 'chessever' ? null : source,
          );
          expect(pushedRoutes, coldStart ? ['/home_screen'] : isEmpty);
        },
      );
    }
  }

  for (final coldStart in [true, false]) {
    testWidgets('tester broadcast URL opens event (cold=$coldStart)', (
      tester,
    ) async {
      DeepLinkService.instance.dispose();
      final tours = _Tours();
      final groups = _Groups();
      final selection = _Selection();
      final ref = await pumpHost(
        tester,
        overrides: [
          authStateProvider.overrideWith(_Authenticated.new),
          tourRepositoryProvider.overrideWithValue(tours),
          groupBroadcastRepositoryProvider.overrideWithValue(groups),
          tourDetailRepoProvider.overrideWithValue(selection),
        ],
      );
      const data = <String, dynamic>{
        'url':
            'https://chessever.com/broadcast/2026-titled-tuesday-blitz-september-29/mKgqPByN',
      };
      final authSubscription = ProviderScope.containerOf(
        navigatorKey.currentContext!,
      ).listen(authStateProvider, (_, __) {});
      await tester.pump();
      addTearDown(authSubscription.close);
      pushedRoutes.clear();
      if (!coldStart) {
        DeepLinkService.instance.attachNotificationRouter(navigatorKey, ref);
      }
      DeepLinkService.instance.ingestNotificationData(data);
      if (coldStart) {
        DeepLinkService.instance.attachNotificationRouter(navigatorKey, ref);
      }
      DeepLinkService.notifyAppReady();
      await tester.pumpAndSettle();
      expect(tours.requested, ['mKgqPByN']);
      expect(groups.requested, 'gb_mKgqPByN');
      expect(selection.tourId, 'mKgqPByN');
      expect(pushedRoutes, ['/tournament_detail_screen']);
      expect(
        ProviderScope.containerOf(
          navigatorKey.currentContext!,
        ).read(selectedBroadcastModelProvider)?.id,
        'gb_mKgqPByN',
      );
    });
  }

  testWidgets('a tap that lands before the router is attached is not lost', (
    tester,
  ) async {
    final ref = await pumpHost(tester);
    pushedRoutes.clear();

    // Cold start: the click listener fires while nothing can navigate yet.
    DeepLinkService.instance.ingestNotificationData(noHintsPayload);
    await tester.pump();

    expect(
      pushedRoutes,
      isEmpty,
      reason: 'nothing should navigate before the router is attached',
    );

    // The tree comes up and claims the tap.
    DeepLinkService.instance.attachNotificationRouter(navigatorKey, ref);
    await tester.pump();

    expect(pushedRoutes, contains('/home_screen'));
  });

  testWidgets('a tap that lands after attach routes straight away', (
    tester,
  ) async {
    final ref = await pumpHost(tester);
    DeepLinkService.instance.attachNotificationRouter(navigatorKey, ref);
    pushedRoutes.clear();

    // Warm start: the app is already up when the tap arrives.
    DeepLinkService.instance.ingestNotificationData(noHintsPayload);
    await tester.pump();

    expect(pushedRoutes, contains('/home_screen'));
  });

  testWidgets('only the most recent buffered tap is routed', (tester) async {
    final ref = await pumpHost(tester);
    pushedRoutes.clear();

    DeepLinkService.instance.ingestNotificationData(noHintsPayload);
    DeepLinkService.instance.ingestNotificationData(noHintsPayload);
    DeepLinkService.instance.ingestNotificationData(noHintsPayload);
    await tester.pump();

    DeepLinkService.instance.attachNotificationRouter(navigatorKey, ref);
    await tester.pump();

    // Three buffered taps must not become three competing navigations — the
    // user tapped one notification.
    expect(
      pushedRoutes.where((r) => r == '/home_screen'),
      hasLength(1),
      reason: 'buffered taps collapse to the newest one',
    );
  });

  testWidgets('attaching with an empty buffer navigates nothing', (
    tester,
  ) async {
    final ref = await pumpHost(tester);
    pushedRoutes.clear();

    DeepLinkService.instance.attachNotificationRouter(navigatorKey, ref);
    await tester.pump();

    expect(pushedRoutes, isEmpty);
  });
}

class _Authenticated extends AuthController {
  @override
  Future<AppAuthState> build() async =>
      const AppAuthState(status: AppAuthStatus.authenticated);
}

class _Tours implements TourRepository {
  List<String>? requested;
  @override
  Future<List<Tour>> getToursByIds(List<String> ids) async {
    requested = ids;
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
  String? tourId;
  @override
  Future<void> saveSelectedTourId({
    required String groupEventId,
    required String tourId,
  }) async {
    this.tourId = tourId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
