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
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/search/search_landing.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search/enhanced_rounded_search_bar.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/search/search_overlay_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Search tab: the app-wide search (players, events, openings, FIDE
/// countries) as one page.
///
/// The field sits at the top; everything under it is the page. With nothing
/// typed the page is the landing: the recent searches, then the events in
/// play, the top players and the main openings, all real destinations, each
/// section only when it has something to list ([searchLiveNowProvider],
/// [searchTopPlayersProvider], [searchLandingOpeningsProvider]). Typing
/// turns it into the live results, openings then players then events, in
/// one column. The page is the same with the keyboard up or down: there is
/// no drop-down over it and no second results screen behind it. The field
/// scrolls away with the results and back (X-style).
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

    // Arriving on the tab (it stays alive once visited) or re-tapping it:
    // the field comes back into view with the cursor in it, and a ranking
    // read or live lookup that failed earlier gets another go.
    ref.listen<BottomNavBarItem>(selectedBottomNavBarItemProvider, (_, next) {
      if (next != BottomNavBarItem.search) return;
      if (ref.read(searchTopPlayersProvider).hasError) {
        ref.invalidate(searchTopPlayersProvider);
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
    ref.listen<BottomNavBarReTapRequest>(bottomNavBarReTapRequestProvider, (
      previous,
      next,
    ) {
      if (next.item != BottomNavBarItem.search) return;
      if (previous != null && previous.sequence == next.sequence) return;
      ScrollChromeScope.maybeOf(context)?.show();
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

    // A pick from the page: remembered as a recent search, then opened.
    void remember(RecentSearchEntry entry) {
      unawaited(ref.read(recentSearchesProvider.notifier).record(entry));
      FocusScope.of(context).unfocus();
      HapticFeedbackService.buttonPress();
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
          ),
        ),
      );
    }

    final chrome = ScrollChromeScope.maybeOf(context);
    final field = HomeTopBarFrame(
      statusBar: false,
      child: SizedBox(
        width: double.infinity,
        child: EnhancedRoundedSearchBar(
          controller: controller,
          focusNode: focusNode,
          showProfile: false,
          // The page under the field is the results; no drop-down over it,
          // and no filter: the event filter narrows Today, not a search.
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
              SizedBox(height: MediaQuery.viewPaddingOf(context).top),
              // While the keyboard is up the field holds still; reading
              // results, it steps away with them.
              ListenableBuilder(
                listenable: focusNode,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 8.h),
                  child: field,
                ),
                builder: (context, child) {
                  if (chrome == null) return child!;
                  chrome.held = focusNode.hasFocus;
                  return CollapsingChrome(controller: chrome, child: child!);
                },
              ),
              Expanded(
                child: SearchOverlay(
                  key: const ValueKey('search_tab_page'),
                  fullPage: true,
                  // The rows carry their own inset ([searchPageRowInset]);
                  // together with this they land on the field's gutter, in
                  // the one unit they use. The page itself runs edge to
                  // edge, so a row of opening cards scrolls out to the
                  // screen's edge instead of stopping short of it.
                  pageInset:
                      HomeTopBarMetrics.horizontalPadding - searchPageRowInset,
                  query: controller.text,
                  onTournamentTap: openEvent,
                  onPlayerTap: openPlayer,
                  onOpeningTap: openOpening,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
