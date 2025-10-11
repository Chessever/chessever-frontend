import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/calendar/provider/calendar_detail_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:chessever2/screens/group_event/widget/all_events_tab_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/month_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup.dart';
import 'package:chessever2/widgets/event_card/starred_provider.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class CalendarDetailsScreen extends ConsumerStatefulWidget {
  const CalendarDetailsScreen({super.key});

  @override
  ConsumerState<CalendarDetailsScreen> createState() =>
      _CalendarDetailsScreenState();
}

class _CalendarDetailsScreenState extends ConsumerState<CalendarDetailsScreen> {
  final TextEditingController searchController = TextEditingController();
  final FocusNode focusNode = FocusNode();

  @override
  void dispose() {
    searchController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedMonth = ref.read(selectedMonthProvider);
    final selectedYear = ref.read(selectedYearProvider);
    final filteredTours = ref.watch(
      calendarDetailScreenProvider(
        CalendarFilterArgs(month: selectedMonth, year: selectedYear),
      ),
    );

    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: Scaffold(
        body: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.sp),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 24.h + MediaQuery.of(context).viewPadding.top,
                  ),
                  AnimatedBuilder(
                    animation: focusNode,
                    builder: (cxt, _) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 24.ic,
                            height: 24.ic,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => Navigator.of(context).pop(),
                              icon: Icon(
                                Icons.arrow_back_ios_new_outlined,
                                size: 24.ic,
                              ),
                            ),
                          ),

                          SizedBox(width: 11.w),
                          Expanded(
                            child: Hero(
                              tag: 'search_bar',
                              child: Material(
                                color: Colors.transparent,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                  padding: EdgeInsets.all(2.sp),
                                  decoration: BoxDecoration(
                                    color: kGrey900,
                                    borderRadius: BorderRadius.circular(8.br),
                                    border: Border.all(
                                      color:
                                          focusNode.hasFocus
                                              ? kPrimaryColor.withOpacity(0.5)
                                              : Colors.transparent,
                                      width: 2.0,
                                    ),
                                    boxShadow:
                                        focusNode.hasFocus
                                            ? [
                                              BoxShadow(
                                                color: kPrimaryColor
                                                    .withOpacity(0.15),
                                                blurRadius: 12,
                                                offset: const Offset(0, 4),
                                              ),
                                            ]
                                            : [],
                                  ),
                                  child: SimpleSearchBar(
                                    controller: searchController,
                                    hintText: 'Search tournaments or players',
                                    focusNode: focusNode,
                                    onCloseTap: () {
                                      searchController.clear();
                                      focusNode.unfocus();
                                      ref
                                          .read(
                                            calendarDetailScreenProvider(
                                              CalendarFilterArgs(
                                                month: selectedMonth,
                                                year: selectedYear,
                                              ),
                                            ).notifier,
                                          )
                                          .refresh();
                                    },
                                    onChanged:
                                        (query) => ref
                                            .read(
                                              calendarDetailScreenProvider(
                                                CalendarFilterArgs(
                                                  month: selectedMonth,
                                                  year: selectedYear,
                                                ),
                                              ).notifier,
                                            )
                                            .search(query),
                                    onOpenFilter: () {
                                      showDialog(
                                        context: context,
                                        barrierColor: kLightBlack,
                                        builder:
                                            (context) => FilterPopup(
                                              onApplyFilters: (filterState) {},
                                            ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      );
                    },
                  ),
                  SizedBox(height: 32.h),
                  Text(
                    "Tournaments in ${ref.read(monthProvider).monthNumberToName(selectedMonth)} $selectedYear",
                    style: AppTypography.textLgBold,
                  ),
                  SizedBox(height: 20.h),
                ],
              ),
            ),
            filteredTours.when(
              data: (filteredEvents) {
                final currentFav = ref.watch(
                  starredProvider(GroupEventCategory.current.name),
                );

                final pastFav = ref.watch(
                  starredProvider(GroupEventCategory.past.name),
                );

                final liveFav = ref.watch(
                  starredProvider(GroupEventCategory.upcoming.name),
                );

                final starredFavorites = [
                  ...currentFav,
                  ...pastFav,
                  ...liveFav,
                ];

                // Combine both lists
                final allFavorites = <String>{...starredFavorites}.toList();

                final isSearching = searchController.text.trim().isNotEmpty;

                final finalEvents =
                    isSearching
                        ? filteredEvents
                        : ref
                            .read(tournamentSortingServiceProvider)
                            .sortBasedOnFavorite(
                              tours: filteredEvents,
                              favorites: allFavorites,
                            );
                return Expanded(
                  child: AllEventsTabWidget(
                    filteredEvents: finalEvents,
                    onSelect: (_) {},
                  ),
                );
              },
              loading: () {
                final mockData = GroupEventCardModel(
                  id: 'tour_001',
                  title: 'World Chess Championship 2025',
                  dates: '2025-03-15',
                  maxAvgElo: 200,
                  timeUntilStart: 'Starts in 8 months',
                  tourEventCategory: TourEventCategory.live,
                  timeControl: 'Standard',
                  endDate: null,
                  startDate: null,
                );
                return Expanded(
                  child: SkeletonWidget(
                    child: AllEventsTabWidget(
                      filteredEvents: List.generate(10, (index) => mockData),
                      onSelect: (_) {},
                    ),
                  ),
                );
              },
              error: (error, stackTrace) => const GenericErrorWidget(),
            ),
          ],
        ),
      ),
    );
  }
}
