import 'dart:async';

import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A tablet-optimized navigation rail that replaces the bottom navigation bar.
/// Provides a vertical navigation experience with icons and labels.
class TabletNavRail extends ConsumerWidget {
  final GlobalKey<ScaffoldState>? scaffoldKey;

  const TabletNavRail({super.key, this.scaffoldKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedItem = ref.watch(selectedBottomNavBarItemProvider);

    // Get orientation from MediaQuery for reliable updates
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    // Wider rail in landscape for better touch targets
    final railWidth = isLandscape ? 110.0 : 90.0;

    return Container(
      width: railWidth,
      color: context.colors.background,
      child: SafeArea(
        child: Column(
          children: [
            // Menu button at top
            Padding(
              padding: const EdgeInsets.only(top: 16.0, bottom: 24.0),
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
                children:
                    BottomNavBarItem.values.map((item) {
                      return _NavRailItem(
                        item: item,
                        isSelected: selectedItem == item,
                        onTap: () {
                          final previous = ref.read(
                            selectedBottomNavBarItemProvider,
                          );
                          if (previous == item) return;

                          ref
                              .read(selectedBottomNavBarItemProvider.notifier)
                              .state = item;

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
        width: 48.0,
        height: 48.0,
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Icon(
          Icons.menu_rounded,
          color: context.colors.iconPrimary,
          size: 24.0,
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

    // Get orientation from MediaQuery for reliable updates
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    // Use fixed pixel sizes for tablet to avoid ResponsiveHelper timing issues
    final iconSize = isLandscape ? 28.0 : 24.0;
    final iconColor = isSelected
        ? kPrimaryColor
        : context.isLightTheme
            ? context.colors.textTertiary
            : context.colors.textPrimaryMuted;
    final verticalPadding = isLandscape ? 16.0 : 12.0;
    final horizontalIconPadding = isLandscape ? 20.0 : 16.0;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          vertical: verticalPadding,
          horizontal: 8.0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Indicator background for selected item
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalIconPadding,
                vertical: 8.0,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? kPrimaryColor.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: SvgWidget(
                iconPath,
                width: iconSize,
                height: iconSize,
                colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
              ),
            ),
            const SizedBox(height: 4.0),
            // Label
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.0,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? kPrimaryColor
                    : context.isLightTheme
                        ? context.colors.textTertiary
                        : context.colors.textPrimaryMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
