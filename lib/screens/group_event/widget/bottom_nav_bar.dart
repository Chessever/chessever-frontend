import 'package:chessever2/screens/group_event/widget/bottom_nav_bar_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum BottomNavBarItem { tournaments, calendar, library }

final Map<BottomNavBarItem, String> bottomNavBarIcons = {
  BottomNavBarItem.tournaments: SvgAsset.tournamentIcon,
  BottomNavBarItem.calendar: SvgAsset.calendarIcon,
  BottomNavBarItem.library: SvgAsset.bookIcon,
};

final namesBottomNavBarIcons = {
  BottomNavBarItem.tournaments: 'Events',
  BottomNavBarItem.calendar: 'Calendar',
  BottomNavBarItem.library: 'Library',
};

final selectedBottomNavBarItemProvider =
    StateProvider.autoDispose<BottomNavBarItem>(
      (ref) => BottomNavBarItem.tournaments,
    );

class BottomNavBar extends ConsumerWidget {
  const BottomNavBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedItem = ref.watch(selectedBottomNavBarItemProvider);
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      padding: EdgeInsets.only(
        top: 0,
        bottom: MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: BoxDecoration(
        color: kBackgroundColor,
        border: Border(top: BorderSide(color: kDarkGreyColor, width: 1.w)),
      ),
      height: (70.h + bottomPadding).clamp(70.0, 120.0),
      child: Row(
        children: List.generate(
          BottomNavBarItem.values.length,
          (index) => BottomNavBarWidget(
            width:
                MediaQuery.of(context).size.width /
                BottomNavBarItem.values.length,
            isSelected: selectedItem == BottomNavBarItem.values[index],
            onTap: () {
              ref.read(selectedBottomNavBarItemProvider.notifier).state =
                  BottomNavBarItem.values[index];
            },
            svgIcon: bottomNavBarIcons[BottomNavBarItem.values[index]]!,
            title: namesBottomNavBarIcons[BottomNavBarItem.values[index]]!,
          ),
        ),
      ),
    );
  }
}
