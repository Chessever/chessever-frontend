import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/calendar/provider/calendar_screen_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/calendar/provider/calendar_detail_screen_provider.dart';
import 'package:chessever2/screens/group_event/widget/all_events_tab_widget.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/month_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_search.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_top_bar.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
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
  bool _searchExpanded = false;

  @override
  void initState() {
    super.initState();
    searchController.text = ref.read(calendarSearchQueryProvider);
    if (searchController.text.trim().isNotEmpty) {
      _searchExpanded = true;
    }
  }

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

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );

    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: ScreenWrapper(
        child: Scaffold(
          key: e2eKey(E2eIds.calendarDetailRoot),
          backgroundColor: Colors.transparent,
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: ResponsiveHelper.contentMaxWidth,
              ),
              child: Column(
                children: [
                  // Island chrome: back circle + expand-on-tap search.
                  GlassIslandTopBar(
                    horizontalPadding: horizontalPadding,
                    leading: const GlassBackButton(),
                    center: GlassIslandSearch(
                      controller: searchController,
                      focusNode: focusNode,
                      expanded: _searchExpanded,
                      hintText: 'Search',
                      onExpandedChanged:
                          (v) => setState(() => _searchExpanded = v),
                      onChanged:
                          (query) =>
                              ref
                                  .read(calendarSearchQueryProvider.notifier)
                                  .state = query,
                      onClear: () {
                        ref.read(calendarSearchQueryProvider.notifier).state =
                            '';
                      },
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      8.h,
                      horizontalPadding,
                      12.h,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Tournaments in ${ref.read(monthProvider).monthNumberToName(selectedMonth)} $selectedYear",
                        style: AppTypography.textLgBold,
                      ),
                    ),
                  ),
                filteredTours.when(
                  data: (filteredEvents) {
                    return Expanded(
                      child: AllEventsTabWidget(
                        filteredEvents: filteredEvents,
                        onSelect: (event) {
                          ref
                              .read(
                                calendarDetailScreenProvider(
                                  CalendarFilterArgs(
                                    month: selectedMonth,
                                    year: selectedYear,
                                  ),
                                ).notifier,
                              )
                              .onSelectTournament(
                                context: context,
                                id: event.id,
                              );
                        },
                      ),
                    );
                  },
                  loading: () {
                    // Generate unique skeleton cards to avoid duplicate hero tags
                    final skeletonCards = List.generate(
                      10,
                      (index) => GroupEventCardModel(
                        id: 'skeleton_loading_$index', // Unique ID for each skeleton
                        title: 'Loading Tournament $index',
                        dates: 'Loading...',
                        maxAvgElo: 2000 + (index * 50),
                        timeUntilStart: 'Loading...',
                        tourEventCategory: TourEventCategory.upcoming,
                        timeControl: 'Standard',
                        endDate: null,
                        startDate: null,
                      ),
                    );
                    return Expanded(
                      child: SkeletonWidget(
                        child: AllEventsTabWidget(
                          filteredEvents: skeletonCards,
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
        ),
      ),
      ),
    );
  }
}
