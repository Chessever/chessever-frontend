import 'dart:async';
import 'dart:math';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/group_event/widget/search_results_widget.dart';
import 'package:chessever2/screens/group_event/widget/all_events_tab_widget.dart';
import 'package:chessever2/screens/group_event/widget/events_load_error_state.dart';
import 'package:chessever2/screens/group_event/widget/upcoming_events_empty_state.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/home/home_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/home_live_first_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/text_scale.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart'
    show PageBackButton;
import 'package:chessever2/widgets/search/enhanced_rounded_search_bar.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessever2/widgets/stable_height_slot.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/live_first_capsule.dart';
import 'package:chessever2/widgets/page_spring.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';

/// The Events section's lists: Past | Current | Upcoming
/// ([eventsHomeCategories]), plus [search] while a query is active. The
/// personalised feed is not an Events list; it lives in For You > Today.
enum GroupEventCategory { past, current, upcoming, search }

/// The Events segments shown when no search is active, in display order.
const eventsHomeCategories = <GroupEventCategory>[
  GroupEventCategory.past,
  GroupEventCategory.current,
  GroupEventCategory.upcoming,
];

/// The segments the Events switcher renders. Search is appended (never
/// inserted) so the home segments keep their page index while a query runs.
List<GroupEventCategory> visibleEventCategories({
  required bool hasActiveSearch,
}) => hasActiveSearch
    ? const [...eventsHomeCategories, GroupEventCategory.search]
    : eventsHomeCategories;

/// Provider for the current search query used in search tab
final searchTabQueryProvider = StateProvider<String>((ref) => '');

final _mappedName = {
  GroupEventCategory.past: 'Past',
  GroupEventCategory.current: 'Current',
  GroupEventCategory.upcoming: 'Upcoming',
  GroupEventCategory.search: 'Search',
};

/// The list Events opens on unless a Premium viewer picked another (hold a
/// segment, or hold the Events tab while on it). Search is a transient
/// segment, never a start page.
const GroupEventCategory kDefaultEventsCategory = GroupEventCategory.current;

const String defaultEventsCategoryPrefsKey = 'default_events_tab_v1';

GroupEventCategory readDefaultEventsCategory() {
  final name = SharedPreferencesService.instance.prefsOrNull?.getString(
    defaultEventsCategoryPrefsKey,
  );
  if (name == null) return kDefaultEventsCategory;
  for (final category in eventsHomeCategories) {
    if (category.name == name) return category;
  }
  return kDefaultEventsCategory;
}

Future<void> writeDefaultEventsCategory(GroupEventCategory category) async {
  assert(eventsHomeCategories.contains(category));
  final prefs =
      SharedPreferencesService.instance.prefsOrNull ??
      await SharedPreferencesService.instance.ensureInitialized();
  await prefs?.setString(defaultEventsCategoryPrefsKey, category.name);
}

/// The Events segment label, shared with the start-screen confirmation.
String groupEventCategoryLabel(GroupEventCategory category) =>
    _mappedName[category]!;

final selectedGroupCategoryProvider = StateProvider<GroupEventCategory>(
  (ref) => readDefaultEventsCategory(),
);

final groupEventSearchTabControllerProvider =
    Provider<GroupEventSearchTabController>(GroupEventSearchTabController.new);

class GroupEventSearchTabController {
  GroupEventSearchTabController(this._ref);

  final Ref _ref;
  GroupEventCategory _categoryBeforeSearch = readDefaultEventsCategory();

  /// The list Events returns to when the search ends: the one the viewer was
  /// on before it began.
  GroupEventCategory get categoryBeforeSearch => _categoryBeforeSearch;

  void showSearch() {
    final currentCategory = _ref.read(selectedGroupCategoryProvider);
    if (currentCategory != GroupEventCategory.search) {
      _categoryBeforeSearch = currentCategory;
    }
    _ref.read(selectedGroupCategoryProvider.notifier).state =
        GroupEventCategory.search;
  }

  void restorePreviousTab() {
    if (_ref.read(selectedGroupCategoryProvider) != GroupEventCategory.search) {
      return;
    }
    _ref.read(selectedGroupCategoryProvider.notifier).state =
        _categoryBeforeSearch;
  }
}

/// Builds the body of one Events list around the scroll controller the screen
/// owns for it (re-tapping the nav item scrolls that controller to the top).
typedef GroupEventPageBuilder =
    Widget Function(
      BuildContext context,
      GroupEventCategory category,
      ScrollController scrollController,
    );

class GroupEventScreen extends HookConsumerWidget {
  const GroupEventScreen({super.key, this.pageBuilder});

  /// Replaces the list bodies, so widget tests can drive the screen (its top
  /// bar above all) without the network- and database-backed lists. Null in
  /// the app.
  @visibleForTesting
  final GroupEventPageBuilder? pageBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchController = useTextEditingController();
    final searchTabDebounce = useRef<Timer?>(null);
    useEffect(
      () =>
          () => searchTabDebounce.value?.cancel(),
      const [],
    );
    final selectedTourEvent = ref.watch(selectedGroupCategoryProvider);
    final searchQuery = ref.watch(searchTabQueryProvider);
    final hasActiveSearch = searchQuery.trim().isNotEmpty;
    final appliedFilterState = ref.watch(eventAppliedFilterProvider);

    int activeFilterCount(FilterPopupState state) {
      return state.formatsAndStates.length +
          (state.hasEloFilter ? 1 : 0) +
          (state.eco.isAll ? 0 : 1);
    }

    final filterBadgeCount = activeFilterCount(appliedFilterState);

    // Search tab only appears when searching.
    final visibleCategories = visibleEventCategories(
      hasActiveSearch: hasActiveSearch,
    );
    // Search can outlive its query by a frame while the tab is restored; show
    // Current then instead of whatever page the index clamp would land on.
    final activeCategory = visibleCategories.contains(selectedTourEvent)
        ? selectedTourEvent
        : GroupEventCategory.current;

    final pageController = usePageController(
      initialPage: visibleCategories.indexOf(activeCategory),
    );
    final pastScrollController = useScrollController();
    final currentScrollController = useScrollController();
    final upcomingScrollController = useScrollController();
    final searchScrollController = useScrollController();
    // Category changes still moving the pages: the pages passed on the way
    // pick no category. A count, as a category tapped mid-flight turns the
    // spring toward it and the guard holds until the last one lands.
    final pagingFlights = useRef(0);
    final focusNode = useFocusNode();
    final chrome = useScrollChromeController();
    // While the field has the keyboard the bar holds still, shown: the
    // field sits on the bar, outside the lists' region, so the page holds
    // it ([ScrollChromeController.held]) and the bar springs back if it was
    // away, instead of snapping as a disabled region would.
    useEffect(() {
      void hold() => chrome.held = focusNode.hasFocus;
      hold();
      focusNode.addListener(hold);
      return () => focusNode.removeListener(hold);
    }, [focusNode, chrome]);

    // The field's panel reads the app-wide search providers, which the
    // Search tab's field writes too. This page opens with its own query (or
    // none): what those providers hold now is the Search tab's, and focusing
    // this field must not open on its results. Leaving, it hands them back
    // empty; the Search tab takes its own query back when it is shown.
    // Deferred: providers cannot change while the tree builds or unmounts.
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final own = searchController.text.trim();
        if (ref.read(searchQueryProvider) == own &&
            ref.read(debouncedSearchQueryProvider) == own) {
          return;
        }
        cancelSearchDebounce();
        ref.read(searchQueryProvider.notifier).state = own;
        ref.read(debouncedSearchQueryProvider.notifier).state = own;
      });
      final container = ProviderScope.containerOf(context, listen: false);
      return () {
        final text = searchController.text.trim();
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
            // The whole scope went away with the page; nothing to reset.
          }
        });
      };
    }, const []);
    // A new segment opens with its bar in view.
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) chrome.show();
      });
      return null;
    }, [activeCategory]);

    ScrollController scrollControllerFor(GroupEventCategory category) {
      return switch (category) {
        GroupEventCategory.past => pastScrollController,
        GroupEventCategory.upcoming => upcomingScrollController,
        GroupEventCategory.search => searchScrollController,
        GroupEventCategory.current => currentScrollController,
      };
    }

    // No `isSearching` state here on purpose. Mirroring the focus node into a
    // hook rebuilt this entire screen — four tabs, their lists and the
    // PageView — on the frame the keyboard came up, right as the search field
    // started its morph. The avatar now collapses from inside the search bar,
    // which listens to the focus node itself.

    useEffect(() {
      if (!focusNode.hasFocus && searchController.text != searchQuery) {
        searchController.value = TextEditingValue(
          text: searchQuery,
          selection: TextSelection.collapsed(offset: searchQuery.length),
        );
      }
      return null;
    }, [searchQuery, focusNode]);

    useEffect(() {
      final newIndex = visibleCategories.indexOf(activeCategory);
      if (newIndex >= 0 &&
          pageController.hasClients &&
          pageController.page?.round() != newIndex) {
        pagingFlights.value++;
        PageSpring.to(
          pageController,
          newIndex,
          context: context,
        ).then((_) => pagingFlights.value--);
      }
      return null;
    }, [activeCategory, visibleCategories]);

    ref.listen<GroupEventCategory>(selectedGroupCategoryProvider, (
      previous,
      next,
    ) {
      if (previous == null) return;
      // Don't clear search when switching TO the search tab
      // Only clear when switching between non-search tabs
      if (next == GroupEventCategory.search) return;

      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          // Only clear search-related state if we're leaving the search tab
          if (previous == GroupEventCategory.search) {
            ref.read(searchQueryProvider.notifier).state = '';
            ref.read(searchTabQueryProvider.notifier).state = '';
            searchController.clear();
          }
          FocusScope.of(context).unfocus();
          // ignore: unused_result
          ref.refresh(groupEventScreenProvider);
        }
      });
    });

    // Live first just came on over Current: bring its top, now the live
    // events, into view. From another segment Current opens fresh.
    void showCurrentTop() {
      if (activeCategory != GroupEventCategory.current ||
          !currentScrollController.hasClients) {
        return;
      }
      currentScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }

    // Past pages in as its end comes near: on a scroll, and on a change of
    // the list's size or its viewport (a page landing, a spinner going, the
    // bars folding), so a list that stops short of the screen asks for the
    // next page without waiting for a scroll that cannot come.
    void onScroll() {
      if (!context.mounted ||
          activeCategory != GroupEventCategory.past ||
          !pastScrollController.hasClients) {
        return;
      }
      final position = pastScrollController.position;
      if (!position.hasContentDimensions) return;
      if (position.maxScrollExtent - position.pixels <= 200) {
        ref.read(groupEventScreenProvider.notifier).loadMorePast();
      }
    }

    useEffect(() {
      pastScrollController.addListener(onScroll);
      return () => pastScrollController.removeListener(onScroll);
    }, [pastScrollController, activeCategory]);

    // The segments share the top bar's gutter.
    final horizontalPadding = HomeTopBarMetrics.horizontalPadding;

    // The page is its own Scaffold, so Live first floats in the button slot
    // every page's floating buttons use ([SlidingFabs] over an
    // [InkFabStack]), on the window's insets, and a snack it raises lands
    // above it rather than over it.
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: context.colors.background,
      // Live first floats in the thumb's reach (Trello #1420), while an
      // event is in play, while its count is not known yet, or while it is
      // on, and steps away with the bar as the list scrolls.
      floatingActionButton: SlidingFabs(
        controller: chrome,
        child: InkFabStack(
          children: [
            EventsLiveFirstFab(
              key: const ValueKey(kHomeLiveFirstButtonKey),
              onTurnedOn: showCurrentTop,
            ),
          ],
        ),
      ),
      body: Material(
        key: e2eKey(E2eIds.eventsRoot),
        color: context.colors.background,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The status bar's inset stays put; the bar under it scrolls
                    // away with the list and back (X-style), the search field and
                    // the segments together.
                    SizedBox(height: MediaQuery.viewPaddingOf(context).top),
                    CollapsingChrome(
                      controller: chrome,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          HomeTopBarFrame(
                            statusBar: false,
                            // Plain SizedBox, not an AnimatedSwitcher: the switcher's child
                            // key never changed, so it never transitioned — it only added a
                            // Stack for the search bar's own morph to relayout through
                            // every frame.
                            child: SizedBox(
                              width: double.infinity,
                              // The bar's geometry is the reference every home tab
                              // matches. Live first floats over the list as its own
                              // capsule (EventsLiveFirstFab), not in the field.
                              child: EnhancedRoundedSearchBar(
                                focusNode: focusNode,
                                controller: searchController,
                                textFieldKey: e2eKey(E2eIds.eventsSearchField),
                                filterButtonKey: e2eKey(
                                  E2eIds.eventsFilterButton,
                                ),
                                hintText: 'Search',
                                rotatingHints: const [
                                  'player',
                                  'tournament',
                                  'openings',
                                  'FIDE country',
                                ],
                                filterBadgeCount: filterBadgeCount,
                                onChanged: (value) {
                                  // Tab switch is instant; the query that drives the
                                  // search fan-out (network + local scoring) is
                                  // debounced so keystrokes never trigger heavy work.
                                  final trimmed = value.trim();
                                  final previousQuery = ref.read(
                                    searchTabQueryProvider,
                                  );
                                  searchTabDebounce.value?.cancel();
                                  if (trimmed.isNotEmpty) {
                                    ref
                                        .read(
                                          groupEventSearchTabControllerProvider,
                                        )
                                        .showSearch();
                                    if (previousQuery.isEmpty) {
                                      // First keystroke must apply instantly: the search
                                      // tab is only rendered while the query is
                                      // non-empty (sub-2-char queries short-circuit in
                                      // the provider, so this is cheap).
                                      ref
                                              .read(
                                                searchTabQueryProvider.notifier,
                                              )
                                              .state =
                                          trimmed;
                                    } else {
                                      searchTabDebounce.value = Timer(
                                        const Duration(milliseconds: 300),
                                        () {
                                          ref
                                                  .read(
                                                    searchTabQueryProvider
                                                        .notifier,
                                                  )
                                                  .state =
                                              trimmed;
                                        },
                                      );
                                    }
                                  } else {
                                    ref
                                            .read(
                                              searchTabQueryProvider.notifier,
                                            )
                                            .state =
                                        '';
                                    if (previousQuery.isNotEmpty) {
                                      // Only switch tabs when user actively clears a
                                      // non-empty search (not on tapping an empty field)
                                      searchAnimatedEventIds.clear();
                                      ref
                                          .read(
                                            groupEventSearchTabControllerProvider,
                                          )
                                          .restorePreviousTab();
                                      // ignore: unused_result
                                      ref.refresh(groupEventScreenProvider);
                                    }
                                  }
                                },
                                onTournamentSelected: (t) => ref
                                    .read(groupEventScreenProvider.notifier)
                                    .onSelectTournament(
                                      context: context,
                                      id: t.id,
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
                                        gamebasePlayerId:
                                            player.gamebasePlayerId,
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
                                        request:
                                            SmartEventRequest.forOpeningSelection(
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
                                      onApplyFilters: (filterState) {
                                        ref
                                                .read(
                                                  eventAppliedFilterProvider
                                                      .notifier,
                                                )
                                                .state =
                                            filterState;
                                        ref.invalidate(forYouEventsProvider);
                                      },
                                      onResetFilters: () {
                                        ref
                                                .read(
                                                  eventAppliedFilterProvider
                                                      .notifier,
                                                )
                                                .state =
                                            defaultFilterPopupState;
                                        ref.invalidate(forYouEventsProvider);
                                      },
                                    ),
                                  );
                                },
                                showProfile: false,
                                leading: const PageBackButton(
                                  key: ValueKey('events_back'),
                                ),
                                onClearSearchField: () {
                                  // ignore: unused_result
                                  ref.refresh(groupEventScreenProvider);
                                  // Clear search tab state and switch back if on search tab
                                  ref
                                          .read(searchTabQueryProvider.notifier)
                                          .state =
                                      '';
                                  searchAnimatedEventIds.clear();
                                  ref
                                      .read(
                                        groupEventSearchTabControllerProvider,
                                      )
                                      .restorePreviousTab();
                                },
                              ),
                            ),
                          ),

                          SizedBox(height: 16.h),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontalPadding,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _SegmentedSwitcher(
                                    searchController: searchController,
                                    selectedTourEvent: activeCategory,
                                    visibleCategories: visibleCategories,
                                    onSelectedChanged: (index) {
                                      final newCategory =
                                          visibleCategories[index];
                                      final currentCategory = activeCategory;

                                      // If tapping the same tab, scroll to top
                                      if (newCategory == currentCategory) {
                                        final controller = scrollControllerFor(
                                          newCategory,
                                        );

                                        if (controller.hasClients) {
                                          controller.animateTo(
                                            0,
                                            duration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            curve: Curves.easeOutCubic,
                                          );
                                        }
                                        return; // Don't change category
                                      }

                                      ref
                                              .read(
                                                selectedGroupCategoryProvider
                                                    .notifier,
                                              )
                                              .state =
                                          newCategory;
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),

                          SizedBox(height: 12.h),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ScrollChromeRegion(
                        controller: chrome,
                        child: NotificationListener<ScrollMetricsNotification>(
                          // The list in a page, one scrollable below the
                          // pager: Past asks for its next page when its end
                          // comes into reach without a scroll.
                          onNotification: (notification) {
                            if (notification.depth == 1 &&
                                notification.metrics.axis == Axis.vertical) {
                              onScroll();
                            }
                            return false;
                          },
                          child: StableHeightSlot(
                            child: PageView.builder(
                              controller: pageController,
                              itemCount: visibleCategories.length,
                              onPageChanged: (index) {
                                if (pagingFlights.value == 0 &&
                                    index < visibleCategories.length) {
                                  final newCategory = visibleCategories[index];
                                  ref
                                          .read(
                                            selectedGroupCategoryProvider
                                                .notifier,
                                          )
                                          .state =
                                      newCategory;
                                }
                              },
                              itemBuilder: (context, index) {
                                if (index >= visibleCategories.length) {
                                  return const SizedBox.shrink();
                                }
                                final currentCategory =
                                    visibleCategories[index];
                                final isPast =
                                    currentCategory == GroupEventCategory.past;
                                final isUpcoming =
                                    currentCategory ==
                                    GroupEventCategory.upcoming;
                                final isSearch =
                                    currentCategory ==
                                    GroupEventCategory.search;
                                final scrollController = scrollControllerFor(
                                  currentCategory,
                                );

                                // Only load data for the currently selected tab. Heavy
                                // tabs keep their provider caches, not their widget trees.
                                if (currentCategory != activeCategory) {
                                  return const SizedBox.shrink();
                                }

                                final buildPage = pageBuilder;
                                if (buildPage != null) {
                                  return buildPage(
                                    context,
                                    currentCategory,
                                    scrollController,
                                  );
                                }

                                // Special handling for "Search" tab - show search results
                                if (isSearch) {
                                  return SearchResultsWidget(
                                    scrollController: searchScrollController,
                                    searchQuery: searchQuery,
                                  );
                                }

                                return ref
                                    .watch(groupEventScreenProvider)
                                    .when(
                                      data: (filteredEvents) {
                                        final isLoadingMore =
                                            isPast &&
                                            ref
                                                .read(
                                                  groupEventScreenProvider
                                                      .notifier,
                                                )
                                                .isFetchingMore;

                                        // Get favorites from unified favorites system (Supabase + local cache)
                                        final favoritesAsync = ref.watch(
                                          favoriteEventsProvider,
                                        );
                                        final favoriteEvents =
                                            favoritesAsync.valueOrNull ?? [];

                                        // Extract event IDs from favorites
                                        final allFavorites = favoriteEvents
                                            .map((e) => e.eventId)
                                            .where((id) => id.isNotEmpty)
                                            .toList();

                                        // Build timestamp map for sorting within groups
                                        final favoriteTimestamps =
                                            <String, DateTime>{};
                                        for (final fav in favoriteEvents) {
                                          favoriteTimestamps[fav.eventId] =
                                              fav.createdAt;
                                        }

                                        final isSearching = searchController
                                            .text
                                            .trim()
                                            .isNotEmpty;

                                        // Get cached favorite player data (populated by event cards as they render)
                                        final cachedEventFavoritePlayers = ref
                                            .watch(
                                              eventFavoritePlayersCacheProvider,
                                            );

                                        // Past keeps its date order; Upcoming keeps its
                                        // soonest-first order with starred events pinned
                                        // on top; Current ranks favourites and hearts.
                                        final List<GroupEventCardModel>
                                        finalEvents;
                                        if (isSearching || isPast) {
                                          finalEvents = filteredEvents;
                                        } else if (isUpcoming) {
                                          finalEvents = sortUpcomingEvents(
                                            filteredEvents,
                                            starredIds: allFavorites.toSet(),
                                          );
                                        } else {
                                          // Live first is laid over the ranking here
                                          // too: re-ranking the favourites would undo
                                          // the order the list arrives in.
                                          final liveFirst = ref.watch(
                                            homeEventsLiveFirstProvider,
                                          );
                                          finalEvents = currentEventsDisplayOrder(
                                            events: filteredEvents,
                                            sorter: ref.read(
                                              tournamentSortingServiceProvider,
                                            ),
                                            favorites: allFavorites,
                                            eventFavoritePlayersMap:
                                                cachedEventFavoritePlayers,
                                            favoriteTimestamps:
                                                favoriteTimestamps,
                                            liveFirst: liveFirst,
                                            liveIds: liveFirst
                                                ? homeLiveEventIds(
                                                    strict: ref
                                                        .watch(
                                                          liveGroupBroadcastIdsProvider,
                                                        )
                                                        .valueOrNull,
                                                    mirror: ref.watch(
                                                      liveBroadcastIdsProvider,
                                                    ),
                                                  )
                                                : const <String>{},
                                          );
                                        }
                                        return RefreshIndicator(
                                          onRefresh: ref
                                              .read(homeScreenProvider)
                                              .onEventsPullRefresh,
                                          color: context.colors.textSecondary,
                                          backgroundColor:
                                              context.colors.surface,
                                          displacement: 60.h,
                                          strokeWidth: 3.w,
                                          child:
                                              isUpcoming && finalEvents.isEmpty
                                              ? UpcomingEventsEmptyState(
                                                  filtersActive:
                                                      filterBadgeCount > 0,
                                                  onResetFilters: () {
                                                    HapticFeedbackService.buttonPress();
                                                    ref
                                                            .read(
                                                              eventAppliedFilterProvider
                                                                  .notifier,
                                                            )
                                                            .state =
                                                        defaultFilterPopupState;
                                                    ref.invalidate(
                                                      forYouEventsProvider,
                                                    );
                                                  },
                                                  scrollController:
                                                      scrollController,
                                                )
                                              : AllEventsTabWidget(
                                                  filteredEvents: finalEvents,
                                                  onSelect:
                                                      (
                                                        tourEventCardModel,
                                                      ) => ref
                                                          .read(
                                                            groupEventScreenProvider
                                                                .notifier,
                                                          )
                                                          .onSelectTournament(
                                                            context: context,
                                                            id: tourEventCardModel
                                                                .id,
                                                          ),
                                                  isLoadingMore: isLoadingMore,
                                                  paged: isPast,
                                                  scrollController:
                                                      scrollController,
                                                  clearsFloatingButtons: true,
                                                ),
                                        );
                                      },
                                      loading: () => SkeletonWidget(
                                        child: AllEventsTabWidget(
                                          onSelect: (_) {},
                                          filteredEvents: List.generate(
                                            10,
                                            (index) => GroupEventCardModel(
                                              id: 'tour_001',
                                              title:
                                                  'World Chess Championship 2025',
                                              dates: 'Mar 15 - 25,2025',
                                              timeUntilStart:
                                                  'Starts in 8 months',
                                              tourEventCategory:
                                                  TourEventCategory
                                                      .values[Random().nextInt(
                                                    TourEventCategory
                                                        .values
                                                        .length,
                                                  )],
                                              maxAvgElo: 0,
                                              timeControl: 'Standard',
                                              endDate: null,
                                              startDate: null,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // A failed load (nothing cached to fall back on)
                                      // says so and offers Retry on every tab; only a
                                      // successful empty load shows an empty state.
                                      error: (error, stackTrace) => RefreshIndicator(
                                        onRefresh: ref
                                            .read(homeScreenProvider)
                                            .onEventsPullRefresh,
                                        color: context.colors.textSecondary,
                                        backgroundColor: context.colors.surface,
                                        displacement: 60.h,
                                        strokeWidth: 3.w,
                                        child: EventsLoadErrorState(
                                          key: ValueKey(
                                            'events_load_error_${currentCategory.name}',
                                          ),
                                          error: error,
                                          fallbackMessage: isUpcoming
                                              ? "Couldn't load upcoming events."
                                              : "Couldn't load these events.",
                                          scrollController: scrollController,
                                          onRetry: () {
                                            HapticFeedbackService.buttonPress();
                                            unawaited(
                                              ref
                                                  .read(
                                                    groupEventScreenProvider
                                                        .notifier,
                                                  )
                                                  .loadTours(),
                                            );
                                          },
                                        ),
                                      ),
                                    );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentedSwitcher extends ConsumerWidget {
  const _SegmentedSwitcher({
    required this.searchController,
    required this.selectedTourEvent,
    required this.visibleCategories,
    required this.onSelectedChanged,
  });

  final TextEditingController searchController;
  final GroupEventCategory selectedTourEvent;
  final List<GroupEventCategory> visibleCategories;
  final ValueChanged<int> onSelectedChanged;

  /// Formats search query for tab display with title casing and smart truncation.
  /// Examples:
  ///   "magnus carlsen" -> "Magnus Carlsen"
  ///   "world championship 2024" -> "World Cham…" (truncated gracefully)
  ///   "HIKARU" -> "Hikaru"
  String _formatSearchTabTitle(String query, {int maxLength = 12}) {
    if (query.isEmpty) return query;

    // Apply title case: capitalize first letter of each word
    final titleCased = query
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');

    // If it fits, return as-is
    if (titleCased.length <= maxLength) {
      return titleCased;
    }

    // Smart truncation: try to break at word boundary
    final words = titleCased.split(' ');
    final buffer = StringBuffer();

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final separator = i > 0 ? ' ' : '';
      final potentialLength = buffer.length + separator.length + word.length;

      // If adding this word would exceed limit (leaving room for ellipsis)
      if (potentialLength > maxLength - 1) {
        // If we have at least one word, truncate at word boundary
        if (buffer.isNotEmpty) {
          return '${buffer.toString().trim()}…';
        }
        // First word is too long, truncate mid-word
        return '${word.substring(0, maxLength - 1)}…';
      }

      if (i > 0) buffer.write(' ');
      buffer.write(word);
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Tab labels depend only on the debounced query; watching the raw
    // per-keystroke searchQueryProvider here rebuilt the whole tab bar on
    // every character for no benefit.
    final searchTabQuery = ref.watch(searchTabQueryProvider);

    final options = visibleCategories.map((category) {
      if (category == GroupEventCategory.search && searchTabQuery.isNotEmpty) {
        return _formatSearchTabTitle(searchTabQuery);
      }
      return _mappedName[category]!;
    }).toList();

    final optionLabels = visibleCategories.map((category) {
      String baseLabel;
      if (category == GroupEventCategory.search && searchTabQuery.isNotEmpty) {
        baseLabel = _formatSearchTabTitle(searchTabQuery);
      } else {
        baseLabel = _mappedName[category]!;
      }
      // Above the default size a label scales down rather than wrap
      // into a second line the strip would clip.
      if (context.textGrowth > 1) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(baseLabel, maxLines: 1, softWrap: false),
        );
      }
      return Text(baseLabel);
    }).toList();

    return SegmentedSwitcher(
      dotScope: 'events.tab',
      height: context.textExtent(40.h),
      backgroundColor: context.colors.popup,
      selectedBackgroundColor: context.colors.popup,
      options: options,
      optionLabels: optionLabels,
      currentSelection: visibleCategories
          .indexOf(selectedTourEvent)
          .clamp(0, visibleCategories.length - 1),
      onSelectionChanged: onSelectedChanged,
      notifyOnReselect: true,
    );
  }
}

/// The key of the Events lists' Live first button.
const String kHomeLiveFirstButtonKey = 'events_live_first_button';

/// Live first on the Events lists (Trello #1420), the live mark on a glass
/// disc ([LiveFirstCapsule]) floating where the thumb rests. Its tooltip and
/// what is read aloud count exactly the events a press lifts (Current's
/// events in play under its filters, [eventsLiveEventCountProvider]),
/// leaving the number out until it is known; one tap lists the live events
/// first, from any segment ([pressHomeEventsLiveFirst]). It only reorders
/// ([LiveFirstMode.reorder]): every event stays listed. It is there while an
/// event is in play, while the count is not known, or while it is on
/// ([showsHomeLiveFirst]), so a flag left on can always be turned off. The
/// page's only floating button, so the regular disc.
/// [onTurnedOn] runs once it has come on.
class EventsLiveFirstFab extends ConsumerWidget {
  const EventsLiveFirstFab({super.key, this.onTurnedOn});

  final VoidCallback? onTurnedOn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(homeEventsLiveFirstProvider);
    final liveCount = ref.watch(eventsLiveEventCountProvider);
    if (!showsHomeLiveFirst(liveCount: liveCount, on: on)) {
      return const SizedBox.shrink();
    }
    return LiveFirstCapsule(
      subject: 'events',
      size: InkFabSize.regular,
      on: on,
      liveCount: liveCount,
      onTap: () {
        if (pressHomeEventsLiveFirst(context: context, ref: ref)) {
          onTurnedOn?.call();
        }
      },
    );
  }
}
