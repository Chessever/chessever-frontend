import 'dart:async';
import 'dart:io';

import 'package:chessever2/repository/api_utils/api_exceptions.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/repository/supabase/settings/settings.dart';
import 'package:chessever2/repository/supabase/settings/settings_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _SilentSettingsRepository implements SettingsRepository {
  @override
  Future<Settings?> getSettings() async => null;

  @override
  Stream<Settings?> subscribeToSettings() => const Stream<Settings?>.empty();

  @override
  Stream<List<String>> subscribeToLiveGroupBroadcastIds() =>
      const Stream<List<String>>.empty();

  @override
  Stream<List<String>> subscribeToLiveRoundIds() =>
      const Stream<List<String>>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StreamingSettingsRepository implements SettingsRepository {
  final StreamController<Settings?> _controller =
      StreamController<Settings?>.broadcast();

  Settings? currentSettings;

  @override
  Future<Settings?> getSettings() async => currentSettings;

  @override
  Stream<Settings?> subscribeToSettings() => _controller.stream;

  void add(Settings? settings) {
    currentSettings = settings;
    _controller.add(settings);
  }

  void addError(Object error) {
    _controller.addError(error, StackTrace.current);
  }

  Future<void> dispose() => _controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGroupBroadcastRepository implements GroupBroadcastRepository {
  _FakeGroupBroadcastRepository({this.broadcasts = const []});

  final List<GroupBroadcast> broadcasts;

  @override
  Future<List<GroupBroadcast>> getGroupBroadcastsByIdsOrNames(
    List<String> identifiers,
  ) async {
    return broadcasts
        .where(
          (broadcast) =>
              identifiers.contains(broadcast.id) ||
              identifiers.contains(broadcast.name),
        )
        .toList(growable: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeTourRepository implements TourRepository {
  _FakeTourRepository({this.tours = const []});

  final List<Tour> tours;

  @override
  Future<Map<String, List<Tour>>> getToursByGroupBroadcastIds(
    List<String> groupBroadcastIds,
  ) async {
    final result = <String, List<Tour>>{};
    for (final groupBroadcastId in groupBroadcastIds) {
      result[groupBroadcastId] = tours
          .where((tour) => tour.groupBroadcastId == groupBroadcastId)
          .toList(growable: false);
    }
    return result;
  }

  @override
  Future<List<Tour>> getToursByIds(List<String> tourIds) async {
    return tours
        .where((tour) => tourIds.contains(tour.id))
        .toList(growable: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRoundRepository implements RoundRepository {
  _FakeRoundRepository({this.rounds = const []});

  final List<Round> rounds;

  @override
  Future<List<Round>> getRoundsByIds(List<String> roundIds) async {
    return rounds
        .where((round) => roundIds.contains(round.id))
        .toList(growable: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGameRepository implements GameRepository {
  _FakeGameRepository({this.latestMoveTimesByRoundId = const {}});

  final Map<String, DateTime> latestMoveTimesByRoundId;

  @override
  Future<Map<String, DateTime>> getLatestLastMoveTimesByRoundIds(
    List<String> roundIds,
  ) async {
    return {
      for (final roundId in roundIds)
        if (latestMoveTimesByRoundId[roundId] != null)
          roundId: latestMoveTimesByRoundId[roundId]!,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

GroupBroadcast _broadcast({
  required String id,
  required String name,
  DateTime? start,
  DateTime? end,
}) {
  return GroupBroadcast(
    id: id,
    createdAt: DateTime(2026, 4, 9, 12),
    name: name,
    search: const <String>[],
    dateStart: start,
    dateEnd: end,
  );
}

Tour _tour({required String id, required String groupBroadcastId}) {
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
    'created_at': DateTime(2026, 4, 9, 10).toIso8601String(),
    'url': 'https://example.com/$id',
    'tier': 1,
    'dates': [DateTime(2026, 4, 9, 12).toIso8601String()],
    'players': const <Map<String, dynamic>>[],
    'search': const <String>[],
    'group_broadcast_id': groupBroadcastId,
    'avg_elo': 2700,
  });
}

Round _round({
  required String id,
  required String tourId,
  required DateTime startsAt,
}) {
  return Round(
    id: id,
    slug: id,
    tourId: tourId,
    tourSlug: tourId,
    name: 'Round $id',
    createdAt: startsAt.subtract(const Duration(hours: 1)),
    startsAt: startsAt,
    url: 'https://example.com/$id',
  );
}

Settings _settings({
  List<String> liveGroupBroadcastIds = const <String>[],
  List<String> liveRoundIds = const <String>[],
}) {
  return Settings(
    id: 1,
    createdAt: DateTime(2026, 4, 9, 10),
    liveGroupBroadcastIds: liveGroupBroadcastIds,
    liveTourIds: const <String>[],
    liveRoundIds: liveRoundIds,
  );
}

Future<void> _pumpUntil(
  bool Function() condition, {
  String Function()? reason,
}) async {
  for (var i = 0; i < 100; i += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail(reason?.call() ?? 'condition was not met');
}

void main() {
  group('liveGroupBroadcastIdsProvider', () {
    test(
      'emits a fallback immediately before settings snapshots arrive',
      () async {
        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              _SilentSettingsRepository(),
            ),
            groupBroadcastRepositoryProvider.overrideWithValue(
              _FakeGroupBroadcastRepository(),
            ),
            tourRepositoryProvider.overrideWithValue(_FakeTourRepository()),
            roundRepositoryProvider.overrideWithValue(_FakeRoundRepository()),
            gameRepositoryProvider.overrideWithValue(_FakeGameRepository()),
          ],
        );
        addTearDown(container.dispose);

        await expectLater(
          container
              .read(liveGroupBroadcastIdsProvider.future)
              .timeout(const Duration(milliseconds: 100)),
          completion(isEmpty),
        );
      },
    );

    test(
      'keeps the last live ids when Supabase realtime reports a channel error',
      () async {
        final now = DateTime.now();
        final broadcast = _broadcast(
          id: 'event-1',
          name: 'Event One',
          start: now.subtract(const Duration(days: 1)),
          end: now.add(const Duration(days: 1)),
        );
        final tour = _tour(id: 'tour-1', groupBroadcastId: broadcast.id);
        final round = _round(
          id: 'round-1',
          tourId: tour.id,
          startsAt: now.subtract(const Duration(minutes: 45)),
        );
        final settingsRepository = _StreamingSettingsRepository();
        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepository),
            groupBroadcastRepositoryProvider.overrideWithValue(
              _FakeGroupBroadcastRepository(broadcasts: [broadcast]),
            ),
            tourRepositoryProvider.overrideWithValue(
              _FakeTourRepository(tours: [tour]),
            ),
            roundRepositoryProvider.overrideWithValue(
              _FakeRoundRepository(rounds: [round]),
            ),
            gameRepositoryProvider.overrideWithValue(
              _FakeGameRepository(
                latestMoveTimesByRoundId: {
                  round.id: now.subtract(const Duration(minutes: 5)),
                },
              ),
            ),
          ],
        );
        final emittedIds = <List<String>>[];
        final subscription = container.listen<AsyncValue<List<String>>>(
          liveGroupBroadcastIdsProvider,
          (_, next) => next.whenData(emittedIds.add),
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        addTearDown(container.dispose);
        addTearDown(settingsRepository.dispose);

        await _pumpUntil(
          () => emittedIds.any((ids) => ids.isEmpty),
          reason: () => 'initial fallback was not emitted',
        );

        settingsRepository.add(
          _settings(
            liveGroupBroadcastIds: [broadcast.id],
            liveRoundIds: [round.id],
          ),
        );

        await _pumpUntil(
          () => emittedIds.any(
            (ids) => ids.length == 1 && ids.single == broadcast.id,
          ),
          reason: () => 'live event id was not emitted; emitted=$emittedIds',
        );

        settingsRepository.addError(
          Exception(
            'RealtimeSubscribeException(status: '
            'RealtimeSubscribeStatus.channelError, details: null)',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(container.read(liveGroupBroadcastIdsProvider).valueOrNull, [
          broadcast.id,
        ]);
        expect(emittedIds.last, [broadcast.id]);
      },
    );

    test('classifies Supabase realtime subscribe errors as recoverable', () {
      expect(
        isRecoverableRealtimeSettingsStreamError(
          Exception(
            'RealtimeSubscribeException(status: '
            'RealtimeSubscribeStatus.channelError, details: null)',
          ),
        ),
        isTrue,
      );
      expect(
        isRecoverableRealtimeSettingsStreamError(Exception('PostgREST failed')),
        isFalse,
      );
    });
  });

  group('computeStrictLiveGroupBroadcastIds', () {
    final now = DateTime(2026, 4, 9, 18);
    final broadcast = _broadcast(
      id: 'event-1',
      name: 'Event One',
      start: now.subtract(const Duration(days: 1)),
      end: now.add(const Duration(days: 1)),
    );
    final tour = _tour(id: 'tour-1', groupBroadcastId: broadcast.id);
    final round = _round(
      id: 'round-1',
      tourId: tour.id,
      startsAt: now.subtract(const Duration(minutes: 45)),
    );
    final toursByBroadcastId = <String, List<Tour>>{
      broadcast.id: [tour],
    };

    test('keeps event live when a live round has a recent move', () {
      final result = computeStrictLiveGroupBroadcastIds(
        broadcasts: [broadcast],
        configuredLiveEntries: [broadcast.id],
        toursByGroupBroadcastId: toursByBroadcastId,
        liveRounds: [round],
        latestMoveTimesByRoundId: {
          round.id: now.subtract(const Duration(minutes: 10)),
        },
        now: now,
      );

      expect(result, [broadcast.id]);
    });

    test('drops event when the latest move is older than two hours', () {
      final result = computeStrictLiveGroupBroadcastIds(
        broadcasts: [broadcast],
        configuredLiveEntries: [broadcast.id],
        toursByGroupBroadcastId: toursByBroadcastId,
        liveRounds: [round],
        latestMoveTimesByRoundId: {
          round.id: now.subtract(const Duration(hours: 2, minutes: 1)),
        },
        now: now,
      );

      expect(result, isEmpty);
    });

    test('uses the round start time when no move has arrived yet', () {
      final freshRound = _round(
        id: 'round-2',
        tourId: tour.id,
        startsAt: now.subtract(const Duration(minutes: 90)),
      );

      final staleRound = _round(
        id: 'round-3',
        tourId: tour.id,
        startsAt: now.subtract(const Duration(hours: 3)),
      );

      final freshResult = computeStrictLiveGroupBroadcastIds(
        broadcasts: [broadcast],
        configuredLiveEntries: [broadcast.id],
        toursByGroupBroadcastId: toursByBroadcastId,
        liveRounds: [freshRound],
        latestMoveTimesByRoundId: const <String, DateTime>{},
        now: now,
      );

      final staleResult = computeStrictLiveGroupBroadcastIds(
        broadcasts: [broadcast],
        configuredLiveEntries: [broadcast.id],
        toursByGroupBroadcastId: toursByBroadcastId,
        liveRounds: [staleRound],
        latestMoveTimesByRoundId: const <String, DateTime>{},
        now: now,
      );

      expect(freshResult, [broadcast.id]);
      expect(staleResult, isEmpty);
    });

    test('keeps event live even when the broadcast end date is stale', () {
      final staleScheduleBroadcast = _broadcast(
        id: 'event-2',
        name: 'Event Two',
        start: now.subtract(const Duration(days: 2)),
        end: now.subtract(const Duration(hours: 12)),
      );
      final staleScheduleTour = _tour(
        id: 'tour-2',
        groupBroadcastId: staleScheduleBroadcast.id,
      );
      final staleScheduleRound = _round(
        id: 'round-4',
        tourId: staleScheduleTour.id,
        startsAt: now.subtract(const Duration(hours: 1)),
      );

      final result = computeStrictLiveGroupBroadcastIds(
        broadcasts: [staleScheduleBroadcast],
        configuredLiveEntries: [staleScheduleBroadcast.id],
        toursByGroupBroadcastId: {
          staleScheduleBroadcast.id: [staleScheduleTour],
        },
        liveRounds: [staleScheduleRound],
        latestMoveTimesByRoundId: {
          staleScheduleRound.id: now.subtract(const Duration(minutes: 5)),
        },
        now: now,
      );

      expect(result, [staleScheduleBroadcast.id]);
    });

    test('supports configured live entries that match the event name', () {
      final result = computeStrictLiveGroupBroadcastIds(
        broadcasts: [broadcast],
        configuredLiveEntries: [broadcast.name],
        toursByGroupBroadcastId: toursByBroadcastId,
        liveRounds: [round],
        latestMoveTimesByRoundId: {
          round.id: now.subtract(const Duration(minutes: 5)),
        },
        now: now,
      );

      expect(result, [broadcast.id]);
    });
  });

  group('isExpectedLiveResolveError', () {
    test('treats the offline NetworkException as expected (no stack spam)', () {
      expect(
        isExpectedLiveResolveError(NetworkException('No internet connection')),
        isTrue,
      );
      expect(
        isExpectedLiveResolveError(NetworkException('Request timeout')),
        isTrue,
      );
    });

    test('treats raw SocketException and TimeoutException as expected', () {
      expect(
        isExpectedLiveResolveError(const SocketException('connect failed')),
        isTrue,
      );
      expect(isExpectedLiveResolveError(TimeoutException('slow')), isTrue);
    });

    test('treats genuinely unexpected errors as not expected', () {
      expect(isExpectedLiveResolveError(GenericApiException('boom')), isFalse);
      expect(isExpectedLiveResolveError(StateError('bad state')), isFalse);
    });
  });
}
