import 'dart:io';

import 'package:chessever2/providers/event_pin_refresh_provider.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/providers/for_you_games_logic.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _FakeForYouPinStorage implements ForYouPinStorage {
  final Map<String, List<String>> pinsByTourId;
  final Map<String, List<String>> unpinnedOverridesByTourId;

  _FakeForYouPinStorage({
    Map<String, List<String>>? initialPins,
    Map<String, List<String>>? initialUnpinnedOverrides,
  }) : pinsByTourId = {
         for (final entry
             in (initialPins ?? const <String, List<String>>{}).entries)
           entry.key: List<String>.from(entry.value),
       },
       unpinnedOverridesByTourId = {
         for (final entry
             in (initialUnpinnedOverrides ?? const <String, List<String>>{})
                 .entries)
           entry.key: List<String>.from(entry.value),
       };

  @override
  Future<void> addPinnedGameId(String tourId, String gameId) async {
    final pins = pinsByTourId.putIfAbsent(tourId, () => <String>[]);
    if (!pins.contains(gameId)) {
      pins.add(gameId);
    }
  }

  @override
  Future<List<String>> getPinnedGameIds(String tourId) async {
    return List<String>.from(pinsByTourId[tourId] ?? const <String>[]);
  }

  @override
  Future<List<String>> getUnpinnedGameIds(String tourId) async {
    return List<String>.from(
      unpinnedOverridesByTourId[tourId] ?? const <String>[],
    );
  }

  @override
  Future<void> removePinnedGameId(String tourId, String gameId) async {
    final pins = pinsByTourId[tourId];
    if (pins == null) {
      return;
    }
    pins.removeWhere((pinnedGameId) => pinnedGameId == gameId);
  }

  @override
  Future<void> addUnpinnedGameId(String tourId, String gameId) async {
    final overrides = unpinnedOverridesByTourId.putIfAbsent(
      tourId,
      () => <String>[],
    );
    if (!overrides.contains(gameId)) {
      overrides.add(gameId);
    }
  }

  @override
  Future<void> removeUnpinnedGameId(String tourId, String gameId) async {
    final overrides = unpinnedOverridesByTourId[tourId];
    if (overrides == null) {
      return;
    }
    overrides.removeWhere((pinnedGameId) => pinnedGameId == gameId);
  }
}

PlayerCard _player(String name) {
  return PlayerCard(
    name: name,
    federation: 'USA',
    title: 'GM',
    rating: 2700,
    countryCode: 'USA',
    team: null,
  );
}

GamesTourModel _game(String id, {String tourId = 'tour-1'}) {
  return GamesTourModel(
    gameId: id,
    whitePlayer: _player('White $id'),
    blackPlayer: _player('Black $id'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.ongoing,
    roundId: 'round-1',
    tourId: tourId,
  );
}

Games _rpcGame({
  required String id,
  required String tourId,
  required String roundId,
  required int avgElo,
  required int boardNr,
}) {
  return Games(
    id: id,
    roundId: roundId,
    roundSlug: roundId,
    tourId: tourId,
    tourSlug: tourId,
    players: [
      Player(
        name: 'White $id',
        title: 'GM',
        rating: 2700,
        fideId: 1,
        fed: 'USA',
        clock: 600,
        team: '',
      ),
      Player(
        name: 'Black $id',
        title: 'GM',
        rating: 2690,
        fideId: 2,
        fed: 'USA',
        clock: 600,
        team: '',
      ),
    ],
    lastMove: 'e2e4',
    status: 'ongoing',
    boardNr: boardNr,
    avgElo: avgElo,
  );
}

ForYouEventGamesSnapshot _snapshot(
  String eventId, {
  String tourId = 'tour-1',
  List<GamesTourModel>? visibleGames,
  List<String> pinnedIds = const <String>[],
  List<String> manualPinnedIds = const <String>[],
  List<String> autoPinnedIds = const <String>[],
  List<String> unpinnedOverrideIds = const <String>[],
  bool hasGames = true,
}) {
  final games =
      visibleGames ??
      (hasGames
          ? [_game('mock-game', tourId: tourId)]
          : const <GamesTourModel>[]);
  return ForYouEventGamesSnapshot(
    eventId: eventId,
    tourId: tourId,
    visibleGames: games,
    pinnedIds: pinnedIds,
    manualPinnedIds: manualPinnedIds,
    autoPinnedIds: autoPinnedIds,
    unpinnedOverrideIds: unpinnedOverrideIds,
  );
}

Round _round({
  required String id,
  required String tourId,
  required DateTime createdAt,
}) {
  return Round(
    id: id,
    slug: id,
    tourId: tourId,
    tourSlug: tourId,
    name: 'Round $id',
    createdAt: createdAt,
    startsAt: createdAt.add(const Duration(hours: 1)),
    url: 'https://example.com/$id',
  );
}

GroupBroadcast _broadcast(String id) {
  return GroupBroadcast(
    id: id,
    createdAt: DateTime(2026, 3, 25, 12),
    name: 'Broadcast $id',
    search: const <String>[],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final triggerPinRefreshProvider = Provider.family<void Function(), String?>((
    ref,
    eventId,
  ) {
    return () => bumpEventPinRefreshSignal(ref, eventId);
  });

  group('For You automatic freshness', () {
    test('fresh visibility refresh updates only top-game membership', () {
      final now = DateTime.utc(2026, 7, 10, 12);

      expect(
        resolveForYouVisibilityRefresh(
          lastFeedRefreshAt: now.subtract(const Duration(minutes: 2)),
          now: now,
          maxFeedAge: const Duration(minutes: 5),
        ),
        ForYouVisibilityRefresh.topGames,
      );
    });

    test('stale visibility refresh updates the full ordered feed', () {
      final now = DateTime.utc(2026, 7, 10, 12);

      expect(
        resolveForYouVisibilityRefresh(
          lastFeedRefreshAt: now.subtract(const Duration(minutes: 5)),
          now: now,
          maxFeedAge: const Duration(minutes: 5),
        ),
        ForYouVisibilityRefresh.fullFeed,
      );
    });

    test('For You does not attach RPC work to the periodic live resolver', () {
      final widgetSource =
          File(
            'lib/screens/group_event/widget/for_you_games_widget.dart',
          ).readAsStringSync();
      final resolverSource =
          File(
            'lib/screens/group_event/providers/live_group_broadcast_id_provider.dart',
          ).readAsStringSync();

      expect(
        widgetSource,
        isNot(contains('liveGroupBroadcastRefreshTickProvider')),
      );
      expect(
        resolverSource,
        isNot(contains('liveGroupBroadcastRefreshTickProvider')),
      );
    });

    test('For You previews have no per-event client hydration fallback', () {
      final providerSource =
          File('lib/providers/for_you_games_provider.dart').readAsStringSync();

      expect(providerSource, isNot(contains('eventGamesProvider')));
      expect(providerSource, isNot(contains('_loadForYouResolvedEventData')));
      expect(providerSource, isNot(contains('fetchAndSaveGames')));
      expect(providerSource, isNot(contains('getRoundsByTourId')));
      expect(providerSource, isNot(contains('getTourByGroupId')));
    });

    test('unchanged refreshed snapshots preserve cache identity', () {
      final current = <String, ForYouEventGamesSnapshot>{
        'event-1': _snapshot('event-1', visibleGames: [_game('game-1')]),
      };
      final incoming = <String, ForYouEventGamesSnapshot>{
        'event-1': _snapshot('event-1', visibleGames: [_game('game-1')]),
      };

      final merged = mergeForYouTopGameSnapshots(
        current: current,
        incoming: incoming,
        replace: false,
      );

      expect(identical(merged, current), isTrue);
    });

    test('refreshed snapshots replace only changed event entries', () {
      final event1 = _snapshot('event-1', visibleGames: [_game('game-1')]);
      final event2 = _snapshot('event-2', visibleGames: [_game('game-2')]);
      final current = <String, ForYouEventGamesSnapshot>{
        'event-1': event1,
        'event-2': event2,
      };

      final merged = mergeForYouTopGameSnapshots(
        current: current,
        incoming: {
          'event-1': _snapshot('event-1', visibleGames: [_game('game-1')]),
          'event-2': _snapshot('event-2', visibleGames: [_game('game-3')]),
        },
        replace: false,
      );

      expect(identical(merged['event-1'], event1), isTrue);
      expect(identical(merged['event-2'], event2), isFalse);
      expect(merged['event-2']!.visibleGames.single.gameId, 'game-3');
    });
  });

  group('mergeMissingFavoriteCurrentBroadcasts', () {
    test(
      'prepends favorite current broadcasts missing from the first page',
      () {
        final page = [_broadcast('event-page-a'), _broadcast('event-page-b')];
        final favoriteBroadcasts = [_broadcast('event-favorite')];

        final merged = mergeMissingFavoriteCurrentBroadcasts(
          pageBroadcasts: page,
          favoriteBroadcasts: favoriteBroadcasts,
          favoriteIds: const ['event-favorite'],
        );

        expect(merged.map((broadcast) => broadcast.id), [
          'event-favorite',
          'event-page-a',
          'event-page-b',
        ]);
      },
    );

    test('does not duplicate favorites already present on the page', () {
      final page = [_broadcast('event-favorite'), _broadcast('event-page-a')];
      final favoriteBroadcasts = [_broadcast('event-favorite')];

      final merged = mergeMissingFavoriteCurrentBroadcasts(
        pageBroadcasts: page,
        favoriteBroadcasts: favoriteBroadcasts,
        favoriteIds: const ['event-favorite'],
      );

      expect(identical(merged, page), isTrue);
    });

    test('keeps favorite order when multiple favorites are injected', () {
      final page = [_broadcast('event-page-a')];
      final favoriteBroadcasts = [
        _broadcast('event-favorite-a'),
        _broadcast('event-favorite-b'),
      ];

      final merged = mergeMissingFavoriteCurrentBroadcasts(
        pageBroadcasts: page,
        favoriteBroadcasts: favoriteBroadcasts,
        favoriteIds: const ['event-favorite-b', 'event-favorite-a'],
      );

      expect(merged.map((broadcast) => broadcast.id), [
        'event-favorite-b',
        'event-favorite-a',
        'event-page-a',
      ]);
    });
  });

  test('eventPinRefreshProvider only increments the matching event key', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(eventPinRefreshProvider('event-a')), 0);
    expect(container.read(eventPinRefreshProvider('event-b')), 0);

    container.read(triggerPinRefreshProvider('event-a'))();
    container.read(triggerPinRefreshProvider(''))();
    container.read(triggerPinRefreshProvider(null))();

    expect(container.read(eventPinRefreshProvider('event-a')), 1);
    expect(container.read(eventPinRefreshProvider('event-b')), 0);
  });

  test('mergeEffectivePins keeps legacy ordering when no overrides exist', () {
    final merged = mergeEffectivePins(
      manualPins: const ['game-a', 'game-b'],
      autoPins: const ['game-b', 'game-c'],
      unpinnedOverrides: const [],
    );

    expect(merged, ['game-a', 'game-b', 'game-c']);
  });

  test('areEquivalentForYouSnapshots matches identical rendered content', () {
    final first = _snapshot(
      'event-1',
      tourId: 'tour-1',
      visibleGames: [_game('game-1')],
      pinnedIds: const ['game-1'],
      manualPinnedIds: const ['game-1'],
    );
    final second = _snapshot(
      'event-1',
      tourId: 'tour-1',
      visibleGames: [_game('game-1')],
      pinnedIds: const ['game-1'],
      manualPinnedIds: const ['game-1'],
    );

    expect(areEquivalentForYouSnapshots(first, second), isTrue);
  });

  test('areEquivalentForYouSnapshots detects visible game changes', () {
    final first = _snapshot('event-1', visibleGames: [_game('game-1')]);
    final second = _snapshot(
      'event-1',
      visibleGames: [
        _game('game-1').copyWith(gameStatus: GameStatus.whiteWins),
      ],
    );

    expect(areEquivalentForYouSnapshots(first, second), isFalse);
  });

  test(
    'top-game snapshot backfills from older rounds of the selected RPC tour',
    () {
      final snapshot = buildForYouTopGamesSnapshot(
        eventId: 'biel-2026',
        maxGames: 4,
        games: [
          _rpcGame(
            id: 'masters-board-1',
            tourId: 'masters',
            roundId: 'masters-round',
            avgElo: 2604,
            boardNr: 1,
          ),
          _rpcGame(
            id: 'masters-board-1',
            tourId: 'masters',
            roundId: 'masters-round',
            avgElo: 2604,
            boardNr: 1,
          ),
          _rpcGame(
            id: 'challengers-board-1',
            tourId: 'challengers',
            roundId: 'challengers-round',
            avgElo: 2428,
            boardNr: 1,
          ),
          _rpcGame(
            id: 'open-board-1',
            tourId: 'open',
            roundId: 'open-round',
            avgElo: 2416,
            boardNr: 1,
          ),
          _rpcGame(
            id: 'masters-board-2',
            tourId: 'masters',
            roundId: 'masters-round',
            avgElo: 2604,
            boardNr: 2,
          ),
          _rpcGame(
            id: 'masters-previous-board-1',
            tourId: 'masters',
            roundId: 'masters-previous-round',
            avgElo: 2604,
            boardNr: 1,
          ),
          _rpcGame(
            id: 'masters-previous-board-2',
            tourId: 'masters',
            roundId: 'masters-previous-round',
            avgElo: 2604,
            boardNr: 2,
          ),
        ],
      );

      expect(snapshot.tourId, 'masters');
      expect(snapshot.visibleGames.map((game) => game.gameId), [
        'masters-board-1',
        'masters-board-2',
        'masters-previous-board-1',
        'masters-previous-board-2',
      ]);
      expect(
        snapshot.visibleGames.every((game) => game.tourId == 'masters'),
        isTrue,
      );
    },
  );

  group('resolvePinToggleMode', () {
    test('keeps legacy manual-only unpin behavior', () {
      expect(
        resolvePinToggleMode(
          isManualPinned: true,
          isAutoPinned: false,
          isOverridden: false,
        ),
        PinToggleMode.unpinManualOnly,
      );
    });

    test('uses persistent override for auto-pinned games', () {
      expect(
        resolvePinToggleMode(
          isManualPinned: false,
          isAutoPinned: true,
          isOverridden: false,
        ),
        PinToggleMode.unpinWithOverride,
      );
    });

    test('repin clears override and restores manual pin', () {
      expect(
        resolvePinToggleMode(
          isManualPinned: false,
          isAutoPinned: false,
          isOverridden: true,
        ),
        PinToggleMode.repin,
      );
    });
  });

  test(
    'groupRoundsByTourIdPreservingOrder sorts each tour by createdAt and keeps empty tours',
    () {
      final now = DateTime(2026, 3, 25, 12);

      final grouped = groupRoundsByTourIdPreservingOrder(
        rounds: [
          _round(
            id: 'tour-b-late',
            tourId: 'tour-b',
            createdAt: now.add(const Duration(hours: 1)),
          ),
          _round(
            id: 'tour-a-late',
            tourId: 'tour-a',
            createdAt: now.add(const Duration(hours: 2)),
          ),
          _round(id: 'tour-a-early', tourId: 'tour-a', createdAt: now),
          _round(
            id: 'tour-b-early',
            tourId: 'tour-b',
            createdAt: now.subtract(const Duration(hours: 1)),
          ),
        ],
        tourIds: const ['tour-a', 'tour-b', 'tour-c'],
      );

      expect(grouped['tour-a']!.map((round) => round.id), [
        'tour-a-early',
        'tour-a-late',
      ]);
      expect(grouped['tour-b']!.map((round) => round.id), [
        'tour-b-early',
        'tour-b-late',
      ]);
      expect(grouped['tour-c'], isEmpty);
    },
  );

  test(
    'section visibility is driven by snapshot: empty snapshot hides section',
    () async {
      // With the new architecture, visibility is determined by each section
      // watching forYouEventSnapshotProvider directly.
      // An event whose snapshot resolves with no games should be hidden.
      final container = ProviderContainer(
        overrides: [
          forYouEventSnapshotProvider.overrideWith((ref, eventId) {
            if (eventId == 'event-hidden') {
              return AsyncValue.data(_snapshot(eventId, hasGames: false));
            }
            return AsyncValue.data(_snapshot(eventId));
          }),
        ],
      );
      addTearDown(container.dispose);

      final hiddenSnapshot = container.read(
        forYouEventSnapshotProvider('event-hidden'),
      );
      final visibleSnapshot = container.read(
        forYouEventSnapshotProvider('event-visible'),
      );

      expect(hiddenSnapshot.valueOrNull?.hasGames, false);
      expect(visibleSnapshot.valueOrNull?.hasGames, true);
    },
  );

  test(
    'section stays in loading state when snapshot has not resolved yet',
    () async {
      // Before the snapshot resolves, sections should remain visible
      // (loading state) so shimmer placeholders are shown.
      final container = ProviderContainer(
        overrides: [
          forYouEventSnapshotProvider.overrideWith((ref, eventId) {
            return const AsyncValue<ForYouEventGamesSnapshot>.loading();
          }),
        ],
      );
      addTearDown(container.dispose);

      final snapshot = container.read(
        forYouEventSnapshotProvider('event-loading'),
      );

      expect(snapshot.isLoading, true);
      // Loading sections should NOT be hidden — they show shimmer
      final shouldHide = snapshot.maybeWhen(
        data: (s) => !s.hasGames,
        orElse: () => false,
      );
      expect(shouldHide, false);
    },
  );

  test('live-aware For You snapshot renders cached RPC boards directly', () {
    final cachedSnapshot = _snapshot(
      'event-1',
      visibleGames: [_game('rpc-board')],
    );
    final container = ProviderContainer(
      overrides: [
        forYouTopGamesSnapshotCacheProvider.overrideWith(
          (ref) => {'event-1': cachedSnapshot},
        ),
        shouldStreamProvider.overrideWith((ref) => false),
      ],
    );
    addTearDown(container.dispose);

    final snapshot = container.read(
      forYouEventGamesWithAutoRefreshProvider('event-1'),
    );

    expect(snapshot.valueOrNull?.visibleGames.single.gameId, 'rpc-board');
  });

  test(
    'forYouPinActionProvider writes manual pins against the provided tour id',
    () async {
      final storage = _FakeForYouPinStorage();
      final container = ProviderContainer(
        overrides: [
          forYouPinStorageProvider.overrideWithValue(storage),
          forYouEventSnapshotProvider.overrideWith((ref, eventId) {
            return AsyncValue.data(_snapshot(eventId));
          }),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(forYouPinActionProvider)
          .togglePin(eventId: 'event-1', gameId: 'game-1', tourId: 'tour-b');

      expect(storage.pinsByTourId['tour-b'], ['game-1']);
      expect(storage.pinsByTourId['tour-a'], isNull);
      expect(storage.unpinnedOverridesByTourId['tour-b'], isNull);
    },
  );

  test(
    'forYouPinActionProvider removes existing manual pins from the same tour',
    () async {
      final storage = _FakeForYouPinStorage(
        initialPins: {
          'tour-b': ['game-1', 'game-2'],
        },
      );
      final container = ProviderContainer(
        overrides: [
          forYouPinStorageProvider.overrideWithValue(storage),
          forYouEventSnapshotProvider.overrideWith((ref, eventId) {
            return AsyncValue.data(
              _snapshot(
                eventId,
                manualPinnedIds: const ['game-1', 'game-2'],
                pinnedIds: const ['game-1', 'game-2'],
              ),
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(forYouPinActionProvider)
          .togglePin(eventId: 'event-1', gameId: 'game-1', tourId: 'tour-b');

      expect(storage.pinsByTourId['tour-b'], ['game-2']);
      expect(storage.unpinnedOverridesByTourId['tour-b'], isNull);
    },
  );

  test(
    'forYouPinActionProvider stores persistent unpin overrides for auto-pinned games',
    () async {
      final storage = _FakeForYouPinStorage();
      final container = ProviderContainer(
        overrides: [
          forYouPinStorageProvider.overrideWithValue(storage),
          forYouEventSnapshotProvider.overrideWith((ref, eventId) {
            return AsyncValue.data(
              _snapshot(
                eventId,
                autoPinnedIds: const ['game-1'],
                pinnedIds: const ['game-1'],
              ),
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(forYouPinActionProvider)
          .togglePin(eventId: 'event-1', gameId: 'game-1', tourId: 'tour-b');

      expect(storage.pinsByTourId['tour-b'], isNull);
      expect(storage.unpinnedOverridesByTourId['tour-b'], ['game-1']);
    },
  );

  test(
    'forYouPinActionProvider re-pins games by clearing the override first',
    () async {
      final storage = _FakeForYouPinStorage(
        initialUnpinnedOverrides: {
          'tour-b': ['game-1'],
        },
      );
      final container = ProviderContainer(
        overrides: [
          forYouPinStorageProvider.overrideWithValue(storage),
          forYouEventSnapshotProvider.overrideWith((ref, eventId) {
            return AsyncValue.data(
              _snapshot(eventId, unpinnedOverrideIds: const ['game-1']),
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(forYouPinActionProvider)
          .togglePin(eventId: 'event-1', gameId: 'game-1', tourId: 'tour-b');

      expect(storage.pinsByTourId['tour-b'], ['game-1']);
      expect(storage.unpinnedOverridesByTourId['tour-b'], isEmpty);
    },
  );
}
