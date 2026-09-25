import 'dart:async';

import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// A tablet-optimized navigation rail that replaces the bottom navigation bar.
/// Provides a vertical navigation experience with icons and labels.
class TabletNavRail extends ConsumerWidget {
  final GlobalKey<ScaffoldState>? scaffoldKey;

  const TabletNavRail({super.key, this.scaffoldKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedItem = ref.watch(selectedBottomNavBarItemProvider);

    // Get orientation from MediaQuery for reliable updates
    final orientation = MediaQuery.orientationOf(context);
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
                          if (previous == item) {
                            // Same contract as the phone bar: a re-tap asks
                            // the tab to jump (Flow: next clip, lists: top).
                            ref
                                .read(bottomNavBarReTapRequestProvider.notifier)
                                .request(item);
                            return;
                          }

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
    // The bare mark on the rail, no tile behind it; 48 square to tap.
    return SizedBox.square(
      dimension: 48.0,
      child: IconButton(
        tooltip: 'Menu',
        onPressed: onTap,
        padding: EdgeInsets.zero,
        color: context.colors.iconPrimary,
        icon: const Icon(Icons.menu_rounded, size: 24.0),
      ),
    );
  }
}

/// One rail slot, in the phone bar's language: the selected slot in full ink
/// with a heavier label, the rest in secondary ink (both clear 4.5:1 on the
/// rail in either theme). A press settles the slot to 0.97 on a spring and
/// lets go the same way; reduced motion snaps instead.
class _NavRailItem extends StatefulWidget {
  final BottomNavBarItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavRailItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_NavRailItem> createState() => _NavRailItemState();
}

class _NavRailItemState extends State<_NavRailItem> {
  static const _press = CupertinoMotion.snappy(
    duration: Duration(milliseconds: 260),
  );

  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final iconPath = bottomNavBarIcons[widget.item]!;
    final title = namesBottomNavBarIcons[widget.item]!;

    // Get orientation from MediaQuery for reliable updates
    final orientation = MediaQuery.orientationOf(context);
    final isLandscape = orientation == Orientation.landscape;

    // Use fixed pixel sizes for tablet to avoid ResponsiveHelper timing issues
    final iconSize = isLandscape ? 28.0 : 24.0;
    final colors = context.colors;
    final ink = widget.isSelected ? colors.textPrimary : colors.textSecondary;
    final verticalPadding = isLandscape ? 16.0 : 12.0;

    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: widget.isSelected,
        child: GestureDetector(
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              vertical: verticalPadding,
              horizontal: 8.0,
            ),
            child: SingleMotionBuilder(
              motion: _press,
              value: _pressed ? 0.97 : 1.0,
              active: !MediaQuery.disableAnimationsOf(context),
              builder:
                  (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: SvgWidget(
                      iconPath,
                      width: iconSize,
                      height: iconSize,
                      colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
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
                      fontWeight:
                          widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
