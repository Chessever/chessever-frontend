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
  Stream<List<String>> subscribeToLiveGroupBroadcastIds() =>
      const Stream<List<String>>.empty();

  @override
  Stream<List<String>> subscribeToLiveRoundIds() =>
      const Stream<List<String>>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGroupBroadcastRepository implements GroupBroadcastRepository {
  @override
  Future<List<GroupBroadcast>> getGroupBroadcastsByIdsOrNames(
    List<String> identifiers,
  ) async => <GroupBroadcast>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeTourRepository implements TourRepository {
  @override
  Future<Map<String, List<Tour>>> getToursByGroupBroadcastIds(
    List<String> groupBroadcastIds,
  ) async => <String, List<Tour>>{};

  @override
  Future<List<Tour>> getToursByIds(List<String> tourIds) async => <Tour>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRoundRepository implements RoundRepository {
  @override
  Future<List<Round>> getRoundsByIds(List<String> roundIds) async => <Round>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGameRepository implements GameRepository {
  @override
  Future<Map<String, DateTime>> getLatestLastMoveTimesByRoundIds(
    List<String> roundIds,
  ) async => <String, DateTime>{};

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
      expect(
        isExpectedLiveResolveError(TimeoutException('slow')),
        isTrue,
      );
    });

    test('treats genuinely unexpected errors as not expected', () {
      expect(isExpectedLiveResolveError(GenericApiException('boom')), isFalse);
      expect(isExpectedLiveResolveError(StateError('bad state')), isFalse);
    });
  });
}
