import 'package:chessever2/utils/responsive_helper.dart';
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

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  final TextEditingController _searchController = TextEditingController();
  int _selectedYear = 2025;
  String _selectedMonth = 'May'; // Default to current month

  // List of all months
  final List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    // Set current month based on date - for now we'll use the current date
    final currentDate = DateTime.now();
    _selectedMonth = _months[currentDate.month - 1];
    _selectedYear = currentDate.year;
  }

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
            padding:  EdgeInsets.symmetric(horizontal: 16.sp),
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
                          barrierColor: Colors.black.withOpacity(0.5),
                          builder: (context) => const FilterPopup(),
                        );
                      },
                    ),
                  ),
                ),

                // Small spacing between search bar and dropdown
                const SizedBox(width: 8),

                // Year dropdown with border outline and transparent background
                Expanded(
                  flex: 3,
                  child: Container(
                    height: 40, // Match height with search bar
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedYear,
                        onChanged: (int? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _selectedYear = newValue;
                            });
                          }
                        },
                        icon: const Icon(
                          Icons.keyboard_arrow_down,
                          color: kWhiteColor,
                          size: 24,
                        ),
                        isExpanded: true,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        style: AppTypography.textLgBold.copyWith(
                          color: kWhiteColor,
                        ),
                        dropdownColor: kBackgroundColor,
                        // Match background
                        items:
                            [
                              2023,
                              2024,
                              2025,
                              2026,
                              2027,
                            ].map<DropdownMenuItem<int>>((int value) {
                              return DropdownMenuItem<int>(
                                value: value,
                                alignment: Alignment.center,
                                child: Text(
                                  value.toString(),
                                  style: AppTypography.textLgBold.copyWith(
                                    color: kWhiteColor,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              );
                            }).toList(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          // Increased gap to 24px between search bar and first month card
          // Months list
          Expanded(
            child: ListView.builder(
              itemCount: _months.length,
              padding: EdgeInsets.zero,
              itemBuilder: (context, index) {
                final month = _months[index];
                final isSelected = month == _selectedMonth;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedMonth = month;
                    });

                    // Navigate to tournament details screen
                    Navigator.pushNamed(
                      context,
                      '/tournament_details',
                      arguments: {'month': month, 'year': _selectedYear},
                    );
                  },
                  child: Container(
                    height: 42, // Set fixed height to 42px
                    margin: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 16, // 16px gap between cards
                      top:
                          index == 0
                              ? 16
                              : 0, // Add top margin only for first card
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? kActiveCalendarColor : kBlack2Color,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                        bottomLeft: Radius.zero,
                        bottomRight: Radius.zero,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12, // 12px padding left and right
                        vertical: 8, // 8px padding top and bottom
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          month,
                          style: AppTypography.textLgMedium.copyWith(
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
