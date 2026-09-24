import 'dart:math' as math;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/screens/for_you/discovery/discovery_view.dart';
import 'package:chessever2/screens/for_you/open_for_you_event.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/screens/group_event/widget/for_you_games_widget.dart';
import 'package:chessever2/screens/group_event/widget/search_results_widget.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/my_space/my_space_view.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/search/enhanced_rounded_search_bar.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/stable_height_slot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// Builds the body of one For You page around the scroll controller the shell
/// owns for it (re-tapping the nav item scrolls that controller to the top).
typedef ForYouPageBuilder =
    Widget Function(
      BuildContext context,
      ForYouTab tab,
      ScrollController scrollController,
    );

/// The real pages. Today is the personalised feed that used to open the
/// Events screen, unchanged.
Widget buildForYouPage(
  BuildContext context,
  ForYouTab tab,
  ScrollController scrollController,
) {
  return switch (tab) {
    ForYouTab.mySpace => MySpaceView(scrollController: scrollController),
    ForYouTab.today => ForYouGamesWidget(scrollController: scrollController),
    ForYouTab.discovery => DiscoveryView(scrollController: scrollController),
  };
}

/// Scroll-to-top on re-tap settles on a spring, with no overshoot past the
/// top edge.
const CupertinoMotion _scrollTopMotion = CupertinoMotion.smooth(
  duration: Duration(milliseconds: 360),
);
final Curve _scrollTopCurve = _scrollTopMotion.toCurve;

/// The For You section: My Space | Today | Discovery under the same header
/// as Events (avatar, search with its filter, segmented tabs).
///
/// Typing in the header runs the Events global search: a transient Search
/// segment is appended while the query is non-empty and shows the same
/// results list; clearing it (or picking a tab) returns to the tab the user
/// was on. The picked tab holds for the session; a launch opens on Today.
class ForYouScreen extends HookConsumerWidget {
  const ForYouScreen({super.key, this.pageBuilder});

  /// Replaces the page bodies, so widget tests can drive the shell without
  /// the network-backed pages. Null in the app.
  @visibleForTesting
  final ForYouPageBuilder? pageBuilder;

  static const int _tabCount = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchController = useTextEditingController();
    final focusNode = useFocusNode();
    final selectedTab = ref.watch(selectedForYouTabProvider);
    final searchQuery = ref.watch(forYouSearchQueryProvider);
    final hasSearch = searchQuery.isNotEmpty;
    final pageCount = hasSearch ? _tabCount + 1 : _tabCount;
    final selectedIndex = hasSearch ? _tabCount : selectedTab.index;
    final appliedFilterState = ref.watch(eventAppliedFilterProvider);
    final filterBadgeCount =
        appliedFilterState.formatsAndStates.length +
        (appliedFilterState.hasEloFilter ? 1 : 0) +
        (appliedFilterState.eco.isAll ? 0 : 1);

    final pageController = usePageController(initialPage: selectedIndex);
    final mySpaceScrollController = useScrollController();
    final todayScrollController = useScrollController();
    final discoveryScrollController = useScrollController();
    final searchScrollController = useScrollController();
    // Set while the shell moves the PageView itself, so the resulting
    // onPageChanged is not mistaken for a swipe.
    final isJumping = useRef(false);
    // The page a swipe just selected. PageView reports a page as soon as the
    // offset rounds over to it, mid-drag or mid-fling, while the gesture is
    // still carrying the view there: the shell must not jump it.
    final swipedTo = useRef<int?>(null);
    final lastPageCount = useRef(pageCount);
    // The page the current build's PageView should rest on, read by syncs
    // that run after the build that set it.
    final restingIndex = useRef(selectedIndex);
    restingIndex.value = selectedIndex;
    // The pages the PageView shows, first to last: one at rest, two while a
    // swipe or its settle carries the view between them. Null until the
    // view first moves, which means the selected page alone.
    final shownPages = useState<(int, int)?>(null);
    // Watched so it lives exactly as long as this screen; written below.
    ref.watch(forYouTodayInViewProvider);

    ScrollController controllerForIndex(int index) {
      if (index >= _tabCount) return searchScrollController;
      return switch (ForYouTab.values[index]) {
        ForYouTab.mySpace => mySpaceScrollController,
        ForYouTab.today => todayScrollController,
        ForYouTab.discovery => discoveryScrollController,
      };
    }

    void scrollToTop(ScrollController controller) {
      if (!controller.hasClients) return;
      controller.animateTo(
        0,
        duration: _scrollTopMotion.duration,
        curve: _scrollTopCurve,
      );
    }

    // Moves the PageView onto the selected page when the shell changed the
    // selection (a segment tap, Search appearing or going). Compared on raw
    // pixels, not `page`: when Search goes, the offset sits past the new last
    // page and `page` already reads clamped, which would skip the jump and
    // leave the viewport's own settle to report a page change nobody asked
    // for. Unless [force]d, a scroll in flight is left alone: that is the
    // user's drag or fling, and the scroll-end listener below re-syncs once
    // it lets go.
    void syncPage({required bool force}) {
      if (!context.mounted || !pageController.hasClients) return;
      final position = pageController.position;
      if (!position.hasPixels || !position.hasViewportDimension) return;
      final index = restingIndex.value;
      final target = index * position.viewportDimension;
      if ((position.pixels - target).abs() < 0.5) return;
      if (!force && position.isScrollingNotifier.value) return;
      isJumping.value = true;
      pageController.jumpToPage(index);
      isJumping.value = false;
    }

    // Keep the PageView on the selected page. Deferred to after layout so
    // the page count change has reached the viewport and the jump never runs
    // mid-build. A selection the user swiped to is skipped outright. Search
    // going away is forced: the shrink itself starts a settle toward the old
    // last page, which is not a gesture to wait for.
    useEffect(() {
      final shrank = pageCount < lastPageCount.value;
      lastPageCount.value = pageCount;
      final fromSwipe = swipedTo.value == selectedIndex;
      swipedTo.value = null;
      if (fromSwipe) return null;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => syncPage(force: shrank),
      );
      return null;
    }, [selectedIndex, pageCount]);

    // Tracks which pages are in view as the PageView moves. The selection
    // flips at a swipe's halfway mark, so without this the page the swipe is
    // carrying in (before it) or leaving (after it) would render empty while
    // still half on screen. A page counts once more than a pixel of it shows,
    // so a settle that stops a hair off the edge leaves its neighbour unbuilt.
    useEffect(() {
      void track() {
        if (!pageController.hasClients) return;
        final position = pageController.position;
        if (!position.hasPixels || !position.hasViewportDimension) return;
        final viewport = position.viewportDimension;
        if (viewport <= 0) return;
        final page = position.pixels / viewport;
        final slack = 1 / viewport;
        final first = math.max(0, (page - 1 + slack).ceil());
        final last = math.max(first, (page + 1 - slack).floor());
        final next = (first, last);
        if (shownPages.value == next) return;
        final todayIndex = ForYouTab.today.index;
        final todayInView = first <= todayIndex && todayIndex <= last;
        void apply() {
          if (!context.mounted) return;
          shownPages.value = next;
          final inView = ref.read(forYouTodayInViewProvider.notifier);
          if (inView.state != todayInView) inView.state = todayInView;
        }

        // Scroll notifications can land inside layout (a viewport resize);
        // the tree cannot be dirtied there.
        if (SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks) {
          WidgetsBinding.instance.addPostFrameCallback((_) => apply());
        } else {
          apply();
        }
      }

      pageController.addListener(track);
      return () => pageController.removeListener(track);
    }, [pageController]);

    // The header's search bar writes the app-wide search providers, which the
    // Events header reads too. Leaving For You mid-search must not hand that
    // header a stale query, so drop it, but only while it is still this
    // field's text (Events may already have restored its own). Deferred:
    // providers cannot change during unmount.
    useEffect(() {
      final container = ProviderScope.containerOf(context, listen: false);
      return () {
        final text = searchController.text;
        if (text.isEmpty) return;
        Future<void>.microtask(() {
          try {
            if (container.read(searchQueryProvider) == text) {
              container.read(searchQueryProvider.notifier).state = '';
              container.read(isSearchingProvider.notifier).state = false;
            }
            if (container.read(debouncedSearchQueryProvider) == text) {
              container.read(debouncedSearchQueryProvider.notifier).state = '';
            }
          } catch (_) {
            // The whole scope went away with the screen; nothing to reset.
          }
        });
      };
    }, const []);

    // The reverse leak: this field always mounts empty, so anything the
    // shared providers hold now is another header's query (Events keeps its
    // own copy and restores it when it comes back). Left in place, focusing
    // this empty field would open on that query's results. Deferred: the
    // providers cannot change while the tree is building.
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || searchController.text.isNotEmpty) return;
        final staleQuery =
            ref.read(searchQueryProvider).isNotEmpty ||
            ref.read(debouncedSearchQueryProvider).isNotEmpty;
        if (!staleQuery) return;
        cancelSearchDebounce();
        ref.read(searchQueryProvider.notifier).state = '';
        ref.read(debouncedSearchQueryProvider.notifier).state = '';
        if (!focusNode.hasFocus) {
          ref.read(isSearchingProvider.notifier).state = false;
        }
      });
      return null;
    }, const []);

    void leaveSearch() {
      searchAnimatedEventIds.clear();
      ref.read(forYouSearchQueryProvider.notifier).state = '';
    }

    void selectTab(ForYouTab tab) {
      if (ref.read(forYouSearchQueryProvider).isNotEmpty) {
        // Clearing the field also resets the shared search providers the bar
        // drives; the query itself is cleared here so the tab switch is
        // immediate rather than waiting for the bar's debounce.
        searchController.clear();
        leaveSearch();
      }
      ref.read(selectedForYouTabProvider.notifier).select(tab);
      FocusScope.of(context).unfocus();
    }

    // Only Today and the Search page read this filter. Changed from My Space
    // or Discovery it would alter nothing on screen, so land on the feed it
    // filters. Apply always lands there (the user asked to see filtered
    // games); Reset only when it actually cleared something.
    void applyFilter(FilterPopupState next, {required bool isReset}) {
      final notifier = ref.read(eventAppliedFilterProvider.notifier);
      final changed = notifier.state != next;
      notifier.state = next;
      ref.invalidate(forYouEventsProvider);
      if (!context.mounted || (isReset && !changed)) return;
      if (ref.read(forYouSearchQueryProvider).isNotEmpty) return;
      if (ref.read(selectedForYouTabProvider) == ForYouTab.today) return;
      selectTab(ForYouTab.today);
    }

    ref.listen<BottomNavBarReTapRequest>(bottomNavBarReTapRequestProvider, (
      previous,
      next,
    ) {
      if (next.item != BottomNavBarItem.forYou) return;
      if (previous != null && previous.sequence == next.sequence) return;
      scrollToTop(controllerForIndex(selectedIndex));
    });

    // The segments share the top bar's gutter.
    final horizontalPadding = HomeTopBarMetrics.horizontalPadding;
    final buildPage = pageBuilder ?? buildForYouPage;

    return Material(
      key: e2eKey(E2eIds.forYouRoot),
      color: context.colors.background,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The home bar's shared frame: the same inset and gutter as
              // every other home tab, so the avatar never moves on a switch.
              HomeTopBarFrame(
                child: SizedBox(
                  width: double.infinity,
                  child: EnhancedRoundedSearchBar(
                    focusNode: focusNode,
                    controller: searchController,
                    textFieldKey: e2eKey(E2eIds.forYouSearchField),
                    filterButtonKey: e2eKey(E2eIds.forYouFilterButton),
                    hintText: 'Search',
                    rotatingHints: const [
                      'player',
                      'tournament',
                      'openings',
                      'FIDE country',
                    ],
                    filterBadgeCount: filterBadgeCount,
                    // Already debounced by the bar, so the query drives the
                    // search fan-out directly.
                    onChanged: (value) {
                      final trimmed = value.trim();
                      final notifier = ref.read(
                        forYouSearchQueryProvider.notifier,
                      );
                      if (trimmed.isNotEmpty) {
                        if (notifier.state != trimmed) notifier.state = trimmed;
                      } else if (notifier.state.isNotEmpty) {
                        leaveSearch();
                      }
                    },
                    onClearSearchField: leaveSearch,
                    onTournamentSelected: (tournament) => openForYouEvent(
                      context,
                      ref,
                      eventId: tournament.id,
                      category: GroupEventCategory.search,
                    ),
                    onPlayerSelected: (player) {
                      FocusScope.of(context).unfocus();
                      HapticFeedbackService.buttonPress();
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
                            memorialSourceIdentity:
                                player.memorialSourceIdentity,
                            memorialRouteId: player.memorialRouteId,
                          ),
                        ),
                      );
                    },
                    onOpeningSelected: (opening) {
                      FocusScope.of(context).unfocus();
                      HapticFeedbackService.buttonPress();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SmartEventScreen(
                            request: SmartEventRequest.forOpeningSelection(
                              opening,
                            ),
                          ),
                        ),
                      );
                    },
                    onFilterTap: () {
                      ref
                          .read(filterPopupProvider.notifier)
                          .setState(appliedFilterState);
                      showAlertModal<void>(
                        context: context,
                        horizontalPadding: 0,
                        child: FilterPopup(
                          onApplyFilters: (filterState) =>
                              applyFilter(filterState, isReset: false),
                          onResetFilters: () => applyFilter(
                            defaultFilterPopupState,
                            isReset: true,
                          ),
                        ),
                      );
                    },
                    onProfileTap: () => Scaffold.maybeOf(context)?.openDrawer(),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: _ForYouSegments(
                  selectedIndex: selectedIndex,
                  searchQuery: searchQuery,
                  onSelected: (index) {
                    if (index == selectedIndex) {
                      scrollToTop(controllerForIndex(index));
                      return;
                    }
                    if (index < _tabCount) selectTab(ForYouTab.values[index]);
                  },
                ),
              ),
              SizedBox(height: 12.h),
              Expanded(
                child: StableHeightSlot(
                  child: NotificationListener<ScrollEndNotification>(
                    // A selection made while a gesture owned the PageView (a
                    // segment tapped mid-fling) was left for the gesture to
                    // finish; put the view on it now. Deferred: the
                    // notification fires from inside the position's own
                    // activity change.
                    onNotification: (notification) {
                      if (notification.depth == 0 && !isJumping.value) {
                        Future<void>.microtask(() => syncPage(force: false));
                      }
                      return false;
                    },
                    child: PageView.builder(
                      controller: pageController,
                      itemCount: pageCount,
                      onPageChanged: (index) {
                        if (isJumping.value || index >= _tabCount) return;
                        final tab = ForYouTab.values[index];
                        // Already there: nothing to select, and no reason to
                        // drop the keyboard.
                        if (ref.read(forYouSearchQueryProvider).isEmpty &&
                            ref.read(selectedForYouTabProvider) == tab) {
                          return;
                        }
                        // A swipe onto a regular page leaves the search (the
                        // Search page is always last, so a swipe can only move
                        // off it, never onto it). The gesture is already
                        // carrying the view there, so the sync effect skips it.
                        swipedTo.value = index;
                        selectTab(tab);
                      },
                      itemBuilder: (context, index) {
                        // Built: the selected page and any page a swipe shows
                        // beside it. At rest that is the selected page alone;
                        // the others keep their provider caches, not their
                        // widget trees.
                        final shown = shownPages.value;
                        final inView =
                            shown != null &&
                            index >= shown.$1 &&
                            index <= shown.$2;
                        if (index >= pageCount ||
                            (index != selectedIndex && !inView)) {
                          return const SizedBox.shrink();
                        }
                        if (index >= _tabCount) {
                          return SearchResultsWidget(
                            scrollController: searchScrollController,
                            searchQuery: searchQuery,
                          );
                        }
                        return buildPage(
                          context,
                          ForYouTab.values[index],
                          controllerForIndex(index),
                        );
                      },
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

class _ForYouSegments extends StatelessWidget {
  const _ForYouSegments({
    required this.selectedIndex,
    required this.searchQuery,
    required this.onSelected,
  });

  final int selectedIndex;
  final String searchQuery;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = [
      for (final tab in ForYouTab.values) tab.label,
      if (searchQuery.isNotEmpty) forYouSearchTabTitle(searchQuery),
    ];
    final colors = context.colors;
    final current = selectedIndex.clamp(0, options.length - 1);
    return SegmentedSwitcher(
      backgroundColor: colors.popup,
      selectedBackgroundColor: colors.popup,
      options: options,
      // One line, scaled down rather than wrapped: with the Search segment
      // showing on a narrow phone at a large text scale, "My Space" would
      // otherwise break onto a second line the 40-high strip clips.
      //
      // Ink is set here, not left to the switcher: its default dims the
      // resting segments to 70% of a faint tab ink, under 4.5:1 in both
      // themes. Secondary ink at full strength clears it on the strip.
      // The strip has no thumb, so the selected label also steps up in
      // weight: ink alone is too small a change to read the page at a glance.
      optionLabels: [
        for (var i = 0; i < options.length; i++)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.w),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                options[i],
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color:
                      i == current ? colors.textPrimary : colors.textSecondary,
                  fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
      currentSelection: current,
      onSelectionChanged: onSelected,
      notifyOnReselect: true,
    );
  }
}

/// Title-cases the query for the Search segment and trims it at a word
/// boundary so it fits beside the three tabs: "magnus carlsen" reads
/// "Magnus…", "HIKARU" reads "Hikaru".
@visibleForTesting
String forYouSearchTabTitle(String query, {int maxLength = 12}) {
  final words = [
    for (final word in query.trim().split(RegExp(r'\s+')))
      if (word.isNotEmpty)
        word[0].toUpperCase() + word.substring(1).toLowerCase(),
  ];
  if (words.isEmpty) return 'Search';
  final full = words.join(' ');
  if (full.length <= maxLength) return full;

  final buffer = StringBuffer();
  for (final word in words) {
    final separator = buffer.isEmpty ? '' : ' ';
    if (buffer.length + separator.length + word.length > maxLength - 1) break;
    buffer
      ..write(separator)
      ..write(word);
  }
  if (buffer.isNotEmpty) return '$buffer…';
  return '${words.first.substring(0, maxLength - 1)}…';
}
