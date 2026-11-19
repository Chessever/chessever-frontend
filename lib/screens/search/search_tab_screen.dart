import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/for_you/open_for_you_event.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/my_space/actions/space_star_pin.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/search/search_landing.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search/enhanced_rounded_search_bar.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/search/search_overlay_widget.dart';
import 'package:chessever2/widgets/page_spring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Search tab: the app-wide search (players, events, openings, FIDE
/// countries) as one page.
///
/// The field sits in the home bar's frame ([HomeTopBarFrame]), where every
/// root tab starts; everything under it is the page. With nothing typed the
/// page is the landing: the recent searches, the events in play, the top
/// players, the main openings and the built-in smart events, the events
/// coming up. Typing turns it into the results: players, openings, events.
/// Every one is drawn in the card the app already draws it in (event cards,
/// player cards, Rankings rows, smart event cards) with that card's own tap
/// and long-press, so a pick here behaves as it does everywhere else. The
/// page is the same with the keyboard up or down; the field scrolls away
/// with it and back (X-style), and holds still while it has the keyboard.
///
/// Opening the tab puts the cursor in the field, so it is one tap from
/// typing.
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

    void focusIfEmpty() {
      if (controller.text.isEmpty && !focusNode.hasFocus) {
        focusNode.requestFocus();
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

    // Arriving on the tab (it stays alive once visited) or re-tapping it:
    // the field comes back into view with the cursor in it, and a read or
    // live lookup that failed earlier gets another go.
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        reclaimSharedQuery();
        focusIfEmpty();
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
      // spring, and the field takes the cursor.
      scroll.springToOffset(0, context: context);
      focusNode.requestFocus();
    });
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        reclaimSharedQuery();
        focusIfEmpty();
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

    // A pick from the page: remembered as a recent search, then opened. The
    // card that was tapped gave its own haptic; this adds none.
    void remember(RecentSearchEntry entry) {
      unawaited(ref.read(recentSearchesProvider.notifier).record(entry));
      FocusScope.of(context).unfocus();
    }

    void openEvent(GroupEventCardModel tournament) {
      remember(RecentSearchEntry.tournament(tournament));
      openForYouEvent(
        context,
        ref,
        eventId: tournament.id,
        category: GroupEventCategory.search,
      );
    }

    void openPlayer(SearchPlayer player) {
      remember(RecentSearchEntry.player(player));
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
      remember(RecentSearchEntry.openingSelection(opening));
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

    // The one root bar ([HomeTopBarFrame]): the status bar's inset, then the
    // band with the field as its row and the standard gap under it, so the
    // field and the page under it land exactly where every root's do. In the
    // home shell the band steps away with the page and back (X-style).
    final header = HomeTopBarFrame(
      child: EnhancedRoundedSearchBar(
        controller: controller,
        focusNode: focusNode,
        showProfile: false,
        // The page under the field is the results; no drop-down over it, and
        // no filter: the event filter narrows Today, not a search.
        dropdown: false,
        showFilter: false,
        textFieldKey: const ValueKey('search_tab_field'),
        hintText: 'Search',
        rotatingHints: const [
          'player',
          'tournament',
          'openings',
          'FIDE country',
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
                    child: SearchOverlay(
                      key: const ValueKey('search_tab_page'),
                      fullPage: true,
                      query: controller.text,
                      onTournamentTap: openEvent,
                      onPlayerTap: openPlayer,
                      onOpeningTap: openOpening,
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
