import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/providers/for_you_games_logic.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart'
    show kDiscoveryPreviewCards;
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// The live data My Database draws under what the user saved: the saved
// events' cards and current boards, and the saved players' games in
// progress. One read per kind for the whole page, never one per card, each
// kept warm for a while after the page lets go of it.

/// A value-equal, sorted, de-duplicated list of ids: the key of one batched
/// read, so the same saved things always share one read.
@immutable
class SpaceIds {
  SpaceIds(Iterable<String> ids)
    : ids = List.unmodifiable(
        {
          for (final id in ids)
            if (id.trim().isNotEmpty) id.trim(),
        }.toList()..sort(),
      );

  final List<String> ids;

  bool get isEmpty => ids.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is SpaceIds && listEquals(other.ids, ids);

  @override
  int get hashCode => Object.hashAll(ids);

  @override
  String toString() => 'SpaceIds($ids)';
}

/// Keeps an autoDispose read for [warm] after its last listener leaves.
/// Returns a closer for a failed read, which is never kept.
void Function() _keepWarm(Ref<Object?> ref, Duration warm) {
  final link = ref.keepAlive();
  Timer? release;
  ref.onCancel(() {
    release?.cancel();
    release = Timer(warm, link.close);
  });
  ref.onResume(() {
    release?.cancel();
    release = null;
  });
  ref.onDispose(() => release?.cancel());
  return link.close;
}

/// The broadcast an event shortcut stands for: the group broadcast when the
/// pin names it, else its target.
String spaceEventIdOf(SpaceShortcut s) {
  String? str(String key) {
    final v = s.params[key];
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  return str('groupBroadcastId') ?? str('eventId') ?? s.targetId;
}

/// Every saved broadcast event, read in one query and kept 5 minutes.
final spaceEventBroadcastsProvider = FutureProvider.autoDispose
    .family<List<GroupBroadcast>, SpaceIds>((ref, ids) async {
      if (ids.isEmpty) return const <GroupBroadcast>[];
      final close = _keepWarm(ref, const Duration(minutes: 5));
      try {
        return await ref
            .read(groupBroadcastRepositoryProvider)
            .getGroupBroadcastsByIdsOrNames(ids.ids);
      } catch (e) {
        close();
        rethrow;
      }
    });

/// The saved events as the Events list draws them, by id: dates, rating and
/// whether each is live. Liveness re-derives the cards without a refetch.
/// Empty until the read lands (the cards draw from their snapshot until
/// then) and when it fails.
final spaceEventCardModelsProvider = Provider.autoDispose
    .family<Map<String, GroupEventCardModel>, SpaceIds>((ref, ids) {
      final broadcasts = ref.watch(spaceEventBroadcastsProvider(ids));
      final liveIds =
          ref.watch(liveGroupBroadcastIdsProvider).valueOrNull ??
          const <String>[];
      final list = broadcasts.valueOrNull ?? const <GroupBroadcast>[];
      return {
        for (final b in list)
          b.id: GroupEventCardModel.fromGroupBroadcast(b, liveIds),
      };
    });

/// How many boards a saved live event can show under its card: the most
/// any games preview draws ([kDiscoveryPreviewCards]).
const int kSpaceEventBoards = kDiscoveryPreviewCards;

/// The current boards of the saved live events: what Today already holds
/// for them, and one read for the rest. [failed] names the events whose read
/// failed, so each can offer a retry without hiding the others.
@immutable
class SpaceLiveEventGames {
  const SpaceLiveEventGames({required this.byEvent, this.failed = const {}});

  final Map<String, ForYouEventGamesSnapshot> byEvent;
  final Set<String> failed;
}

/// Today's snapshot of [eventId] trimmed to [kSpaceEventBoards] boards.
ForYouEventGamesSnapshot _trimmed(ForYouEventGamesSnapshot s) =>
    ForYouEventGamesSnapshot(
      eventId: s.eventId,
      tourId: s.tourId,
      visibleGames: s.visibleGames.take(kSpaceEventBoards).toList(),
      pinnedIds: s.pinnedIds,
    );

final spaceLiveEventGamesProvider = FutureProvider.autoDispose
    .family<SpaceLiveEventGames, SpaceIds>((ref, ids) async {
      if (ids.isEmpty) return const SpaceLiveEventGames(byEvent: {});
      final close = _keepWarm(ref, const Duration(minutes: 2));
      // Today's cache first: an event it holds costs nothing.
      final cache = ref.read(forYouTopGamesSnapshotCacheProvider);
      final byEvent = <String, ForYouEventGamesSnapshot>{
        for (final id in ids.ids)
          if (cache[id] case final snapshot? when snapshot.hasGames)
            id: _trimmed(snapshot),
      };
      final missing = [
        for (final id in ids.ids)
          if (!byEvent.containsKey(id)) id,
      ];
      if (missing.isEmpty) return SpaceLiveEventGames(byEvent: byEvent);
      try {
        final fetched = await ref
            .read(gameRepositoryProvider)
            .getForYouTopGamesByEventIds(
              eventIds: missing,
              boardsPerEvent: kSpaceEventBoards,
            );
        for (final id in missing) {
          byEvent[id] = buildForYouTopGamesSnapshot(
            eventId: id,
            games: fetched[id] ?? const [],
            maxGames: kSpaceEventBoards,
          );
        }
        return SpaceLiveEventGames(byEvent: byEvent);
      } catch (e) {
        debugPrint('[MySpace] live boards not loaded: $e');
        // What Today held still shows; the rest offer a retry. Not kept, so
        // the next visit tries again.
        close();
        return SpaceLiveEventGames(byEvent: byEvent, failed: missing.toSet());
      }
    });

/// How long a game without a move still counts as in progress: a stale
/// "ongoing" row from a feed that stopped is not a player at the board.
const Duration kSpacePlayerLiveWindow = Duration(hours: 3);

/// The games in progress among [games], newest first, one per game id: from
/// the broadcast feed, not finished, with a move in the last
/// [kSpacePlayerLiveWindow] before [now].
@visibleForTesting
List<GamesTourModel> spaceLivePlayerGames(
  Iterable<GamesTourModel> games, {
  required DateTime now,
}) {
  final seen = <String>{};
  final out = <GamesTourModel>[];
  for (final g in games) {
    if (g.source != GameSource.supabase) continue;
    if (g.gameStatus.isFinished) continue;
    final at = g.lastMoveTime;
    if (at == null || now.difference(at) > kSpacePlayerLiveWindow) continue;
    if (!seen.add(g.gameId)) continue;
    out.add(g);
  }
  return out;
}

/// The saved players' games in progress: one query for every saved player
/// (by FIDE id), kept 2 minutes.
final spacePlayersLiveGamesProvider = FutureProvider.autoDispose
    .family<List<GamesTourModel>, SpaceIds>((ref, fideIds) async {
      if (fideIds.isEmpty) return const <GamesTourModel>[];
      final close = _keepWarm(ref, const Duration(minutes: 2));
      try {
        final raw = await ref
            .read(gameRepositoryProvider)
            .getGamesByMultipleFideIds(
              fideIds: fideIds.ids,
              limit: math.min(60, 6 * fideIds.ids.length),
            );
        final models = <GamesTourModel>[];
        for (final g in raw) {
          try {
            models.add(GamesTourModel.fromGame(g));
          } catch (_) {}
        }
        return spaceLivePlayerGames(models, now: DateTime.now());
      } catch (e) {
        close();
        rethrow;
      }
    });
