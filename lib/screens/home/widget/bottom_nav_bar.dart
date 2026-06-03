import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar_widget.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum BottomNavBarItem { tournaments, calendar, library }

final Map<BottomNavBarItem, String> bottomNavBarIcons = {
  BottomNavBarItem.tournaments: SvgAsset.tournamentIcon,
  BottomNavBarItem.calendar: SvgAsset.calendarNavIcon,
  BottomNavBarItem.library: SvgAsset.libraryNavIcon,
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
      padding: EdgeInsets.only(top: 0, bottom: bottomPadding),
      decoration: BoxDecoration(
        color: context.colors.background,
        border: Border(
          top: BorderSide(color: context.colors.divider, width: 1.w),
        ),
      ),
      // Design height (70.h) is a floor, not a fixed slot: each nav item is a
      // Column (icon + label + vertical padding) whose label height rides
      // MediaQuery.textScaler. A fixed height that also had the safe-area inset
      // carved out of a capped total starved that Column on short screens /
      // large text scales / large insets and overflowed the bottom. Flooring
      // the row content (so it can grow when it must) and adding the inset on
      // top via padding keeps the normal-device look while never overflowing.
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 70.h),
        child: Row(
          children: List.generate(
          BottomNavBarItem.values.length,
          (index) => BottomNavBarWidget(
            key: switch (BottomNavBarItem.values[index]) {
              BottomNavBarItem.tournaments => e2eKey(E2eIds.navEvents),
              BottomNavBarItem.calendar => e2eKey(E2eIds.navCalendar),
              BottomNavBarItem.library => e2eKey(E2eIds.navLibrary),
            },
            width:
                MediaQuery.of(context).size.width /
                BottomNavBarItem.values.length,
            isSelected: selectedItem == BottomNavBarItem.values[index],
            onTap: () {
              final previous = ref.read(selectedBottomNavBarItemProvider);
              final next = BottomNavBarItem.values[index];
              if (previous == next) return;

              ref.read(selectedBottomNavBarItemProvider.notifier).state = next;

              unawaited(
                AnalyticsService.instance.trackEvent(
                  'Bottom Nav Changed',
                  properties: {'previous_tab': previous.name, 'tab': next.name},
                ),
              );
            },
            svgIcon: bottomNavBarIcons[BottomNavBarItem.values[index]]!,
            title: namesBottomNavBarIcons[BottomNavBarItem.values[index]]!,
            ),
          ),
        ),
      ),
    );
  }
}
