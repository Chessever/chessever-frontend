import 'package:chessever2/utils/month_converter.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup.dart';

final availableYearsProvider = Provider<List<int>>((ref) {
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
  final FocusNode focusNode = FocusNode();

  @override
  void dispose() {
    searchController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final yearList = ref.watch(availableYearsProvider);

    return ScreenWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 24.h + MediaQuery.of(context).viewPadding.top),

          /// Search bar + year dropdown
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.sp),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                /// Search bar
                Expanded(
                  flex: 7,
                  child: Hero(
                    tag: 'search_bar',
                    child: SimpleSearchBar(
                      controller: searchController,
                      focusNode: focusNode,
                      hintText: 'Search Events or Players',
                      onCloseTap: () {
                        searchController.clear();
                        focusNode.unfocus();
                      },
                      onOpenFilter: () {
                        showDialog(
                          context: context,
                          barrierColor: kLightBlack,
                          builder: (context) => const FilterPopup(),
                        );
                      },
                    ),
                  ),
                ),

                SizedBox(width: 8.w),

                /// Year dropdown
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

                        /// Dropdown items
                        items:
                            yearList.asMap().entries.map((entry) {
                              final index = entry.key;
                              final value = entry.value;
                              final isLast = index == yearList.length - 1;

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
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),

                        /// Selected item style
                        selectedItemBuilder: (BuildContext context) {
                          return yearList.map((value) {
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

          /// Month list
          Expanded(
            child: ListView.builder(
              itemCount: MonthConverter.getAllMonthNames().length,
              padding: EdgeInsets.zero,
              itemBuilder: (context, index) {
                final month = MonthConverter.getAllMonthNames()[index];
                final monthNumber = MonthConverter.monthNameToNumber(month);

                return GestureDetector(
                  onTap: () {
                    ref.read(selectedMonthProvider.notifier).state =
                        monthNumber;

                    Navigator.pushNamed(context, '/calendar_detail_screen');
                  },
                  child: Container(
                    height: 42.h,
                    margin: EdgeInsets.only(
                      left: 16.sp,
                      right: 16.sp,
                      bottom: 16.sp,
                      top: index == 0 ? 16 : 0,
                    ),
                    decoration: BoxDecoration(
                      color: kBlack2Color,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(8.br),
                        topRight: Radius.circular(8.br),
                        bottomLeft: Radius.zero,
                        bottomRight: Radius.zero,
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12.sp,
                        vertical: 8.sp,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          month,
                          style: AppTypography.textLgRegular.copyWith(
                            color: kWhiteColor,
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
  const YearSelectorList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yearList = ref.watch(availableYearsProvider);
    final selectedYear = ref.watch(selectedYearProvider);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8.br),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.w),
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
              color: Colors.white.withOpacity(0.2),
              height: 1,
              thickness: 0.5,
            ),
      ),
    );
  }
}
