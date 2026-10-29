import 'dart:async';

import 'package:chessever2/screens/for_you/discovery/data/discovery_repository.dart';
import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:chessever2/screens/for_you/discovery/providers/reports_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_mode_provider.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/for_you/discovery/likes_screen.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';

import 'package:chessever2/screens/favorites/favorites_tab_screen.dart';
import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart';
import 'package:chessever2/screens/library/twic_contents_screen.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/settings/settings_page.dart';
import 'package:chessever2/services/app_destination_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _MiniaturesRepo extends Fake implements GamebaseRepository {
  final filters = <MiniatureGamesFilter>[];
  @override
  Future<GamebaseMiniaturesPage> getMiniatures({
    MiniatureGamesFilter filter = MiniatureGamesFilter.defaultFilter,
    int limit = 50,
    int offset = 0,
  }) async {
    filters.add(filter);
    return const GamebaseMiniaturesPage(
      items: [],
      total: 0,
      limit: 50,
      offset: 0,
    );
  }
}

class _ReportsRepo extends Fake implements DiscoveryRepository {
  final requests =
      <({ReportGameType? type, DateTime? since, DateTime? until})>[];
  @override
  Future<AnalyzedGamesPage> fetchAnalyzedGamesPage({
    int pageSize = 30,
    AnalyzedGamesCursor? after,
    DateTime? since,
    DateTime? until,
    ReportGameType? gameType,
  }) async {
    requests.add((type: gameType, since: since, until: until));
    return const AnalyzedGamesPage(items: []);
  }
}

void main() {
  late BuildContext context;
  late WidgetRef ref;
  late List<Widget> opened;
  late List<String> routeNames;
  late List<String> requestedFeatures;
  late List<String> legacyLinks;
  late List<String> inboxIds;
  var entitled = true;

  setUp(() {
    opened = [];
    routeNames = [];
    requestedFeatures = [];
    legacyLinks = [];
    inboxIds = [];
    entitled = true;
  });

  Future<void> host(WidgetTester tester, {List<Override> extra = const []}) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...extra,
            appDestinationPageNavigationProvider.overrideWithValue((
              _,
              page,
              name,
            ) {
              opened.add(page);
              routeNames.add(name);
            }),
            appDestinationAccessRequestProvider.overrideWithValue((
              _,
              feature,
            ) async {
              requestedFeatures.add(feature);
              return entitled;
            }),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (ctx, widgetRef, _) {
                context = ctx;
                ref = widgetRef;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

  Future<bool> open(String raw) => openAppDestination(
    context,
    ref,
    parseAppDestination(raw)!,
    openLegacyLink: (link) async {
      legacyLinks.add(link);
      return true;
    },
    openInboxMessage: (id) async {
      inboxIds.add(id);
      return true;
    },
  );

  testWidgets(
    'Reports links retain the Premium gate and scope type/date into the query',
    (tester) async {
      final repo = _ReportsRepo();
      await host(
        tester,
        extra: [discoveryRepositoryProvider.overrideWithValue(repo)],
      );
      final parent = ProviderScope.containerOf(context, listen: false);
      ref.read(reportsGameTypeProvider.notifier).state =
          ReportGameType.marathon;
      ref.read(reportsDateProvider.notifier).state = DateTime.utc(2026, 9, 1);
      final rootSubscription = parent.listen(reportsGamesProvider, (_, __) {});
      await tester.pump();
      for (final type in <ReportGameType?>[null, ...ReportGameType.values]) {
        opened.clear();
        expect(
          await open('/app/reports/${type?.key ?? 'all'}?date=2026-10-28'),
          isTrue,
        );
        final scope = opened.single as ProviderScope;
        final child = ProviderContainer(
          parent: parent,
          overrides: scope.overrides,
        );
        final subscription = child.listen(reportsGamesProvider, (_, __) {});
        await tester.pump(const Duration(milliseconds: 1));
        expect(child.read(reportsGameTypeProvider), type);
        expect(child.read(reportsDateProvider), DateTime.utc(2026, 10, 28));
        expect(repo.requests.last, (
          type: type,
          since: DateTime.utc(2026, 10, 28),
          until: DateTime.utc(2026, 10, 29),
        ));
        expect(parent.read(reportsGameTypeProvider), ReportGameType.marathon);
        expect(parent.read(reportsDateProvider), DateTime.utc(2026, 9, 1));
        subscription.close();
        child.dispose();
        await tester.pump(const Duration(milliseconds: 1));
      }
      opened.clear();
      entitled = false;
      expect(await open('/app/reports/comeback?date=2026-10-28'), isTrue);
      expect(opened, isEmpty);
      expect(requestedFeatures, everyElement('game_reports'));
      rootSubscription.close();
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'Miniatures links scope the tab and date and feed the paginated query',
    (tester) async {
      final repo = _MiniaturesRepo();
      await host(
        tester,
        extra: [gamebaseRepositoryProvider.overrideWithValue(repo)],
      );
      final parent = ProviderScope.containerOf(context, listen: false);
      final parentListener = parent.listen(miniatureGamesProvider, (_, __) {});
      ref.read(miniaturesFilterProvider.notifier).state =
          const MiniatureGamesFilter(search: 'old filter');
      final playerQueryListener = parent.listen(
        miniaturePlayersQueryProvider,
        (_, __) {},
      );
      ref.read(miniaturePlayersQueryProvider.notifier).state =
          const MiniaturePlayersQuery(search: 'old player');
      await tester.pump();
      for (final tab in MiniaturesScreenMode.values) {
        opened.clear();
        final date = tab == MiniaturesScreenMode.games ? '2026-10-28' : null;
        expect(
          await open(
            '/app/miniatures/${tab.name}${date == null ? '' : '?date=$date'}',
          ),
          isTrue,
        );
        final scope = opened.single as ProviderScope;
        final child = ProviderContainer(
          parent: parent,
          overrides: scope.overrides,
        );
        final gamesListener = child.listen(miniatureGamesProvider, (_, __) {});
        await tester.pump();
        expect(child.read(selectedMiniaturesModeProvider), tab);
        expect(child.read(miniaturesFilterProvider).dateFrom, date);
        expect(child.read(miniaturesFilterProvider).dateTo, date);
        expect(child.read(miniaturesFilterProvider).search, isNull);
        expect(child.read(miniaturePlayersQueryProvider).search, isNull);
        expect(parent.read(miniaturePlayersQueryProvider).search, 'old player');
        expect(repo.filters.last.dateFrom, date);
        expect(repo.filters.last.dateTo, date);
        expect(
          repo.filters.last.queryParameters(limit: 50, offset: 0)['dateFrom'],
          date,
        );
        expect(parent.read(miniaturesFilterProvider).search, 'old filter');
        gamesListener.close();
        child.dispose();
        await tester.pump(const Duration(milliseconds: 1));
      }
      parentListener.close();
      playerQueryListener.close();
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'Likes destination restores period, range and Players in its own scope',
    (tester) async {
      await host(tester);
      ref.read(mostLikedDayProvider.notifier).state = DateTime(2026, 8, 1);
      expect(
        await open('/app/likes/month?date=2026-09-23&view=players'),
        isTrue,
      );
      final scope = opened.single as ProviderScope;
      final container = ProviderContainer(overrides: scope.overrides);
      addTearDown(container.dispose);
      expect(container.read(mostLikedPeriodProvider), MostLikedPeriod.month);
      expect(
        MostLikedQuery(
          container.read(mostLikedPeriodProvider),
          container.read(mostLikedDayProvider)!,
        ).start,
        DateTime(2026, 9),
      );
      expect((scope.child as LikesScreen).initialView, MostLikedView.players);
      expect(ref.read(mostLikedDayProvider), DateTime(2026, 8, 1));
      opened.clear();
      expect(await open('/app/likes/week'), isTrue);
      final currentScope = opened.single as ProviderScope;
      final current = ProviderContainer(overrides: currentScope.overrides);
      addTearDown(current.dispose);
      expect(current.read(mostLikedDayProvider), isNull);
      expect(current.read(mostLikedPeriodProvider), MostLikedPeriod.week);
    },
  );

  testWidgets('notification settings selects the actual nested section', (
    tester,
  ) async {
    await host(tester);
    expect(await open('/app/settings/notifications'), isTrue);
    expect(
      (opened.single as SettingsPage).initiallyExpanded,
      SettingsSection.notification,
    );
    expect(routeNames, ['/app/settings/notifications']);
  });

  testWidgets('player games opens the selected player on Games', (
    tester,
  ) async {
    await host(tester);
    expect(
      await open('/app/players/1503014/games?name=Magnus+Carlsen'),
      isTrue,
    );
    final profile = opened.single as PlayerProfileScreen;
    expect(profile.fideId, 1503014);
    expect(profile.playerName, 'Magnus Carlsen');
    expect(profile.initialTab, PlayerProfileTab.games);
  });

  testWidgets('favorites players lands in the rankings page', (tester) async {
    await host(tester);
    expect(await open('/app/favorites/players'), isTrue);
    expect(
      (opened.single as FavoritesTabScreen).initialMode,
      FavoritesScreenMode.players,
    );
  });

  testWidgets('database event remains an exact filter', (tester) async {
    await host(tester);
    expect(await open('/app/library/database?event=Tata+Steel+2026'), isTrue);
    expect(
      (opened.single as TwicContentsScreen).initialEvent,
      'Tata Steel 2026',
    );
  });

  testWidgets('opening line seeds an isolated explorer with its full moves', (
    tester,
  ) async {
    await host(tester);
    expect(await open('/app/explorer?moves=e4+c5+Nf3'), isTrue);
    final scope = opened.single as ProviderScope;
    final explorer = scope.child as GamebaseExplorerScreen;
    expect(explorer.initialMoves, ['e2e4', 'c7c5', 'g1f3']);
    expect(
      explorer.initialFen,
      parseAppDestination('/app/explorer?moves=e4+c5+Nf3')!.line!.fen,
    );
  });

  for (final entry in {
    '/app/reports': 'game_reports',
    '/app/players/1503014/openings': 'opening_tree',
  }.entries) {
    testWidgets('dismissed ${entry.value} paywall consumes its route', (
      tester,
    ) async {
      await host(tester);
      entitled = false;
      expect(await open(entry.key), isTrue);
      expect(requestedFeatures, [entry.value]);
      expect(opened, isEmpty);
      expect(legacyLinks, isEmpty);
      expect(inboxIds, isEmpty);
    });
  }

  testWidgets('exact inbox message delegates its immutable identity', (
    tester,
  ) async {
    await host(tester);
    expect(await open('/app/inbox/immutable-message-id'), isTrue);
    expect(inboxIds, ['immutable-message-id']);
    expect(opened, isEmpty);
    expect(legacyLinks, isEmpty);
  });

  testWidgets('exact inbox route fails when its opener is unavailable', (
    tester,
  ) async {
    await host(tester);
    final result = await openAppDestination(
      context,
      ref,
      parseAppDestination('/app/inbox/message')!,
      openLegacyLink: (_) async => true,
    );
    expect(result, isFalse);
    expect(opened, isEmpty);
  });

  testWidgets('event scorecard delegates the full nested content route', (
    tester,
  ) async {
    await host(tester);
    expect(
      await open('/app/broadcast/olympiad/event-id/team/United%20States'),
      isTrue,
    );
    expect(legacyLinks, [
      'https://chessever.com/broadcast/olympiad/event-id/team/United%20States',
    ]);
    expect(opened, isEmpty);
  });

  testWidgets('content resolution failure remains available to the caller', (
    tester,
  ) async {
    await host(tester);
    final result = await openAppDestination(
      context,
      ref,
      parseAppDestination('/app/books/token')!,
      openLegacyLink: (_) async => false,
    );
    expect(result, isFalse);
  });

  testWidgets('a newer destination supersedes a pending Premium response', (
    tester,
  ) async {
    await host(tester);
    final access = Completer<bool>();
    ProviderScope.containerOf(context).updateOverrides([
      appDestinationPageNavigationProvider.overrideWithValue((_, page, name) {
        opened.add(page);
        routeNames.add(name);
      }),
      appDestinationAccessRequestProvider.overrideWithValue(
        (_, _) => access.future,
      ),
    ]);
    var current = true;
    final pending = openAppDestination(
      context,
      ref,
      parseAppDestination('/app/reports')!,
      openLegacyLink: (_) async => true,
      isCurrent: () => current,
    );
    current = false;
    expect(await open('/app/settings/notifications'), isTrue);
    access.complete(true);
    expect(await pending, isTrue);
    expect(routeNames, ['/app/settings/notifications']);
    expect(opened.single, isA<SettingsPage>());
  });

  testWidgets(
    'a superseded request does not start another paywall or resolver',
    (tester) async {
      await host(tester);
      expect(
        await openAppDestination(
          context,
          ref,
          parseAppDestination('/app/reports')!,
          openLegacyLink: (_) async => throw StateError('Must not resolve'),
          isCurrent: () => false,
        ),
        isTrue,
      );
      expect(requestedFeatures, isEmpty);
      expect(opened, isEmpty);
    },
  );
}
