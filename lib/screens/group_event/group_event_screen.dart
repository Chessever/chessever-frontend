import 'dart:async';
import 'dart:math';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/screens/group_event/widget/search_results_widget.dart';
import 'package:chessever2/screens/group_event/widget/all_events_tab_widget.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/group_event/widget/for_you_games_widget.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/home/home_screen_provider.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/search/enhanced_rounded_search_bar.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';

enum GroupEventCategory { past, current, forYou, search }

/// Provider for the current search query used in search tab
final searchTabQueryProvider = StateProvider<String>((ref) => '');

final _mappedName = {
  GroupEventCategory.past: 'Past',
  GroupEventCategory.current: 'Current',
  GroupEventCategory.forYou: 'For You',
  GroupEventCategory.search: 'Search',
};

final selectedGroupCategoryProvider = StateProvider<GroupEventCategory>(
  (ref) => GroupEventCategory.forYou,
);

class GroupEventScreen extends HookConsumerWidget {
  const GroupEventScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchController = useTextEditingController();
    final selectedTourEvent = ref.watch(selectedGroupCategoryProvider);
    final searchQuery = ref.watch(searchTabQueryProvider);
    final hasActiveSearch = searchQuery.trim().isNotEmpty;
    final appliedFilterState = ref.watch(eventAppliedFilterProvider);
    final dismissedSmartEventCardKeys = ref.watch(
      dismissedSmartEventCardKeysProvider,
    );

    int activeFilterCount(FilterPopupState state) {
      return state.formatsAndStates.length + (state.hasEloFilter ? 1 : 0);
    }

    final filterBadgeCount = activeFilterCount(appliedFilterState);

    // Determine which categories to show (search tab only appears when searching)
    final visibleCategories =
        hasActiveSearch
            ? [
              GroupEventCategory.forYou,
              GroupEventCategory.current,
              GroupEventCategory.past,
              GroupEventCategory.search,
            ]
            : [
              GroupEventCategory.forYou,
              GroupEventCategory.current,
              GroupEventCategory.past,
            ];

    final pageController = usePageController(
      initialPage: visibleCategories
          .indexOf(selectedTourEvent)
          .clamp(0, visibleCategories.length - 1),
    );
    final pastScrollController = useScrollController();
    final currentScrollController = useScrollController();
    final forYouScrollController = useScrollController();
    final searchScrollController = useScrollController();
    final isAnimating = useRef(false);
    final isSearching = useState(false);
    final focusNode = useFocusNode();

    useEffect(() {
      void onFocus() => isSearching.value = focusNode.hasFocus;
      focusNode.addListener(onFocus);
      return () => focusNode.removeListener(onFocus);
    }, [focusNode]);

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
      final newIndex = visibleCategories.indexOf(selectedTourEvent);
      if (newIndex >= 0 &&
          pageController.hasClients &&
          pageController.page?.round() != newIndex) {
        isAnimating.value = true;
        pageController
            .animateToPage(
              newIndex,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeInOut,
            )
            .then((_) => isAnimating.value = false);
      }
      return null;
    }, [selectedTourEvent, visibleCategories]);

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
          if (next == GroupEventCategory.forYou) {
            unawaited(ref.read(forYouEventsProvider.notifier).refreshIfStale());
          }
          FocusScope.of(context).unfocus();
          // ignore: unused_result
          ref.refresh(groupEventScreenProvider);
        }
      });
    });

    void scrollActiveEventsTabToTop() {
      final ScrollController target;
      if (selectedTourEvent == GroupEventCategory.forYou) {
        target = forYouScrollController;
      } else if (selectedTourEvent == GroupEventCategory.past) {
        target = pastScrollController;
      } else if (selectedTourEvent == GroupEventCategory.current) {
        target = currentScrollController;
      } else {
        target = searchScrollController;
      }
      if (!target.hasClients) return;
      target.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }

    ref.listen<BottomNavBarReTapRequest>(bottomNavBarReTapRequestProvider, (
      previous,
      next,
    ) {
      if (next.item == BottomNavBarItem.tournaments) {
        scrollActiveEventsTabToTop();
      }
    });

    void onScroll() {
      if (!context.mounted || selectedTourEvent != GroupEventCategory.past) {
        return;
      } else {
        final max = pastScrollController.position.maxScrollExtent;
        final current = pastScrollController.position.pixels;
        if (max - current <= 200) {
          ref.read(groupEventScreenProvider.notifier).loadMorePast();
        }
      }
    }

    useEffect(() {
      pastScrollController.addListener(onScroll);
      return () => pastScrollController.removeListener(onScroll);
    }, [pastScrollController, selectedTourEvent]);

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );

    return Material(
      key: e2eKey(E2eIds.eventsRoot),
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
              SizedBox(height: 24.h + MediaQuery.of(context).viewPadding.top),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder:
                      (Widget child, Animation<double> animation) =>
                          FadeTransition(
                            opacity: animation,
                            child: SizeTransition(
                              sizeFactor: animation,
                              axis: Axis.horizontal,
                              child: child,
                            ),
                          ),
                  child: SizedBox(
                    width: double.infinity,
                    key: const ValueKey('search_bar'),
                    child: EnhancedRoundedSearchBar(
                      focusNode: focusNode,
                      controller: searchController,
                      textFieldKey: e2eKey(E2eIds.eventsSearchField),
                      filterButtonKey: e2eKey(E2eIds.eventsFilterButton),
                      hintText: 'Search',
                      rotatingHints: const [
                        'player',
                        'tournament',
                        'openings',
                        'FIDE country',
                      ],
                      showProfile: !isSearching.value,
                      filterBadgeCount: filterBadgeCount,
                      onChanged: (value) {
                        ref
                            .read(groupEventScreenProvider.notifier)
                            .searchForTournament(value, selectedTourEvent);
                        // Update search tab query
                        final trimmed = value.trim();
                        final previousQuery = ref.read(searchTabQueryProvider);
                        ref.read(searchTabQueryProvider.notifier).state =
                            trimmed;
                        if (trimmed.isNotEmpty) {
                          // Switch to search tab immediately when typing
                          ref
                              .read(selectedGroupCategoryProvider.notifier)
                              .state = GroupEventCategory.search;
                        } else if (previousQuery.isNotEmpty) {
                          // Only switch tabs when user actively clears a non-empty search
                          // (not when tapping on an already empty field)
                          searchAnimatedEventIds.clear();
                          ref
                              .read(selectedGroupCategoryProvider.notifier)
                              .state = GroupEventCategory.current;
                          // ignore: unused_result
                          ref.refresh(groupEventScreenProvider);
                        }
                      },
                      onTournamentSelected:
                          (t) => ref
                              .read(groupEventScreenProvider.notifier)
                              .onSelectTournament(context: context, id: t.id),
                      onPlayerSelected: (player) {
                        FocusScope.of(context).unfocus();
                        HapticFeedbackService.buttonPress();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) => PlayerProfileScreen(
                                  fideId: player.fideId,
                                  playerName: player.name,
                                  title: player.title,
                                  federation: player.fed,
                                  rating: player.rating,
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
                                  .read(eventAppliedFilterProvider.notifier)
                                  .state = filterState;
                              ref.invalidate(forYouEventsProvider);
                            },
                            onResetFilters: () {
                              ref
                                  .read(eventAppliedFilterProvider.notifier)
                                  .state = defaultFilterPopupState;
                              ref.invalidate(forYouEventsProvider);
                            },
                          ),
                        );
                      },
                      onProfileTap:
                          () => Scaffold.maybeOf(context)?.openDrawer(),
                      onClearSearchField: () {
                        // ignore: unused_result
                        ref.refresh(groupEventScreenProvider);
                        // Clear search tab state and switch back if on search tab
                        ref.read(searchTabQueryProvider.notifier).state = '';
                        searchAnimatedEventIds.clear();
                        if (selectedTourEvent == GroupEventCategory.search) {
                          ref
                              .read(selectedGroupCategoryProvider.notifier)
                              .state = GroupEventCategory.current;
                        }
                      },
                    ),
                  ),
                ),
              ),

              SizedBox(height: 16.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Row(
                  children: [
                    Expanded(
                      child: _SegmentedSwitcher(
                        searchController: searchController,
                        selectedTourEvent: selectedTourEvent,
                        visibleCategories: visibleCategories,
                        onSelectedChanged: (index) {
                          final newCategory = visibleCategories[index];
                          final currentCategory = selectedTourEvent;

                          // If tapping the same tab, scroll to top
                          if (newCategory == currentCategory) {
                            ScrollController? controller;
                            if (newCategory == GroupEventCategory.forYou) {
                              controller = forYouScrollController;
                            } else if (newCategory == GroupEventCategory.past) {
                              controller = pastScrollController;
                            } else if (newCategory ==
                                GroupEventCategory.current) {
                              controller = currentScrollController;
                            } else if (newCategory ==
                                GroupEventCategory.search) {
                              controller = searchScrollController;
                            }

                            if (controller != null && controller.hasClients) {
                              controller.animateTo(
                                0,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                              );
                            }
                            return; // Don't change category
                          }

                          ref
                              .read(selectedGroupCategoryProvider.notifier)
                              .state = newCategory;
                        },
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 12.h),
              Expanded(
                child: PageView.builder(
                  controller: pageController,
                  itemCount: visibleCategories.length,
                  onPageChanged: (index) {
                    if (!isAnimating.value &&
                        index < visibleCategories.length) {
                      final newCategory = visibleCategories[index];
                      ref.read(selectedGroupCategoryProvider.notifier).state =
                          newCategory;
                    }
                  },
                  itemBuilder: (context, index) {
                    if (index >= visibleCategories.length) {
                      return const SizedBox.shrink();
                    }
                    final currentCategory = visibleCategories[index];
                    final isPast = currentCategory == GroupEventCategory.past;
                    final isCurrent =
                        currentCategory == GroupEventCategory.current;
                    final isForYou =
                        currentCategory == GroupEventCategory.forYou;
                    final isSearch =
                        currentCategory == GroupEventCategory.search;
                    final scrollController =
                        isPast
                            ? pastScrollController
                            : isCurrent
                            ? currentScrollController
                            : isForYou
                            ? forYouScrollController
                            : isSearch
                            ? searchScrollController
                            : null;

                    // Only load data for the currently selected tab. Heavy
                    // tabs keep their provider caches, not their widget trees.
                    if (currentCategory != selectedTourEvent) {
                      return const SizedBox.shrink();
                    }

                    // Special handling for "Search" tab - show search results
                    if (isSearch) {
                      return SearchResultsWidget(
                        scrollController: searchScrollController,
                        searchQuery: searchQuery,
                      );
                    }

                    // Special handling for "For You" tab - show games instead of events
                    if (isForYou) {
                      return ForYouGamesWidget(
                        scrollController: forYouScrollController,
                      );
                    }

                    return ref
                        .watch(groupEventScreenProvider)
                        .when(
                          data: (filteredEvents) {
                            final isLoadingMore =
                                isPast &&
                                ref
                                    .read(groupEventScreenProvider.notifier)
                                    .isFetchingMore;

                            // Get favorites from unified favorites system (Supabase + local cache)
                            final favoritesAsync = ref.watch(
                              favoriteEventsProvider,
                            );
                            final favoriteEvents =
                                favoritesAsync.valueOrNull ?? [];

                            // Extract event IDs from favorites
                            final allFavorites =
                                favoriteEvents
                                    .map((e) => e.eventId)
                                    .where((id) => id.isNotEmpty)
                                    .toList();

                            // Build timestamp map for sorting within groups
                            final favoriteTimestamps = <String, DateTime>{};
                            for (final fav in favoriteEvents) {
                              favoriteTimestamps[fav.eventId] = fav.createdAt;
                            }

                            final isSearching =
                                searchController.text.trim().isNotEmpty;

                            // Get cached favorite player data (populated by event cards as they render)
                            final cachedEventFavoritePlayers = ref.watch(
                              eventFavoritePlayersCacheProvider,
                            );

                            // Disable favorite prioritization for past events
                            final shouldApplyFavoriteSorting =
                                currentCategory != GroupEventCategory.past;

                            final finalEvents =
                                isSearching || !shouldApplyFavoriteSorting
                                    ? filteredEvents
                                    : ref
                                        .read(tournamentSortingServiceProvider)
                                        .sortBasedOnFavorite(
                                          tours: filteredEvents,
                                          favorites: allFavorites,
                                          eventFavoritePlayersMap:
                                              cachedEventFavoritePlayers,
                                          favoriteTimestamps:
                                              favoriteTimestamps,
                                        );
                            final smartData =
                                isCurrent
                                    ? visibleSmartEventCardData(
                                      SmartEventCardData.fromState(
                                        filter: appliedFilterState,
                                        events: finalEvents,
                                        source: SmartEventSource.current,
                                      ),
                                      dismissedSmartEventCardKeys,
                                    )
                                    : null;

                            return RefreshIndicator(
                              onRefresh:
                                  ref.read(homeScreenProvider).onPullRefresh,
                              color: context.colors.textSecondary,
                              backgroundColor: context.colors.surface,
                              displacement: 60.h,
                              strokeWidth: 3.w,
                              child: AllEventsTabWidget(
                                filteredEvents: finalEvents,
                                smartData: smartData,
                                onSelect:
                                    (tourEventCardModel) => ref
                                        .read(groupEventScreenProvider.notifier)
                                        .onSelectTournament(
                                          context: context,
                                          id: tourEventCardModel.id,
                                        ),
                                isLoadingMore: isLoadingMore,
                                scrollController: scrollController,
                              ),
                            );
                          },
                          loading:
                              () => SkeletonWidget(
                                child: AllEventsTabWidget(
                                  onSelect: (_) {},
                                  filteredEvents: List.generate(
                                    10,
                                    (index) => GroupEventCardModel(
                                      id: 'tour_001',
                                      title: 'World Chess Championship 2025',
                                      dates: 'Mar 15 - 25,2025',
                                      timeUntilStart: 'Starts in 8 months',
                                      tourEventCategory:
                                          TourEventCategory.values[Random()
                                              .nextInt(
                                                TourEventCategory.values.length,
                                              )],
                                      maxAvgElo: 0,
                                      timeControl: 'Standard',
                                      endDate: null,
                                      startDate: null,
                                    ),
                                  ),
                                ),
                              ),
                          error:
                              (error, stackTrace) => const GenericErrorWidget(),
                        );
                  },
                ),
              ),
            ],
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
    ref.watch(searchQueryProvider); // Watch to trigger rebuilds
    final searchTabQuery = ref.watch(searchTabQueryProvider);

    final options =
        visibleCategories.map((category) {
          if (category == GroupEventCategory.search &&
              searchTabQuery.isNotEmpty) {
            return _formatSearchTabTitle(searchTabQuery);
          }
          return _mappedName[category]!;
        }).toList();

    final optionLabels =
        visibleCategories.map((category) {
          String baseLabel;
          if (category == GroupEventCategory.search &&
              searchTabQuery.isNotEmpty) {
            baseLabel = _formatSearchTabTitle(searchTabQuery);
          } else {
            baseLabel = _mappedName[category]!;
          }
          return Text(baseLabel);
        }).toList();

    return SegmentedSwitcher(
      backgroundColor: kBlackColor,
      selectedBackgroundColor: kBlackColor,
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
