import 'package:chessever2/utils/month_converter.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/divider_widget.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../theme/app_theme.dart';
import '../widgets/simple_search_bar.dart';
import '../utils/app_typography.dart';
import '../widgets/filter_popup.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

final selectedYearProvider = StateProvider<int>((ref) {
  final currentDate = DateTime.now();
  return currentDate.year; // Default to current year
});

final selectedMonthProvider = StateProvider<int>((ref) {
  final currentDate = DateTime.now();
  return currentDate.month; // Default to current year
});

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 24.h + MediaQuery.of(context).viewPadding.top),
          // Search bar with year dropdown beside it
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.sp),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Search bar
                Expanded(
                  flex: 7,
                  child: Hero(
                    tag: 'search_bar',
                    child: SimpleSearchBar(
                      controller: _searchController,
                      hintText: 'Search tournaments or players',
                      onChanged: (value) {
                        // Handle search
                      },
                      onMenuTap: () {
                        // Handle menu tap
                        print('Menu tapped');
                      },
                      onFilterTap: () {
                        // Show the filter popup
                        showDialog(
                          context: context,
                          barrierColor: kLightBlack,
                          builder: (context) => const FilterPopup(),
                        );
                      },
                    ),
                  ),
                ),

                // Small spacing between search bar and dropdown
                SizedBox(width: 8.w),

                // Year dropdown with border outline and transparent background
                Expanded(
                  flex: 3,
                  child: Container(
                    height: 40.h,
                    padding: EdgeInsets.symmetric(horizontal: 12.w),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(8.br),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                        width: 1.w,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: ref.watch(selectedYearProvider),

                        onChanged: (int? newValue) {
                          if (newValue != null) {
                            ref.read(selectedYearProvider.notifier).state =
                                newValue;
                          }
                        },
                        icon: Icon(
                          Icons.keyboard_arrow_down_outlined,
                          color: kWhiteColor,
                          size: 20.ic,
                        ),
                        style: AppTypography.textLgBold.copyWith(
                          color: kWhiteColor,
                        ),
                        dropdownColor: kBlack2Color,
                        borderRadius: BorderRadius.circular(20.br),
                        isExpanded: true,
                        // Items
                        items:
                            [2023, 2024, 2025, 2026, 2027].asMap().entries.map((
                              entry,
                            ) {
                              final index = entry.key;
                              final value = entry.value;
                              final isLast = index == 4;

                              return DropdownMenuItem<int>(
                                value: value,
                                child: Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.symmetric(
                                    vertical: 12.sp,
                                    horizontal: 20.sp,
                                  ),
                                  decoration: BoxDecoration(
                                    border:
                                        !isLast
                                            ? Border(
                                              bottom: BorderSide(
                                                color: Colors.white.withOpacity(
                                                  0.1,
                                                ),
                                                width: 0.5,
                                              ),
                                            )
                                            : null,
                                  ),
                                  child: Text(
                                    value.toString(),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),

                        // Selected item style
                        selectedItemBuilder: (BuildContext context) {
                          return [2023, 2024, 2025, 2026, 2027].map((value) {
                            return Container(
                              alignment: Alignment.centerLeft,
                              padding: EdgeInsets.only(left: 0),
                              child: Text(
                                value.toString(),
                                style: AppTypography.textLgBold.copyWith(
                                  color: kWhiteColor,
                                ),
                              ),
                            );
                          }).toList();
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 8.h),
          // Increased gap to 24px between search bar and first month card
          // Months list
          Expanded(
            child: ListView.builder(
              itemCount: MonthConverter.getAllMonthNames().length,
              padding: EdgeInsets.zero,
              itemBuilder: (context, index) {
                final month = MonthConverter.getAllMonthNames()[index];
                final monthNumber = MonthConverter.monthNameToNumber(month);

                final isSelected =
                    monthNumber == ref.read(selectedMonthProvider);

                return GestureDetector(
                  onTap: () {
                    ref
                        .read(selectedMonthProvider.notifier)
                        .state = MonthConverter.monthNameToNumber(month);

                    // Navigate to tournament details screen
                    Navigator.pushNamed(context, '/calendar_detail_screen');
                  },
                  child: Container(
                    height: 42.h, // Set fixed height to 42px
                    margin: EdgeInsets.only(
                      left: 16.sp,
                      right: 16.sp,
                      bottom: 16.sp, // 16px gap between cards
                      top:
                          index == 0
                              ? 16
                              : 0, // Add top margin only for first card
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? kActiveCalendarColor : kBlack2Color,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(8.br),
                        topRight: Radius.circular(8.br),
                        bottomLeft: Radius.zero,
                        bottomRight: Radius.zero,
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12.sp, // 12px padding left and right
                        vertical: 8.sp, // 8px padding top and bottom
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          month,
                          style: AppTypography.textLgRegular.copyWith(
                            color: isSelected ? kBlack2Color : kWhiteColor,
                          ),
                        ),
                      ),
                    ),
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

class YearSelectorList extends ConsumerWidget {
  final List<int> years = [2023, 2024, 2025, 2026, 2027];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedYear = ref.watch(selectedYearProvider);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8.br),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.w),
      ),
      constraints: BoxConstraints(maxHeight: 200.h), // Scroll limit
      child: ListView.separated(
        itemCount: years.length,
        shrinkWrap: true,
        itemBuilder: (context, index) {
          final year = years[index];
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
              color: Colors.white.withOpacity(0.2),
              height: 1,
              thickness: 0.5,
            ),
      ),
    );
  }
}
