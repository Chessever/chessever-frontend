import 'dart:math';
import 'package:chessever2/screens/group_event/widget/all_events_tab_widget.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/home/home_screen.dart';
import 'package:chessever2/screens/home/home_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:chessever2/repository/local_storage/unified_favorites/unified_favorites_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/starred_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/search/enhanced_rounded_search_bar.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';

enum GroupEventCategory { past, current, upcoming }

final _mappedName = {
  GroupEventCategory.past: 'Past',
  GroupEventCategory.current: 'Current',
  GroupEventCategory.upcoming: 'Upcoming',
};

final selectedGroupCategoryProvider = StateProvider<GroupEventCategory>(
  (ref) => GroupEventCategory.current,
);

class GroupEventScreen extends HookConsumerWidget {
  const GroupEventScreen({super.key});

  void _showFilterPopup(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: kBlackColor.withOpacity(0.5),
      builder: (context) => const FilterPopup(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchController = useTextEditingController();
    final selectedTourEvent = ref.watch(selectedGroupCategoryProvider);
    final pageController = usePageController(
      initialPage: GroupEventCategory.values.indexOf(selectedTourEvent),
    );
    final pastScrollController = useScrollController();
    final isAnimating = useRef(false);
    final isSearching = useState(false);
    final focusNode = useFocusNode();

    useEffect(() {
      void onFocus() => isSearching.value = focusNode.hasFocus;
      focusNode.addListener(onFocus);
      return () => focusNode.removeListener(onFocus);
    }, [focusNode]);

    useEffect(() {
      final newIndex = GroupEventCategory.values.indexOf(selectedTourEvent);
      if (pageController.hasClients &&
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
    }, [selectedTourEvent]);

    ref.listen<GroupEventCategory>(selectedGroupCategoryProvider, (
      previous,
      next,
    ) {
      if (previous == null) return;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ref.read(searchQueryProvider.notifier).state = '';
          searchController.clear();
          FocusScope.of(context).unfocus();
          ref.read(groupEventScreenProvider.notifier).loadTours();
        }
      });
    });

    void onScroll() {
      if (!context.mounted || selectedTourEvent != GroupEventCategory.past) {
        return;
      }

      final max = pastScrollController.position.maxScrollExtent;
      final current = pastScrollController.position.pixels;
      if (max - current <= 200) {
        ref.read(groupEventScreenProvider.notifier).loadMorePast();
      }
    }

    useEffect(() {
      pastScrollController.addListener(onScroll);
      return () => pastScrollController.removeListener(onScroll);
    }, [pastScrollController, selectedTourEvent]);

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
                  onChanged:
                      (value) => ref
                          .read(groupEventScreenProvider.notifier)
                          .searchForTournament(value, selectedTourEvent),
                  onTournamentSelected:
                      (t) => ref
                          .read(groupEventScreenProvider.notifier)
                          .onSelectTournament(context: context, id: t.id),
                  onPlayerSelected: (player) {
                    FocusScope.of(context).unfocus();
                    searchController.text = player.name;
                    if (context.mounted) {
                      ref.read(searchQueryProvider.notifier).state =
                          player.name;
                    }
                  },
                  onFilterTap: () => _showFilterPopup(context),
                  onProfileTap:
                      () => HomeScreen.scaffoldKey.currentState?.openDrawer(),
                  onClearSearchField: () {
                    ref.read(groupEventScreenProvider.notifier).loadTours();
                  },
                ),
              ),
            ),
          ),

          SizedBox(height: 16.h),
          _SegmentedSwitcher(
            searchController: searchController,
            selectedTourEvent: selectedTourEvent,
            onSelectedChanged: (index) {
              final newCategory = GroupEventCategory.values[index];
              ref.invalidate(filterPopupProvider);
              ref.read(selectedGroupCategoryProvider.notifier).state =
                  newCategory;
            },
          ),

          SizedBox(height: 12.h),
          Expanded(
            child: PageView.builder(
              controller: pageController,
              itemCount: GroupEventCategory.values.length,
              onPageChanged: (index) {
                if (!isAnimating.value) {
                  final newCategory = GroupEventCategory.values[index];
                  ref.read(selectedGroupCategoryProvider.notifier).state =
                      newCategory;
                }
              },
              itemBuilder: (context, index) {
                final currentCategory = GroupEventCategory.values[index];
                final isPast = currentCategory == GroupEventCategory.past;
                final scrollController = isPast ? pastScrollController : null;
                print('Building page for $currentCategory');
                final selectedCategory = ref.watch(
                  selectedGroupCategoryProvider,
                );

                // Only load data for the currently selected tab
                if (currentCategory != selectedCategory) {
                  print(" Not the active tab, returning empty widget.");
                  return const Center(
                    child:
                        SizedBox.shrink(), // Return empty widget for non-active tabs
                  );
                }

                final controller = ref.watch(groupEventScreenProvider.notifier);
                final isLoadingMore = isPast && controller.isFetchingMore;

                return ref
                    .watch(groupEventScreenProvider)
                    .when(
                      data: (filteredEvents) {
                        // Combine old starred favorites with new unified favorites
                        final starredFavorites = ref.watch(starredProvider);
                        final unifiedFavoritesAsync = ref.watch(
                          favoriteEventsProvider,
                        );
                        final unifiedFavorites = unifiedFavoritesAsync
                            .maybeWhen(
                              data:
                                  (events) =>
                                      events
                                          .map((e) => e['id'] as String)
                                          .toList(),
                              orElse: () => <String>[],
                            );

                        // Combine both lists
                        final allFavorites =
                            <String>{
                              ...starredFavorites,
                              ...unifiedFavorites,
                            }.toList();

                        final isSearching =
                            searchController.text.trim().isNotEmpty;

                        final finalEvents =
                            isSearching
                                ? filteredEvents
                                : ref
                                    .read(tournamentSortingServiceProvider)
                                    .sortBasedOnFavorite(
                                      tours: filteredEvents,
                                      favorites: allFavorites,
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
    required this.onSelectedChanged,
  });

  final TextEditingController searchController;
  final GroupEventCategory selectedTourEvent;
  final ValueChanged<int> onSelectedChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameUpdate = ref.watch(searchQueryProvider);
    final realQuery = searchController.text.trim();

    final options =
        GroupEventCategory.values.map((category) {
          if (realQuery.isNotEmpty && category == selectedTourEvent) {
            return realQuery;
          } else {
            return _mappedName[category]!;
          }
        }).toList();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.sp),
      child: SegmentedSwitcher(
        backgroundColor: kBlackColor,
        selectedBackgroundColor: kBlackColor,
        options: options,
        currentSelection: GroupEventCategory.values.indexOf(selectedTourEvent),
        onSelectionChanged: onSelectedChanged,
      ),
    );
  }
}
