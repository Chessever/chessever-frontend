import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart' show routeObserver;
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
import 'package:chessever2/screens/my_space/actions/space_star_pin.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
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
import 'package:chessever2/widgets/page_back_float.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search/enhanced_rounded_search_bar.dart';
import 'package:chessever2/widgets/search/search_cancel_button.dart';
import 'package:chessever2/widgets/search/search_motion.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart'
    show PageBackButton, SearchHeaderMetrics;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Search's route, for the screen views analytics records by route name.
const String searchRouteName = '/search_screen';

/// Whether Search has been opened this session. From then on the home shell
/// keeps its landing's sources warm ([keepSearchLandingWarm]), as the dock's
/// Search tab did once visited, so every later visit opens on a landing
/// already read.
final searchOpenedProvider = StateProvider<bool>((ref) => false);

/// When Search's Coming up was last read: a visit after it has grown old
/// ([searchUpcomingMaxAge]) reads it again. Lives across visits with the
/// read it times.
final searchUpcomingReadAtProvider = StateProvider<DateTime?>((ref) => null);

/// Keeps Search's landing sources alive for the session once Search has
/// been opened ([searchOpenedProvider]): a later visit opens on a landing
/// already read, with nothing asked for again. Each source is fetched once
/// and then only follows the live set. Call from the build of a widget that
/// outlives every visit (the home shell).
void keepSearchLandingWarm(WidgetRef ref) {
  if (!ref.watch(searchOpenedProvider)) return;
  ref.listen(searchTopPlayersProvider, (_, __) {});
  ref.listen(searchLandingOpeningsProvider, (_, __) {});
  ref.listen(searchUpcomingProvider, (_, __) {});
  // The sections' pages read on from those heads, and the two read from
  // their first page; a row read far on is still there next visit.
  ref.listen(searchTopPlayersFeedProvider, (_, __) {});
  ref.listen(searchOpeningsFeedProvider, (_, __) {});
  ref.listen(searchComingUpFeedProvider, (_, __) {});
  ref.listen(searchCollectionsFeedProvider, (_, __) {});
  ref.listen(searchNewsFeedProvider, (_, __) {});
}

/// Search: the app-wide search (players, events, openings, smart events,
/// collections, news) as one page, behaving as X's search does. It opens
/// over Home from the Search button in the corner of My Space, Today and
/// Discovery ([open], `homeSearchFab`), where the 38.17 field stood over
/// all three; it left the dock, whose slot Collections holds now.
///
/// A pushed page in the pushed pages' language: the way back
/// ([PageBackButton], where every pushed page's chevron is) and the field
/// on one row under the status bar, the iOS back swipe and Android's back
/// leaving it. The row steps away as the page is read down and back (the
/// page's own scroll chrome), and the floating back ([PageBackFloat]) keeps
/// a way out in reach while it is away. Everything under the row is the
/// page.
///
/// Arriving never puts the cursor in the field: the landing is there to
/// read (the top players, the main openings and the built-in smart events,
/// the events coming up, the collections and the news), and the field takes
/// the cursor only when the reader taps it. With
/// the cursor in an empty field the page is the recent searches
/// ([SearchRecentsView]): the things last opened from Search, then the
/// queries last searched. Typing turns it into the results, every landing
/// section that holds a match under its own heading. Every one is drawn in
/// the card the app already draws it in, with that card's own tap and
/// long-press.
///
/// The search row is X's: while the field has the cursor the way back
/// squeezes out and the field starts on the gutter; while it has the cursor
/// or holds text, Cancel stands at the end of the row, outside the field
/// ([SearchCancelButton]): it clears the query, drops the keyboard and
/// brings the landing back. The field narrows to make room on the morph's
/// spring. The circled x inside the field, there while it holds words, only
/// empties it.
class SearchTabScreen extends HookConsumerWidget {
  const SearchTabScreen({super.key});

  /// Opens Search over the page [context] is on. The caller's button gives
  /// the press its haptic.
  static Future<void> open(BuildContext context) {
    final container = ProviderScope.containerOf(context, listen: false);
    container.read(searchOpenedProvider.notifier).state = true;
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: searchRouteName),
        builder: (_) => const SearchTabScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController();
    final focusNode = useFocusNode();
    // The page's own bars: the field's row steps away as the page is read
    // down, and back.
    final chrome = useScrollChromeController();

    // The field writes the app-wide search providers the page reads, which
    // the Events page's field (on Profile) shares. Arriving, the page must
    // show this field's query (none yet), not that one's.
    void reclaimSharedQuery() {
      final text = controller.text.trim();
      if (ref.read(searchQueryProvider) != text) {
        ref.read(searchQueryProvider.notifier).state = text;
      }
      if (ref.read(debouncedSearchQueryProvider) != text) {
        ref.read(debouncedSearchQueryProvider.notifier).state = text;
      }
    }

    // The shared query moves under the page while it is covered and as it
    // is uncovered: an event page leaving resets it, and the Events page
    // hands it back empty. Results opened from (an event, a player, an
    // opening) must still be there on the way back, as Home's Search
    // segment's were in 38.17: whenever the shared query leaves this
    // field's words, or the page is uncovered, the page takes them back.
    // After the frame: providers cannot change while the tree builds or
    // unmounts.
    void reclaimWhenInFront() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
        reclaimSharedQuery();
      });
    }

    ref.listen<String>(searchQueryProvider, (_, next) {
      if (next.trim() != controller.text.trim()) reclaimWhenInFront();
    });
    final route = ModalRoute.of(context);
    useEffect(() {
      if (route == null) return null;
      final watcher = _Uncovered(reclaimWhenInFront);
      routeObserver.subscribe(watcher, route);
      return () => routeObserver.unsubscribe(watcher);
    }, [route]);

    // The landing's sources live as long as the page does, and the home
    // shell holds them between visits ([keepSearchLandingWarm]): a search
    // typed and cleared brings the landing back at once, with nothing asked
    // for again.
    ref.listen(searchTopPlayersProvider, (_, __) {});
    ref.listen(searchLandingOpeningsProvider, (_, __) {});
    ref.listen(searchUpcomingProvider, (_, __) {});
    ref.listen(searchTopPlayersFeedProvider, (_, __) {});
    ref.listen(searchOpeningsFeedProvider, (_, __) {});
    ref.listen(searchComingUpFeedProvider, (_, __) {});
    ref.listen(searchCollectionsFeedProvider, (_, __) {});
    ref.listen(searchNewsFeedProvider, (_, __) {});

    // Coming up is one read, read again while the page is open when one of
    // its events starts (it is no longer coming up: it leaves the section,
    // the read's spare events fill in at once and the new read restocks
    // them), and on arriving after the read has grown old. The last read
    // stays on screen meanwhile.
    void readUpcomingAgain() {
      ref.read(searchUpcomingReadAtProvider.notifier).state = DateTime.now();
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

    // Arriving: a read that failed on an earlier visit gets another go, and
    // an old Coming up is read again. The field is left at
    // rest: arriving never takes the cursor or raises the keyboard.
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        reclaimSharedQuery();
        if (ref.read(searchTopPlayersProvider).hasError) {
          ref.invalidate(searchTopPlayersProvider);
        }
        final readAt = ref.read(searchUpcomingReadAtProvider);
        if (readAt == null) {
          // The first read is the one this visit started.
          ref.read(searchUpcomingReadAtProvider.notifier).state =
              DateTime.now();
        } else if (ref.read(searchUpcomingProvider).hasError ||
            DateTime.now().difference(readAt) > searchUpcomingMaxAge) {
          readUpcomingAgain();
        }
        // A section whose first page failed is not shown: arriving reads it
        // again.
        if (searchFeedFirstPageFailed(
          ref.read(searchCollectionsFeedProvider),
        )) {
          ref.invalidate(searchCollectionsFeedProvider);
        }
        if (searchFeedFirstPageFailed(ref.read(searchNewsFeedProvider))) {
          ref.invalidate(searchNewsFeedProvider);
        }
      });
      return null;
    }, const []);
    final scroll = useScrollController();

    // While the field has the keyboard the row holds still; reading results,
    // it steps away with them. Set from the focus change itself, never from
    // a build.
    useEffect(() {
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

    // The search row, in X's order: the field (the clear button in it while
    // it holds words), then Cancel ending on the gutter while the field has
    // the cursor or holds text. At rest the page's way back stands before
    // the field at [SearchHeaderMetrics.leadingInset], where every pushed
    // page's chevron is; with the cursor in the field it squeezes out and
    // the field starts on the gutter, as the full-page search headers'
    // field does. It sits right under the status bar's inset, as every
    // pushed page's back row does.
    final header = Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        0,
        0,
        SearchHeaderMetrics.gutter,
        HomeTopBarMetrics.bottomGap,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: SearchHeaderMetrics.rowHeight,
        ),
        child: Row(
          children: [
            _SearchBackSlot(focusNode: focusNode),
            Expanded(
              child: EnhancedRoundedSearchBar(
                controller: controller,
                focusNode: focusNode,
                showProfile: false,
                // The page under the field is the results; no drop-down over
                // it, and no filter: the event filter belongs to Events.
                dropdown: false,
                showFilter: false,
                // The page's own Cancel follows: it brings the landing back.
                showCancel: false,
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
      ),
    );

    final page = Column(
      children: [
        // The status bar's inset stays put: the row folds up to it, never
        // into it.
        SizedBox(height: MediaQuery.viewPaddingOf(context).top + 4.h),
        CollapsingChrome(controller: chrome, child: header),
        Expanded(
          child: ScrollChromeRegion(
            controller: chrome,
            // The landing and the results scroll on it, so the page's own
            // spring can take either back to its top.
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
        ),
      ],
    );

    return Scaffold(
      key: e2eKey(E2eIds.searchRoot),
      backgroundColor: context.colors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          // The row's way back stays in reach while the row is folded away.
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              page,
              PageBackFloat(controller: chrome),
            ],
          ),
        ),
      ),
    );
  }
}

/// The page under Search's field, one of three:
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
class SearchTabPage extends HookConsumerWidget {
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
    // The field's own words decide it, not the app-wide query they are
    // written to: another page moving that one (an event page leaving
    // resets it) must not take the results away from under the field.
    final searching = useListenableSelector(
      controller,
      () => isSearchableQuery(controller.text.trim()),
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

/// Calls [onUncovered] when the route above Search is popped.
class _Uncovered extends RouteAware {
  _Uncovered(this.onUncovered);

  final VoidCallback onUncovered;

  @override
  void didPopNext() => onUncovered();
}

/// The page's way back before the field, at
/// [SearchHeaderMetrics.leadingInset]. While the field has the cursor it
/// squeezes out on the field morph's spring ([SearchMotion.morph]) and the
/// row's start moves to the gutter with it, so the field ends up exactly
/// where the full-page search headers start theirs.
class _SearchBackSlot extends StatelessWidget {
  const _SearchBackSlot({required this.focusNode});

  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: focusNode,
      child: const PageBackButton(key: ValueKey('search_back')),
      builder: (context, back) => ParkedMotionBuilder(
        value: focusNode.hasFocus ? 1.0 : 0.0,
        motion: SearchMotion.morph,
        // Under reduced motion it goes, and comes back, at once, with
        // Cancel.
        active: !MediaQuery.disableAnimationsOf(context),
        child: back,
        builder: (context, value, back) {
          final away = value.clamp(0.0, 1.0);
          final shown = 1 - away;
          return Padding(
            padding: EdgeInsetsDirectional.only(
              start: lerpDouble(
                SearchHeaderMetrics.leadingInset,
                SearchHeaderMetrics.gutter,
                away,
              )!,
            ),
            child: IgnorePointer(
              ignoring: focusNode.hasFocus,
              child: ExcludeSemantics(
                excluding: shown <= 0,
                child: Align(
                  widthFactor: shown,
                  child: Transform.scale(
                    scale: shown,
                    child: TickerMode(enabled: shown > 0, child: back!),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
