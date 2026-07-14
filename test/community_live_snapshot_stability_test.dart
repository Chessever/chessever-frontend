import 'dart:async';

import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _EmptyFavoriteEventsNotifier extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const <FavoriteEvent>[];
}

class _NewEventFavoriteEventsNotifier extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async {
    final now = DateTime.now();
    return <FavoriteEvent>[
      FavoriteEvent(
        id: 'favorite-row',
        userId: 'user-1',
        eventId: 'new-starred-event',
        eventName: 'New starred event',
        metadata: const <String, dynamic>{},
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }
}

class _EmptyFavoritePlayersNotifier extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => const <FavoritePlayer>[];
}

class _SequencedBroadcastRepository implements GroupBroadcastRepository {
  _SequencedBroadcastRepository(this.snapshots);

  final List<List<GroupBroadcast>> snapshots;
  int calls = 0;

  @override
  Future<List<GroupBroadcast>> getForYouGroupBroadcasts({
    int limit = 20,
    int offset = 0,
    List<String>? timeControlFilters,
    int? minElo,
    int? maxElo,
    Set<String>? statusFilters,
  }) async {
    final index = calls.clamp(0, snapshots.length - 1);
    calls += 1;
    return snapshots[index];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyGameRepository implements GameRepository {
  @override
  Future<Map<String, List<Games>>> getForYouTopGamesByEventIds({
    required List<String> eventIds,
    int boardsPerEvent = 4,
  }) async => <String, List<Games>>{
    for (final eventId in eventIds) eventId: const <Games>[],
  };

  @override
  Future<Map<String, List<int>>> getForYouFavoritePlayerFideIdsByEventIds({
    required List<String> eventIds,
    required List<int> favoriteFideIds,
  }) async => <String, List<int>>{};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GroupBroadcast _broadcast({
  required String id,
  required String name,
  required int maxAvgElo,
}) {
  final now = DateTime.now();
  return GroupBroadcast(
    id: id,
    createdAt: now.subtract(const Duration(hours: 2)),
    name: name,
    search: const <String>[],
    maxAvgElo: maxAvgElo,
    dateStart: now.subtract(const Duration(hours: 1)),
    dateEnd: now.add(const Duration(hours: 8)),
    timeControl: 'blitz',
  );
}

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for replay state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'live refresh does not swap Titled Tuesday siblings when mutable ranking snapshots alternate',
    () async {
      final initial = <GroupBroadcast>[
        _broadcast(
          id: 'titled-tuesday-1',
          name: 'Titled Tuesday #1',
          maxAvgElo: 2800,
        ),
        _broadcast(
          id: 'titled-tuesday-2',
          name: 'Titled Tuesday #2',
          maxAvgElo: 2700,
        ),
      ];
      final second = <GroupBroadcast>[
        _broadcast(
          id: 'titled-tuesday-2',
          name: 'Titled Tuesday #2',
          maxAvgElo: 2810,
        ),
        _broadcast(
          id: 'titled-tuesday-1',
          name: 'Titled Tuesday #1',
          maxAvgElo: 2790,
        ),
      ];
      final third = <GroupBroadcast>[
        _broadcast(
          id: 'titled-tuesday-1',
          name: 'Titled Tuesday #1',
          maxAvgElo: 2820,
        ),
        _broadcast(
          id: 'titled-tuesday-2',
          name: 'Titled Tuesday #2',
          maxAvgElo: 2780,
        ),
      ];
      final broadcasts = _SequencedBroadcastRepository([
        initial,
        second,
        third,
      ]);
      final liveRounds = StreamController<List<String>>.broadcast();
      final container = ProviderContainer(
        overrides: [
          groupBroadcastRepositoryProvider.overrideWithValue(broadcasts),
          gameRepositoryProvider.overrideWithValue(_EmptyGameRepository()),
          favoriteEventsProvider.overrideWith(_EmptyFavoriteEventsNotifier.new),
          favoritePlayersProviderNew.overrideWith(
            _EmptyFavoritePlayersNotifier.new,
          ),
          liveGroupBroadcastIdsProvider.overrideWith(
            (ref) => Stream<List<String>>.value(const <String>[
              'titled-tuesday-1',
              'titled-tuesday-2',
            ]),
          ),
          liveRoundsIdProvider.overrideWith((ref) => liveRounds.stream),
          liveTourIdProvider.overrideWith(
            (ref) => const Stream<List<String>>.empty(),
          ),
          forYouSurfaceVisibleProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await liveRounds.close();
      });

      final subscription = container.listen<ForYouState>(
        forYouEventsProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await _waitFor(
        () =>
            broadcasts.calls >= 1 &&
            container.read(forYouEventsProvider).events.length == 2,
      );
      expect(
        container.read(forYouEventsProvider).events.map((event) => event.id),
        <String>['titled-tuesday-1', 'titled-tuesday-2'],
      );

      liveRounds.add(const <String>['round-6']);
      await _waitFor(() => broadcasts.calls >= 2);
      await _waitFor(
        () => container.read(forYouEventsProvider).isLoading == false,
      );

      // Contract: live metadata may change, but already-visible sibling cards
      // keep their session order instead of swapping under the user's finger.
      expect(
        container.read(forYouEventsProvider).events.map((event) => event.id),
        <String>['titled-tuesday-1', 'titled-tuesday-2'],
      );

      liveRounds.add(const <String>['round-7']);
      await _waitFor(() => broadcasts.calls >= 3);
      await _waitFor(
        () => container.read(forYouEventsProvider).isLoading == false,
      );
      expect(
        container.read(forYouEventsProvider).events.map((event) => event.id),
        <String>['titled-tuesday-1', 'titled-tuesday-2'],
      );
    },
  );

  test(
    'a genuinely new starred live event enters through personalized ranking',
    () async {
      final initial = <GroupBroadcast>[
        _broadcast(id: 'regular-a', name: 'Regular A', maxAvgElo: 2900),
        _broadcast(id: 'regular-b', name: 'Regular B', maxAvgElo: 2800),
      ];
      final withNewStar = <GroupBroadcast>[
        ...initial,
        _broadcast(
          id: 'new-starred-event',
          name: 'New starred event',
          maxAvgElo: 2200,
        ),
      ];
      final broadcasts = _SequencedBroadcastRepository(<List<GroupBroadcast>>[
        initial,
        withNewStar,
      ]);
      final liveRounds = StreamController<List<String>>.broadcast();
      final container = ProviderContainer(
        overrides: [
          groupBroadcastRepositoryProvider.overrideWithValue(broadcasts),
          gameRepositoryProvider.overrideWithValue(_EmptyGameRepository()),
          favoriteEventsProvider.overrideWith(
            _NewEventFavoriteEventsNotifier.new,
          ),
          favoritePlayersProviderNew.overrideWith(
            _EmptyFavoritePlayersNotifier.new,
          ),
          liveGroupBroadcastIdsProvider.overrideWith(
            (ref) => Stream<List<String>>.value(const <String>[]),
          ),
          liveRoundsIdProvider.overrideWith((ref) => liveRounds.stream),
          liveTourIdProvider.overrideWith(
            (ref) => const Stream<List<String>>.empty(),
          ),
          forYouSurfaceVisibleProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await liveRounds.close();
      });

      final subscription = container.listen<ForYouState>(
        forYouEventsProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await _waitFor(
        () =>
            broadcasts.calls >= 1 &&
            container.read(forYouEventsProvider).events.length == 2,
      );
      expect(
        container.read(forYouEventsProvider).events.map((event) => event.id),
        <String>['regular-a', 'regular-b'],
      );

      liveRounds.add(const <String>['new-live-round']);
      await _waitFor(
        () =>
            broadcasts.calls >= 2 &&
            container.read(forYouEventsProvider).events.length == 3,
      );
      await _waitFor(
        () => container.read(forYouEventsProvider).isLoading == false,
      );

      expect(
        container.read(forYouEventsProvider).events.map((event) => event.id),
        <String>['new-starred-event', 'regular-a', 'regular-b'],
      );
    },
  );

  test(
    'round reconciliation updates newer fields without dropping siblings',
    () {
      final startsAt = DateTime.utc(2026, 7, 14, 18);
      final missingCounts = <String, int>{};
      const previous = <GamesAppBarModel>[
        GamesAppBarModel(
          id: 'round-5',
          name: 'Round 5',
          startsAt: null,
          roundStatus: RoundStatus.ongoing,
          sourceRoundIds: <String>['round-5'],
        ),
        GamesAppBarModel(
          id: 'round-6',
          name: 'Round 6',
          startsAt: null,
          roundStatus: RoundStatus.upcoming,
          sourceRoundIds: <String>['round-6'],
        ),
      ];
      final merged = mergePublishedRoundModels(
        previous: previous,
        incoming: <GamesAppBarModel>[
          GamesAppBarModel(
            id: 'round-6',
            name: 'Round 6 (Live)',
            startsAt: startsAt,
            roundStatus: RoundStatus.upcoming,
            sourceRoundIds: const <String>['round-6'],
          ),
        ],
        liveRoundIds: const <String>['round-6'],
        missingSnapshotCounts: missingCounts,
      );

      expect(
        merged.map((round) => round.id),
        containsAll(<String>['round-5', 'round-6']),
      );
      final round6 = merged.singleWhere((round) => round.id == 'round-6');
      expect(round6.name, 'Round 6 (Live)');
      expect(round6.startsAt, startsAt);
      expect(round6.roundStatus, RoundStatus.live);
    },
  );

  test(
    'round cache syncs live status and prunes only after bounded misses',
    () {
      final startsAt = DateTime.now().add(const Duration(hours: 2));
      final missingCounts = <String, int>{};
      var known = mergePublishedRoundModels(
        previous: const <GamesAppBarModel>[],
        incoming: <GamesAppBarModel>[
          GamesAppBarModel(
            id: 'round-8',
            name: 'Round 8',
            startsAt: startsAt,
            roundStatus: RoundStatus.upcoming,
            sourceRoundIds: const <String>['round-8'],
          ),
        ],
        liveRoundIds: const <String>['round-8'],
        missingSnapshotCounts: missingCounts,
        missingSnapshotTolerance: 2,
      );
      expect(known.single.roundStatus, RoundStatus.live);

      final firstMiss = mergePublishedRoundModels(
        previous: known,
        incoming: const <GamesAppBarModel>[],
        liveRoundIds: const <String>['round-8'],
        missingSnapshotCounts: missingCounts,
        missingSnapshotTolerance: 2,
      );
      known = firstMiss;
      final secondMiss = mergePublishedRoundModels(
        previous: known,
        incoming: const <GamesAppBarModel>[],
        liveRoundIds: const <String>[],
        missingSnapshotCounts: missingCounts,
        missingSnapshotTolerance: 2,
      );
      known = secondMiss;
      expect(firstMiss.map((round) => round.id), contains('round-8'));
      expect(firstMiss.single.roundStatus, RoundStatus.live);
      expect(secondMiss.map((round) => round.id), contains('round-8'));

      final thirdMiss = mergePublishedRoundModels(
        previous: known,
        incoming: const <GamesAppBarModel>[],
        liveRoundIds: const <String>[],
        missingSnapshotCounts: missingCounts,
        missingSnapshotTolerance: 2,
      );
      expect(thirdMiss.map((round) => round.id), contains('round-8'));

      final fourthMiss = mergePublishedRoundModels(
        previous: thirdMiss,
        incoming: const <GamesAppBarModel>[],
        liveRoundIds: const <String>[],
        missingSnapshotCounts: missingCounts,
        missingSnapshotTolerance: 2,
      );
      expect(fourthMiss, isEmpty);
      expect(missingCounts, isEmpty);
    },
  );
}
