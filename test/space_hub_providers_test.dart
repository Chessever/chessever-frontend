import 'package:chessever2/providers/for_you_games_logic.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_hub_providers.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Games implements GameRepository {
  final topCalls = <List<String>>[];
  final fideCalls = <List<String>>[];

  @override
  Future<Map<String, List<Games>>> getForYouTopGamesByEventIds({
    required List<String> eventIds,
    int boardsPerEvent = 4,
  }) async {
    topCalls.add(eventIds);
    return const {};
  }

  @override
  Future<List<Games>> getGamesByMultipleFideIds({
    required List<String> fideIds,
    int limit = 50,
    int offset = 0,
  }) async {
    fideCalls.add(fideIds);
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Broadcasts implements GroupBroadcastRepository {
  final calls = <List<String>>[];

  @override
  Future<List<GroupBroadcast>> getGroupBroadcastsByIdsOrNames(
    List<String> identifiers,
  ) async {
    calls.add(identifiers);
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PlayerCard _player(String name, int fide) => PlayerCard(
  name: name,
  federation: 'NOR',
  title: 'GM',
  rating: 2800,
  countryCode: 'NO',
  team: null,
  fideId: fide,
);

GamesTourModel _game(
  String id, {
  GameStatus status = GameStatus.ongoing,
  GameSource source = GameSource.supabase,
  Duration ago = const Duration(minutes: 5),
  DateTime? now,
}) => GamesTourModel(
  gameId: id,
  source: source,
  whitePlayer: _player('Carlsen, Magnus', 1503014),
  blackPlayer: _player('Caruana, Fabiano', 2020009),
  whiteTimeDisplay: '1:00:00',
  blackTimeDisplay: '1:00:00',
  whiteClockCentiseconds: 360000,
  blackClockCentiseconds: 360000,
  gameStatus: status,
  roundId: 'r',
  tourId: 't',
  lastMoveTime: (now ?? DateTime(2026, 9, 25, 15)).subtract(ago),
);

ForYouEventGamesSnapshot _snapshot(String id, int games) =>
    ForYouEventGamesSnapshot(
      eventId: id,
      tourId: 't-$id',
      visibleGames: [for (var i = 0; i < games; i++) _game('$id-$i')],
      pinnedIds: const [],
    );

void main() {
  test('SpaceIds is one key for the same ids in any order', () {
    expect(SpaceIds(['b', 'a', 'a', ' ']), SpaceIds(['a', 'b']));
    expect(SpaceIds(['b', 'a']).hashCode, SpaceIds(['a', 'b']).hashCode);
    expect(SpaceIds(['a']), isNot(SpaceIds(['b'])));
    expect(SpaceIds(const []).isEmpty, isTrue);
  });

  test('an event pin names its group broadcast when it knows it', () {
    const pin = SpaceShortcut(
      id: 'x',
      kind: SpaceShortcutKind.event,
      targetId: 'tour-1',
      title: 'Sinquefield Cup',
      params: {'groupBroadcastId': 'gb-1'},
    );
    expect(spaceEventIdOf(pin), 'gb-1');
    expect(
      spaceEventIdOf(
        const SpaceShortcut(
          id: 'y',
          kind: SpaceShortcutKind.event,
          targetId: 'gb-2',
          title: 'Norway Chess',
        ),
      ),
      'gb-2',
    );
  });

  group('saved events', () {
    late _Games games;
    late _Broadcasts broadcasts;
    late ProviderContainer container;

    setUp(() {
      games = _Games();
      broadcasts = _Broadcasts();
      container = ProviderContainer(
        overrides: [
          gameRepositoryProvider.overrideWithValue(games),
          groupBroadcastRepositoryProvider.overrideWithValue(broadcasts),
        ],
      );
      addTearDown(container.dispose);
    });

    test('Today\'s boards first; one read for the rest, none when Today '
        'holds them all', () async {
      container.read(forYouTopGamesSnapshotCacheProvider.notifier).state = {
        'a': _snapshot('a', 4),
        'b': _snapshot('b', 4),
      };
      final some = await container.read(
        spaceLiveEventGamesProvider(SpaceIds(['a', 'c', 'd'])).future,
      );
      expect(games.topCalls, [
        ['c', 'd'],
      ]);
      // Trimmed to the two boards a saved event shows.
      expect(some.byEvent['a']!.visibleGames, hasLength(kSpaceEventBoards));
      expect(some.failed, isEmpty);

      await container.read(
        spaceLiveEventGamesProvider(SpaceIds(['a', 'b'])).future,
      );
      expect(games.topCalls, hasLength(1), reason: 'all cached, no read');
    });

    test('one broadcasts read for every saved event', () async {
      await container.read(
        spaceEventBroadcastsProvider(SpaceIds(['x', 'y', 'z'])).future,
      );
      expect(broadcasts.calls, [
        ['x', 'y', 'z'],
      ]);
      expect(
        container.read(spaceEventCardModelsProvider(SpaceIds(['z', 'y', 'x']))),
        isEmpty,
      );
      expect(broadcasts.calls, hasLength(1), reason: 'same key, same read');
    });

    test('one games read for every saved player', () async {
      await container.read(
        spacePlayersLiveGamesProvider(SpaceIds(['1', '2', '3'])).future,
      );
      expect(games.fideCalls, [
        ['1', '2', '3'],
      ]);
    });
  });

  test('a player is playing only in an unfinished broadcast game with a '
      'recent move, each game once', () {
    final now = DateTime(2026, 9, 25, 15);
    final live = spaceLivePlayerGames([
      _game('live', now: now),
      _game('live', now: now),
      _game('stale', ago: const Duration(hours: 4), now: now),
      _game('done', status: GameStatus.whiteWins, now: now),
      _game('archive', source: GameSource.gamebase, now: now),
    ], now: now);
    expect([for (final g in live) g.gameId], ['live']);
  });
}
