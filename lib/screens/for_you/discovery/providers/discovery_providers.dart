import 'dart:async';

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/for_you/discovery/data/discovery_repository.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart'
    show filterBroadcastsByPopupState, liveBroadcastIdsProvider;
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/providers/streak_providers.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// How long a Discovery read outlives its last listener, so switching the
/// For You pages back and forth is instant instead of a fresh round trip.
const Duration kDiscoveryKeepAlive = Duration(minutes: 5);

/// Keeps an autoDispose read cached for [kDiscoveryKeepAlive] after its last
/// listener leaves. Returns a closer for the failure path: a failed read is
/// never kept, so coming back retries it.
void Function() _keepWarm(Ref<Object?> ref) {
  final link = ref.keepAlive();
  Timer? release;
  ref.onCancel(() {
    release?.cancel();
    release = Timer(kDiscoveryKeepAlive, link.close);
  });
  ref.onResume(() {
    release?.cancel();
    release = null;
  });
  ref.onDispose(() => release?.cancel());
  return link.close;
}

/// How long one Analyzed games read is reused. Its query filters the PGN
/// text of every game of the last three days, and the report prewarm that
/// annotates them runs hourly, so each viewer asks at most this often.
/// Pull-to-refresh ([refreshDiscovery]) still reads it again at once.
const Duration kDiscoveryAnalyzedMaxAge = Duration(minutes: 15);

/// Keeps an autoDispose read cached for [maxAge] from the moment it was
/// made, whether or not anything listens, and lets it go with its last
/// listener after that. Returns a closer for the failure path: a failed
/// read is never kept, so coming back retries it.
void Function() _keepFor(Ref<Object?> ref, Duration maxAge) {
  final link = ref.keepAlive();
  final expiry = Timer(maxAge, link.close);
  ref.onDispose(expiry.cancel);
  return () {
    expiry.cancel();
    link.close();
  };
}

// ---------------------------------------------------------------- Most Liked

/// The period the viewer picked. Premium periods are only ever set after the
/// premium guard passed (see the Most Liked section).
final mostLikedPeriodProvider = StateProvider<MostLikedPeriod>(
  (ref) => MostLikedPeriod.today,
);

/// The day the viewer walked the date control to, or null for today. The
/// ranking shown is the picked period holding this day, so going back to
/// 14 Sep and then picking Week shows the week of 14 Sep. Null follows the
/// clock across midnight instead of pinning yesterday. Only ever set past
/// today after the premium guard passed.
final mostLikedDayProvider = StateProvider<DateTime?>((ref) => null);

/// Games or Players. Players is only ever set after the premium guard.
final mostLikedViewProvider = StateProvider<MostLikedView>(
  (ref) => MostLikedView.games,
);

final mostLikedProvider = FutureProvider.autoDispose
    .family<MostLikedResult, MostLikedQuery>((ref, query) async {
      final close = _keepWarm(ref);
      try {
        return await ref
            .watch(discoveryRepositoryProvider)
            .fetchMostLiked(query);
      } catch (_) {
        close();
        rethrow;
      }
    });

// ------------------------------------------------------------- Who's hot

/// Rating floor for the Discovery rail: familiar, strong players only.
const int kDiscoveryHotMinRating = 2400;

/// How many tiles the Who's hot rail holds.
const int kDiscoveryHotCount = 10;

/// The time class picked on the rail. Separate from the wall's own switch so
/// browsing here never moves the wall.
final discoveryHotClassProvider = StateProvider<StreakTimeClass>(
  (ref) => StreakTimeClass.standard,
);

/// The strongest live runs in [tc] among players rated [kDiscoveryHotMinRating]
/// or more, in wall order (streak desc, rating desc, FIDE id).
final discoveryHotRowsProvider =
    Provider.family<List<StreakRow>, StreakTimeClass>((ref, tc) {
      return ref
          .watch(streakClassRowsProvider(tc))
          .where((row) => (row.rating ?? 0) >= kDiscoveryHotMinRating)
          .take(kDiscoveryHotCount)
          .toList(growable: false);
    });

/// The FIDE ids of the players the viewer follows. The seam Discovery reads
/// favourites through (tests override it rather than reach the account).
final discoveryFollowedFideIdsProvider = Provider.autoDispose<Set<int>>((ref) {
  final favorites =
      ref.watch(favoritePlayersProviderNew).valueOrNull ??
      const <FavoritePlayer>[];
  return {
    for (final f in favorites)
      if (int.tryParse(f.fideId?.trim() ?? '') case final id?) id,
  };
});

/// One tile on the Streaks rail: a live run, and whether the viewer follows
/// the player behind it.
@immutable
class DiscoveryStreakItem {
  const DiscoveryStreakItem(this.row, {required this.followed});

  final StreakRow row;
  final bool followed;
}

/// Wall order: the longest current run first, then the higher rating, then
/// the FIDE id, so ties never swap between reads.
int _hottestFirst(StreakRow a, StreakRow b) {
  final byRun = b.currentStreak.compareTo(a.currentStreak);
  if (byRun != 0) return byRun;
  final byRating = (b.rating ?? 0).compareTo(a.rating ?? 0);
  if (byRating != 0) return byRating;
  return a.fideId.compareTo(b.fideId);
}

/// The Streaks rail for [tc]: the live runs of players the viewer follows
/// first (any rating: they chose them), strongest first, then the strongest
/// 2400+ runs ([discoveryHotRowsProvider]) that are not already there. At
/// most [kDiscoveryHotCount] tiles.
final discoveryStreakRowsProvider = Provider.autoDispose
    .family<List<DiscoveryStreakItem>, StreakTimeClass>((ref, tc) {
      final followed = ref.watch(discoveryFollowedFideIdsProvider);
      final seen = <int>{};
      final out = <DiscoveryStreakItem>[];
      if (followed.isNotEmpty) {
        final mine = [
          for (final row in ref.watch(streakAllClassRowsProvider(tc)))
            if (followed.contains(row.fideId)) row,
        ]..sort(_hottestFirst);
        for (final row in mine) {
          if (seen.add(row.fideId)) {
            out.add(DiscoveryStreakItem(row, followed: true));
          }
        }
      }
      for (final row in ref.watch(discoveryHotRowsProvider(tc))) {
        if (seen.add(row.fideId)) {
          out.add(
            DiscoveryStreakItem(row, followed: followed.contains(row.fideId)),
          );
        }
      }
      return out.take(kDiscoveryHotCount).toList(growable: false);
    });

// -------------------------------------------------------------- Miniatures

final discoveryTodayMiniaturesProvider =
    FutureProvider.autoDispose<List<DiscoveryMiniature>>((ref) async {
      final close = _keepWarm(ref);
      try {
        return await ref
            .watch(discoveryRepositoryProvider)
            .fetchTodayMiniatures();
      } catch (_) {
        close();
        rethrow;
      }
    });

// --------------------------------------------------------- Analyzed games

/// The strongest recently analyzed games. Read at most once per
/// [kDiscoveryAnalyzedMaxAge] (the query scans PGN text server-side), not
/// on every visit; pull-to-refresh and Retry read it again.
final discoveryAnalyzedGamesProvider =
    FutureProvider.autoDispose<List<GamesTourModel>>((ref) async {
      final close = _keepFor(ref, kDiscoveryAnalyzedMaxAge);
      try {
        return await ref
            .watch(discoveryRepositoryProvider)
            .fetchAnalyzedGames();
      } catch (_) {
        close();
        rethrow;
      }
    });

/// The evaluation curve of the strongest analyzed game, drawn on the "Full
/// game reviews" tile. Null when there is no analyzed game or its PGN holds
/// too few evaluations to draw. Kept as long as the read it comes from: a
/// game's evaluations never change, so it is only read again with it.
final discoveryReviewCurveProvider = FutureProvider.autoDispose<List<int>?>((
  ref,
) async {
  final games = await ref.watch(discoveryAnalyzedGamesProvider.future);
  if (games.isEmpty) return null;
  final close = _keepFor(ref, kDiscoveryAnalyzedMaxAge);
  try {
    final curve = await ref
        .watch(discoveryRepositoryProvider)
        .fetchEvalCurve(games.first.gameId);
    return curve.length >= 8 ? curve : null;
  } catch (_) {
    close();
    return null;
  }
});

// ------------------------------------------------------------ Smart Events

/// Tier previews shown until the viewer has saved a Smart Event of their own.
/// Both are the same criteria the rating-tier filter builds (game average at
/// or above the floor), so opening one is exactly what the filter would give.
SmartEventRequest discoveryTierPreset({
  required String tier,
  required int minElo,
}) {
  return SmartEventRequest(
    source: SmartEventSource.forYou,
    tierLabel: tier,
    titleSuffix: 'Games',
    minElo: minElo,
    maxElo: kFilterMaxElo.round(),
    caption: 'Every game averaging $minElo+',
    countSingular: 'event',
    countPlural: 'events',
    events: const [],
  );
}

final List<SmartEventRequest> kDiscoverySmartPresets = [
  discoveryTierPreset(tier: 'GM', minElo: 2500),
  discoveryTierPreset(tier: 'IM', minElo: 2400),
];

/// At most this many Smart Events show on Discovery.
const int kDiscoverySmartEventLimit = 3;

/// The viewer's saved Smart Events (one per criteria), or the tier previews
/// when there are none. A favourites read that fails falls back to the
/// previews too: they need no account.
final discoverySmartRequestsProvider =
    Provider.autoDispose<AsyncValue<List<SmartEventRequest>>>((ref) {
      final favorites = ref.watch(favoriteEventsProvider);
      return favorites.when(
        data: (list) {
          final seen = <String>{};
          final saved =
              <SmartEventRequest>[
                    for (final favorite in list)
                      if (isSmartFavoriteEvent(favorite))
                        SmartEventRequest.fromFavoriteEvent(favorite),
                  ]
                  .where((r) => seen.add(r.criteriaKey))
                  .take(kDiscoverySmartEventLimit);
          final requests = saved.toList(growable: false);
          return AsyncData(
            requests.isEmpty ? kDiscoverySmartPresets : requests,
          );
        },
        loading: () => const AsyncLoading(),
        error: (_, __) => AsyncData(kDiscoverySmartPresets),
      );
    });

/// The server's `group_broadcasts_current` view, read ONCE for every Smart
/// Event tile on Discovery and kept warm, instead of one full read per tile
/// on every visit.
final discoveryCurrentBroadcastsProvider =
    FutureProvider.autoDispose<List<GroupBroadcast>>((ref) async {
      final close = _keepWarm(ref);
      try {
        return await ref
            .read(groupBroadcastRepositoryProvider)
            .getCurrentGroupBroadcasts();
      } catch (_) {
        close();
        rethrow;
      }
    });

/// One Smart Event's current membership, filtered in memory from
/// [discoveryCurrentBroadcastsProvider]. Same matching as
/// `smartEventResolvedEventsProvider`; liveness changes re-filter the cached
/// read rather than downloading the view again.
final discoverySmartEventMembersProvider = FutureProvider.autoDispose
    .family<List<GroupEventCardModel>, SmartEventCriteria>((
      ref,
      criteria,
    ) async {
      final close = _keepWarm(ref);
      try {
        List<String> liveIds;
        try {
          liveIds = await ref.watch(liveGroupBroadcastIdsProvider.future);
        } catch (_) {
          liveIds = ref.read(liveBroadcastIdsProvider);
        }
        final broadcasts = await ref.watch(
          discoveryCurrentBroadcastsProvider.future,
        );
        return filterBroadcastsByPopupState(
              broadcasts,
              criteria.toPopupState(),
              liveIds: liveIds,
            )
            .map((b) => GroupEventCardModel.fromGroupBroadcast(b, liveIds))
            .toList(growable: false);
      } catch (_) {
        close();
        rethrow;
      }
    });

// ------------------------------------------------------------------ context

/// The viewer's country, for the Countrymen tile. Null until it is known.
final discoveryCountryProvider = Provider.autoDispose<Country?>((ref) {
  return ref.watch(countryDropdownProvider).valueOrNull;
});

/// Drops every Discovery read so pull-to-refresh starts each section over,
/// Analyzed games included: its [kDiscoveryAnalyzedMaxAge] cache only
/// spares the visits in between.
void refreshDiscovery(WidgetRef ref) {
  ref.invalidate(mostLikedProvider);
  ref.invalidate(discoveryTodayMiniaturesProvider);
  ref.invalidate(collectionsProvider);
}
