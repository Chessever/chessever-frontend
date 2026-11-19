import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/screens/feed/news/news_repository.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart'
    show kDiscoverySmartPresets;
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart'
    show SmartEventRequest;
import 'package:chessever2/screens/my_space/defaults/space_defaults.dart'
    show kSpaceSmartFormatPresets, kSpaceSmartLevelPresets;
import 'package:chessever2/screens/search/search_landing.dart';
import 'package:chessever2/utils/transient_request_retry.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// The Search tab's sections, read a page at a time: the head each section
// has always read (the strongest players, the main openings, the strongest
// events coming up) lands first, and the rest of the same source follows as
// the reader nears the end of the section's row, its list or its page. One
// provider per section, so the row on the landing, the section opened in
// place and its own page show one list and read each page once.

/// One section's cards as far as they have been read, and where the next
/// page stands.
@immutable
class SearchFeed<T> {
  const SearchFeed({
    this.items = const [],
    this.hasMore = false,
    this.loading = false,
    this.failed = false,
    this.ready = true,
  });

  /// The first page is on its way: the section holds its room.
  const SearchFeed.loading()
    : items = const [],
      hasMore = true,
      loading = true,
      failed = false,
      ready = false;

  final List<T> items;

  /// The source holds more than [items].
  final bool hasMore;

  /// A page is on its way.
  final bool loading;

  /// The last page failed. Before the first page lands ([ready] false) the
  /// section is not shown; after it, the row ends in a quiet retry card.
  final bool failed;

  /// The first page has landed.
  final bool ready;

  /// Nothing to show, and nothing on its way.
  bool get isEmpty => ready && items.isEmpty && !loading && !hasMore;

  SearchFeed<T> copyWith({
    List<T>? items,
    bool? hasMore,
    bool? loading,
    bool? failed,
    bool? ready,
  }) => SearchFeed<T>(
    items: items ?? this.items,
    hasMore: hasMore ?? this.hasMore,
    loading: loading ?? this.loading,
    failed: failed ?? this.failed,
    ready: ready ?? this.ready,
  );
}

/// Whether [feed]'s first page failed: its section is not shown, and the
/// tab reads it again on the next arrival.
bool searchFeedFirstPageFailed(SearchFeed<Object?> feed) =>
    !feed.ready && feed.failed;

/// One page of a section's source.
@immutable
class SearchFeedPage<T> {
  const SearchFeedPage(this.items, {required this.hasMore, this.commit});

  final List<T> items;
  final bool hasMore;

  /// Moves the source's cursor past this page. Run only when the page is
  /// taken: a page that lands after the source was read again is dropped,
  /// and must not move the new read's cursor.
  final VoidCallback? commit;
}

/// [head] (a section's first read) as a feed: holding its room while it
/// loads, gone when it fails, and [hasMore] once it lands.
SearchFeed<T> searchFeedFromHead<T>(
  AsyncValue<List<T>> head, {
  required bool Function(List<T> items) hasMore,
}) {
  final value = head.valueOrNull;
  if (value != null) {
    return SearchFeed<T>(items: value, hasMore: hasMore(value));
  }
  if (head.hasError) {
    return SearchFeed<T>(ready: false, failed: true);
  }
  return SearchFeed<T>.loading();
}

/// A section's source, a page at a time. Subclasses build the first state
/// (a head read, or [startEmpty] to read the first page here) through
/// [restart], and read the page after what is loaded in [fetchPage].
///
/// A page in flight when the source is read again (or the section goes
/// away) is dropped, never appended to the new list.
abstract class SearchFeedNotifier<T>
    extends AutoDisposeNotifier<SearchFeed<T>> {
  int _generation = 0;
  bool _busy = false;
  SearchFeed<T>? _last;

  /// The page on its way while [_busy]: a second ask waits on it.
  Future<void>? _reading;

  /// The state before this build, while [build] runs (null on the first):
  /// what a source read again can keep.
  @protected
  SearchFeed<T>? get previous => _last;

  @override
  set state(SearchFeed<T> value) {
    _last = value;
    super.state = value;
  }

  /// The page after [loaded].
  @protected
  Future<SearchFeedPage<T>> fetchPage(List<T> loaded);

  /// What makes two items the same card: a page that repeats one (a source
  /// that shifted under the reader) never lists it twice.
  @protected
  Object identityOf(T item);

  /// Begins a new read of the source with [first] as its state.
  @protected
  SearchFeed<T> restart(SearchFeed<T> first) {
    _generation++;
    _busy = false;
    _last = first;
    final generation = _generation;
    ref.onDispose(() {
      if (_generation == generation) _generation++;
    });
    return first;
  }

  /// A source with no head: the first page is read now.
  @protected
  SearchFeed<T> startEmpty() {
    final first = restart(SearchFeed<T>.loading());
    final generation = _generation;
    scheduleMicrotask(() {
      if (generation == _generation) unawaited(_read(generation));
    });
    return first;
  }

  /// Reads the next page, unless the source is spent or the last read
  /// failed (that waits for [retry]). With a page already on its way, waits
  /// for that one instead of asking twice.
  Future<void> loadMore() {
    if (_busy) return _reading ?? Future<void>.value();
    final current = state;
    if (!current.ready || !current.hasMore || current.failed) {
      return Future<void>.value();
    }
    state = current.copyWith(loading: true);
    return _read(_generation);
  }

  /// Reads the page that failed again.
  Future<void> retry() {
    if (_busy) return _reading ?? Future<void>.value();
    final current = state;
    if (!current.failed) return Future<void>.value();
    if (!current.ready) {
      state = SearchFeed<T>.loading();
    } else {
      state = current.copyWith(failed: false, loading: true);
    }
    return _read(_generation);
  }

  Future<void> _read(int generation) {
    if (_busy) return _reading ?? Future<void>.value();
    _busy = true;
    return _reading = _fetch(generation);
  }

  Future<void> _fetch(int generation) async {
    try {
      final page = await fetchPage(state.items);
      if (generation != _generation) return;
      page.commit?.call();
      final loaded = state.items;
      final seen = <Object>{for (final item in loaded) identityOf(item)};
      final added = [
        for (final item in page.items)
          if (seen.add(identityOf(item))) item,
      ];
      state = SearchFeed<T>(
        items: added.isEmpty ? loaded : [...loaded, ...added],
        // A page that added nothing new ends the source: asking again would
        // only repeat it.
        hasMore: page.hasMore && page.items.isNotEmpty,
      );
    } catch (error) {
      if (generation != _generation) return;
      debugPrint('[SearchFeed] ${runtimeType.toString()}: $error');
      state = state.copyWith(loading: false, failed: true);
    } finally {
      if (generation == _generation) _busy = false;
    }
  }
}

// ------------------------------------------------------------- top players

/// Players a page reads after the head ([searchTopPlayersProvider]).
const int searchPlayersPageSize = 12;

/// Top players: the head of the world ranking, then the ranking on from
/// there, as Rankings lists it.
final searchTopPlayersFeedProvider =
    NotifierProvider.autoDispose<
      SearchTopPlayersFeed,
      SearchFeed<SearchPlayer>
    >(SearchTopPlayersFeed.new);

class SearchTopPlayersFeed extends SearchFeedNotifier<SearchPlayer> {
  /// Ranking rows read so far (nameless rows are read and skipped).
  int _offset = searchLandingPlayerCount;

  @override
  SearchFeed<SearchPlayer> build() {
    _offset = searchLandingPlayerCount;
    return restart(
      searchFeedFromHead(
        ref.watch(searchTopPlayersProvider),
        // A nameless row read and skipped leaves the head short of what it
        // asked for, so only an empty head ends the ranking (a page past
        // its end comes back empty and ends it too).
        hasMore: (players) => players.isNotEmpty,
      ),
    );
  }

  @override
  Future<SearchFeedPage<SearchPlayer>> fetchPage(
    List<SearchPlayer> loaded,
  ) async {
    final repository = ref.read(chessPlayerRepositoryProvider);
    final offset = _offset;
    final rows = await retryTransientRead(
      () => repository.getRankedPlayers(
        filters: RankingFilters.defaults,
        limit: searchPlayersPageSize,
        offset: offset,
      ),
    );
    return SearchFeedPage(
      [
        for (final row in rows)
          if (row.name.trim().isNotEmpty) searchPlayerFromRanking(row),
      ],
      hasMore: rows.length >= searchPlayersPageSize,
      commit: () => _offset = offset + rows.length,
    );
  }

  @override
  Object identityOf(SearchPlayer item) => item.fideId ?? item.id;
}

// ---------------------------------------------------------------- openings

/// Openings a page lists after the main ones.
const int searchOpeningsPageSize = 12;

/// Every opening the catalog can open as a smart event, after the main
/// ones: the named families (the Dutch, the Pirc, the Najdorf), then every
/// ECO code, in the catalog's order.
List<OpeningSearchSuggestion> searchOpeningCatalog(Object? _) {
  final browse = browseOpeningSuggestions();
  return [
    for (final opening in browse)
      if (opening.isFamily) opening,
    for (final opening in browse)
      if (!opening.isFamily) opening,
  ];
}

/// Reads [searchOpeningCatalog], off the UI isolate (the catalog builds
/// some 550 destinations). A function, so a test can answer at once.
final searchOpeningCatalogLoaderProvider =
    Provider<Future<List<OpeningSearchSuggestion>> Function()>(
      (ref) =>
          () => compute(searchOpeningCatalog, null),
    );

/// One smart event per opening: named lines that share an ECO code open the
/// same smart event.
Object searchOpeningIdentity(OpeningSearchSuggestion opening) =>
    opening.filter.code ?? opening.id;

/// Openings: the main openings ([searchLandingOpeningsProvider]), then the
/// rest of the catalog ([searchOpeningCatalog]), each one smart event.
final searchOpeningsFeedProvider =
    NotifierProvider.autoDispose<
      SearchOpeningsFeed,
      SearchFeed<OpeningSearchSuggestion>
    >(SearchOpeningsFeed.new);

class SearchOpeningsFeed extends SearchFeedNotifier<OpeningSearchSuggestion> {
  Future<List<OpeningSearchSuggestion>>? _catalog;

  @override
  SearchFeed<OpeningSearchSuggestion> build() {
    return restart(
      searchFeedFromHead(
        ref
            .watch(searchLandingOpeningsProvider)
            .whenData(
              (resolved) => distinctSearchOpenings(
                resolved,
                limit: searchLandingOpeningQueries.length,
              ),
            ),
        hasMore: (_) => true,
      ),
    );
  }

  @override
  Future<SearchFeedPage<OpeningSearchSuggestion>> fetchPage(
    List<OpeningSearchSuggestion> loaded,
  ) async {
    final catalog = await (_catalog ??= ref.read(
      searchOpeningCatalogLoaderProvider,
    )());
    final listed = {
      for (final opening in loaded) searchOpeningIdentity(opening),
    };
    final rest = [
      for (final opening in distinctSearchOpenings(catalog))
        if (!listed.contains(searchOpeningIdentity(opening))) opening,
    ];
    return SearchFeedPage(
      rest.take(searchOpeningsPageSize).toList(growable: false),
      hasMore: rest.length > searchOpeningsPageSize,
    );
  }

  @override
  Object identityOf(OpeningSearchSuggestion item) =>
      searchOpeningIdentity(item);
}

/// One opening per smart event, in [openings]' order, at most [limit] (all
/// of them without one): the best-ranked named line stands for the rest of
/// its ECO code.
List<OpeningSearchSuggestion> distinctSearchOpenings(
  List<OpeningSearchSuggestion> openings, {
  int? limit,
}) {
  final seen = <Object>{};
  final distinct = [
    for (final opening in openings)
      if (seen.add(searchOpeningIdentity(opening))) opening,
  ];
  if (limit == null || distinct.length <= limit) return distinct;
  return distinct.take(limit).toList(growable: false);
}

// ------------------------------------------------------------ smart events

/// The built-in smart events, as My Space's picker offers them: every level
/// (Super GM, GM and IM first, as the landing always led), then every time
/// control. A fixed set: the whole source is one page.
final List<SmartEventRequest> searchSmartEventRequests = List.unmodifiable(() {
  final seen = <String>{};
  return [
    for (final request in [
      ...kDiscoverySmartPresets,
      ...kSpaceSmartLevelPresets,
      ...kSpaceSmartFormatPresets,
    ])
      if (seen.add(request.criteriaKey)) request,
  ];
}());

// --------------------------------------------------------------- coming up

/// Upcoming events a page reads after the first read.
const int searchUpcomingPageSize = searchUpcomingReadLimit;

/// Coming up: the strongest events coming up ([searchComingUpProvider]),
/// then the rest of the upcoming view, strongest first: the first read's
/// spares, then a page at a time from where it stopped.
final searchComingUpFeedProvider =
    NotifierProvider.autoDispose<
      SearchComingUpFeed,
      SearchFeed<GroupEventCardModel>
    >(SearchComingUpFeed.new);

class SearchComingUpFeed extends SearchFeedNotifier<GroupEventCardModel> {
  List<GroupEventCardModel> _spares = const [];
  int _offset = 0;
  List<String> _liveIds = const [];

  /// The read of the upcoming view the pages read on from.
  List<GroupEventCardModel>? _upcomingRead;

  @override
  SearchFeed<GroupEventCardModel> build() {
    final head = ref.watch(searchComingUpProvider);
    final read = ref.watch(searchUpcomingProvider);
    final key = ref.watch(searchLiveIdsKeyProvider);
    _liveIds = key.isEmpty ? const <String>[] : key.split('\n');
    if (head == null) {
      _upcomingRead = null;
      return restart(
        read.hasError && !read.hasValue
            ? const SearchFeed(ready: false, failed: true)
            : SearchFeed<GroupEventCardModel>.loading(),
      );
    }
    final events = read.valueOrNull ?? const <GroupEventCardModel>[];
    final listed = {for (final event in head) event.id};
    // The cards already listed stay where they are, after the head, less
    // any that has started: whether the live set moved on or the upcoming
    // view was read again (one of its events started, or the read grew
    // old). A row scrolled far, or the section opened in place, keeps its
    // cards; nothing drops back to the first page.
    final before = previous;
    final kept = before != null && before.ready
        ? searchUpcomingEvents(
            before.items.where((event) => !listed.contains(event.id)),
            liveIds: _liveIds,
            limit: before.items.length,
            soonestFirst: false,
          )
        : const <GroupEventCardModel>[];
    if (!identical(events, _upcomingRead)) {
      _upcomingRead = events;
      if (kept.isEmpty) {
        _offset = events.length;
      } else {
        // A new read: the pages go on from where they stopped. The events
        // that have left the view since moved the rest up a place each, so
        // the cursor steps back as many (a card read twice is listed once).
        final stayed = {...listed, for (final event in kept) event.id};
        final gone = before!.items
            .where((event) => !stayed.contains(event.id))
            .length;
        _offset = math.max(events.length, _offset - gone);
      }
    }
    final have = {...listed, for (final event in kept) event.id};
    _spares = searchUpcomingEvents(
      events.where((event) => !have.contains(event.id)),
      liveIds: _liveIds,
      limit: events.length,
      soonestFirst: false,
    );
    final remote = kept.isEmpty
        ? events.length >= searchUpcomingReadLimit
        : before!.hasMore;
    return restart(
      SearchFeed(
        items: kept.isEmpty ? head : [...head, ...kept],
        hasMore: _spares.isNotEmpty || remote,
      ),
    );
  }

  @override
  Future<SearchFeedPage<GroupEventCardModel>> fetchPage(
    List<GroupEventCardModel> loaded,
  ) async {
    final spares = _spares;
    if (spares.isNotEmpty) {
      return SearchFeedPage(
        spares,
        hasMore: _offset >= searchUpcomingReadLimit,
        commit: () => _spares = const [],
      );
    }
    final repository = ref.read(groupBroadcastRepositoryProvider);
    final offset = _offset;
    final broadcasts = await retryTransientRead(
      () => repository.getUpcomingGroupBroadcasts(
        limit: searchUpcomingPageSize,
        offset: offset,
      ),
    );
    return SearchFeedPage(
      searchUpcomingEvents(
        [
          for (final broadcast in broadcasts)
            GroupEventCardModel.fromGroupBroadcast(broadcast, const []),
        ],
        liveIds: _liveIds,
        limit: broadcasts.length,
        soonestFirst: false,
      ),
      hasMore: broadcasts.length >= searchUpcomingPageSize,
      commit: () => _offset = offset + broadcasts.length,
    );
  }

  @override
  Object identityOf(GroupEventCardModel item) => item.id;
}

// ------------------------------------------------------------- collections

/// Collections: the published books as the Collections page lists them,
/// read a page at a time from the catalog (never the whole catalog).
final searchCollectionsFeedProvider =
    NotifierProvider.autoDispose<SearchCollectionsFeed, SearchFeed<Collection>>(
      SearchCollectionsFeed.new,
    );

class SearchCollectionsFeed extends SearchFeedNotifier<Collection> {
  int _offset = 0;

  @override
  SearchFeed<Collection> build() {
    _offset = 0;
    return startEmpty();
  }

  @override
  Future<SearchFeedPage<Collection>> fetchPage(List<Collection> loaded) async {
    final repository = ref.read(collectionsRepositoryProvider);
    final offset = _offset;
    final page = await repository.searchBooks(
      const CollectionSearchQuery(),
      offset,
    );
    final next = offset + page.items.length;
    return SearchFeedPage(
      page.items,
      hasMore: page.items.isNotEmpty && next < page.total,
      commit: () => _offset = next,
    );
  }

  @override
  Object identityOf(Collection item) => item.id;
}

// -------------------------------------------------------------------- news

/// News: the News page's stories, newest first, a page at a time from the
/// same catalog (its own cursor).
final searchNewsFeedProvider =
    NotifierProvider.autoDispose<SearchNewsFeed, SearchFeed<FeedNews>>(
      SearchNewsFeed.new,
    );

class SearchNewsFeed extends SearchFeedNotifier<FeedNews> {
  late NewsCatalogRepository _catalog;

  @override
  SearchFeed<FeedNews> build() {
    _catalog = ref.read(newsCatalogFactoryProvider)();
    return startEmpty();
  }

  @override
  Future<SearchFeedPage<FeedNews>> fetchPage(List<FeedNews> loaded) async {
    final page = await _catalog.loadNext();
    return SearchFeedPage(page.items, hasMore: page.hasMore);
  }

  @override
  Object identityOf(FeedNews item) => item.key;
}

// --------------------------------------------------------------- expansion

/// The sections opened in place on the landing (by [SearchSectionId.name]),
/// kept while the tab lives, so a search typed and cleared finds them as
/// they were.
final searchExpandedSectionsProvider = StateProvider.autoDispose<Set<String>>(
  (ref) => const <String>{},
);
