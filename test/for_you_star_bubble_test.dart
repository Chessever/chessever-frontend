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
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _ControllableFavoriteEventsNotifier extends FavoriteEventsNotifier {
  List<FavoriteEvent> _events = const <FavoriteEvent>[];

  @override
  Future<List<FavoriteEvent>> build() async => _events;

  void replaceFavorites(List<FavoriteEvent> events) {
    _events = List<FavoriteEvent>.unmodifiable(events);
    state = AsyncValue.data(_events);
  }
}

class _SeedableFavoriteEventsNotifier extends FavoriteEventsNotifier {
  _SeedableFavoriteEventsNotifier(this._events);

  List<FavoriteEvent> _events;

  @override
  Future<List<FavoriteEvent>> build() async => _events;

  void replaceFavorites(List<FavoriteEvent> events) {
    _events = List<FavoriteEvent>.unmodifiable(events);
    state = AsyncValue.data(_events);
  }
}

class _EmptyFavoritePlayersNotifier extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => const <FavoritePlayer>[];
}

class _FixedBroadcastRepository implements GroupBroadcastRepository {
  _FixedBroadcastRepository(this.broadcasts);

  final List<GroupBroadcast> broadcasts;

  @override
  Future<List<GroupBroadcast>> getForYouGroupBroadcasts({
    int limit = 20,
    int offset = 0,
    List<String>? timeControlFilters,
    int? minElo,
    int? maxElo,
    Set<String>? statusFilters,
  }) async {
    if (offset > 0) return const <GroupBroadcast>[];
    return broadcasts;
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

FavoriteEvent _favorite({
  required String eventId,
  required String eventName,
}) {
  final now = DateTime.now();
  return FavoriteEvent(
    id: 'fav-$eventId',
    userId: 'user-1',
    eventId: eventId,
    eventName: eventName,
    metadata: const <String, dynamic>{},
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for For You state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'For You reorders visible events when a mid-list event is starred',
    () async {
      final favoritesNotifier = _ControllableFavoriteEventsNotifier();
      final broadcasts = _FixedBroadcastRepository([
        _broadcast(id: 'regular-a', name: 'Regular A', maxAvgElo: 2900),
        _broadcast(id: 'regular-b', name: 'Regular B', maxAvgElo: 2800),
        _broadcast(id: 'to-star', name: 'To Star', maxAvgElo: 2400),
      ]);

      final container = ProviderContainer(
        overrides: [
          groupBroadcastRepositoryProvider.overrideWithValue(broadcasts),
          gameRepositoryProvider.overrideWithValue(_EmptyGameRepository()),
          favoriteEventsProvider.overrideWith(() => favoritesNotifier),
          favoritePlayersProviderNew.overrideWith(
            _EmptyFavoritePlayersNotifier.new,
          ),
          liveGroupBroadcastIdsProvider.overrideWith(
            (ref) => Stream<List<String>>.value(const <String>[]),
          ),
          liveRoundsIdProvider.overrideWith(
            (ref) => const Stream<List<String>>.empty(),
          ),
          liveTourIdProvider.overrideWith(
            (ref) => const Stream<List<String>>.empty(),
          ),
          forYouSurfaceVisibleProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen<ForYouState>(
        forYouEventsProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await _waitFor(
        () =>
            !container.read(forYouEventsProvider).isLoading &&
            container.read(forYouEventsProvider).events.length == 3,
      );

      expect(
        container.read(forYouEventsProvider).events.map((e) => e.id).toList(),
        ['regular-a', 'regular-b', 'to-star'],
      );

      favoritesNotifier.replaceFavorites([
        _favorite(eventId: 'to-star', eventName: 'To Star'),
      ]);

      await _waitFor(
        () =>
            container.read(forYouEventsProvider).events.first.id == 'to-star',
      );

      expect(
        container.read(forYouEventsProvider).events.map((e) => e.id).toList(),
        ['to-star', 'regular-a', 'regular-b'],
      );
    },
  );

  test(
    'For You unstar demotes a previously starred event without refresh',
    () async {
      final favoritesNotifier = _SeedableFavoriteEventsNotifier([
        _favorite(eventId: 'to-unstar', eventName: 'To Unstar'),
      ]);

      final broadcasts = _FixedBroadcastRepository([
        _broadcast(id: 'regular-a', name: 'Regular A', maxAvgElo: 2900),
        _broadcast(id: 'to-unstar', name: 'To Unstar', maxAvgElo: 2400),
        _broadcast(id: 'regular-b', name: 'Regular B', maxAvgElo: 2800),
      ]);

      final container = ProviderContainer(
        overrides: [
          groupBroadcastRepositoryProvider.overrideWithValue(broadcasts),
          gameRepositoryProvider.overrideWithValue(_EmptyGameRepository()),
          favoriteEventsProvider.overrideWith(() => favoritesNotifier),
          favoritePlayersProviderNew.overrideWith(
            _EmptyFavoritePlayersNotifier.new,
          ),
          liveGroupBroadcastIdsProvider.overrideWith(
            (ref) => Stream<List<String>>.value(const <String>[]),
          ),
          liveRoundsIdProvider.overrideWith(
            (ref) => const Stream<List<String>>.empty(),
          ),
          liveTourIdProvider.overrideWith(
            (ref) => const Stream<List<String>>.empty(),
          ),
          forYouSurfaceVisibleProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen<ForYouState>(
        forYouEventsProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await _waitFor(
        () =>
            !container.read(forYouEventsProvider).isLoading &&
            container.read(forYouEventsProvider).events.length == 3,
      );

      expect(
        container.read(forYouEventsProvider).events.map((e) => e.id).toList(),
        ['to-unstar', 'regular-a', 'regular-b'],
      );

      favoritesNotifier.replaceFavorites(const <FavoriteEvent>[]);

      await _waitFor(
        () =>
            container.read(forYouEventsProvider).events.first.id ==
            'regular-a',
      );

      expect(
        container.read(forYouEventsProvider).events.map((e) => e.id).toList(),
        ['regular-a', 'regular-b', 'to-unstar'],
      );
    },
  );

  test(
    'For You does not re-sort when favorite metadata refreshes with same ids',
    () async {
      final favoritesNotifier = _SeedableFavoriteEventsNotifier([
        _favorite(eventId: 'starred', eventName: 'Starred'),
      ]);
      final broadcasts = _FixedBroadcastRepository([
        _broadcast(id: 'starred', name: 'Starred', maxAvgElo: 2400),
        _broadcast(id: 'regular-a', name: 'Regular A', maxAvgElo: 2900),
      ]);

      final container = ProviderContainer(
        overrides: [
          groupBroadcastRepositoryProvider.overrideWithValue(broadcasts),
          gameRepositoryProvider.overrideWithValue(_EmptyGameRepository()),
          favoriteEventsProvider.overrideWith(() => favoritesNotifier),
          favoritePlayersProviderNew.overrideWith(
            _EmptyFavoritePlayersNotifier.new,
          ),
          liveGroupBroadcastIdsProvider.overrideWith(
            (ref) => Stream<List<String>>.value(const <String>[]),
          ),
          liveRoundsIdProvider.overrideWith(
            (ref) => const Stream<List<String>>.empty(),
          ),
          liveTourIdProvider.overrideWith(
            (ref) => const Stream<List<String>>.empty(),
          ),
          forYouSurfaceVisibleProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen<ForYouState>(
        forYouEventsProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await _waitFor(
        () =>
            !container.read(forYouEventsProvider).isLoading &&
            container.read(forYouEventsProvider).events.length == 2,
      );

      final firstInstance = container.read(forYouEventsProvider).events;
      expect(firstInstance.map((e) => e.id).toList(), [
        'starred',
        'regular-a',
      ]);

      // Same ids, new FavoriteEvent instances (metadata/timestamp refresh).
      favoritesNotifier.replaceFavorites([
        FavoriteEvent(
          id: 'fav-starred-2',
          userId: 'user-1',
          eventId: 'starred',
          eventName: 'Starred',
          metadata: const {'touched': true},
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ]);

      // Allow any microtasks from the listener to run.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final after = container.read(forYouEventsProvider).events;
      expect(after.map((e) => e.id).toList(), ['starred', 'regular-a']);
      // No state rewrite when order is unchanged.
      expect(identical(after, firstInstance), isTrue);
    },
  );
}
