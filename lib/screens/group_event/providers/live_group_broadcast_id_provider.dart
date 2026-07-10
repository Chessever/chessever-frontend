import 'dart:async';
import 'dart:io';

import 'package:chessever2/providers/app_resume_signal_provider.dart';
import 'package:chessever2/repository/api_utils/api_exceptions.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/settings/settings.dart';
import 'package:chessever2/repository/supabase/settings/settings_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
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
  var liveRoundIds = const <String>[];
  var hasSettingsSnapshot = false;
  var refreshedAfterRealtimeInterruption = false;
  var resolveInFlight = false;
  var resolveQueued = false;
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

  Future<List<String>?> resolve({required List<String> liveRoundIds}) async {
    try {
      return await resolver.resolve(liveRoundIds: liveRoundIds);
    } catch (error, stackTrace) {
      _logStrictLiveResolveIssue('resolve live event IDs', error, stackTrace);
      return null;
    }
  }

  Future<void> emitResolvedIds() async {
    if (!hasSettingsSnapshot) {
      return;
    }
    if (resolveInFlight) {
      resolveQueued = true;
      return;
    }

    resolveInFlight = true;
    try {
      do {
        resolveQueued = false;
        final resolvedIds = await resolve(
          liveRoundIds: List<String>.of(liveRoundIds),
        );
        if (controller.isClosed) return;
        if (!resolveQueued && resolvedIds != null) {
          emit(resolvedIds);
        }
      } while (resolveQueued && !controller.isClosed);
    } finally {
      resolveInFlight = false;
    }
  }

  void applySettingsSnapshot(Settings? settings, {bool forceResolve = false}) {
    final nextLiveRoundIds = List<String>.unmodifiable(
      settings?.liveRoundIds ?? const <String>[],
    );
    final liveInputsChanged =
        !hasSettingsSnapshot ||
        !setEquals(liveRoundIds.toSet(), nextLiveRoundIds.toSet());
    if (liveInputsChanged) {
      settingsSnapshotVersion += 1;
    }

    liveRoundIds = nextLiveRoundIds;
    hasSettingsSnapshot = true;
    refreshedAfterRealtimeInterruption = false;
    if (!forceResolve && !liveInputsChanged) {
      return;
    }
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
      // Explicit snapshot pulls happen only on startup, recovery, and app
      // resume. Force those to re-check activity even when settings IDs are
      // unchanged; ordinary Realtime row replays are deduplicated above.
      applySettingsSnapshot(settings, forceResolve: true);
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

  // Keep the time-based activity cutoff accurate during long foreground
  // sessions. The heartbeat now performs one compact IDs-only RPC instead of
  // the previous multi-table client sweep, and unchanged sets do not emit.
  final refreshTimer = Timer.periodic(_liveIndicatorRefreshInterval, (_) {
    unawaited(emitResolvedIds());
  });

  // The realtime settings stream can die silently while the app is
  // backgrounded; re-pull the snapshot on resume so live ids (and everything
  // derived from them) reflect events/rounds that started in the meantime.
  ref.listen<int>(appResumedSignalProvider, (_, __) {
    unawaited(refreshSettingsSnapshot('app resume'));
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
  const _StrictLiveGroupBroadcastResolver({required this.gameRepository});

  final GameRepository gameRepository;

  Future<List<String>> resolve({required List<String> liveRoundIds}) async {
    return gameRepository.getStrictLiveGroupBroadcastIds(
      liveRoundIds: liveRoundIds,
      staleAfterSeconds: liveIndicatorStaleAfter.inSeconds,
    );
  }
}

/// Whether [error] is an expected connectivity hiccup (offline / timeout)
/// rather than a genuine defect.
///
/// Connectivity errors are an expected, gracefully-handled state (the resolver
/// preserves its last good live list), so they are logged tersely and without
/// a stack trace; everything else keeps the full diagnostic.
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
