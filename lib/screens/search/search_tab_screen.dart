import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/collections/collections_data.dart'
    show Collection;
import 'package:chessever2/screens/feed/news/news_models.dart' show FeedNews;
import 'package:chessever2/screens/for_you/open_for_you_event.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart'
    show isSearchableQuery;
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/my_space/actions/space_star_pin.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/search/search_cancel_button.dart';
import 'package:chessever2/screens/search/search_feeds.dart';
import 'package:chessever2/screens/search/search_landing.dart';
import 'package:chessever2/screens/search/search_page_landing.dart';
import 'package:chessever2/screens/search/search_page_results.dart';
import 'package:chessever2/screens/search/search_page_sections.dart';
import 'package:chessever2/screens/search/search_recents_store.dart';
import 'package:chessever2/screens/search/search_recents_view.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/dismiss_keyboard.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search/enhanced_rounded_search_bar.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/page_spring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Search tab: the app-wide search (players, events, openings, smart
/// events, collections, news) as one page, behaving as X's search does.
///
/// The field sits in the home bar's frame ([HomeTopBarFrame]), where every
/// root tab starts; everything under it is the page. Arriving never puts
/// the cursor in the field: the landing is there to read (the events in
/// play, the top players, the main openings and the built-in smart events,
/// the events coming up, the collections and the news), and the field takes
/// the cursor only when the reader taps it. With the cursor in an empty
/// field the page is the recent searches ([SearchRecentsView]): the things
/// last opened from Search, then the queries last searched. Typing turns it
/// into the results, every landing section that holds a match under its own
/// heading. Every one is drawn in the card the app already draws it in,
/// with that card's own tap and long-press.
///
/// While the field has the cursor or holds text, Cancel stands at the end
/// of the row, outside the field ([SearchCancelButton]): it clears the
/// query, drops the keyboard and brings the landing back. The field narrows
/// to make room on the morph's spring.
class SearchTabScreen extends HookConsumerWidget {
  const SearchTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController();
    final focusNode = useFocusNode();

    // The field writes the app-wide search providers the page reads, which
    // the Events page's field (on Profile) shares. Coming back to this tab,
    // the page must show this field's query again, not that one's.
    void reclaimSharedQuery() {
      final text = controller.text.trim();
      if (ref.read(searchQueryProvider) != text) {
        ref.read(searchQueryProvider.notifier).state = text;
      }
      if (ref.read(debouncedSearchQueryProvider) != text) {
        ref.read(debouncedSearchQueryProvider.notifier).state = text;
      }
    }

    // The landing's sources live as long as the tab does, not only while the
    // landing is on screen: a search typed and cleared brings the landing
    // back at once, with nothing asked for again. Each is fetched once and
    // then only follows the live set.
    ref.listen(searchLiveNowProvider, (_, __) {});
    ref.listen(searchTopPlayersProvider, (_, __) {});
    ref.listen(searchLandingOpeningsProvider, (_, __) {});
    ref.listen(searchUpcomingProvider, (_, __) {});
    // The sections' pages read on from those heads, and the two read from
    // their first page; they last as long as the tab, so a row read far on
    // is still there after a search.
    ref.listen(searchTopPlayersFeedProvider, (_, __) {});
    ref.listen(searchOpeningsFeedProvider, (_, __) {});
    ref.listen(searchComingUpFeedProvider, (_, __) {});
    ref.listen(searchCollectionsFeedProvider, (_, __) {});
    ref.listen(searchNewsFeedProvider, (_, __) {});

    // Coming up is one read, read again while the tab lives: when one of
    // its events starts (it has moved to Live now; the read's spare events
    // fill in at once, the new read restocks them) and on arriving after
    // the read has grown old. The last read stays on screen meanwhile.
    final upcomingReadAt = useRef(DateTime.now());
    void readUpcomingAgain() {
      upcomingReadAt.value = DateTime.now();
      ref.invalidate(searchUpcomingProvider);
    }

    ref.listen<String>(searchLiveIdsKeyProvider, (previous, next) {
      final read = ref.read(searchUpcomingProvider).valueOrNull;
      if (read == null || next.isEmpty || previous == next) return;
      final before = previous == null || previous.isEmpty
          ? const <String>{}
          : previous.split('\n').toSet();
      final started = next.split('\n').where((id) => !before.contains(id));
      if (read.any((event) => searchEventIsLive(event, started))) {
        readUpcomingAgain();
      }
    });

    // Arriving on the tab (it stays alive once visited): a read or live
    // lookup that failed earlier gets another go. The field is left as it
    // was: arriving never takes the cursor or raises the keyboard.
    ref.listen<BottomNavBarItem>(selectedBottomNavBarItemProvider, (_, next) {
      if (next != BottomNavBarItem.search) return;
      if (ref.read(searchTopPlayersProvider).hasError) {
        ref.invalidate(searchTopPlayersProvider);
      }
      if (ref.read(searchUpcomingProvider).hasError ||
          DateTime.now().difference(upcomingReadAt.value) >
              searchUpcomingMaxAge) {
        readUpcomingAgain();
      }
      if (ref.read(searchLiveNowProvider.notifier).lookupFailed) {
        ref.invalidate(searchLiveNowProvider);
      }
      // A section whose first page failed is not shown: arriving reads it
      // again.
      if (searchFeedFirstPageFailed(ref.read(searchCollectionsFeedProvider))) {
        ref.invalidate(searchCollectionsFeedProvider);
      }
      if (searchFeedFirstPageFailed(ref.read(searchNewsFeedProvider))) {
        ref.invalidate(searchNewsFeedProvider);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        reclaimSharedQuery();
      });
    });
    final scroll = useScrollController();
    ref.listen<BottomNavBarReTapRequest>(bottomNavBarReTapRequestProvider, (
      previous,
      next,
    ) {
      if (next.item != BottomNavBarItem.search) return;
      if (previous != null && previous.sequence == next.sequence) return;
      ScrollChromeScope.maybeOf(context)?.show();
      // As every root does on a re-tap: the page goes back to its top (the
      // landing or the results, whichever is on screen), on the tabs'
      // spring. The field is left alone: a re-tap never raises the keyboard.
      if (scroll.hasClients) scroll.springToOffset(0, context: context);
    });
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        reclaimSharedQuery();
      });
      return null;
    }, const []);

    // While the field has the keyboard the bar holds still; reading results,
    // it steps away with them. Set from the focus change itself, never from
    // a build.
    final chrome = ScrollChromeScope.maybeOf(context);
    useEffect(() {
      if (chrome == null) return null;
      void hold() => chrome.held = focusNode.hasFocus;
      focusNode.addListener(hold);
      return () {
        focusNode.removeListener(hold);
        chrome.held = false;
      };
    }, [chrome, focusNode]);

    SearchRecentsNotifier recents() => ref.read(searchRecentsProvider.notifier);

    // A pick from the page: remembered in the tab's recent searches (with
    // the query it was found by, when it came from the results) and, for
    // the kinds the Events page's field shares, in its history too; then
    // the keyboard goes down. The card that was tapped gave its own
    // haptic; this adds none.
    void remember(SearchRecentPick pick, {RecentSearchEntry? shared}) {
      unawaited(recents().recordPick(pick));
      final query = controller.text.trim();
      if (isSearchableQuery(query)) unawaited(recents().recordQuery(query));
      if (shared != null) {
        unawaited(ref.read(recentSearchesProvider.notifier).record(shared));
      }
      FocusScope.of(context).unfocus();
    }

    void openEvent(GroupEventCardModel tournament) {
      remember(
        SearchRecentPick.event(tournament),
        shared: RecentSearchEntry.tournament(tournament),
      );
      openForYouEvent(
        context,
        ref,
        eventId: tournament.id,
        category: GroupEventCategory.search,
      );
    }

    void openPlayer(SearchPlayer player) {
      remember(
        SearchRecentPick.player(player),
        shared: RecentSearchEntry.player(player),
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerProfileScreen(
            fideId: player.fideId,
            playerName: player.name,
            title: player.title,
            federation: player.fed,
            rating: player.rating,
            gamebasePlayerId: player.gamebasePlayerId,
            memorialSourceIdentity: player.memorialSourceIdentity,
            memorialRouteId: player.memorialRouteId,
          ),
        ),
      );
    }

    void openOpening(OpeningSearchSelection opening) {
      remember(
        SearchRecentPick.opening(opening),
        shared: RecentSearchEntry.openingSelection(opening),
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SmartEventScreen(
            request: SmartEventRequest.forOpeningSelection(opening),
            // Opened from Search it is exactly what was searched for: no
            // Filters on it (the title's tier dropdown still moves it).
            showFilters: false,
          ),
        ),
      );
    }

    void openSmartEvent(SmartEventRequest request) {
      remember(SearchRecentPick.smartEvent(request));
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          // As its card opens it on the Search tab: no Filters.
          builder: (_) =>
              SmartEventScreen(request: request, showFilters: false),
        ),
      );
    }

    void collectionOpened(Collection collection) =>
        remember(SearchRecentPick.collection(collection));

    void newsOpened(FeedNews news) => remember(SearchRecentPick.news(news));

    final picks = useMemoized(
      () => SearchPicks(
        event: openEvent,
        player: openPlayer,
        opening: openOpening,
        smartEvent: openSmartEvent,
        collection: collectionOpened,
        news: newsOpened,
      ),
    );

    // A query committed from the keyboard's Search key.
    void submitted(String text) {
      final query = text.trim();
      if (isSearchableQuery(query)) unawaited(recents().recordQuery(query));
    }

    // Writes [text] to the field and the page's query at once (no
    // typing debounce): a recent query is searched the moment it is
    // picked.
    void putQuery(String text) {
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      ref.read(searchQueryProvider.notifier).state = text;
      ref.read(debouncedSearchQueryProvider.notifier).state = text;
      cancelSearchDebounce();
    }

    // A recent query's row: searched again, in front of the queries, the
    // keyboard down to read the results.
    void runQuery(String query) {
      putQuery(query);
      unawaited(recents().recordQuery(query));
      dismissSoftwareKeyboard(focusNode: focusNode);
    }

    // A recent query's arrow: back in the field, the cursor after it, to
    // go on typing.
    void fillQuery(String query) {
      putQuery(query);
      if (!focusNode.hasFocus) focusNode.requestFocus();
    }

    // Cancel: the query cleared, the keyboard down, the landing back.
    void cancel() {
      controller.clear();
      ref.read(searchQueryProvider.notifier).state = '';
      ref.read(debouncedSearchQueryProvider.notifier).state = '';
      cancelSearchDebounce();
      dismissSoftwareKeyboard(focusNode: focusNode);
    }

    // The one root bar ([HomeTopBarFrame]): the status bar's inset, then the
    // band with the field and its Cancel as its row and the standard gap
    // under it, so the field and the page under it land exactly where every
    // root's do. In the home shell the band steps away with the page and
    // back (X-style).
    final header = HomeTopBarFrame(
      child: Row(
        children: [
          Expanded(
            child: EnhancedRoundedSearchBar(
              controller: controller,
              focusNode: focusNode,
              showProfile: false,
              // The page under the field is the results; no drop-down over
              // it, and no filter: the event filter narrows Today, not a
              // search.
              dropdown: false,
              showFilter: false,
              // Cancel, beside the field, clears it.
              showClear: false,
              textInputAction: TextInputAction.search,
              onSubmitted: submitted,
              textFieldKey: const ValueKey('search_tab_field'),
              hintText: 'Search',
              rotatingHints: const [
                'player',
                'tournament',
                'openings',
                'FIDE country',
              ],
            ),
          ),
          SearchCancelButton(
            controller: controller,
            focusNode: focusNode,
            onCancel: cancel,
          ),
        ],
      ),
    );

    return Material(
      key: e2eKey(E2eIds.searchRoot),
      color: context.colors.background,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: Column(
            children: [
              header,
              Expanded(
                // The landing and the results scroll on it, so a re-tap of
                // the tab can take either back to its top.
                child: PrimaryScrollController(
                  controller: scroll,
                  // A star on this page (an event's, a smart event's) also
                  // keeps it in My Space; an unstar leaves My Space alone.
                  child: SpaceStarPins(
                    child: SearchTabPage(
                      key: const ValueKey('search_tab_page'),
                      picks: picks,
                      controller: controller,
                      focusNode: focusNode,
                      onRunQuery: runQuery,
                      onFillQuery: fillQuery,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The page under the Search tab's field, one of three:
///
/// * a query that can be searched (two letters or more): its results
///   ([SearchPageResultsLoader]), the last ones held while the next load;
/// * the field taking the cursor, or holding a letter, with recent searches
///   to offer: those ([SearchRecentsView]), over the landing, which keeps
///   its place and its rows' scroll underneath;
/// * otherwise the landing ([SearchPageLanding]).
///
/// Raw keystrokes reach it only when the query becomes (or stops being) a
/// search, so typing a search never rebuilds the landing.
class SearchTabPage extends ConsumerWidget {
  const SearchTabPage({
    super.key,
    required this.picks,
    required this.controller,
    required this.focusNode,
    required this.onRunQuery,
    required this.onFillQuery,
  });

  final SearchPicks picks;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onRunQuery;
  final ValueChanged<String> onFillQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searching = ref.watch(
      searchQueryProvider.select((raw) => isSearchableQuery(raw.trim())),
    );
    if (searching) {
      final debounced = ref.watch(debouncedSearchQueryProvider).trim();
      if (!isSearchableQuery(debounced)) return const SearchPageSpinner();
      return SearchPageResultsLoader(query: debounced, picks: picks);
    }
    final landing = SearchPageLanding(picks: picks);
    return ListenableBuilder(
      listenable: Listenable.merge([focusNode, controller]),
      builder: (context, _) {
        final active = focusNode.hasFocus || controller.text.isNotEmpty;
        return Consumer(
          builder: (context, ref, _) {
            final recents = active ? ref.watch(searchRecentsProvider) : null;
            final showRecents = recents != null && !recents.isEmpty;
            return Stack(
              fit: StackFit.expand,
              children: [
                // Kept, not rebuilt: Cancel brings the landing back where
                // the reader left it.
                Offstage(
                  offstage: showRecents,
                  child: TickerMode(enabled: !showRecents, child: landing),
                ),
                if (showRecents)
                  // Its own surface over the landing, which a row's press
                  // ink lands on.
                  Material(
                    color: context.colors.background,
                    child: SearchRecentsView(
                      recents: recents,
                      picks: picks,
                      focusNode: focusNode,
                      onRunQuery: onRunQuery,
                      onFillQuery: onFillQuery,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
