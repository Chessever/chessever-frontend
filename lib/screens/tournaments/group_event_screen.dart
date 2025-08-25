import 'package:chessever2/screens/authentication/home_screen/home_screen.dart';
import 'package:chessever2/screens/authentication/home_screen/home_screen_provider.dart';
import 'package:chessever2/screens/tournaments/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/filter_popup.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/search/enhanced_rounded_search_bar.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../widgets/segmented_switcher.dart';
import '../../widgets/event_card/completed_event_card.dart';

enum GroupEventCategory { current, upcoming }

final _mappedName = {
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
              child: Hero(
                tag: 'search_bar',
                child: EnhancedRoundedSearchBar(
                  showFilter: true,
                  controller: searchController,
                  hintText: 'Search Events or Players',
                  onChanged: (value) {
                    ref
                        .read(groupEventScreenProvider.notifier)
                        .searchForTournament(value, selectedTourEvent);
                  },
                  onTournamentSelected: (tournament) {
                    ref
                        .read(groupEventScreenProvider.notifier)
                        .onSelectTournament(
                          context: context,
                          id: tournament.id,
                        );
                  },
                  onPlayerSelected: (player) {
                    ref
                        .read(groupEventScreenProvider.notifier)
                        .onSelectPlayer(context: context, player: player);
                  },
                  onFilterTap: () {
                    _showFilterPopup(context);
                  },
                  onProfileTap: () {
                    HomeScreen.scaffoldKey.currentState?.openDrawer();
                  },
                ),
              ),
            ),

            SizedBox(height: 16.h),

            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.sp),
              child: SegmentedSwitcher(
                backgroundColor: kBlackColor,
                selectedBackgroundColor: kBlackColor,
                options: _mappedName.values.toList(),
                initialSelection: _mappedName.values.toList().indexOf(
                  _mappedName[selectedTourEvent]!,
                ),
                onSelectionChanged: (index) {
                  ref.read(selectedGroupCategoryProvider.notifier).state =
                      GroupEventCategory.values[index];
                },
              ),
            ),

            SizedBox(height: 12.h),

            ref
                .watch(groupEventScreenProvider)
                .when(
                  data: (filteredEvents) {
                    return Expanded(
                      child: AllEventsTabWidget(
                        filteredEvents: filteredEvents,
                        onSelect:
                            (tourEventCardModel) => ref
                                .read(groupEventScreenProvider.notifier)
                                .onSelectTournament(
                                  context: context,
                                  id: tourEventCardModel.id,
                                ),
                      ),
                    );
                  },
                  loading: () {
                    final mockData = GroupEventCardModel(
                      id: 'tour_001',
                      title: 'World Chess Championship 2025',
                      dates: 'Mar 15 - 25,2025',
                      timeUntilStart: 'Starts in 8 months',
                      tourEventCategory: TourEventCategory.live,
                      maxAvgElo: 0,
                      timeControl: 'Standard',
                      startDate: DateTime(2025, 3, 15),
                      endDate: DateTime.now(),
                    );
                    return Expanded(
                      child: SkeletonWidget(
                        child: AllEventsTabWidget(
                          onSelect: (_) {},
                          filteredEvents: List.generate(
                            10,
                            (index) => mockData,
                          ),
                        ),
                      ),
                    );
                  },
                  error: (error, stackTrace) => GenericErrorWidget(),
                ),
          ],
        ),
      ),
    );
  }
}

class AllEventsTabWidget extends ConsumerWidget {
  const AllEventsTabWidget({
    required this.filteredEvents,
    required this.onSelect,
    super.key,
  });

  final List<GroupEventCardModel> filteredEvents;
  final ValueChanged<GroupEventCardModel> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (filteredEvents.isEmpty) {
      return const Center(
        child: Text(
          'No tournaments found',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(
        left: 20.sp,
        right: 20.sp,
        bottom: MediaQuery.of(context).viewPadding.bottom + 12.sp,
      ),
      itemCount: filteredEvents.length,
      itemBuilder: (context, index) {
        // if (index == 0) {
        //   return SizedBox.shrink();
        //   return CountrymenCardWidget();
        // }

        // final tourEventCardModel = filteredEvents[index - 1];
        final tourEventCardModel = filteredEvents[index];

        switch (tourEventCardModel.tourEventCategory) {
          case TourEventCategory.live:
            return Padding(
              padding: EdgeInsets.only(bottom: 12.sp),
              child: EventCard(
                tourEventCardModel: tourEventCardModel,
                onTap: () => onSelect(tourEventCardModel),
              ),
            );
          case TourEventCategory.upcoming:
            return Padding(
              padding: EdgeInsets.only(bottom: 12.sp),
              child: EventCard(
                tourEventCardModel: tourEventCardModel,
                //todo:
                onTap: () => onSelect(tourEventCardModel),
              ),
            );
          case TourEventCategory.ongoing:
            return Padding(
              padding: EdgeInsets.only(bottom: 12.sp),
              child: EventCard(
                tourEventCardModel: tourEventCardModel,
                //todo:
                onTap: () => onSelect(tourEventCardModel),
              ),
            );
          case TourEventCategory.completed:
            return Padding(
              padding: EdgeInsets.only(bottom: 12.sp),
              child: CompletedEventCard(
                tourEventCardModel: tourEventCardModel,
                onTap: () => onSelect(tourEventCardModel),
                onDownloadTournament: () {
                  // Download tournament
                },
                onAddToLibrary: () {
                  // Add to library
                },
              ),
            );
        }
      },
    );
  }
}
