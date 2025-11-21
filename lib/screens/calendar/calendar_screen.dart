import 'package:chessever2/screens/calendar/provider/calendar_screen_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/time_utils.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import 'package:country_picker/country_picker.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:chessever2/utils/app_typography.dart';

final availableYearsProvider = AutoDisposeProvider<List<int>>((ref) {
  final currentYear = DateTime.now().year;
  return [currentYear - 1, currentYear, currentYear + 1];
});

final selectedYearProvider = StateProvider<int>((ref) {
  return DateTime.now().year;
});

final selectedMonthProvider = StateProvider<int>((ref) {
  return DateTime.now().month;
});

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  final TextEditingController searchController = TextEditingController();
  final focusNode = FocusNode();

  @override
  void dispose() {
    searchController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final yearList = ref.read(availableYearsProvider);
    final timeControls = ['Blitz', 'Rapid', 'Standard', 'Bullet'];

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 24.h + MediaQuery.of(context).viewPadding.top),

          /// Search bar + Filters
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.sp),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    /// Search bar
                    Expanded(
                      child: Hero(
                        tag: 'search_bar',
                        child: Material(
                          color: Colors.transparent,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            padding: EdgeInsets.symmetric(
                              horizontal: 2.sp,
                              vertical: 4.sp,
                            ),
                            decoration: BoxDecoration(
                              color: kGrey900,
                              borderRadius: BorderRadius.circular(8.br),
                              border: Border.all(
                                color:
                                    focusNode.hasFocus
                                        ? kPrimaryColor.withValues(alpha: 0.5)
                                        : Colors.transparent,
                                width: 2.0,
                              ),
                              boxShadow:
                                  focusNode.hasFocus
                                      ? [
                                        BoxShadow(
                                          color:
                                              kPrimaryColor.withValues(alpha: 0.15),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                      : [],
                            ),
                            child: SimpleSearchBar(
                              controller: searchController,
                              focusNode: focusNode,
                              hintText: 'Search Country (e.g. Aze)',
                              onCloseTap: () {
                                searchController.clear();
                                focusNode.unfocus();
                                ref
                                    .read(calendarSearchQueryProvider.notifier)
                                    .state = '';
                              },
                              onChanged: (val) {
                                ref
                                    .read(calendarSearchQueryProvider.notifier)
                                    .state = val;
                              },
                              onOpenFilter: null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                Row(
                  children: [
                    /// Year dropdown
                    Expanded(
                      child: Container(
                        height: 40.h,
                        padding: EdgeInsets.symmetric(horizontal: 12.w),
                        decoration: BoxDecoration(
                          color: kBlack2Color,
                          borderRadius: BorderRadius.circular(8.br),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                            width: 1.w,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: ref.watch(selectedYearProvider),
                            onChanged: (int? newValue) {
                              if (newValue != null) {
                                ref
                                    .read(selectedYearProvider.notifier)
                                    .state = newValue;
                              }
                            },
                            icon: Icon(
                              Icons.keyboard_arrow_down_outlined,
                              color: kWhiteColor,
                              size: 20.ic,
                            ),
                            style: AppTypography.textMdBold.copyWith(
                              color: kWhiteColor,
                            ),
                            dropdownColor: kBlack2Color,
                            borderRadius: BorderRadius.circular(8.br),
                            isExpanded: true,
                            items:
                                yearList.map((value) {
                                  return DropdownMenuItem<int>(
                                    value: value,
                                    child: Text(value.toString()),
                                  );
                                }).toList(),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    /// Time Control dropdown
                    Expanded(
                      child: Container(
                        height: 40.h,
                        padding: EdgeInsets.symmetric(horizontal: 12.w),
                        decoration: BoxDecoration(
                          color: kBlack2Color,
                          borderRadius: BorderRadius.circular(8.br),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                            width: 1.w,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: ref.watch(calendarTimeControlProvider),
                            hint: Text(
                              'Time Control',
                              style: AppTypography.textSmRegular.copyWith(
                                color: kDarkGreyColor,
                              ),
                            ),
                            onChanged: (String? newValue) {
                              ref
                                  .read(calendarTimeControlProvider.notifier)
                                  .state = newValue;
                            },
                            icon: Icon(
                              Icons.keyboard_arrow_down_outlined,
                              color: kWhiteColor,
                              size: 20.ic,
                            ),
                            style: AppTypography.textMdBold.copyWith(
                              color: kWhiteColor,
                            ),
                            dropdownColor: kBlack2Color,
                            borderRadius: BorderRadius.circular(8.br),
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('All Formats'),
                              ),
                              ...timeControls.map((value) {
                                return DropdownMenuItem<String?>(
                                  value: value,
                                  child: Text(value),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          SizedBox(height: 16.h),

          /// Month Grid
          Expanded(
            child: ref
                .watch(calendarScreenProvider)
                .when(
                  data: (data) {
                      if (data.isNotEmpty) {
                      final isTablet = ResponsiveHelper.isTablet;
                      final crossAxisCount = isTablet ? 3 : 2;
                      final tileHeight = isTablet ? 350.h : 290.h;
                      final maxPreviewEvents = isTablet ? 3 : 2;

                      return GridView.builder(
                        padding: EdgeInsets.symmetric(horizontal: 16.sp),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 14.sp,
                          crossAxisSpacing: 14.sp,
                          mainAxisExtent: tileHeight,
                        ),
                        itemCount: data.length,
                        itemBuilder: (context, index) {
                          final summary = data[index];
                          void openMonth() {
                            ref.read(selectedMonthProvider.notifier).state =
                                summary.monthNumber;

                            Navigator.pushNamed(
                              context,
                              '/calendar_detail_screen',
                            );
                          }

                          return _MonthCard(
                            summary: summary,
                            maxPreviewEvents: maxPreviewEvents,
                            onOpenMonth: openMonth,
                          );
                        },
                      );
                    } else {
                      return Center(
                        child: Text(
                          'No Events Found',
                          style: AppTypography.textLgRegular.copyWith(
                            color: kWhiteColor,
                          ),
                        ),
                      );
                    }
                  },
                  error: (e, _) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Failed To Load Months! \nPlease Try Again Later',
                            style: AppTypography.textLgRegular.copyWith(
                              color: kWhiteColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  loading: () {
                    final isTablet = ResponsiveHelper.isTablet;
                    final crossAxisCount = isTablet ? 3 : 2;
                    final tileHeight = isTablet ? 350.h : 290.h;
                    return SkeletonWidget(
                      child: GridView.builder(
                        padding: EdgeInsets.symmetric(horizontal: 16.sp),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 14.sp,
                          crossAxisSpacing: 14.sp,
                          mainAxisExtent: tileHeight,
                        ),
                        itemCount: 12,
                        itemBuilder: (context, index) {
                          return Container(
                            decoration: BoxDecoration(
                              color: kBlack2Color,
                              borderRadius: BorderRadius.circular(12.br),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({
    required this.summary,
    required this.maxPreviewEvents,
    required this.onOpenMonth,
  });

  final MonthEventsSummary summary;
  final int maxPreviewEvents;
  final VoidCallback onOpenMonth;

  @override
  Widget build(BuildContext context) {
    final eventsToShow = summary.events.take(maxPreviewEvents).toList();

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12.br),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.br),
        onTap: onOpenMonth,
        child: Container(
          decoration: BoxDecoration(
            color: kBlack2Color,
            borderRadius: BorderRadius.circular(12.br),
            border: Border.all(color: kWhiteColor.withValues(alpha: 0.06), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: EdgeInsets.all(12.sp),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      summary.monthName,
                      style: AppTypography.textMdBold.copyWith(
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  _EventCountBadge(count: summary.eventCount),
                ],
              ),
              SizedBox(height: 12.h),
              if (eventsToShow.isEmpty)
                const _MonthEmptyState()
              else ...[
                for (var i = 0; i < eventsToShow.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom:
                          i == eventsToShow.length - 1 &&
                                  summary.eventCount <= eventsToShow.length
                              ? 0
                              : 8.sp,
                    ),
                    child: _CalendarEventTile(
                      event: eventsToShow[i],
                      gradientIndex: i,
                    ),
                  ),
                if (summary.eventCount > eventsToShow.length)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onOpenMonth,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 6.sp),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: kActiveCalendarColor,
                      ),
                      icon: Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14.ic,
                        color: kActiveCalendarColor,
                      ),
                      label: Text(
                        'View all ${summary.eventCount}',
                        style: AppTypography.textSmMedium.copyWith(
                          color: kActiveCalendarColor,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EventCountBadge extends StatelessWidget {
  const _EventCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 4.sp),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      constraints: BoxConstraints(minWidth: 28.w),
      alignment: Alignment.center,
      child: Text(
        count.toString(),
        style: AppTypography.textXsBold.copyWith(
          color: Colors.white,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

class _MonthEmptyState extends StatelessWidget {
  const _MonthEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 16.sp),
      decoration: BoxDecoration(
        color: kBlackColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10.br),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_off_rounded,
            color: kWhiteColor.withValues(alpha: 0.6),
            size: 18.ic,
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              'No events match your filters',
              style: AppTypography.textSmMedium.copyWith(
                color: kWhiteColor70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarEventTile extends StatelessWidget {
  const _CalendarEventTile({
    required this.event,
    required this.gradientIndex,
  });

  final GroupEventCardModel event;
  final int gradientIndex;

  @override
  Widget build(BuildContext context) {
    final countryCode = CalendarSearchHelper.getCountryCodeForLocation(
      event.location,
    );
    final countryName = _deriveCountryName(event.location, countryCode);
    final cityName = _deriveCity(event.location);
    final dateLabel = _formatDateLabel(event);

    final palette = _cardGradients[gradientIndex % _cardGradients.length];
    final locationLabel = [
      if (cityName != null && cityName.isNotEmpty) cityName,
      if (countryName != null && countryName.isNotEmpty) countryName,
    ].join(', ');

    return Container(
      padding: EdgeInsets.all(10.sp),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10.br),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          _FlagTile(countryCode: countryCode, palette: palette),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: AppTypography.textSmBold.copyWith(
                    color: Colors.white,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 6.h),
                Wrap(
                  spacing: 6.w,
                  runSpacing: 4.h,
                  children: [
                    _InfoChip(
                      icon: Icons.event_outlined,
                      label: dateLabel,
                    ),
                    _InfoChip(
                      icon: Icons.timer_outlined,
                      label: _formatTimeControlLabel(event.timeControl),
                    ),
                  ],
                ),
                SizedBox(height: 8.h),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 14.ic,
                      color: Colors.white70,
                    ),
                    SizedBox(width: 6.w),
                    Expanded(
                      child: Text(
                        locationLabel.isNotEmpty
                            ? locationLabel
                            : 'Location TBA',
                        style: AppTypography.textXsMedium.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _deriveCity(String? location) {
    if (location == null || location.isEmpty) return null;
    final segments = location.split(',');
    if (segments.length > 1) {
      return segments.first.trim().isNotEmpty ? segments.first.trim() : null;
    }
    return location.trim().isNotEmpty ? location.trim() : null;
  }

  String? _deriveCountryName(String? location, String? countryCode) {
    if (countryCode != null) {
      final country = CountryService().findByCode(countryCode);
      if (country != null) return country.name;
    }
    if (location == null || location.isEmpty) return null;
    final segments = location.split(',');
    if (segments.length > 1 && segments.last.trim().isNotEmpty) {
      return segments.last.trim();
    }
    return location.trim().isNotEmpty ? location.trim() : null;
  }

  String _formatTimeControlLabel(String? timeControl) {
    final normalized = normalizeTimeControl(timeControl);
    switch (normalized) {
      case 'rapid':
        return 'Rapid';
      case 'blitz':
        return 'Blitz';
      case 'bullet':
        return 'Bullet';
      case 'standard':
        return 'Classical';
      default:
        return timeControl?.isNotEmpty == true ? timeControl! : 'Format TBA';
    }
  }

  String _formatDateLabel(GroupEventCardModel event) {
    final start = event.startDate;
    final end = event.endDate;
    if (start == null && end == null) return 'Dates TBA';
    final range = TimeUtils.formatDateRange(start, end);
    return range.isNotEmpty ? range : 'Dates TBA';
  }
}

class _FlagTile extends StatelessWidget {
  const _FlagTile({
    required this.countryCode,
    required this.palette,
  });

  final String? countryCode;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62.w,
      height: 62.h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10.br),
        gradient: LinearGradient(
          colors: palette,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9.br),
        child:
            countryCode != null && countryCode!.isNotEmpty
                ? CountryFlag.fromCountryCode(
                  countryCode!,
                  height: double.infinity,
                  width: double.infinity,
                )
                : Container(
                  color: Colors.black.withValues(alpha: 0.2),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.flag_outlined,
                    size: 18.ic,
                    color: Colors.white70,
                  ),
                ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 5.sp),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8.br),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12.ic,
            color: Colors.white,
          ),
          SizedBox(width: 4.w),
          Text(
            label,
            style: AppTypography.textXsMedium.copyWith(
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

const List<List<Color>> _cardGradients = [
  [Color(0xFF1F1C2C), Color(0xFF928DAB)],
  [Color(0xFF0F2027), Color(0xFF2C5364)],
  [Color(0xFF1D976C), Color(0xFF93F9B9)],
  [Color(0xFF41295A), Color(0xFF2F0743)],
];

class YearSelectorList extends ConsumerWidget {
  const YearSelectorList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yearList = ref.read(availableYearsProvider);
    final selectedYear = ref.watch(selectedYearProvider);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8.br),
        border: Border.all(
          color: kWhiteColor.withValues(alpha: 0.1),
          width: 1.w,
        ),
      ),
      constraints: BoxConstraints(maxHeight: 200.h),
      child: ListView.separated(
        itemCount: yearList.length,
        shrinkWrap: true,
        itemBuilder: (context, index) {
          final year = yearList[index];
          final isSelected = year == selectedYear;

          return InkWell(
            onTap: () {
              ref.read(selectedYearProvider.notifier).state = year;
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Text(
                year.toString(),
                style:
                    isSelected
                        ? AppTypography.textLgBold.copyWith(
                          color: kPrimaryColor,
                        )
                        : AppTypography.textLgRegular.copyWith(
                          color: kWhiteColor,
                        ),
              ),
            ),
          );
        },
        separatorBuilder:
            (context, index) => Divider(
              color: kWhiteColor.withValues(alpha: 0.2),
              height: 1,
              thickness: 0.5,
            ),
      ),
    );
  }
}
