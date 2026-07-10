import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/calendar/provider/calendar_screen_provider.dart';
import 'package:chessever2/screens/calendar/provider/calendar_detail_screen_provider.dart';
import 'package:chessever2/screens/group_event/widget/all_events_tab_widget.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/month_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_search.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_top_bar.dart';
import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:chessever2/widgets/liquid_glass/glass_title_chip.dart';
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
    final selectedMonth = ref.watch(selectedMonthProvider);
    final selectedYear = ref.watch(selectedYearProvider);
    final filteredTours = ref.watch(
      calendarDetailScreenProvider(
        CalendarFilterArgs(month: selectedMonth, year: selectedYear),
      ),
    );

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 12.sp,
      tablet: 24.sp,
    );
    final scaledLabelHeight = MediaQuery.textScalerOf(context).scale(14) * 1.2;
    final controlHeight = (scaledLabelHeight + 20).clamp(48.0, 96.0);
    final contentWidth = MediaQuery.sizeOf(
      context,
    ).width.clamp(0.0, ResponsiveHelper.contentMaxWidth);
    final monthName = ref.read(monthProvider).monthNumberToName(selectedMonth);
    final title = '$monthName $selectedYear';

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: GlassFullScreenPage(
        key: e2eKey(E2eIds.calendarDetailRoot),
        backgroundColor: context.colors.background,
        contentPadding: EdgeInsets.only(top: controlHeight + 16, bottom: 8),
        topOverlayPadding: const EdgeInsets.only(top: 4),
        topOverlay: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: contentWidth,
            child: GlassIslandTopBar(
              key: const ValueKey<String>('calendar-detail-floating-controls'),
              horizontalPadding: horizontalPadding,
              topPadding: 0,
              height: controlHeight,
              leading: const GlassBackButton(),
              title:
                  _searchExpanded
                      ? null
                      : Semantics(
                        header: true,
                        label: 'Tournaments in $title',
                        child: GlassTitleChip(
                          label: title,
                          height: controlHeight,
                          maxWidth: 184.sp,
                          textStyle: AppTypography.textMdBold.copyWith(
                            color: context.colors.textPrimary,
                          ),
                        ),
                      ),
              center: Semantics(
                label:
                    _searchExpanded
                        ? 'Search tournaments field'
                        : 'Search tournaments',
                button: !_searchExpanded,
                textField: _searchExpanded,
                child: GlassIslandSearch(
                  controller: searchController,
                  focusNode: focusNode,
                  expanded: _searchExpanded,
                  hintText: 'Search tournaments',
                  collapsedSize: controlHeight,
                  expandedHeight: controlHeight,
                  onExpandedChanged:
                      (expanded) => setState(() => _searchExpanded = expanded),
                  onChanged:
                      (query) =>
                          ref.read(calendarSearchQueryProvider.notifier).state =
                              query,
                  onClear: () {
                    ref.read(calendarSearchQueryProvider.notifier).state = '';
                  },
                ),
              ),
            ),
          ),
        ),
        content: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: AnimatedSwitcher(
              duration: GlassMotion.resolveDuration(
                context,
                const Duration(milliseconds: 180),
              ),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              child: filteredTours.when(
                data:
                    (filteredEvents) => KeyedSubtree(
                      key: const ValueKey<String>('calendar-detail-data'),
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
                    ),
                loading: () {
                  return const KeyedSubtree(
                    key: ValueKey<String>('calendar-detail-loading'),
                    child: _CalendarDetailLoading(),
                  );
                },
                error:
                    (error, stackTrace) => const KeyedSubtree(
                      key: ValueKey<String>('calendar-detail-error'),
                      child: GenericErrorWidget(),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarDetailLoading extends StatelessWidget {
  const _CalendarDetailLoading();

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 24.sp,
    );
    final isTablet = ResponsiveHelper.isTablet;
    final crossAxisCount = ResponsiveHelper.getGridCrossAxisCount(
      phoneCount: 1,
    );

    return Semantics(
      label: 'Loading tournaments',
      liveRegion: true,
      child: ExcludeSemantics(
        child: GridView.builder(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            0,
            horizontalPadding,
            MediaQuery.viewPaddingOf(context).bottom + 12,
          ),
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isTablet ? crossAxisCount : 1,
            crossAxisSpacing: 16.sp,
            mainAxisSpacing: 12.sp,
            childAspectRatio: isTablet ? 1.2 : 2.15,
          ),
          itemCount: 8,
          itemBuilder:
              (context, index) => DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.surfaceElevated,
                  borderRadius: BorderRadius.circular(16.br),
                ),
                child: Padding(
                  padding: EdgeInsets.all(16.sp),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: FractionallySizedBox(
                      widthFactor: index.isEven ? 0.7 : 0.5,
                      child: Container(
                        height: 14.h,
                        decoration: BoxDecoration(
                          color: context.colors.surfaceRecessed,
                          borderRadius: BorderRadius.circular(7.br),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        ),
      ),
    );
  }
}
