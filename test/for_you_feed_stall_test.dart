import 'dart:async';
import 'dart:ui' as ui;

import 'package:chessever2/main.dart' show pageRouteObserver;
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/local_storage/for_you/for_you_feed_local_storage.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/widget/for_you_games_widget.dart';
import 'package:chessever2/screens/group_event/widget/premium_collection_cards.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Answers each feed call with the next queued future; an exhausted queue
/// answers with one event.
class _BroadcastRepository implements GroupBroadcastRepository {
  final responses = <Future<List<GroupBroadcast>>>[];
  int calls = 0;

  @override
  Future<List<GroupBroadcast>> getForYouGroupBroadcasts({
    int limit = 20,
    int offset = 0,
    List<String>? timeControlFilters,
    int? minElo,
    int? maxElo,
    Set<String>? statusFilters,
  }) {
    calls++;
    if (responses.isNotEmpty) return responses.removeAt(0);
    return Future.value([_broadcast('event-1')]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected broadcast call: ${invocation.memberName}');
}

class _GameRepository implements GameRepository {
  final responses = <Future<Map<String, List<Games>>>>[];
  int calls = 0;

  @override
  Future<Map<String, List<Games>>> getForYouTopGamesByEventIds({
    required List<String> eventIds,
    int boardsPerEvent = 4,
  }) {
    calls++;
    if (responses.isNotEmpty) return responses.removeAt(0);
    return Future.value({
      for (final eventId in eventIds) eventId: [_game()],
    });
  }

  @override
  Future<Map<String, List<int>>> getForYouFavoritePlayerFideIdsByEventIds({
    required List<String> eventIds,
    required List<int> favoriteFideIds,
  }) async => {};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected game call: ${invocation.memberName}');
}

class _FavoritePlayers extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => [];
}

class _FavoriteEvents extends FavoriteEventsNotifier {
  _FavoriteEvents(this.favorites);
  final List<FavoriteEvent> favorites;

  @override
  Future<List<FavoriteEvent>> build() async => favorites;
}

class _Database implements AppDatabase {
  @override
  Future<CacheEntry?> getCache({
    required String key,
    String? userId,
    Duration? maxAge,
  }) async => null;

  @override
  Future<void> setCache({
    required String key,
    required String value,
    String? userId,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected database call: ${invocation.memberName}');
}

GroupBroadcast _broadcast(String id) => GroupBroadcast(
  id: id,
  name: id,
  createdAt: DateTime.utc(2026, 10, 1),
  search: const [],
);

Games _game() => Games(
  id: 'game-1',
  roundId: 'round-1',
  roundSlug: 'round-1',
  tourId: 'tour-1',
  tourSlug: 'tour-1',
  status: 'ongoing',
  lastMove: 'e2e4',
  players: [
    Player(
      name: 'White',
      title: 'GM',
      rating: 2700,
      fideId: 123,
      fed: 'USA',
      clock: 600,
      team: '',
    ),
    Player(
      name: 'Black',
      title: 'GM',
      rating: 2690,
      fideId: 456,
      fed: 'USA',
      clock: 600,
      team: '',
    ),
  ],
);

/// A wall clock the test moves by hand. It keeps running while an app is
/// suspended, unlike the timers [WidgetTester.pump] advances.
class _WallClock {
  DateTime now = DateTime.utc(2026, 10, 15, 9);
}

ProviderContainer _container({
  required _BroadcastRepository broadcasts,
  required _GameRepository games,
  required _WallClock clock,
  List<Override> extra = const [],
  List<FavoriteEvent> favoriteEvents = const [],
}) => ProviderContainer(
  overrides: [
    ...extra,
    forYouEventsProvider.overrideWith((ref) {
      ref.keepAlive();
      return ForYouNotifier(ref, now: () => clock.now);
    }),
    groupBroadcastRepositoryProvider.overrideWithValue(broadcasts),
    gameRepositoryProvider.overrideWithValue(games),
    forYouFeedLocalStorageProvider.overrideWithValue(
      ForYouFeedLocalStorage(_Database()),
    ),
    liveGroupBroadcastIdsProvider.overrideWith((ref) => Stream.value([])),
    liveRoundsIdProvider.overrideWith((ref) => const Stream.empty()),
    liveTourIdProvider.overrideWith((ref) => const Stream.empty()),
    favoritePlayersProviderNew.overrideWith(_FavoritePlayers.new),
    favoriteEventsProvider.overrideWith(() => _FavoriteEvents(favoriteEvents)),
  ],
);

Future<void> _flush(WidgetTester tester) async {
  await tester.pump(Duration.zero);
  await tester.pump(Duration.zero);
}

final _todayKey = GlobalKey();

/// Pumps the real Today feed as the visible For You page.
Future<void> _pumpToday(
  WidgetTester tester,
  ProviderContainer container,
) async {
  // A phone viewport, so ResponsiveHelper picks the phone list layout.
  tester.view
    ..physicalSize = const Size(393 * 3, 852 * 3)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final scrollController = ScrollController();
  addTearDown(scrollController.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        navigatorObservers: [pageRouteObserver],
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: RepaintBoundary(
                key: _todayKey,
                child: ForYouGamesWidget(scrollController: scrollController),
              ),
            );
          },
        ),
      ),
    ),
  );
  await _flush(tester);
}

/// Pixels below the collection cards that differ from the page background.
Future<int> _paintedBelowCollectionCards(WidgetTester tester) async {
  final boundary =
      _todayKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final cardsBottom =
      tester.getBottomLeft(find.byType(PremiumCollectionCards)).dy -
      tester.getTopLeft(find.byKey(_todayKey)).dy;
  final image = (await tester.runAsync(() => boundary.toImage()))!;
  final bytes = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!.buffer.asUint8List();
  // The feed never reaches the last row, so it shows the page background.
  final reference = (image.height - 1) * image.width * 4;
  final r = bytes[reference];
  final g = bytes[reference + 1];
  final b = bytes[reference + 2];
  var painted = 0;
  for (var y = cardsBottom.ceil() + 1; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final i = (y * image.width + x) * 4;
      if ((bytes[i] - r).abs() > 3 ||
          (bytes[i + 1] - g).abs() > 3 ||
          (bytes[i + 2] - b).abs() > 3) {
        painted++;
      }
    }
  }
  return painted;
}

List<Override> _todayVisible() => [
  forYouTodayTabActiveProvider.overrideWith((ref) => true),
  gamesListViewModeProvider.overrideWithValue(GamesListViewMode.gamesCard),
];

void main() {
  testWidgets('a feed request that never answers ends in a retryable error', (
    tester,
  ) async {
    final broadcasts = _BroadcastRepository()
      ..responses.add(Completer<List<GroupBroadcast>>().future);
    final container = _container(
      broadcasts: broadcasts,
      games: _GameRepository(),
      clock: _WallClock(),
    );
    addTearDown(container.dispose);

    container.read(forYouEventsProvider);
    await _flush(tester);
    expect(container.read(forYouEventsProvider).isLoading, isTrue);

    await tester.pump(const Duration(seconds: 15));
    final failed = container.read(forYouEventsProvider);
    expect(failed.isLoading, isFalse);
    expect(failed.events, isEmpty);
    expect(failed.error, contains('TimeoutException'));

    // The hung request no longer blocks the Retry button.
    unawaited(container.read(forYouEventsProvider.notifier).refresh());
    await _flush(tester);
    expect(broadcasts.calls, 2);
    expect(container.read(forYouEventsProvider).events.single.id, 'event-1');
    expect(container.read(forYouEventsProvider).error, isNull);
  });

  testWidgets('a board request that never answers releases the page fetch', (
    tester,
  ) async {
    final games = _GameRepository()
      ..responses.add(Completer<Map<String, List<Games>>>().future);
    final broadcasts = _BroadcastRepository();
    final container = _container(
      broadcasts: broadcasts,
      games: games,
      clock: _WallClock(),
    );
    addTearDown(container.dispose);

    container.read(forYouEventsProvider);
    await _flush(tester);
    await tester.pump(const Duration(seconds: 15));
    expect(container.read(forYouEventsProvider).isLoading, isFalse);
    expect(container.read(forYouEventsProvider).error, isNotNull);

    unawaited(container.read(forYouEventsProvider.notifier).refresh());
    await _flush(tester);
    expect(broadcasts.calls, 2);
    expect(
      container.read(forYouTopGamesSnapshotCacheProvider)['event-1']?.hasGames,
      isTrue,
    );
  });

  testWidgets(
    'resume replaces a fetch frozen across a suspension and ignores its late answer',
    (tester) async {
      final frozen = Completer<List<GroupBroadcast>>();
      final broadcasts = _BroadcastRepository()..responses.add(frozen.future);
      final clock = _WallClock();
      final container = _container(
        broadcasts: broadcasts,
        games: _GameRepository(),
        clock: clock,
      );
      addTearDown(container.dispose);

      container.read(forYouEventsProvider);
      await _flush(tester);
      expect(container.read(forYouEventsProvider).isLoading, isTrue);

      // Hours pass while the app is suspended; its timers do not run.
      clock.now = clock.now.add(const Duration(hours: 6));
      unawaited(container.read(forYouEventsProvider.notifier).refreshIfStale());
      await _flush(tester);

      expect(broadcasts.calls, 2);
      final resumed = container.read(forYouEventsProvider);
      expect(resumed.isLoading, isFalse);
      expect(resumed.error, isNull);
      expect(resumed.events.single.id, 'event-1');

      // The abandoned request finally answers: it must not replace the page,
      // and its timeout must not surface an error afterwards.
      frozen.complete([_broadcast('stale-event')]);
      await _flush(tester);
      await tester.pump(const Duration(seconds: 15));
      expect(container.read(forYouEventsProvider).events.single.id, 'event-1');
      expect(container.read(forYouEventsProvider).error, isNull);
    },
  );

  testWidgets('a visibility refresh also replaces a frozen fetch', (
    tester,
  ) async {
    final broadcasts = _BroadcastRepository()
      ..responses.add(Completer<List<GroupBroadcast>>().future);
    final clock = _WallClock();
    final container = _container(
      broadcasts: broadcasts,
      games: _GameRepository(),
      clock: clock,
    );
    addTearDown(container.dispose);

    container.read(forYouEventsProvider);
    await _flush(tester);
    clock.now = clock.now.add(const Duration(minutes: 40));
    unawaited(
      container.read(forYouEventsProvider.notifier).refreshForVisibility(),
    );
    await _flush(tester);

    expect(broadcasts.calls, 2);
    expect(container.read(forYouEventsProvider).events.single.id, 'event-1');

    // The abandoned request's own timeout stays silent.
    await tester.pump(const Duration(seconds: 15));
    expect(container.read(forYouEventsProvider).error, isNull);
    expect(broadcasts.calls, 2);
  });

  testWidgets(
    'a frozen request timing out on resume retries without an error',
    (tester) async {
      final broadcasts = _BroadcastRepository()
        ..responses.add(Completer<List<GroupBroadcast>>().future);
      final clock = _WallClock();
      final container = _container(
        broadcasts: broadcasts,
        games: _GameRepository(),
        clock: clock,
      );
      addTearDown(container.dispose);
      final errors = <String?>[];
      container.listen<ForYouState>(
        forYouEventsProvider,
        (_, next) => errors.add(next.error),
      );

      container.read(forYouEventsProvider);
      await _flush(tester);
      // The timeout timer fires first thing after the suspension.
      clock.now = clock.now.add(const Duration(hours: 2));
      await tester.pump(const Duration(seconds: 15));
      await _flush(tester);

      expect(broadcasts.calls, 2);
      expect(errors.whereType<String>(), isEmpty);
      expect(container.read(forYouEventsProvider).events.single.id, 'event-1');
    },
  );

  testWidgets('a fetch still inside its time budget is not restarted', (
    tester,
  ) async {
    final pending = Completer<List<GroupBroadcast>>();
    final broadcasts = _BroadcastRepository()..responses.add(pending.future);
    final clock = _WallClock();
    final container = _container(
      broadcasts: broadcasts,
      games: _GameRepository(),
      clock: clock,
    );
    addTearDown(container.dispose);

    container.read(forYouEventsProvider);
    await _flush(tester);
    clock.now = clock.now.add(const Duration(seconds: 5));
    unawaited(container.read(forYouEventsProvider.notifier).refreshIfStale());
    unawaited(
      container.read(forYouEventsProvider.notifier).refreshForVisibility(),
    );
    await _flush(tester);
    expect(broadcasts.calls, 1);

    pending.complete([_broadcast('event-1')]);
    await _flush(tester);
    expect(container.read(forYouEventsProvider).events.single.id, 'event-1');
  });

  testWidgets('Today draws its loading skeleton below the collection cards', (
    tester,
  ) async {
    final container = _container(
      broadcasts: _BroadcastRepository()
        ..responses.add(Completer<List<GroupBroadcast>>().future),
      games: _GameRepository(),
      clock: _WallClock(),
      extra: _todayVisible(),
    );
    addTearDown(container.dispose);

    await _pumpToday(tester, container);
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(forYouEventsProvider).isLoading, isTrue);
    expect(find.byType(PremiumCollectionCards), findsOneWidget);
    expect(await _paintedBelowCollectionCards(tester), greaterThan(10000));

    // A request that never answers ends on the retryable error page.
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('Today says there is nothing when every event has no boards', (
    tester,
  ) async {
    final container = _container(
      broadcasts: _BroadcastRepository(),
      games: _GameRepository()..responses.add(Future.value({})),
      clock: _WallClock(),
      extra: _todayVisible(),
    );
    addTearDown(container.dispose);

    await _pumpToday(tester, container);
    await tester.pump(const Duration(milliseconds: 200));

    final state = container.read(forYouEventsProvider);
    expect(state.isLoading, isFalse);
    expect(state.events.single.id, 'event-1');
    expect(
      container.read(forYouTopGamesSnapshotCacheProvider)['event-1']?.hasGames,
      isFalse,
    );
    expect(find.text('No events available'), findsOneWidget);
  });

  testWidgets(
    'Today left mid-request for hours shows its events after resume',
    (tester) async {
      // The first feed request never answers: iOS suspended the app with it
      // in flight.
      final broadcasts = _BroadcastRepository()
        ..responses.add(Completer<List<GroupBroadcast>>().future);
      final clock = _WallClock();
      final container = _container(
        broadcasts: broadcasts,
        games: _GameRepository(),
        clock: clock,
        extra: _todayVisible(),
      );

      await _pumpToday(tester, container);
      await tester.pump(const Duration(seconds: 1));
      expect(container.read(forYouEventsProvider).isLoading, isTrue);

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      // Hours in the background; the suspended app's timers do not run.
      clock.now = clock.now.add(const Duration(hours: 6));
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      // The resume refresh runs after the first resumed frame.
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      await tester.pump();

      expect(broadcasts.calls, 2);
      final resumed = container.read(forYouEventsProvider);
      expect(resumed.isLoading, isFalse);
      expect(resumed.error, isNull);
      expect(find.byType(EventCard), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(await _paintedBelowCollectionCards(tester), greaterThan(10000));

      // The abandoned request's timeout stays silent.
      await tester.pump(const Duration(seconds: 15));
      expect(container.read(forYouEventsProvider).error, isNull);
      expect(find.byType(EventCard), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('Today with no events and a dismissed smart card is not blank', (
    tester,
  ) async {
    final smart = FavoriteEvent(
      id: 'smart-favorite',
      userId: 'user',
      eventId: 'smart_event:elite',
      eventName: 'Elite',
      metadata: const {'type': 'smart_event', 'minElo': 2600},
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 1),
    );
    final container = _container(
      broadcasts: _BroadcastRepository()..responses.add(Future.value([])),
      games: _GameRepository(),
      clock: _WallClock(),
      favoriteEvents: [smart],
      extra: [
        ..._todayVisible(),
        dismissedSmartEventCardKeysProvider.overrideWith(
          (ref) => {SmartEventRequest.fromFavoriteEvent(smart).cardDismissKey},
        ),
      ],
    );
    addTearDown(container.dispose);

    await _pumpToday(tester, container);
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(forYouEventsProvider).events, isEmpty);
    expect(find.text('No events available'), findsOneWidget);
  });
}
