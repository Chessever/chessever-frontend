import 'package:chessever2/screens/authentication/home_screen/home_screen.dart';
import 'package:chessever2/screens/authentication/home_screen/home_screen_provider.dart';
import 'package:chessever2/screens/tournaments/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:chessever2/screens/tournaments/providers/sorting_all_event_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/starred_provider.dart';
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
                    final favorites = ref.watch(starredProvider);

                    final sortedEvents = ref
                        .read(tournamentSortingServiceProvider)
                        .sortBasedOnFavorite(
                          tours: filteredEvents,
                          favorites: favorites,
                        );

                    return Expanded(
                      child: AllEventsTabWidget(
                        filteredEvents: sortedEvents,
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

class AllEventsTabWidget extends ConsumerStatefulWidget {
  const AllEventsTabWidget({
    required this.filteredEvents,
    required this.onSelect,
    super.key,
  });

  final List<GroupEventCardModel> filteredEvents;
  final ValueChanged<GroupEventCardModel> onSelect;

  @override
  ConsumerState<AllEventsTabWidget> createState() => _AllEventsTabWidgetState();
}

class _AllEventsTabWidgetState extends ConsumerState<AllEventsTabWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    // Start animation when widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animationController.forward();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.filteredEvents.isEmpty) {
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
      itemCount: widget.filteredEvents.length,
      itemBuilder: (context, index) {
        final tourEventCardModel = widget.filteredEvents[index];

        // Create staggered animation for each item
        final itemAnimation = Tween<Offset>(
          begin: const Offset(0, -0.5),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Interval(
              (index * 0.1).clamp(0.0, 1.0), // Stagger start times
              ((index * 0.1) + 0.6).clamp(0.0, 1.0), // Stagger end times
              curve: Curves.easeOutCubic,
            ),
          ),
        );

        final fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Interval(
              (index * 0.1).clamp(0.0, 1.0),
              ((index * 0.1) + 0.6).clamp(0.0, 1.0),
              curve: Curves.easeOut,
            ),
          ),
        );

        Widget eventCard;
        switch (tourEventCardModel.tourEventCategory) {
          case TourEventCategory.live:
            eventCard = EventCard(
              tourEventCardModel: tourEventCardModel,
              onTap: () => widget.onSelect(tourEventCardModel),
            );
            break;
          case TourEventCategory.upcoming:
            eventCard = EventCard(
              tourEventCardModel: tourEventCardModel,
              onTap: () => widget.onSelect(tourEventCardModel),
            );
            break;
          case TourEventCategory.ongoing:
            eventCard = EventCard(
              tourEventCardModel: tourEventCardModel,
              onTap: () => widget.onSelect(tourEventCardModel),
            );
            break;
          case TourEventCategory.completed:
            eventCard = CompletedEventCard(
              tourEventCardModel: tourEventCardModel,
              onTap: () => widget.onSelect(tourEventCardModel),
              onDownloadTournament: () {
                // Download tournament
              },
              onAddToLibrary: () {
                // Add to library
              },
            );
            break;
        }

        return AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return SlideTransition(
              position: itemAnimation,
              child: FadeTransition(
                opacity: fadeAnimation,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 12.sp),
                  child: eventCard,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
