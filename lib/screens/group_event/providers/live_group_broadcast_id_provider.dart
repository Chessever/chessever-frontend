import 'dart:async';
import 'dart:io';

import 'package:chessever2/repository/api_utils/api_exceptions.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/repository/supabase/settings/settings.dart';
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
  final settingsStream = settingsRepository.subscribeToSettings();
  var configuredLiveEntries = const <String>[];
  var liveRoundIds = const <String>[];
  var hasSettingsSnapshot = false;
  var refreshedAfterRealtimeInterruption = false;
  var resolveRequestId = 0;
  var settingsSnapshotVersion = 0;
  List<String>? lastResolvedIds;

  void emit(List<String> nextIds) {
    if (controller.isClosed) {
      return;
    }

    final stableIds = List<String>.unmodifiable(nextIds);
    if (lastResolvedIds != null && listEquals(lastResolvedIds, stableIds)) {
      return;
    }

    lastResolvedIds = stableIds;
    controller.add(stableIds);
  }

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
      _logStrictLiveResolveIssue('resolve live event IDs', error, stackTrace);
      return const <String>[];
    }
  }

  Future<void> emitResolvedIds() async {
    if (!hasSettingsSnapshot) {
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

    emit(resolvedIds);
  }

  void applySettingsSnapshot(Settings? settings) {
    settingsSnapshotVersion += 1;
    configuredLiveEntries = List<String>.unmodifiable(
      settings?.liveGroupBroadcastIds ?? const <String>[],
    );
    liveRoundIds = List<String>.unmodifiable(
      settings?.liveRoundIds ?? const <String>[],
    );
    hasSettingsSnapshot = true;
    refreshedAfterRealtimeInterruption = false;
    unawaited(emitResolvedIds());
  }

  Future<void> refreshSettingsSnapshot(String reason) async {
    final requestSnapshotVersion = settingsSnapshotVersion;
    try {
      final settings = await settingsRepository.getSettings();
      if (controller.isClosed ||
          requestSnapshotVersion != settingsSnapshotVersion) {
        return;
      }
      applySettingsSnapshot(settings);
    } catch (error, stackTrace) {
      if (_isRecoverableRealtimeSettingsStreamError(error)) {
        debugPrint(
          '[StrictLiveEvents] Settings snapshot refresh skipped after $reason; keeping cached live IDs: $error',
        );
      } else {
        _logStrictLiveResolveIssue(
          'settings snapshot refresh after $reason',
          error,
          stackTrace,
        );
      }

      if (!hasSettingsSnapshot) {
        hasSettingsSnapshot = true;
        unawaited(emitResolvedIds());
      }
    }
  }

  // Unblock first-load callers immediately; strict IDs will stream in later.
  emit(const <String>[]);

  unawaited(refreshSettingsSnapshot('startup'));

  final settingsSubscription = settingsStream.listen(
    applySettingsSnapshot,
    onError: (Object error, StackTrace stackTrace) {
      if (_isRecoverableRealtimeSettingsStreamError(error)) {
        if (!refreshedAfterRealtimeInterruption) {
          refreshedAfterRealtimeInterruption = true;
          unawaited(refreshSettingsSnapshot('realtime interruption'));
        }
        return;
      }

      _logStrictLiveResolveIssue('settings stream', error, stackTrace);
      unawaited(refreshSettingsSnapshot('stream error'));
    },
  );

  final refreshTimer = Timer.periodic(_liveIndicatorRefreshInterval, (_) {
    unawaited(emitResolvedIds());
  });

  ref.onDispose(() {
    refreshTimer.cancel();
    unawaited(settingsSubscription.cancel());
    unawaited(controller.close());
  });

  return controller.stream;
});

@visibleForTesting
bool isRecoverableRealtimeSettingsStreamError(Object error) =>
    _isRecoverableRealtimeSettingsStreamError(error);

bool _isRecoverableRealtimeSettingsStreamError(Object error) {
  final message = error.toString();
  return message.contains('RealtimeSubscribeException') &&
      (message.contains('RealtimeSubscribeStatus.channelError') ||
          message.contains('RealtimeSubscribeStatus.timedOut'));
}

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
    if (liveRoundIds.isEmpty) {
      return const <String>[];
    }

    final liveRounds = await roundRepository.getRoundsByIds(liveRoundIds);
    if (liveRounds.isEmpty) {
      return const <String>[];
    }

    final liveTours = await tourRepository.getToursByIds(
      liveRounds.map((round) => round.tourId).toSet().toList(growable: false),
    );
    final candidateLiveEntries = {
      ...configuredLiveEntries,
      ...liveTours
          .map((tour) => tour.groupBroadcastId)
          .whereType<String>()
          .where((id) => id.isNotEmpty),
    }.toList(growable: false);
    if (candidateLiveEntries.isEmpty) {
      return const <String>[];
    }

    final configuredBroadcasts = await groupBroadcastRepository
        .getGroupBroadcastsByIdsOrNames(candidateLiveEntries);
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

    final latestMoveTimesByRoundId = await gameRepository
        .getLatestLastMoveTimesByRoundIds(
          liveRounds.map((round) => round.id).toList(growable: false),
        );

    return computeStrictLiveGroupBroadcastIds(
      broadcasts: configuredBroadcasts,
      configuredLiveEntries: candidateLiveEntries,
      toursByGroupBroadcastId: toursByGroupBroadcastId,
      liveRounds: liveRounds,
      latestMoveTimesByRoundId: latestMoveTimesByRoundId,
    );
  }
}

/// Whether [error] is an expected connectivity hiccup (offline / timeout)
/// rather than a genuine defect.
///
/// The live-event resolver and its source streams run on a 1-minute refresh
/// timer, so without this distinction a single offline moment dumps a full
/// stack trace to the console every cycle. Connectivity errors are an expected,
/// gracefully-handled state (the resolver falls back to an empty live list), so
/// they are logged tersely and without a stack trace; everything else keeps the
/// full diagnostic.
@visibleForTesting
bool isExpectedLiveResolveError(Object error) {
  return error is NetworkException ||
      error is SocketException ||
      error is TimeoutException;
}

void _logStrictLiveResolveIssue(
  String label,
  Object error,
  StackTrace stackTrace,
) {
  if (isExpectedLiveResolveError(error)) {
    debugPrint(
      '[StrictLiveEvents] $label unavailable (offline/transient): $error',
    );
    return;
  }
  debugPrint('[StrictLiveEvents] Failed to $label: $error\n$stackTrace');
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
