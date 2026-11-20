import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/collections/collections_screen.dart'
    show CollectionCard;
import 'package:chessever2/screens/collections/collections_data.dart'
    show Collection, CollectionKind;
import 'package:chessever2/screens/feed/news/news_models.dart' show FeedNews;
import 'package:chessever2/screens/feed/news/news_reader_pager.dart';
import 'package:chessever2/screens/for_you/discovery/news_screen.dart'
    show NewsArticleCard, newsCardExtent, newsGridMetrics;
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart'
    show SmartEventRequest;
import 'package:chessever2/screens/group_event/widget/player_search_cards.dart';
import 'package:chessever2/screens/search/search_carousel.dart';
import 'package:chessever2/screens/search/search_feeds.dart';
import 'package:chessever2/screens/search/search_landing.dart';
import 'package:chessever2/screens/search/search_landing_section.dart';
import 'package:chessever2/screens/search/search_page_sections.dart';
import 'package:chessever2/screens/search/sections/search_section_pages.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/smart_event_card.dart'
    show SmartEventCard;
import 'package:chessever2/widgets/event_card/smart_event_request_card.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Search tab before anything is typed: what is worth opening right now,
/// each in the card the app draws it in everywhere else, so a tap opens it
/// and a long-press offers exactly what it offers there (My Space for
/// events, smart events and collections).
///
/// In order: the events in play, the top of the world ranking, the main
/// openings and the built-in smart events (both as smart events), the
/// strongest events coming up, the collections, the news. Every section is
/// a row of its cards read on as the reader scrolls it
/// ([SearchLandingSection]): its title opens the section's own page, See
/// more opens it in place. A section with nothing to list is simply not
/// there; nothing explains itself in prose. The recent searches are not
/// here: they stand in for the landing while the field has the cursor
/// (`SearchRecentsView`), as X shows them.
///
/// Each section listens to its own source, so a live event starting rebuilds
/// only Live now. The sources are kept warm by the tab (`SearchTabScreen`),
/// so clearing a search brings this back at once.
class SearchPageLanding extends StatelessWidget {
  const SearchPageLanding({super.key, required this.picks});

  final SearchPicks picks;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const ValueKey('search_landing'),
      // The Search tab's controller: a re-tap of the tab takes it to its top.
      primary: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        _LiveNowSection(picks: picks),
        _TopPlayersSection(picks: picks),
        _OpeningsSection(picks: picks),
        _SmartEventsSection(picks: picks),
        _ComingUpSection(picks: picks),
        _CollectionsSection(picks: picks),
        _NewsSection(picks: picks),
        // The last card ends clear of the floating dock the page scrolls
        // under, whose height arrives as the bottom inset.
        SliverToBoxAdapter(
          child: SizedBox(height: 24.h + MediaQuery.paddingOf(context).bottom),
        ),
      ],
    );
  }
}

const Widget _none = SliverToBoxAdapter(child: SizedBox.shrink());

/// The landing's event sections (Live now, Coming up) as the Events list
/// draws its events: compact cards on a phone, the image cards of its grid
/// on a tablet (a column's width in the row, the grid down the page).
SearchLandingSection<GroupEventCardModel> _eventSection(
  BuildContext context, {
  required SearchSectionId section,
  required SearchFeed<GroupEventCardModel> feed,
  required SearchPicks picks,
  int pending = 0,
  VoidCallback? onLoadMore,
  VoidCallback? onRetry,
}) {
  final grid = ResponsiveHelper.isTablet;
  final keyPrefix = 'search-${section.slug}';
  Widget card(GroupEventCardModel event) => searchEventCard(
    event,
    keyPrefix: keyPrefix,
    grid: grid,
    onOpen: picks.event,
  );
  return SearchLandingSection<GroupEventCardModel>(
    id: section.slug,
    title: section.title,
    items: feed.items,
    pending: pending,
    hasMore: feed.hasMore,
    loading: feed.loading,
    failed: feed.failed,
    onLoadMore: onLoadMore,
    onRetry: onRetry,
    onOpen: () => openSearchSectionPage(context, section),
    sizing: grid
        ? SearchCarouselSizing.fixed(EventCard.gridMainAxisExtent)
        // The tallest compact card: a two-line title over the LIVE line.
        : SearchCarouselSizing.ghost((_) => const SearchPendingEventCard()),
    card: (context, event, index, inRow) => card(event),
    columns: (width) => grid
        ? ResponsiveHelper.columnsForWidth(width, spacing: searchCardGap)
        : 1,
    row: (context, items, start, columns, width) {
      final cardWidth = (width - searchCardGap * (columns - 1)) / columns;
      return searchCardRow(
        items,
        start,
        columns,
        cardBuilder: (event, _) => card(event),
        extent: grid ? EventCard.gridMainAxisExtent(context, cardWidth) : null,
      );
    },
  );
}

/// A section's first read as the section shows it: one card's room with a
/// spinner while it loads, nothing once it has failed (null).
({SearchFeed<T> feed, int pending})? _landing<T>(SearchFeed<T> feed) {
  if (!feed.ready) {
    if (feed.failed) return null;
    return (feed: SearchFeed<T>(hasMore: true), pending: 1);
  }
  if (feed.isEmpty) return null;
  return (feed: feed, pending: 0);
}

/// Live now: an event card per event in play, as the Events list draws it,
/// strongest first, more listed as the reader scrolls on. Events still
/// being looked up arrive into room already held for them
/// ([SearchLiveNow.pending]), so nothing moves when they land. Its page is
/// Events on Current, live events first.
class _LiveNowSection extends ConsumerWidget {
  const _LiveNowSection({required this.picks});

  final SearchPicks picks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(searchLiveNowProvider);
    if (live.isEmpty) return _none;
    return _eventSection(
      context,
      section: SearchSectionId.liveNow,
      feed: SearchFeed(items: live.events, hasMore: live.more),
      pending: live.pending,
      picks: picks,
      onLoadMore: () => ref.read(searchLiveNowProvider.notifier).showMore(),
    );
  }
}

/// Top players: the world ranking from its head, the ranking read on as the
/// reader scrolls. The Events page's player cards (photo and flag) stand
/// two to a card's room, their compact pair, in the row and down the page
/// alike. A failed first read leaves no trace; a slow one holds the row's
/// room with one quiet spinner. Its page is Rankings.
///
/// A page can land odd (a nameless row skipped, a player repeated across
/// pages dropped): while more of the ranking is coming, its last player
/// waits for the next page to make a pair, so no card is drawn alone and
/// then turns into a pair. Only once the ranking is spent does a last
/// player stand alone, in its full card, and the row then stands as tall
/// as that card.
class _TopPlayersSection extends ConsumerWidget {
  const _TopPlayersSection({required this.picks});

  final SearchPicks picks;

  /// Nameless stand-ins, only ever laid out: they ask for no photo.
  static const _ghosts = [
    SearchPlayer(
      id: 'search-pending-0',
      name: '\u00A0',
      tournamentId: '',
      tournamentName: '',
    ),
    SearchPlayer(
      id: 'search-pending-1',
      name: '\u00A0',
      tournamentId: '',
      tournamentName: '',
    ),
  ];

  /// The row's tallest card: the compact pair.
  static const Widget _pairGhost = PlayerSearchCards(
    players: _ghosts,
    animateIn: false,
    bottomPadding: 0,
  );

  /// The row's tallest card with a last player alone: the pair, or the one
  /// player's full card, whichever stands taller.
  static final Widget _loneGhost = Stack(
    children: [
      _pairGhost,
      PlayerSearchCards(
        players: [_ghosts.first],
        animateIn: false,
        bottomPadding: 0,
      ),
    ],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = _landing(ref.watch(searchTopPlayersFeedProvider));
    if (shown == null) return _none;
    final feed = shown.feed;
    final notifier = ref.read(searchTopPlayersFeedProvider.notifier);
    final section = SearchSectionId.topPlayers;
    final players = feed.items;
    final listed = feed.hasMore
        ? players.length - players.length % 2
        : players.length;
    final pairs = [
      for (var i = 0; i < listed; i += 2)
        players.sublist(i, math.min(i + 2, listed)),
    ];
    final lone = listed.isOdd;
    Widget pair(List<SearchPlayer> pair, int index) => PlayerSearchCards(
      key: ValueKey('search-top-players-${index * 2}'),
      players: pair,
      animateIn: false,
      bottomPadding: 0,
      onOpen: picks.player,
    );
    return SearchLandingSection<List<SearchPlayer>>(
      id: section.slug,
      title: section.title,
      items: pairs,
      pending: shown.pending,
      hasMore: feed.hasMore,
      loading: feed.loading,
      failed: feed.failed,
      onLoadMore: notifier.loadMore,
      onRetry: notifier.retry,
      onOpen: () => openSearchSectionPage(context, section),
      sizing: SearchCarouselSizing.ghost(
        lone ? (_) => _loneGhost : (_) => _pairGhost,
        tabletMinWidth: 320,
      ),
      card: (context, players, index, inRow) => pair(players, index),
      columns: (_) => 1,
    );
  }
}

/// The tallest smart event card of a row: a two-line name over its two
/// lines. Laid out, never painted. Real glyphs, not blanks: the card
/// trims its name, and blanks (a no-break space too) would lay out as one
/// empty line.
const Widget _smartEventGhost = SmartEventCard(
  tierLabel: 'Ag\nAg',
  titleSuffix: '',
  minElo: 0,
  liveCount: 0,
  avgElo: 0,
  metaText: 'Ag',
  summary: 'Ag',
);

/// Smart event cards in a row: the row card My Space and the Discovery
/// lead draw (the plate beside the words), at a row card's width.
const SearchCarouselSizing _smartEventSizing = SearchCarouselSizing.ghost(
  _smartEventGhostBuilder,
  tabletMinWidth: 320,
);

Widget _smartEventGhostBuilder(double width) => _smartEventGhost;

/// The main openings, each as the smart event its search result opens (the
/// games of every current event played in it), then the rest of the
/// catalog as the reader scrolls on. Down the page and on its own page, the
/// half cards My Space sets side by side.
class _OpeningsSection extends ConsumerWidget {
  const _OpeningsSection({required this.picks});

  final SearchPicks picks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = _landing(ref.watch(searchOpeningsFeedProvider));
    if (shown == null) return _none;
    final feed = shown.feed;
    final notifier = ref.read(searchOpeningsFeedProvider.notifier);
    final section = SearchSectionId.openings;
    final open = picks.opening;
    VoidCallback? tap(OpeningSearchSuggestion opening) =>
        open == null ? null : () => open(opening.selection);
    return SearchLandingSection<OpeningSearchSuggestion>(
      id: section.slug,
      title: section.title,
      items: feed.items,
      pending: shown.pending,
      hasMore: feed.hasMore,
      loading: feed.loading,
      failed: feed.failed,
      onLoadMore: notifier.loadMore,
      onRetry: notifier.retry,
      onOpen: () => openSearchSectionPage(context, section, onOpening: open),
      sizing: _smartEventSizing,
      card: (context, opening, index, inRow) => KeyedSubtree(
        key: ValueKey('opening-result-${opening.id}'),
        child: SmartEventRequestCard(
          request: SmartEventRequest.forOpeningSelection(opening.selection),
          onTap: tap(opening),
          showFilters: false,
        ),
      ),
      columns: searchSmartEventColumns,
      row: (context, items, start, columns, width) {
        final row = items.sublist(
          start,
          math.min(start + columns, items.length),
        );
        return searchSmartEventRow(
          [
            for (final opening in row)
              SmartEventRequest.forOpeningSelection(opening.selection),
          ],
          0,
          columns,
          keyFor: (index) => ValueKey('opening-result-${row[index].id}'),
          onTap: open == null ? null : (index) => tap(row[index]),
        );
      },
    );
  }
}

/// The built-in smart events (every game at each level, every game in each
/// time control), as My Space shows a saved one: star it to hear about its
/// games (here a star also keeps it in My Space), long-press for the same.
class _SmartEventsSection extends StatelessWidget {
  const _SmartEventsSection({required this.picks});

  final SearchPicks picks;

  @override
  Widget build(BuildContext context) {
    final section = SearchSectionId.smartEvents;
    final requests = searchSmartEventRequests;
    Key keyOf(SmartEventRequest request) =>
        ValueKey('search-smart-${request.tierLabel}');
    // The tab remembers the pick, then opens it as the card would.
    final open = picks.smartEvent;
    VoidCallback? tap(SmartEventRequest request) =>
        open == null ? null : () => open(request);
    return SearchLandingSection<SmartEventRequest>(
      id: section.slug,
      title: section.title,
      items: requests,
      onOpen: () => openSearchSectionPage(context, section),
      sizing: _smartEventSizing,
      card: (context, request, index, inRow) => KeyedSubtree(
        key: keyOf(request),
        child: SmartEventRequestCard(
          request: request,
          onTap: tap(request),
          showFilters: false,
        ),
      ),
      columns: searchSmartEventColumns,
      row: (context, items, start, columns, width) => searchSmartEventRow(
        items,
        start,
        columns,
        keyFor: (index) => keyOf(items[index]),
        onTap: open == null ? null : (index) => tap(items[index]),
      ),
    );
  }
}

/// Coming up: the strongest events not started yet, soonest first, then the
/// rest of the upcoming view as the reader scrolls on, as the Events list's
/// Upcoming draws them. One that starts leaves at once (it is under Live
/// now). Its page is Events on Upcoming.
class _ComingUpSection extends ConsumerWidget {
  const _ComingUpSection({required this.picks});

  final SearchPicks picks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = _landing(ref.watch(searchComingUpFeedProvider));
    if (shown == null) return _none;
    final notifier = ref.read(searchComingUpFeedProvider.notifier);
    return _eventSection(
      context,
      section: SearchSectionId.comingUp,
      feed: shown.feed,
      pending: shown.pending,
      picks: picks,
      onLoadMore: notifier.loadMore,
      onRetry: notifier.retry,
    );
  }
}

/// The room the Collections row holds before its first page lands: the
/// usual book card, a two-line title over a one-line byline and a tally
/// that takes two lines beside the star. Laid out, never painted. Real
/// glyphs, not blanks, which the card would trim away.
final Collection _collectionGhost = Collection(
  id: 'search-ghost',
  slug: 'search-ghost',
  kind: CollectionKind.book,
  title: 'Ag\nAg',
  author: 'Ag',
  gameCount: 1000,
  eventCount: 10,
  viewCount: 1000,
  starCount: 100,
);

/// [collection] as its card lays it out, without its cover: the same
/// words and counts, so the same height (the cover's room is fixed), and
/// no picture asked of the network for a card that is never painted.
Collection _collectionLayoutTwin(Collection collection) => Collection(
  id: collection.id,
  slug: collection.slug,
  kind: collection.kind,
  title: collection.title,
  subtitle: collection.subtitle,
  author: collection.author,
  annotator: collection.annotator,
  location: collection.location,
  dateStart: collection.dateStart,
  dateEnd: collection.dateEnd,
  publishedYear: collection.publishedYear,
  gameCount: collection.gameCount,
  viewCount: collection.viewCount,
  starCount: collection.starCount,
  access: collection.access,
  eventCount: collection.eventCount,
  bookCount: collection.bookCount,
  events: collection.events,
  matchedGameCount: collection.matchedGameCount,
);

/// The Collections row's height: its tallest card, each card it holds laid
/// out at a card's width and never painted, so every card fills its slot
/// with no empty room around its words (a card's height follows its title,
/// byline and tally; a worst case of every line would leave the usual card
/// floating in a box half again its height). Before the first page, the
/// usual card's room ([_collectionGhost]).
Widget _collectionsRowGhost(List<Collection> items) {
  if (items.isEmpty) return CollectionCard(collection: _collectionGhost);
  return Stack(
    children: [
      for (final collection in items)
        CollectionCard(
          key: ValueKey('search-collection-ghost-${collection.id}'),
          collection: _collectionLayoutTwin(collection),
        ),
    ],
  );
}

/// Collections: the published books as the Collections page lists them, in
/// its card with its own long-press (Open, Share, notifications, My Space),
/// read a page at a time. Its page is Collections. Every open (a tap, the
/// menu's Open, the lifted copy) is remembered as a recent search.
class _CollectionsSection extends ConsumerWidget {
  const _CollectionsSection({required this.picks});

  final SearchPicks picks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = _landing(ref.watch(searchCollectionsFeedProvider));
    if (shown == null) return _none;
    final feed = shown.feed;
    final notifier = ref.read(searchCollectionsFeedProvider.notifier);
    final section = SearchSectionId.collections;
    final opened = picks.collection;
    Widget card(Collection collection) => CollectionCard(
      key: ValueKey('search-collection-${collection.id}'),
      collection: collection,
      onOpened: opened == null ? null : () => opened(collection),
    );
    return SearchLandingSection<Collection>(
      id: section.slug,
      title: section.title,
      items: feed.items,
      pending: shown.pending,
      hasMore: feed.hasMore,
      loading: feed.loading,
      failed: feed.failed,
      onLoadMore: notifier.loadMore,
      onRetry: notifier.retry,
      onOpen: () => openSearchSectionPage(context, section),
      sizing: SearchCarouselSizing.ghost(
        (_) => _collectionsRowGhost(feed.items),
        tabletMinWidth: 340,
      ),
      card: (context, collection, index, inRow) => card(collection),
      columns: (width) => ResponsiveHelper.isTablet
          ? ResponsiveHelper.columnsForWidth(
              width,
              minItemWidth: 360,
              spacing: searchCardGap,
              maxColumns: 2,
            )
          : 1,
      row: (context, items, start, columns, width) => searchCardRow(
        items,
        start,
        columns,
        cardBuilder: (collection, _) => card(collection),
      ),
    );
  }
}

/// The News stories' hero scope on the Search tab: a story's cover flies to
/// the reader and back from here, never from the News page's own cards.
final Object _searchNewsHeroes = Object();

/// News: the News page's stories, newest first, in its own card, read a
/// page at a time; a tap opens the reader as the News page does, paging on
/// through the same stories. Its page is News.
class _NewsSection extends ConsumerWidget {
  const _NewsSection({required this.picks});

  final SearchPicks picks;

  Future<void> _open(BuildContext context, int index) async {
    FocusScope.of(context).unfocus();
    final container = ProviderScope.containerOf(context, listen: false);
    final feed = container.read(searchNewsFeedProvider);
    if (index >= feed.items.length) return;
    // The tab remembers the story; the reader opens as the News page's.
    picks.news?.call(feed.items[index]);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await NewsReaderPager.open(
        context,
        articles: List.of(feed.items),
        initialIndex: index,
        heroScope: _searchNewsHeroes,
        hasMore: () => container.read(searchNewsFeedProvider).hasMore,
        loadMore: () async {
          final notifier = container.read(searchNewsFeedProvider.notifier);
          // After a page failed, the reader's Retry asks for that page
          // again, as the News page's own reader does.
          if (container.read(searchNewsFeedProvider).failed) {
            await notifier.retry();
          } else {
            await notifier.loadMore();
          }
          final now = container.read(searchNewsFeedProvider);
          if (now.failed) throw StateError('News page unavailable');
          return List.of(now.items);
        },
      );
    } catch (error) {
      debugPrint('[Search] news open failed: $error');
      if (messenger != null) {
        showAppSnackOn(
          messenger,
          "Couldn't open news. Try again.",
          tone: AppSnackTone.danger,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = _landing(ref.watch(searchNewsFeedProvider));
    if (shown == null) return _none;
    final feed = shown.feed;
    final notifier = ref.read(searchNewsFeedProvider.notifier);
    final section = SearchSectionId.news;
    Widget card(FeedNews news, int index, {required bool compact}) =>
        NewsArticleCard(
          key: ValueKey('search-news-${news.key}'),
          news: news,
          compact: compact,
          heroTag: (_searchNewsHeroes, news.key),
          onTap: () => unawaited(_open(context, index)),
        );
    return SearchLandingSection<FeedNews>(
      id: section.slug,
      title: section.title,
      items: feed.items,
      pending: shown.pending,
      hasMore: feed.hasMore,
      loading: feed.loading,
      failed: feed.failed,
      onLoadMore: notifier.loadMore,
      onRetry: notifier.retry,
      onOpen: () => openSearchSectionPage(context, section),
      // The News page's narrow card, two to a phone's row as that page
      // sets them, its stacked sheets (a story with several articles) drawn
      // whole under it.
      sizing: SearchCarouselSizing.fixed(
        (context, width) => newsCardExtent(
          width,
          MediaQuery.textScalerOf(context),
          compact: true,
        ),
        bottomRoom: 8,
        tabletMinWidth: 260,
        phoneColumns: 2,
      ),
      card: (context, news, index, inRow) => LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: AlignmentDirectional.topStart,
          child: SizedBox(
            height: newsCardExtent(
              constraints.maxWidth,
              MediaQuery.textScalerOf(context),
              compact: true,
            ),
            child: card(news, index, compact: true),
          ),
        ),
      ),
      // Down the page, the News page's own grid.
      columns: (width) =>
          newsGridMetrics(width, MediaQuery.textScalerOf(context)).columns,
      row: (context, items, start, columns, width) {
        final grid = newsGridMetrics(width, MediaQuery.textScalerOf(context));
        return searchCardRow(
          items,
          start,
          columns,
          cardBuilder: (news, index) =>
              card(news, index, compact: grid.compact),
          extent: grid.height,
        );
      },
    );
  }
}

/// One opening per smart event, in [openings]' order, at most [limit] (all
/// of them without one).
///
/// Named lines that share an ECO code are one smart event (its criteria are
/// the code), so the best-ranked line stands for the rest instead of the
/// same card repeating under different names.
List<OpeningSearchSuggestion> searchOpeningSmartEvents(
  List<OpeningSearchSuggestion> openings, {
  int? limit,
}) => distinctSearchOpenings(openings, limit: limit);
