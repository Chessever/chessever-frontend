import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/screens/calendar/provider/calendar_screen_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:chessever2/utils/app_typography.dart';

/// Filter mode for the calendar view
enum CalendarFilterMode { all, upcoming, favorites }

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

final calendarFilterModeProvider = StateProvider<CalendarFilterMode>((ref) {
  return CalendarFilterMode.all;
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
                              hintText: 'Search Events or Players',
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
                    SizedBox(width: 12.w),
                    /// Year dropdown
                    Container(
                      height: 48.h,
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
                  ],
                ),
                SizedBox(height: 12.h),
                Row(
                  children: [
                    /// Time Control dropdown with icons
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
                            hint: Row(
                              children: [
                                Icon(
                                  Icons.speed_outlined,
                                  size: 16.ic,
                                  color: kDarkGreyColor,
                                ),
                                SizedBox(width: 8.w),
                                Text(
                                  'Time Control',
                                  style: AppTypography.textSmRegular.copyWith(
                                    color: kDarkGreyColor,
                                  ),
                                ),
                              ],
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
                            selectedItemBuilder: (context) {
                              return [
                                _buildTimeControlRow(null, 'All Formats'),
                                _buildTimeControlRow('Blitz', 'Blitz'),
                                _buildTimeControlRow('Rapid', 'Rapid'),
                                _buildTimeControlRow('Standard', 'Standard'),
                                _buildTimeControlRow('Bullet', 'Bullet'),
                              ];
                            },
                            items: [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: _buildTimeControlDropdownItem(null, 'All Formats'),
                              ),
                              ...timeControls.map((value) {
                                return DropdownMenuItem<String?>(
                                  value: value,
                                  child: _buildTimeControlDropdownItem(value, value),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),

                /// Quick Filter Buttons (Upcoming / Favorites)
                _QuickFilterButtons(),
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
                    final isTablet = ResponsiveHelper.isTablet;
                    final crossAxisCount = isTablet ? 3 : 2;

                    return RefreshIndicator(
                      onRefresh: () async {
                        // Invalidate the calendar provider to refresh data
                        ref.invalidate(calendarScreenProvider);
                      },
                      color: kPrimaryColor,
                      backgroundColor: kBlack2Color,
                      displacement: 60.h,
                      strokeWidth: 3.w,
                      child: GridView.builder(
                        padding: EdgeInsets.symmetric(horizontal: 16.sp),
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 12.sp,
                          crossAxisSpacing: 12.sp,
                          childAspectRatio: 2.2,
                        ),
                        itemCount: data.length,
                        itemBuilder: (context, index) {
                          final summary = data[index];
                          return _MonthButton(
                            monthName: summary.monthName,
                            eventCount: summary.eventCount,
                            onTap: () {
                              ref.read(selectedMonthProvider.notifier).state =
                                  summary.monthNumber;
                              Navigator.pushNamed(
                                context,
                                '/calendar_detail_screen',
                              );
                            },
                          );
                        },
                      ),
                    );
                  },
                  error: (e, _) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Failed To Load Months!\nPlease Try Again Later',
                            style: AppTypography.textLgRegular.copyWith(
                              color: kWhiteColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  },
                  loading: () {
                    final isTablet = ResponsiveHelper.isTablet;
                    final crossAxisCount = isTablet ? 3 : 2;
                    final months = [
                      'January', 'February', 'March', 'April',
                      'May', 'June', 'July', 'August',
                      'September', 'October', 'November', 'December',
                    ];

                    return SkeletonWidget(
                      child: GridView.builder(
                        padding: EdgeInsets.symmetric(horizontal: 16.sp),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 12.sp,
                          crossAxisSpacing: 12.sp,
                          childAspectRatio: 2.2,
                        ),
                        itemCount: 12,
                        itemBuilder: (context, index) {
                          return _MonthButton(
                            monthName: months[index],
                            eventCount: (index % 3 == 0) ? index + 1 : 0,
                            onTap: () {},
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

  /// Build time control row for selected item display
  Widget _buildTimeControlRow(String? timeControl, String label) {
    return Row(
      children: [
        _getTimeControlIcon(timeControl),
        SizedBox(width: 8.w),
        Text(
          label,
          style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
        ),
      ],
    );
  }

  /// Build time control dropdown item with icon
  Widget _buildTimeControlDropdownItem(String? timeControl, String label) {
    return Row(
      children: [
        _getTimeControlIcon(timeControl),
        SizedBox(width: 10.w),
        Text(
          label,
          style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
        ),
      ],
    );
  }

  /// Get the appropriate icon for a time control
  Widget _getTimeControlIcon(String? timeControl) {
    if (timeControl == null) {
      return Icon(
        Icons.grid_view_rounded,
        size: 16.ic,
        color: kWhiteColor70,
      );
    }

    final lower = timeControl.toLowerCase();
    String? assetPath;

    if (lower.contains('blitz')) {
      assetPath = 'assets/pngs/blitz.png';
    } else if (lower.contains('rapid')) {
      assetPath = 'assets/pngs/rapid.png';
    } else if (lower.contains('standard') || lower.contains('classic')) {
      assetPath = 'assets/pngs/classical.png';
    } else if (lower.contains('bullet')) {
      // No bullet asset, use a lightning icon
      return Icon(
        Icons.flash_on_rounded,
        size: 16.ic,
        color: const Color(0xFFFFD700), // Gold color for bullet
      );
    }

    if (assetPath != null) {
      return Image.asset(
        assetPath,
        width: 16.sp,
        height: 16.sp,
        fit: BoxFit.contain,
      );
    }

    return Icon(
      Icons.timer_outlined,
      size: 16.ic,
      color: kWhiteColor70,
    );
  }
}

/// Simple month button - just name and count
class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.monthName,
    required this.eventCount,
    required this.onTap,
  });

  final String monthName;
  final int eventCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8.br),
      child: InkWell(
        borderRadius: BorderRadius.circular(8.br),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: kBlack2Color,
            borderRadius: BorderRadius.circular(8.br),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          child: Row(
            children: [
              // Month name takes available space, aligns left
              Expanded(
                child: Text(
                  monthName,
                  style: AppTypography.textMdMedium.copyWith(
                    color: kWhiteColor,
                  ),
                ),
              ),
              // Event count badge always on the right
              if (eventCount > 0)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 4.sp),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    eventCount.toString(),
                    style: AppTypography.textXsBold.copyWith(
                      color: kWhiteColor70,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickFilterButtons extends ConsumerWidget {
  const _QuickFilterButtons();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterMode = ref.watch(calendarFilterModeProvider);
    final calendarData = ref.watch(calendarScreenProvider);
    final favoriteEvents = ref.watch(favoriteEventsProvider);
    final selectedYear = ref.watch(selectedYearProvider);
    final currentYear = DateTime.now().year;
    final isUpcomingDisabled = selectedYear > currentYear;

    // Calculate upcoming count (events starting today or in future)
    final upcomingCount = calendarData.maybeWhen(
      data: (summaries) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        int count = 0;
        for (final summary in summaries) {
          for (final event in summary.events) {
            final startDate = event.startDate ?? event.endDate;
            if (startDate != null && !startDate.isBefore(today)) {
              count++;
            }
          }
        }
        return count;
      },
      orElse: () => 0,
    );

    // Calculate favorites count
    final favoritesCount = favoriteEvents.maybeWhen(
      data: (events) => events.length,
      orElse: () => 0,
    );

    return Row(
      children: [
        Expanded(
          child: _FilterButton(
            label: 'Upcoming',
            icon: Icons.schedule_rounded,
            count: upcomingCount,
            isSelected: filterMode == CalendarFilterMode.upcoming,
            isDisabled: isUpcomingDisabled,
            onTap: () {
              if (isUpcomingDisabled) return;
              final current = ref.read(calendarFilterModeProvider);
              ref.read(calendarFilterModeProvider.notifier).state =
                  current == CalendarFilterMode.upcoming
                      ? CalendarFilterMode.all
                      : CalendarFilterMode.upcoming;
            },
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: _FilterButton(
            label: 'Favorites',
            icon: Icons.star_rounded,
            count: favoritesCount,
            isSelected: filterMode == CalendarFilterMode.favorites,
            onTap: () {
              final current = ref.read(calendarFilterModeProvider);
              ref.read(calendarFilterModeProvider.notifier).state =
                  current == CalendarFilterMode.favorites
                      ? CalendarFilterMode.all
                      : CalendarFilterMode.favorites;
            },
          ),
        ),
      ],
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.icon,
    required this.count,
    required this.isSelected,
    required this.onTap,
    this.isDisabled = false,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final iconColor = isDisabled
        ? kDarkGreyColor
        : isSelected
            ? kPrimaryColor
            : kWhiteColor70;
    final textColor = isDisabled
        ? kDarkGreyColor
        : isSelected
            ? kPrimaryColor
            : kWhiteColor;
    final badgeColor = isDisabled
        ? Colors.white.withValues(alpha: 0.05)
        : isSelected
            ? kPrimaryColor.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.12);
    final badgeTextColor = isDisabled
        ? kDarkGreyColor
        : isSelected
            ? kPrimaryColor
            : kWhiteColor70;
    final borderColor = isDisabled
        ? Colors.white.withValues(alpha: 0.05)
        : isSelected
            ? kPrimaryColor.withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.15);
    final backgroundColor = isDisabled
        ? kBlack2Color.withValues(alpha: 0.6)
        : isSelected
            ? kPrimaryColor.withValues(alpha: 0.12)
            : kBlack2Color;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10.br),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.br),
        onTap: isDisabled ? null : onTap,
        child: Container(
          height: 44.h,
          padding: EdgeInsets.symmetric(horizontal: 14.w),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(10.br),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 1.5.w : 1.w,
            ),
            // Subtle gradient overlay for filter buttons to differentiate from month boxes
            gradient: isSelected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      kPrimaryColor.withValues(alpha: 0.15),
                      kPrimaryColor.withValues(alpha: 0.05),
                    ],
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon indicator - key visual differentiator
              Icon(
                icon,
                size: 16.ic,
                color: iconColor,
              ),
              SizedBox(width: 6.w),
              Text(
                label,
                style: AppTypography.textSmMedium.copyWith(
                  color: textColor,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (count > 0) ...[
                SizedBox(width: 6.w),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    count.toString(),
                    style: AppTypography.textXsBold.copyWith(
                      color: badgeTextColor,
                      fontSize: 10.sp,
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
