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
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/transient_request_retry.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// What the Search tab lists before anything is typed, under the recent
// searches: the events in play, the strongest players and the main openings.
// Every row is a real destination and opens exactly what the same search
// result opens. A section with nothing in it is not shown.

/// How far a Search tab row's content sits in from the page's gutter: rows,
/// headings, the opening cards and the tab's own gutter sum all use this one
/// value. `.w` and `.sp` scale apart off the 393pt base (short phones, the
/// tablet branch), so mixing them put the rows a couple of points off the
/// field's edge.
double get searchPageRowInset => 12.w;

/// At most this many events under Live now.
const int searchLandingLiveLimit = 8;

/// How many players Top players lists.
const int searchLandingPlayerCount = 5;

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
/// Live now looks again only when the set really changes.
final _searchLiveIdsKeyProvider = Provider.autoDispose<String>((ref) {
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
    final key = ref.watch(_searchLiveIdsKeyProvider);
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

/// One landing row, built like a recent search row so the page reads as one
/// list: a glyph, the name, a quiet second line. 48pt tall at the least.
///
/// To assistive technology it is one button, read as [semanticsLabel] (else
/// the name and the second line), that activates [onTap] like a touch does.
class SearchLandingRow extends StatelessWidget {
  const SearchLandingRow({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.semanticsLabel,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          semanticsLabel ??
          [title, if (subtitle.isNotEmpty) subtitle].join(', '),
      // The InkWell's own node is excluded with the text, so the tap is
      // declared here or the button could not be activated.
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: searchPageRowInset,
              vertical: 6.h,
            ),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 17.ic,
                  child: Center(child: leading),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 10.sp,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Room for [count] landing rows still on their way, so they arrive into it
/// instead of pushing what is below down under a finger. Each slot is a
/// real row's build, never painted, so it is exactly a row tall at any text
/// size; the first carries one small spinner.
class SearchLandingPendingRows extends StatelessWidget {
  const SearchLandingPendingRows({super.key, required this.count});

  final int count;

  static void _inert() {}

  @override
  Widget build(BuildContext context) {
    const slot = Visibility(
      visible: false,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: SearchLandingRow(
        leading: SizedBox.shrink(),
        title: ' ',
        subtitle: ' ',
        onTap: _inert,
      ),
    );
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < count; i++)
            if (i == 0)
              Stack(
                alignment: Alignment.center,
                children: [
                  slot,
                  SizedBox.square(
                    dimension: 18.ic,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              )
            else
              slot,
        ],
      ),
    );
  }
}

/// A Top players row's mark: its place in the ranking, set like the second
/// line's figures.
class SearchLandingRank extends StatelessWidget {
  const SearchLandingRank(this.rank, {super.key});

  final int rank;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$rank',
      maxLines: 1,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: context.colors.textSecondary,
        fontSize: 12.sp,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// A live event's second line: its time control and average rating.
String searchLiveEventSubtitle(GroupEventCardModel event) => [
  if (event.timeControl.trim().isNotEmpty) event.timeControl.trim(),
  if (event.maxAvgElo > 0) 'Ø ${event.maxAvgElo}',
].join(' · ');

/// What a live event's row reads as to assistive technology.
String searchLiveEventSemantics(GroupEventCardModel event) => [
  '${event.title}, live',
  if (event.timeControl.trim().isNotEmpty) event.timeControl.trim(),
  if (event.maxAvgElo > 0) 'average rating ${event.maxAvgElo}',
].join(', ');

/// A player's second line, as a recent player search writes it.
String searchPlayerSubtitle(SearchPlayer player) => [
  if (player.title?.isNotEmpty == true) player.title!,
  if (player.rating != null) '${player.rating}',
  if (player.fed?.isNotEmpty == true) player.fed!,
].join(' · ');

/// What a Top players row reads as to assistive technology.
String searchTopPlayerSemantics(SearchPlayer player, int rank) => [
  player.name,
  'number $rank',
  if (player.title?.isNotEmpty == true) player.title!,
  if (player.rating != null) 'rating ${player.rating}',
  if (player.fed?.isNotEmpty == true) player.fed!,
].join(', ');
