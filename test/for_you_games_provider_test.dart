import 'package:chessever2/providers/event_pin_refresh_provider.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/providers/for_you_games_logic.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
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
  final games = visibleGames ??
      (hasGames ? [_game('mock-game', tourId: tourId)] : const <GamesTourModel>[]);
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

Tour _tour({
  required String id,
  required List<DateTime> dates,
  int? avgElo = 2700,
}) {
  return Tour.fromJson({
    'id': id,
    'name': 'Tour $id',
    'slug': id,
    'info': {
      'format': 'Swiss',
      'tc': '90+30',
      'players': '',
      'location': 'Test City',
    },
    'created_at': DateTime(2026, 3, 25, 8).toIso8601String(),
    'url': 'https://example.com/$id',
    'tier': 1,
    'dates': dates.map((date) => date.toIso8601String()).toList(),
    'players': const <Map<String, dynamic>>[],
    'search': const <String>[],
    'group_broadcast_id': 'event-1',
    'avg_elo': avgElo,
  });
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

  group('currentSelectedTourIdForEventProvider', () {
    test(
      'does not react to selected broadcast changes for unrelated events',
      () {
        final detailTourIdProvider = StateProvider<String?>((ref) => 'tour-a');
        final container = ProviderContainer(
          overrides: [
            currentTournamentDetailSelectedTourIdProvider.overrideWith(
              (ref) => ref.watch(detailTourIdProvider),
            ),
          ],
        );
        addTearDown(container.dispose);

        final values = <String?>[];
        final subscription = container.listen<String?>(
          currentSelectedTourIdForEventProvider('event-y'),
          (previous, next) => values.add(next),
          fireImmediately: true,
        );
        addTearDown(subscription.close);

        expect(values, [null]);

        container
            .read(selectedBroadcastModelProvider.notifier)
            .state = _broadcast('event-x');

        expect(subscription.read(), isNull);
        expect(values, [null]);

        container.read(detailTourIdProvider.notifier).state = 'tour-b';

        expect(subscription.read(), isNull);
        expect(values, [null]);
      },
    );

    test('tracks tournament detail selection only for the active event', () {
      final detailTourIdProvider = StateProvider<String?>((ref) => 'tour-a');
      final container = ProviderContainer(
        overrides: [
          currentTournamentDetailSelectedTourIdProvider.overrideWith(
            (ref) => ref.watch(detailTourIdProvider),
          ),
        ],
      );
      addTearDown(container.dispose);

      final values = <String?>[];
      final subscription = container.listen<String?>(
        currentSelectedTourIdForEventProvider('event-x'),
        (previous, next) => values.add(next),
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      expect(values, [null]);

      container
          .read(selectedBroadcastModelProvider.notifier)
          .state = _broadcast('event-x');

      expect(subscription.read(), 'tour-a');
      expect(values, [null, 'tour-a']);

      container.read(detailTourIdProvider.notifier).state = 'tour-b';

      expect(subscription.read(), 'tour-b');
      expect(values, [null, 'tour-a', 'tour-b']);

      container
          .read(selectedBroadcastModelProvider.notifier)
          .state = _broadcast('event-y');

      expect(subscription.read(), isNull);
      expect(values, [null, 'tour-a', 'tour-b', null]);
    });
  });

  group('shouldLoadDeferredActivityTourId', () {
    test('skips activity lookup when saved selection is already valid', () {
      final now = DateTime(2026, 3, 25, 12);
      final tourA = _tour(
        id: 'tour-a',
        dates: [now.subtract(const Duration(days: 1)), now],
      );
      final tourB = _tour(
        id: 'tour-b',
        dates: [now.subtract(const Duration(days: 1)), now],
        avgElo: 2600,
      );

      final shouldLoad = shouldLoadDeferredActivityTourId(
        tourModels: [
          TourModel(tour: tourA, roundStatus: RoundStatus.ongoing),
          TourModel(tour: tourB, roundStatus: RoundStatus.ongoing),
        ],
        savedTourId: 'tour-b',
      );

      expect(shouldLoad, isFalse);
    });

    test(
      'skips activity lookup when a live tour already resolves selection',
      () {
        final now = DateTime(2026, 3, 25, 12);
        final liveTour = _tour(
          id: 'tour-live',
          dates: [now.subtract(const Duration(hours: 2)), now],
        );
        final otherTour = _tour(
          id: 'tour-other',
          dates: [now.subtract(const Duration(days: 1)), now],
          avgElo: null,
        );

        final shouldLoad = shouldLoadDeferredActivityTourId(
          tourModels: [
            TourModel(tour: liveTour, roundStatus: RoundStatus.live),
            TourModel(tour: otherTour, roundStatus: RoundStatus.ongoing),
          ],
        );

        expect(shouldLoad, isFalse);
      },
    );

    test(
      'requires activity lookup when earlier fallbacks cannot break the tie',
      () {
        final now = DateTime(2026, 3, 25, 12);
        final tourA = _tour(
          id: 'tour-a',
          dates: [now.subtract(const Duration(days: 3)), now],
          avgElo: null,
        );
        final tourB = _tour(
          id: 'tour-b',
          dates: [now.subtract(const Duration(days: 3)), now],
          avgElo: null,
        );

        final shouldLoad = shouldLoadDeferredActivityTourId(
          tourModels: [
            TourModel(tour: tourA, roundStatus: RoundStatus.ongoing),
            TourModel(tour: tourB, roundStatus: RoundStatus.ongoing),
          ],
        );

        expect(shouldLoad, isTrue);
      },
    );
  });

  test('mergePinnedIdsPreservingOrder keeps first-seen tour order', () {
    final merged = mergePinnedIdsPreservingOrder([
      ['game-a', 'game-b'],
      ['game-b', 'game-c'],
      ['game-a', 'game-d'],
    ]);

    expect(merged, ['game-a', 'game-b', 'game-c', 'game-d']);
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
      // watching forYouEventGamesWithAutoRefreshProvider directly.
      // An event whose snapshot resolves with no games should be hidden.
      final container = ProviderContainer(
        overrides: [
          forYouEventGamesWithAutoRefreshProvider.overrideWith((ref, eventId) {
            if (eventId == 'event-hidden') {
              return AsyncValue.data(_snapshot(eventId, hasGames: false));
            }
            return AsyncValue.data(_snapshot(eventId));
          }),
        ],
      );
      addTearDown(container.dispose);

      final hiddenSnapshot = container.read(
        forYouEventGamesWithAutoRefreshProvider('event-hidden'),
      );
      final visibleSnapshot = container.read(
        forYouEventGamesWithAutoRefreshProvider('event-visible'),
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
          forYouEventGamesWithAutoRefreshProvider.overrideWith((ref, eventId) {
            return const AsyncValue<ForYouEventGamesSnapshot>.loading();
          }),
        ],
      );
      addTearDown(container.dispose);

      final snapshot = container.read(
        forYouEventGamesWithAutoRefreshProvider('event-loading'),
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

  test(
    'forYouPinActionProvider writes manual pins against the provided tour id',
    () async {
      final storage = _FakeForYouPinStorage();
      final container = ProviderContainer(
        overrides: [
          forYouPinStorageProvider.overrideWithValue(storage),
          forYouEventGamesWithAutoRefreshProvider.overrideWith((ref, eventId) {
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
          forYouEventGamesWithAutoRefreshProvider.overrideWith((ref, eventId) {
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
          forYouEventGamesWithAutoRefreshProvider.overrideWith((ref, eventId) {
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
          forYouEventGamesWithAutoRefreshProvider.overrideWith((ref, eventId) {
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
