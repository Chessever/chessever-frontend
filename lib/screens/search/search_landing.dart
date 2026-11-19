import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/home_live_first_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/utils/transient_request_retry.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// What the Search tab lists before anything is typed, under the recent
// searches: the events in play, the strongest players, the main openings,
// the built-in smart events and the events coming up. Each is drawn in the
// card the app already draws it in elsewhere and opens exactly what the
// same search result opens. A section with nothing in it is not shown.

/// At most this many events under Live now.
const int searchLandingLiveLimit = 5;

/// How many players Top players lists: one full grid of player cards.
const int searchLandingPlayerCount = 4;

/// At most this many events under Coming up.
const int searchLandingUpcomingLimit = 5;

/// At most this many recent searches lead the landing.
const int searchLandingRecentLimit = 4;

/// The openings the landing offers, each the first result its search gives.
///
/// Every one resolves to a whole family (a `★ All` card over an ECO range),
/// so the row reads evenly. The Italian is not here: the catalog has no
/// Italian family, only the single C50 line, which would be the one card
/// with a move list where the others count codes.
const List<String> searchLandingOpeningQueries = [
  'Sicilian',
  'Ruy Lopez',
  "Queen's Gambit Declined",
  'French',
  'Caro-Kann',
  "King's Indian",
  'Nimzo-Indian',
  'English',
];

/// The events in play, as one value-equal key (sorted ids, one per line), so
/// Live now (and a recent event's LIVE line) looks again only when the set
/// really changes.
final searchLiveIdsKeyProvider = Provider.autoDispose<String>((ref) {
  final ids = homeLiveEventIds(
    strict: ref.watch(liveGroupBroadcastIdsProvider).valueOrNull,
    mirror: ref.watch(liveBroadcastIdsProvider),
  ).where((id) => id.trim().isNotEmpty).toList()..sort();
  return ids.join('\n');
});

/// The Today feed's events, when the feed is already alive. Read, never
/// created: building the feed just to borrow its events would start its
/// whole first load.
final searchLandingFeedEventsProvider =
    Provider.autoDispose<List<GroupEventCardModel>>(
      (ref) => ref.exists(forYouEventsProvider)
          ? ref.read(forYouEventsProvider).events
          : const <GroupEventCardModel>[],
    );

/// What Live now lists: [events], then [pending] rows' worth of room held
/// for the events in play still being looked up.
@immutable
class SearchLiveNow {
  const SearchLiveNow({
    this.events = const <GroupEventCardModel>[],
    this.pending = 0,
  });

  static const none = SearchLiveNow();

  final List<GroupEventCardModel> events;
  final int pending;

  bool get isEmpty => events.isEmpty && pending == 0;
}

/// Live now: the events in play right now.
///
/// Membership is the shared live set ([homeLiveEventIds]), the one the home
/// tabs' Live first reads. The events the Today feed holds, and any found
/// earlier, are listed at once, strongest first. The rest are looked up by
/// id or name; until they arrive their rows' room is held ([SearchLiveNow.
/// pending]) and they land in it, under the rows already shown, so nothing
/// on screen moves when they come. A failed lookup keeps what was shown and
/// gives back the held room. Never an error.
final searchLiveNowProvider =
    NotifierProvider.autoDispose<SearchLiveNowNotifier, SearchLiveNow>(
      SearchLiveNowNotifier.new,
    );

class SearchLiveNowNotifier extends AutoDisposeNotifier<SearchLiveNow> {
  // Kept across changes of the live set (the notifier outlives its builds),
  // so an event found once is listed at once after, and an id that named
  // nothing is not asked for again.
  final _found = <String, GroupEventCardModel>{};
  final _unlisted = <String>{};
  bool _lookupFailed = false;

  /// Whether the last lookup failed, so arriving on the tab may ask again.
  bool get lookupFailed => _lookupFailed;

  @override
  SearchLiveNow build() {
    final key = ref.watch(searchLiveIdsKeyProvider);
    if (key.isEmpty) return SearchLiveNow.none;
    final liveIds = key.split('\n').toSet();
    final feed = ref.read(searchLandingFeedEventsProvider);
    final shown = searchLiveNowEvents(
      liveIds: liveIds,
      feedEvents: feed,
      fetchedEvents: _found.values,
    );
    final held = <String>{
      for (final event in [...feed, ..._found.values]) ...[
        event.id,
        event.title,
      ],
    };
    final missing = [
      for (final id in liveIds)
        if (!held.contains(id) && !_unlisted.contains(id)) id,
    ];
    final pending = math.min(
      missing.length,
      searchLandingLiveLimit - shown.length,
    );
    if (pending <= 0) return SearchLiveNow(events: shown);

    var current = true;
    ref.onDispose(() => current = false);
    final repository = ref.read(groupBroadcastRepositoryProvider);
    unawaited(
      _lookUp(repository, missing, liveIds).then((found) {
        if (!current) return;
        final shownIds = {for (final event in shown) event.id};
        state = SearchLiveNow(
          events: [
            ...shown,
            ...searchLiveNowEvents(
              liveIds: liveIds,
              feedEvents: const [],
              fetchedEvents: found.where((e) => !shownIds.contains(e.id)),
              limit: pending,
            ),
          ],
        );
      }),
    );
    return SearchLiveNow(events: shown, pending: pending);
  }

  Future<List<GroupEventCardModel>> _lookUp(
    GroupBroadcastRepository repository,
    List<String> missing,
    Set<String> liveIds,
  ) async {
    try {
      final broadcasts = await repository
          .getGroupBroadcastsByIdsOrNames(missing)
          .timeout(const Duration(seconds: 12));
      final liveIdList = liveIds.toList(growable: false);
      final found = [
        for (final broadcast in broadcasts)
          GroupEventCardModel.fromGroupBroadcast(broadcast, liveIdList),
      ];
      for (final event in found) {
        if (event.id.trim().isNotEmpty) _found[event.id] = event;
      }
      final answered = {
        for (final event in found) ...[event.id, event.title],
      };
      _unlisted.addAll(missing.where((id) => !answered.contains(id)));
      _lookupFailed = false;
      return found;
    } catch (error) {
      debugPrint('[SearchLanding] Live events by id: $error');
      _lookupFailed = true;
      return const <GroupEventCardModel>[];
    }
  }
}

/// The events [liveIds] names (by id, or by name for the few configured that
/// way) out of [feedEvents] and [fetchedEvents], each once (the feed's copy
/// first), strongest first (average rating, then name), at most [limit].
@visibleForTesting
List<GroupEventCardModel> searchLiveNowEvents({
  required Set<String> liveIds,
  required Iterable<GroupEventCardModel> feedEvents,
  required Iterable<GroupEventCardModel> fetchedEvents,
  int limit = searchLandingLiveLimit,
}) {
  final byId = <String, GroupEventCardModel>{};
  for (final event in [...feedEvents, ...fetchedEvents]) {
    if (event.id.trim().isEmpty) continue;
    if (!liveIds.contains(event.id) && !liveIds.contains(event.title)) {
      continue;
    }
    byId.putIfAbsent(event.id, () => event);
  }
  final events = byId.values.toList()
    ..sort((a, b) {
      final rating = b.maxAvgElo.compareTo(a.maxAvgElo);
      if (rating != 0) return rating;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
  return events.length <= limit ? events : events.sublist(0, limit);
}

/// Top players: the head of the world ranking, as Rankings lists it (active
/// players, classical rating), shaped like a player search result so a tap
/// opens the profile the same way.
final searchTopPlayersProvider = FutureProvider.autoDispose<List<SearchPlayer>>(
  (ref) async {
    final repository = ref.read(chessPlayerRepositoryProvider);
    final players = await retryTransientRead(
      () => repository.getRankedPlayers(
        filters: RankingFilters.defaults,
        limit: searchLandingPlayerCount,
      ),
    );
    return [
      for (final player in players)
        if (player.name.trim().isNotEmpty) searchPlayerFromRanking(player),
    ];
  },
);

/// [player] as the player search shapes a `chess_players` row.
@visibleForTesting
SearchPlayer searchPlayerFromRanking(ChessPlayer player) {
  final title = player.title?.trim();
  final fed = player.country?.trim();
  final rating = player.rating;
  return SearchPlayer(
    id: 'search_${player.fideid}',
    name: player.name.trim(),
    title: title == null || title.isEmpty ? null : title,
    rating: rating != null && rating > 0 ? rating : null,
    fideId: player.fideid > 0 ? player.fideid : null,
    fed: fed == null || fed.isEmpty ? null : fed,
    tournamentId: 'player_search',
    tournamentName: 'Player Search',
  );
}

/// Openings: [searchLandingOpeningQueries], each resolved by the opening
/// search itself, so a card opens exactly what that search result opens.
///
/// The search scans every catalog row per query, far too much for a frame
/// eight times over, so it runs once, off the UI isolate.
final searchLandingOpeningsProvider =
    FutureProvider.autoDispose<List<OpeningSearchSuggestion>>(
      (ref) =>
          compute(resolveSearchLandingOpenings, searchLandingOpeningQueries),
    );

/// The first result of each of [queries], each destination once.
List<OpeningSearchSuggestion> resolveSearchLandingOpenings(
  List<String> queries,
) {
  final seen = <String>{};
  return [
    for (final query in queries)
      for (final suggestion in searchOpeningSuggestions(query, limit: 1))
        if (seen.add(suggestion.id)) suggestion,
  ];
}

/// How many of the strongest upcoming events the tab reads: twice what
/// Coming up lists, so one that starts while the tab is open leaves the
/// next strongest to take its place without another read.
const int searchUpcomingReadLimit = searchLandingUpcomingLimit * 2;

/// How long one read of the upcoming view stands: arriving on the tab after
/// this reads it again (`SearchTabScreen`).
const Duration searchUpcomingMaxAge = Duration(minutes: 15);

/// The strongest events not started yet, as the upcoming view orders them
/// (strongest first), named ones only. Read once and kept while the Search
/// tab lives; the tab reads it again when one of them starts or the read
/// grows old. What Coming up lists is [searchComingUpProvider].
final searchUpcomingProvider =
    FutureProvider.autoDispose<List<GroupEventCardModel>>((ref) async {
      final repository = ref.read(groupBroadcastRepositoryProvider);
      final broadcasts = await retryTransientRead(
        () => repository.getUpcomingGroupBroadcasts(
          limit: searchUpcomingReadLimit,
        ),
      );
      return [
        for (final broadcast in broadcasts)
          GroupEventCardModel.fromGroupBroadcast(broadcast, const []),
      ];
    });

/// Coming up as it stands now: [searchUpcomingEvents] over the last read and
/// today's live set, so an event never shows under Live now and Coming up
/// at once. Null until the first read lands.
final searchComingUpProvider = Provider.autoDispose<List<GroupEventCardModel>?>(
  (ref) {
    final read = ref.watch(searchUpcomingProvider).valueOrNull;
    if (read == null) return null;
    final key = ref.watch(searchLiveIdsKeyProvider);
    return searchUpcomingEvents(
      read,
      liveIds: key.isEmpty ? const <String>[] : key.split('\n'),
    );
  },
);

/// Whether [event] is in [liveIds] (by id, or by name for the few events
/// configured that way).
bool searchEventIsLive(GroupEventCardModel event, Iterable<String> liveIds) {
  for (final id in liveIds) {
    if (id == event.id || id == event.title) return true;
  }
  return false;
}

/// Of [events] (strongest first), the first [searchLandingUpcomingLimit]
/// that have a name and have not started by [now] (nor gone live early by
/// [liveIds]), each once, then soonest first (undated last, then by name).
/// Each reads as it stands now ([GroupEventCardModel.withLiveIds]).
@visibleForTesting
List<GroupEventCardModel> searchUpcomingEvents(
  Iterable<GroupEventCardModel> events, {
  List<String> liveIds = const <String>[],
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final byId = <String, GroupEventCardModel>{};
  for (final event in events) {
    if (byId.length == searchLandingUpcomingLimit) break;
    if (event.id.trim().isEmpty || event.title.trim().isEmpty) continue;
    if (searchEventIsLive(event, liveIds)) continue;
    final start = event.startDate;
    if (start != null && !at.isBefore(start)) continue;
    byId.putIfAbsent(event.id, () => event.withLiveIds(liveIds));
  }
  return byId.values.toList()..sort((a, b) {
    final start = switch ((a.startDate, b.startDate)) {
      (final x?, final y?) => x.compareTo(y),
      (null, null) => 0,
      (null, _) => 1,
      (_, null) => -1,
    };
    if (start != 0) return start;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
}

/// A recent event as it stands now: the snapshot recorded with the search,
/// its status read again from today's live set and its dates
/// ([GroupEventCardModel.withLiveIds]), so a search saved while the event
/// was live never reads LIVE after it ends.
GroupEventCardModel searchRecentEvent(
  GroupEventCardModel saved,
  List<String> liveIds,
) => saved.withLiveIds(liveIds);
