import 'dart:async';

import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A tablet-optimized navigation rail that replaces the bottom navigation bar.
/// Provides a vertical navigation experience with icons and labels.
class TabletNavRail extends ConsumerWidget {
  final GlobalKey<ScaffoldState>? scaffoldKey;

  const TabletNavRail({super.key, this.scaffoldKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedItem = ref.watch(selectedBottomNavBarItemProvider);
    final isLandscape = ResponsiveHelper.isLandscape;

    // Wider rail in landscape for better touch targets
    final railWidth = isLandscape ? 110.0 : 90.0;

    return Container(
      width: railWidth,
      color: kBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            // Menu button at top
            Padding(
              padding: EdgeInsets.only(top: 16.sp, bottom: 24.sp),
              child: _MenuButton(
                onTap: () {
                  scaffoldKey?.currentState?.openDrawer();
                },
              ),
            ),
            // Navigation items
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: BottomNavBarItem.values.map((item) {
                  return _NavRailItem(
                    item: item,
                    isSelected: selectedItem == item,
                    onTap: () {
                      final previous =
                          ref.read(selectedBottomNavBarItemProvider);
                      if (previous == item) return;

                      ref.read(selectedBottomNavBarItemProvider.notifier).state =
                          item;

                      unawaited(
                        AnalyticsService.instance.trackEvent(
                          'Tab Changed',
                          properties: {
                            'previous_tab': previous.name,
                            'tab': item.name,
                            'navigation_type': 'rail',
                          },
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final VoidCallback onTap;

  const _MenuButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48.sp,
        height: 48.sp,
        decoration: BoxDecoration(
          color: kDarkGreyColor.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12.br),
        ),
        child: Icon(
          Icons.menu_rounded,
          color: Colors.white,
          size: 24.ic,
        ),
      ),
    );
  }
}

class _NavRailItem extends StatelessWidget {
  final BottomNavBarItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavRailItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconPath = bottomNavBarIcons[item]!;
    final title = namesBottomNavBarIcons[item]!;
    final isLandscape = ResponsiveHelper.isLandscape;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          vertical: isLandscape ? 16.sp : 12.sp,
          horizontal: 8.sp,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Indicator background for selected item
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(
                horizontal: isLandscape ? 20.sp : 16.sp,
                vertical: 8.sp,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? kPrimaryColor.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16.br),
              ),
              child: SvgPicture.asset(
                iconPath,
                width: 24.ic,
                height: 24.ic,
                colorFilter: ColorFilter.mode(
                  isSelected ? kPrimaryColor : Colors.white.withValues(alpha: 0.7),
                  BlendMode.srcIn,
                ),
              ),
            ),
            SizedBox(height: 4.sp),
            // Label
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.f,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? kPrimaryColor : Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
