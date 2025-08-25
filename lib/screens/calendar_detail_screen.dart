import 'package:chessever2/screens/calendar_screen.dart';
import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:chessever2/screens/tournaments/providers/calendar_tour_view_provider.dart';
import 'package:chessever2/screens/tournaments/group_event_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/month_converter.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/filter_popup.dart';
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
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedMonth = ref.read(selectedMonthProvider);
    final selectedYear = ref.read(selectedYearProvider);
    final filteredTours = ref.watch(
      calendarTourViewProvider(
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 7,
                        child: Hero(
                          tag: 'search_bar',
                          child: SimpleSearchBar(
                            controller: _searchController,
                            hintText: 'Search tournaments or players',
                            onChanged: (value) {
                              ref
                                  .read(
                                    calendarTourViewProvider(
                                      CalendarFilterArgs(
                                        month: selectedMonth,
                                        year: selectedYear,
                                      ),
                                    ).notifier,
                                  )
                                  .search(value);
                            },
                            onMenuTap: () {
                              print('Menu tapped');
                            },
                            onFilterTap: () {
                              showDialog(
                                context: context,
                                barrierColor: kLightBlack,
                                builder: (context) => const FilterPopup(),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                  SizedBox(height: 32.h),
                  Text(
                    "Tournaments in ${MonthConverter.monthNumberToName(selectedMonth)} $selectedYear",
                    style: AppTypography.textLgBold,
                  ),
                  SizedBox(height: 20.h),
                ],
              ),
            ),
            filteredTours.when(
              data: (filteredEvents) {
                return Expanded(
                  child: AllEventsTabWidget(
                    filteredEvents: filteredEvents,
                    onSelect: (_) {
                      //todo:
                    },
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
                  startDate: DateTime(2025, 3, 15),
                  endDate: DateTime.now(),
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
