import 'dart:async';

import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/repository/supabase/settings/settings_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const liveIndicatorStaleAfter = Duration(hours: 2);
const _liveIndicatorRefreshInterval = Duration(minutes: 1);

final configuredLiveGroupBroadcastIdsProvider =
    AutoDisposeStreamProvider<List<String>>(
      (ref) =>
          ref
              .read(settingsRepositoryProvider)
              .subscribeToLiveGroupBroadcastIds(),
    );

final _strictLiveGroupBroadcastResolverProvider =
    AutoDisposeProvider<_StrictLiveGroupBroadcastResolver>(
      (ref) => _StrictLiveGroupBroadcastResolver(
        groupBroadcastRepository: ref.read(groupBroadcastRepositoryProvider),
        tourRepository: ref.read(tourRepositoryProvider),
        roundRepository: ref.read(roundRepositoryProvider),
        gameRepository: ref.read(gameRepositoryProvider),
      ),
    );

final liveGroupBroadcastIdsProvider = AutoDisposeStreamProvider<List<String>>((
  ref,
) {
  final resolver = ref.read(_strictLiveGroupBroadcastResolverProvider);
  final settingsRepository = ref.read(settingsRepositoryProvider);
  final controller = StreamController<List<String>>();
  final configuredLiveEntriesStream =
      settingsRepository.subscribeToLiveGroupBroadcastIds();
  final liveRoundIdsStream = settingsRepository.subscribeToLiveRoundIds();
  var configuredLiveEntries = const <String>[];
  var liveRoundIds = const <String>[];
  var hasConfiguredSnapshot = false;
  var hasLiveRoundsSnapshot = false;
  var resolveRequestId = 0;
  List<String>? lastResolvedIds;

  Future<List<String>> resolve({
    required List<String> configuredLiveEntries,
    required List<String> liveRoundIds,
  }) async {
    try {
      return await resolver.resolve(
        configuredLiveEntries: configuredLiveEntries,
        liveRoundIds: liveRoundIds,
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[StrictLiveEvents] Failed to resolve live event IDs: $error\n$stackTrace',
      );
      return const <String>[];
    }
  }

  Future<void> emitResolvedIds() async {
    if (!hasConfiguredSnapshot || !hasLiveRoundsSnapshot) {
      return;
    }

    final currentRequestId = ++resolveRequestId;
    final resolvedIds = await resolve(
      configuredLiveEntries: List<String>.of(configuredLiveEntries),
      liveRoundIds: List<String>.of(liveRoundIds),
    );

    if (controller.isClosed || currentRequestId != resolveRequestId) {
      return;
    }

    if (lastResolvedIds != null && listEquals(lastResolvedIds, resolvedIds)) {
      return;
    }

    lastResolvedIds = resolvedIds;
    controller.add(resolvedIds);
  }

  final configuredSubscription = configuredLiveEntriesStream.listen(
    (nextConfiguredLiveEntries) {
      configuredLiveEntries = List<String>.unmodifiable(
        nextConfiguredLiveEntries,
      );
      hasConfiguredSnapshot = true;
      unawaited(emitResolvedIds());
    },
    onError: (Object error, StackTrace stackTrace) {
      debugPrint(
        '[StrictLiveEvents] Configured live IDs stream failed: $error\n$stackTrace',
      );
      hasConfiguredSnapshot = true;
      configuredLiveEntries = const <String>[];
      unawaited(emitResolvedIds());
    },
  );

  final liveRoundsSubscription = liveRoundIdsStream.listen(
    (nextLiveRoundIds) {
      liveRoundIds = List<String>.unmodifiable(nextLiveRoundIds);
      hasLiveRoundsSnapshot = true;
      unawaited(emitResolvedIds());
    },
    onError: (Object error, StackTrace stackTrace) {
      debugPrint(
        '[StrictLiveEvents] Live round IDs stream failed: $error\n$stackTrace',
      );
      hasLiveRoundsSnapshot = true;
      liveRoundIds = const <String>[];
      unawaited(emitResolvedIds());
    },
  );

  final refreshTimer = Timer.periodic(_liveIndicatorRefreshInterval, (_) {
    unawaited(emitResolvedIds());
  });

  ref.onDispose(() {
    refreshTimer.cancel();
    unawaited(configuredSubscription.cancel());
    unawaited(liveRoundsSubscription.cancel());
    unawaited(controller.close());
  });

  return controller.stream;
});

class _StrictLiveGroupBroadcastResolver {
  const _StrictLiveGroupBroadcastResolver({
    required this.groupBroadcastRepository,
    required this.tourRepository,
    required this.roundRepository,
    required this.gameRepository,
  });

  final GroupBroadcastRepository groupBroadcastRepository;
  final TourRepository tourRepository;
  final RoundRepository roundRepository;
  final GameRepository gameRepository;

  Future<List<String>> resolve({
    required List<String> configuredLiveEntries,
    required List<String> liveRoundIds,
  }) async {
    if (configuredLiveEntries.isEmpty || liveRoundIds.isEmpty) {
      return const <String>[];
    }

    final configuredBroadcasts = await groupBroadcastRepository
        .getGroupBroadcastsByIdsOrNames(configuredLiveEntries);
    if (configuredBroadcasts.isEmpty) {
      return const <String>[];
    }

    final toursByGroupBroadcastId = await tourRepository
        .getToursByGroupBroadcastIds(
          configuredBroadcasts
              .map((broadcast) => broadcast.id)
              .toList(growable: false),
        );
    if (toursByGroupBroadcastId.isEmpty) {
      return const <String>[];
    }

    final liveRounds = await roundRepository.getRoundsByIds(liveRoundIds);
    if (liveRounds.isEmpty) {
      return const <String>[];
    }

    final latestMoveTimesByRoundId = await gameRepository
        .getLatestLastMoveTimesByRoundIds(
          liveRounds.map((round) => round.id).toList(growable: false),
        );

    return computeStrictLiveGroupBroadcastIds(
      broadcasts: configuredBroadcasts,
      configuredLiveEntries: configuredLiveEntries,
      toursByGroupBroadcastId: toursByGroupBroadcastId,
      liveRounds: liveRounds,
      latestMoveTimesByRoundId: latestMoveTimesByRoundId,
    );
  }
}

@visibleForTesting
bool matchesConfiguredLiveGroup(
  GroupBroadcast broadcast,
  Iterable<String> configuredLiveEntries,
) {
  return configuredLiveEntries.contains(broadcast.id) ||
      configuredLiveEntries.contains(broadcast.name);
}

@visibleForTesting
bool isFreshLiveRoundActivity({
  required DateTime? activityAt,
  required DateTime now,
  Duration staleAfter = liveIndicatorStaleAfter,
}) {
  if (activityAt == null) {
    return false;
  }

  return !now.isAfter(activityAt.add(staleAfter));
}

@visibleForTesting
List<String> computeStrictLiveGroupBroadcastIds({
  required List<GroupBroadcast> broadcasts,
  required Iterable<String> configuredLiveEntries,
  required Map<String, List<Tour>> toursByGroupBroadcastId,
  required List<Round> liveRounds,
  required Map<String, DateTime> latestMoveTimesByRoundId,
  DateTime? now,
  Duration staleAfter = liveIndicatorStaleAfter,
}) {
  if (broadcasts.isEmpty || liveRounds.isEmpty) {
    return const <String>[];
  }

  final effectiveNow = now ?? DateTime.now();
  final tourIdToGroupBroadcastId = <String, String>{};
  for (final entry in toursByGroupBroadcastId.entries) {
    for (final tour in entry.value) {
      tourIdToGroupBroadcastId[tour.id] = entry.key;
    }
  }

  final liveRoundsByGroupBroadcastId = <String, List<Round>>{};
  for (final round in liveRounds) {
    final groupBroadcastId = tourIdToGroupBroadcastId[round.tourId];
    if (groupBroadcastId == null) {
      continue;
    }
    liveRoundsByGroupBroadcastId
        .putIfAbsent(groupBroadcastId, () => <Round>[])
        .add(round);
  }

  final strictLiveIds = <String>[];
  for (final broadcast in broadcasts) {
    if (!matchesConfiguredLiveGroup(broadcast, configuredLiveEntries)) {
      continue;
    }

    final withinStart =
        broadcast.dateStart == null ||
        !effectiveNow.isBefore(broadcast.dateStart!);
    final withinEnd =
        broadcast.dateEnd == null || !effectiveNow.isAfter(broadcast.dateEnd!);
    if (!withinStart || !withinEnd) {
      continue;
    }

    final rounds = liveRoundsByGroupBroadcastId[broadcast.id];
    if (rounds == null || rounds.isEmpty) {
      continue;
    }

    final hasFreshActivity = rounds.any((round) {
      final activityAt = latestMoveTimesByRoundId[round.id] ?? round.startsAt;
      return isFreshLiveRoundActivity(
        activityAt: activityAt,
        now: effectiveNow,
        staleAfter: staleAfter,
      );
    });

    if (hasFreshActivity) {
      strictLiveIds.add(broadcast.id);
    }
  }

  return List<String>.unmodifiable(strictLiveIds);
}
