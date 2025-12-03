import 'dart:math';
import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/providers/search_games_provider.dart';
import 'package:chessever2/screens/group_event/widget/all_events_tab_widget.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/group_event_filter_provider.dart';
import 'package:chessever2/screens/group_event/widget/for_you_games_widget.dart';
import 'package:chessever2/screens/group_event/widget/search_results_widget.dart';
import 'package:chessever2/screens/home/home_screen.dart';
import 'package:chessever2/screens/home/home_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/search/enhanced_rounded_search_bar.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';

enum GroupEventCategory { past, current, forYou, search }

final _mappedName = {
  GroupEventCategory.past: 'Past',
  GroupEventCategory.current: 'Current',
  GroupEventCategory.forYou: 'For You',
  GroupEventCategory.search: 'Search',
};

/// Indicates whether there is at least one live game in the For You feed.
final hasLiveForYouProvider = Provider.autoDispose<bool>((ref) {
  final games = ref.watch(forYouGamesProvider).valueOrNull ?? [];
  return games.any((g) => g.status == '*');
});

final selectedGroupCategoryProvider = StateProvider<GroupEventCategory>(
  (ref) => GroupEventCategory.current,
);

class GroupEventScreen extends HookConsumerWidget {
  const GroupEventScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchController = useTextEditingController();
    final selectedTourEvent = ref.watch(selectedGroupCategoryProvider);
    final searchQuery = ref.watch(searchTabQueryProvider);
    final hasActiveSearch = searchQuery.trim().isNotEmpty;

    // Determine which categories to show (search tab only appears when searching)
    final visibleCategories = hasActiveSearch
        ? [GroupEventCategory.past, GroupEventCategory.current, GroupEventCategory.forYou, GroupEventCategory.search]
        : [GroupEventCategory.past, GroupEventCategory.current, GroupEventCategory.forYou];

    final pageController = usePageController(
      initialPage: visibleCategories.indexOf(selectedTourEvent).clamp(0, visibleCategories.length - 1),
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
      final newIndex = visibleCategories.indexOf(selectedTourEvent);
      if (newIndex >= 0 && pageController.hasClients &&
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
          FocusScope.of(context).unfocus();
          ref.refresh(groupEventScreenProvider);
        }
      });
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

    void onForYouScroll() {
      if (!context.mounted || selectedTourEvent != GroupEventCategory.forYou) {
        return;
      } else {
        final max = forYouScrollController.position.maxScrollExtent;
        final current = forYouScrollController.position.pixels;
        if (max - current <= 200) {
          ref.read(forYouGamesProvider.notifier).loadMore();
        }
      }
    }

    useEffect(() {
      pastScrollController.addListener(onScroll);
      return () => pastScrollController.removeListener(onScroll);
    }, [pastScrollController, selectedTourEvent]);

    useEffect(() {
      forYouScrollController.addListener(onForYouScroll);
      return () => forYouScrollController.removeListener(onForYouScroll);
    }, [forYouScrollController, selectedTourEvent]);

    return Material(
      color: kBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 16.h + MediaQuery.of(context).viewPadding.top),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.sp),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder:
                  (Widget child, Animation<double> animation) => FadeTransition(
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
                  hintText: 'Search Events or Players',
                  showProfile: !isSearching.value,
                  onChanged: (value) {
                    ref.read(groupEventScreenProvider.notifier)
                        .searchForTournament(value, selectedTourEvent);
                    // Update search tab query and trigger search
                    final trimmed = value.trim();
                    ref.read(searchTabQueryProvider.notifier).state = trimmed;
                    if (trimmed.isNotEmpty) {
                      ref.read(searchGamesProvider.notifier).loadGamesForSearch(value);
                      // Switch to search tab immediately when typing
                      ref.read(selectedGroupCategoryProvider.notifier).state = GroupEventCategory.search;
                    }
                  },
                  onTournamentSelected:
                      (t) => ref
                          .read(groupEventScreenProvider.notifier)
                          .onSelectTournament(context: context, id: t.id),
                  onPlayerSelected: (player) {
                    FocusScope.of(context).unfocus();
                    searchController.text = player.name;
                    if (context.mounted) {
                      ref.read(searchQueryProvider.notifier).state = player.name;
                      // Set search tab query and trigger search - tab appears automatically
                      ref.read(searchTabQueryProvider.notifier).state = player.name;
                      ref.read(searchGamesProvider.notifier).loadGamesForSearch(player.name);
                      // Switch to search tab
                      ref.read(selectedGroupCategoryProvider.notifier).state = GroupEventCategory.search;
                    }
                  },
                  onFilterTap:
                      () => showDialog(
                        context: context,
                        barrierColor: kBlackColor.withOpacity(0.5),
                        builder:
                            (cxt) => FilterPopup(
                              onApplyFilters: (filterState) async {
                                final filtered = await ref
                                    .read(groupEventFilterProvider)
                                    .applyAllFilters(
                                      filters:
                                          filterState.formatsAndStates.toList(),
                                      eloRange: filterState.eloRange,
                                      tournamentCategory: selectedTourEvent,
                                    );

                                ref
                                    .read(groupEventScreenProvider.notifier)
                                    .setFilteredModels(filtered);
                              },
                              onResetFilters: () async {
                                await ref
                                    .read(groupEventScreenProvider.notifier)
                                    .resetFilters();
                              },
                            ),
                      ),
                  onProfileTap: () => Scaffold.maybeOf(context)?.openDrawer(),
                  onClearSearchField: () {
                    ref.refresh(groupEventScreenProvider);
                    // Clear search tab state and switch back if on search tab
                    ref.read(searchTabQueryProvider.notifier).state = '';
                    ref.read(searchGamesProvider.notifier).clearSearch();
                    if (selectedTourEvent == GroupEventCategory.search) {
                      ref.read(selectedGroupCategoryProvider.notifier).state = GroupEventCategory.current;
                    }
                  },
                ),
              ),
            ),
          ),

          SizedBox(height: 16.h),
          _SegmentedSwitcher(
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
                } else if (newCategory == GroupEventCategory.current) {
                  controller = currentScrollController;
                } else if (newCategory == GroupEventCategory.search) {
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

              ref.invalidate(filterPopupProvider);
              ref.read(selectedGroupCategoryProvider.notifier).state =
                  newCategory;
            },
          ),

          SizedBox(height: 12.h),
          Expanded(
            child: PageView.builder(
              controller: pageController,
              itemCount: visibleCategories.length,
              onPageChanged: (index) {
                if (!isAnimating.value && index < visibleCategories.length) {
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
                final isCurrent = currentCategory == GroupEventCategory.current;
                final isForYou = currentCategory == GroupEventCategory.forYou;
                final isSearch = currentCategory == GroupEventCategory.search;
                final scrollController = isPast
                    ? pastScrollController
                    : isCurrent
                        ? currentScrollController
                        : isForYou
                            ? forYouScrollController
                            : isSearch
                                ? searchScrollController
                                : null;

                // Only load data for the currently selected tab
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
                        final favoritesAsync = ref.watch(favoriteEventsProvider);
                        final favoriteEvents = favoritesAsync.valueOrNull ?? [];

                        // Extract event IDs from favorites
                        final allFavorites = favoriteEvents
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
                        final cachedEventFavoritePlayers =
                            ref.watch(eventFavoritePlayersCacheProvider);

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
                                      favoriteTimestamps: favoriteTimestamps,
                                    );

                        return RefreshIndicator(
                          onRefresh: ref.read(homeScreenProvider).onPullRefresh,
                          color: kWhiteColor70,
                          backgroundColor: kDarkGreyColor,
                          displacement: 60.h,
                          strokeWidth: 3.w,
                          child: AllEventsTabWidget(
                            filteredEvents: finalEvents,
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
                                      TourEventCategory.values[Random().nextInt(
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
                      error: (error, stackTrace) => const GenericErrorWidget(),
                    );
              },
            ),
          ),
        ],
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
    final titleCased = query.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');

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
    ref.watch(searchQueryProvider);  // Watch to trigger rebuilds
    final searchTabQuery = ref.watch(searchTabQueryProvider);
    final hasLiveForYou = ref.watch(hasLiveForYouProvider);

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

      final showLiveDot = category == GroupEventCategory.forYou &&
          hasLiveForYou &&
          selectedTourEvent != GroupEventCategory.forYou;
      if (!showLiveDot) {
        return Text(baseLabel);
      }

      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(baseLabel),
          SizedBox(width: 6.w),
          const _LiveTabDot(),
        ],
      );
    }).toList();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.sp),
      child: SegmentedSwitcher(
        backgroundColor: kBlackColor,
        selectedBackgroundColor: kBlackColor,
        options: options,
        optionLabels: optionLabels,
        currentSelection: visibleCategories.indexOf(selectedTourEvent).clamp(0, visibleCategories.length - 1),
        onSelectionChanged: onSelectedChanged,
      ),
    );
  }
}

class _LiveTabDot extends StatelessWidget {
  const _LiveTabDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8.w,
      height: 8.h,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kPrimaryColor,
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withValues(alpha: 0.4),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}
