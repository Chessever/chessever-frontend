import 'dart:math';
import 'package:chessever2/screens/group_event/widget/all_events_tab_widget.dart';
import 'package:chessever2/screens/home/home_screen.dart';
import 'package:chessever2/screens/home/home_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/starred_provider.dart';
import 'package:chessever2/widgets/filter_popup.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/search/enhanced_rounded_search_bar.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../widgets/segmented_switcher.dart';

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
      barrierColor: Colors.black.withOpacity(0.5),
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

    final isSearching = useState(false);
    final focusNode = useFocusNode();

    useEffect(() {
      void onFocus() => isSearching.value = focusNode.hasFocus;
      focusNode.addListener(onFocus);
      return () => focusNode.removeListener(onFocus);
    }, [focusNode]);

    useEffect(() {
      final newIndex = GroupEventCategory.values.indexOf(selectedTourEvent);
      if (pageController.hasClients) {
        pageController.animateToPage(
          newIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
      return null;
    }, [selectedTourEvent]);

    return RefreshIndicator(
      onRefresh: ref.read(homeScreenProvider).onPullRefresh,
      color: kWhiteColor70,
      backgroundColor: kDarkGreyColor,
      displacement: 60.h,
      strokeWidth: 3.w,
      child: Material(
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
                    onPlayerSelected:
                        (player) => ref
                            .read(groupEventScreenProvider.notifier)
                            .onSelectPlayer(context: context, player: player),
                    onFilterTap: () => _showFilterPopup(context),
                    onProfileTap:
                        () => HomeScreen.scaffoldKey.currentState?.openDrawer(),
                  ),
                ),
              ),
            ),

            SizedBox(height: 16.h),

            Consumer(
              builder: (context, ref, child) {
                final isSearching = ref.watch(isSearchingProvider);
                return isSearching
                    ? SizedBox.shrink()
                    : Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20.sp),
                      child: SegmentedSwitcher(
                        backgroundColor: kBlackColor,
                        selectedBackgroundColor: kBlackColor,
                        options: _mappedName.values.toList(),
                        initialSelection: _mappedName.values.toList().indexOf(
                          _mappedName[selectedTourEvent]!,
                        ),
                        currentSelection: _mappedName.values.toList().indexOf(
                          _mappedName[selectedTourEvent]!,
                        ),
                        onSelectionChanged: (index) {
                          final newCategory = GroupEventCategory.values[index];
                          ref
                              .read(selectedGroupCategoryProvider.notifier)
                              .state = newCategory;

                          pageController.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                      ),
                    );
              },
            ),

            SizedBox(height: 12.h),

            Expanded(
              child: PageView.builder(
                controller: pageController,
                itemCount: GroupEventCategory.values.length,
                onPageChanged: (index) {
                  final newCategory = GroupEventCategory.values[index];
                  ref.read(selectedGroupCategoryProvider.notifier).state =
                      newCategory;
                },
                itemBuilder: (context, index) {
                  return Consumer(
                    builder: (context, ref, child) {
                      return ref
                          .watch(groupEventScreenProvider)
                          .when(
                            data: (filteredEvents) {
                              final favorites = ref.watch(starredProvider);
                              final isSearching =
                                  searchController.text.trim().isNotEmpty;
                              List<GroupEventCardModel> finalEvents;

                              if (isSearching) {
                                finalEvents = filteredEvents;
                              } else {
                                finalEvents = ref
                                    .read(tournamentSortingServiceProvider)
                                    .sortBasedOnFavorite(
                                      tours: filteredEvents,
                                      favorites: favorites,
                                    );
                              }

                              return AllEventsTabWidget(
                                filteredEvents: finalEvents,
                                onSelect:
                                    (tourEventCardModel) => ref
                                        .read(groupEventScreenProvider.notifier)
                                        .onSelectTournament(
                                          context: context,
                                          id: tourEventCardModel.id,
                                        ),
                              );
                            },
                            loading: () {
                              return SkeletonWidget(
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
                                    ),
                                  ),
                                ),
                              );
                            },
                            error: (error, stackTrace) => GenericErrorWidget(),
                          );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
