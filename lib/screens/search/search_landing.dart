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

// What the Search tab lists before anything is typed: the strongest
// players, the main openings, the built-in smart events and the events
// coming up. Each is drawn in the card the app already draws it in
// elsewhere and opens exactly what the same search result opens. A section
// with nothing in it is not shown.

/// How many players Top players lists: one full grid of player cards.
const int searchLandingPlayerCount = 4;

/// At most this many events under Coming up.
const int searchLandingUpcomingLimit = 5;

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
/// Coming up, a found event's LIVE line and a recent event's look again
/// only when the set really changes.
final searchLiveIdsKeyProvider = Provider.autoDispose<String>((ref) {
  final ids = homeLiveEventIds(
    strict: ref.watch(liveGroupBroadcastIdsProvider).valueOrNull,
    mirror: ref.watch(liveBroadcastIdsProvider),
  ).where((id) => id.trim().isNotEmpty).toList()..sort();
  return ids.join('\n');
});

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
/// today's live set, so an event leaves Coming up the moment it goes live.
/// Null until the first read lands.
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

/// Of [events] (strongest first), the first [limit] that have a name and
/// have not started by [now] (nor gone live early by [liveIds]), each once,
/// then soonest first (undated last, then by name) unless [soonestFirst] is
/// off (the rest of Coming up keeps the view's strongest-first order). Each
/// reads as it stands now ([GroupEventCardModel.withLiveIds]).
List<GroupEventCardModel> searchUpcomingEvents(
  Iterable<GroupEventCardModel> events, {
  List<String> liveIds = const <String>[],
  DateTime? now,
  int limit = searchLandingUpcomingLimit,
  bool soonestFirst = true,
}) {
  final at = now ?? DateTime.now();
  final byId = <String, GroupEventCardModel>{};
  for (final event in events) {
    if (byId.length >= limit) break;
    if (event.id.trim().isEmpty || event.title.trim().isEmpty) continue;
    if (searchEventIsLive(event, liveIds)) continue;
    final start = event.startDate;
    if (start != null && !at.isBefore(start)) continue;
    byId.putIfAbsent(event.id, () => event.withLiveIds(liveIds));
  }
  if (!soonestFirst) return byId.values.toList();
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

/// A recent event as it stands now: the snapshot recorded when it was opened,
/// its status read again from today's live set and its dates
/// ([GroupEventCardModel.withLiveIds]), so a search saved while the event
/// was live never reads LIVE after it ends.
GroupEventCardModel searchRecentEvent(
  GroupEventCardModel saved,
  List<String> liveIds,
) => saved.withLiveIds(liveIds);
