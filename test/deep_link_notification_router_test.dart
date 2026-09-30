import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_repo_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/services/deep_link_service.dart';
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
