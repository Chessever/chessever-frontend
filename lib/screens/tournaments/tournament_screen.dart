import 'package:chessever2/screens/authentication/home_screen/home_screen.dart';
import 'package:chessever2/screens/authentication/home_screen/home_screen_provider.dart';
import 'package:chessever2/screens/tournaments/providers/tournament_screen_provider.dart';
import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/countrymen_card.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../widgets/rounded_search_bar.dart';
import '../../widgets/segmented_switcher.dart';
import '../../widgets/event_card/completed_event_card.dart';

enum TournamentCategory { all, upcoming }

final _mappedName = {
  TournamentCategory.all: 'All Events',
  TournamentCategory.upcoming: 'Upcoming Events',
};

final selectedTourEventProvider = StateProvider<TournamentCategory>(
  (ref) => TournamentCategory.all,
);

class TournamentScreen extends HookConsumerWidget {
  const TournamentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchController = useTextEditingController();
    final selectedTourEvent = ref.watch(selectedTourEventProvider);

    return RefreshIndicator(
      onRefresh: ref.read(homeScreenProvider).onPullRefresh,
      color: kWhiteColor70,
      backgroundColor: kDarkGreyColor,
      displacement: 60.h,
      // Distance from top where indicator appears
      strokeWidth: 3.w,
      child: Material(
        color: kBackgroundColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Add top padding
            SizedBox(height: 24.h + MediaQuery.of(context).viewPadding.top),
            // Search bar
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.sp),
              child: Hero(
                tag: 'search_bar',
                child: RoundedSearchBar(
                  controller: searchController,
                  hintText: 'Search tournaments or players',
                  onChanged: (value) {
                    ref
                        .read(tournamentNotifierProvider.notifier)
                        .searchForTournament(value, selectedTourEvent);
                  },
                  onFilterTap: () {
                    // Show filter popup
                  },
                  onProfileTap: () {
                    // Open hamburger menu drawer using the static _scaffoldKey
                    HomeScreen.scaffoldKey.currentState?.openDrawer();
                  },
                ),
              ),
            ),

            SizedBox(height: 24.h),

            // Segmented switcher for "All Events" and "Upcoming Events"
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
                  ref.read(selectedTourEventProvider.notifier).state =
                      TournamentCategory.values[index];
                },
              ),
            ),

            SizedBox(height: 12.h),

            // Tournament list
            ref
                .watch(tournamentNotifierProvider)
                .when(
                  data: (filteredEvents) {
                    return Expanded(
                      child: AllEventsTabWidget(
                        filteredEvents: filteredEvents,
                      ),
                    );
                  },
                  loading: () {
                    final mockData = TourEventCardModel(
                      id: 'tour_001',
                      title: 'World Chess Championship 2025',
                      dates: 'Mar 15 - 25,2025',
                      timeUntilStart: 'Starts in 8 months',
                      tourEventCategory: TourEventCategory.live,
                      maxAvgElo: 0,
                      timeControl: 'Standard',
                    );
                    return Expanded(
                      child: SkeletonWidget(
                        child: AllEventsTabWidget(
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
  const AllEventsTabWidget({required this.filteredEvents, super.key});

  final List<TourEventCardModel> filteredEvents;

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
    return ListView.separated(
      padding: EdgeInsets.only(
        left: 20.sp,
        right: 20.sp,
        bottom: MediaQuery.of(context).viewPadding.bottom + 12.sp,
      ),
      itemCount: filteredEvents.length,
      separatorBuilder: (context, index) {
        return SizedBox(height: 12.sp);
      },
      itemBuilder: (context, index) {
        if (index == 0) {
          return CountrymenCardWidget();
        }

        final tourEventCardModel = filteredEvents[index - 1];

        switch (tourEventCardModel.tourEventCategory) {
          case TourEventCategory.live:
            return EventCard(
              tourEventCardModel: tourEventCardModel,
              onTap: () {
                ref
                    .read(tournamentNotifierProvider.notifier)
                    .onSelectTournament(
                      context: context,
                      id: tourEventCardModel.id,
                    );
              },
            );
          case TourEventCategory.upcoming:
            return EventCard(
              tourEventCardModel: tourEventCardModel,
              //todo:
              onTap: () {
                ref
                    .read(tournamentNotifierProvider.notifier)
                    .onSelectTournament(
                      context: context,
                      id: tourEventCardModel.id,
                    );
              },
            );
          case TourEventCategory.completed:
            return CompletedEventCard(
              tourEventCardModel: tourEventCardModel,
              onTap: () {
                ref
                    .read(tournamentNotifierProvider.notifier)
                    .onSelectTournament(
                      context: context,
                      id: tourEventCardModel.id,
                    );
              },
              onDownloadTournament: () {
                // Download tournament
              },
              onAddToLibrary: () {
                // Add to library
              },
            );
        }
      },
    );
  }
}
