import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/liquid_glass/glass_nav_icon.dart';
import 'package:chessever2/widgets/liquid_glass/scroll_chrome_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

enum BottomNavBarItem { tournaments, calendar, library }

/// Emitted whenever the user taps the already-selected bottom nav item.
/// Screens that own a scrollable surface for [item] should listen and
/// scroll their active list back to the top. [sequence] increments on
/// every fresh request so repeated re-taps re-fire the listener even
/// when [item] hasn't changed.
class BottomNavBarReTapRequest {
  const BottomNavBarReTapRequest({required this.item, required this.sequence});

  final BottomNavBarItem item;
  final int sequence;
}

class BottomNavBarReTapRequestNotifier
    extends StateNotifier<BottomNavBarReTapRequest> {
  BottomNavBarReTapRequestNotifier()
    : super(
        const BottomNavBarReTapRequest(
          item: BottomNavBarItem.tournaments,
          sequence: 0,
        ),
      );

  void request(BottomNavBarItem item) {
    state = BottomNavBarReTapRequest(item: item, sequence: state.sequence + 1);
  }
}

final bottomNavBarReTapRequestProvider = StateNotifierProvider<
  BottomNavBarReTapRequestNotifier,
  BottomNavBarReTapRequest
>((ref) => BottomNavBarReTapRequestNotifier());

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

/// Floating liquid-glass bottom tab island for the phone home shell.
///
/// Uses package [GlassTabBar.bottom] (floating pill). Scroll-driven
/// minimize scale is applied around the package surface via
/// [homeScrollChromeProvider] — the package still owns the glass rendering.
class BottomNavBar extends ConsumerWidget {
  const BottomNavBar({super.key});

  static const double barHeight = 64;
  static const double verticalPadding = 12;
  static const double horizontalPadding = 20;

  void _onTabSelected(WidgetRef ref, int index) {
    final previous = ref.read(selectedBottomNavBarItemProvider);
    final next = BottomNavBarItem.values[index];
    if (previous == next) {
      // Same tab re-tapped: signal screens to scroll their active list
      // to top. Selected subtab + data are preserved; no pull-to-refresh.
      ref.read(bottomNavBarReTapRequestProvider.notifier).request(next);
      return;
    }

    ref.read(selectedBottomNavBarItemProvider.notifier).state = next;
    // Expand chrome when switching tabs so the new feed starts full-size.
    ref.read(homeScrollChromeProvider.notifier).reset();

    unawaited(
      AnalyticsService.instance.trackEvent(
        'Bottom Nav Changed',
        properties: {'previous_tab': previous.name, 'tab': next.name},
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedItem = ref.watch(selectedBottomNavBarItemProvider);
    final chrome = ref.watch(homeScrollChromeProvider);
    final isLight = context.isLightTheme;
    final selectedIndex = BottomNavBarItem.values.indexOf(selectedItem);

    final selectedColor = isLight ? kPrimaryColor : context.colors.textPrimary;
    final inactiveColor =
        isLight ? context.colors.textTertiary : context.colors.tabInactive;

    final tabs = <GlassTab>[
      for (final item in BottomNavBarItem.values)
        GlassTab(
          icon: GlassNavIcon(bottomNavBarIcons[item]!),
          label: namesBottomNavBarIcons[item]!,
          glowColor: selectedColor.withValues(alpha: 0.45),
        ),
    ];

    final bar = GlassTabBar.bottom(
      tabs: tabs,
      selectedIndex: selectedIndex.clamp(0, tabs.length - 1),
      onTabSelected: (index) => _onTabSelected(ref, index),
      barHeight: barHeight,
      verticalPadding: verticalPadding,
      horizontalPadding: horizontalPadding,
      selectedIconColor: selectedColor,
      unselectedIconColor: inactiveColor,
      selectedLabelColor: selectedColor,
      unselectedLabelColor: inactiveColor,
      iconSize: 22,
      labelFontSize: 11,
    );

    // GlassTabBar dual-paints selected/unselected layers for the jelly
    // indicator morph, so keys cannot live on tab icons (they'd duplicate).
    // Unique e2e keys sit on a translucent hit-target row that routes to the
    // same handler (preserves re-tap / analytics / selection).
    final island = Stack(
      alignment: Alignment.bottomCenter,
      children: [
        bar,
        Positioned(
          left: horizontalPadding,
          right: horizontalPadding,
          bottom: verticalPadding,
          height: barHeight,
          child: Row(
            children: [
              for (var i = 0; i < BottomNavBarItem.values.length; i++)
                Expanded(
                  child: GestureDetector(
                    key: switch (BottomNavBarItem.values[i]) {
                      BottomNavBarItem.tournaments => e2eKey(E2eIds.navEvents),
                      BottomNavBarItem.calendar => e2eKey(E2eIds.navCalendar),
                      BottomNavBarItem.library => e2eKey(E2eIds.navLibrary),
                    },
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _onTabSelected(ref, i),
                    child: const SizedBox.expand(),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    // Scroll-driven shrink: package owns glass; we only scale the island.
    // Alignment.bottomCenter keeps the pill anchored to the bottom edge while
    // it shrinks (Instagram / iOS 26 scroll-minimize behaviour).
    return AnimatedScale(
      scale: chrome.scale,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: island,
    );
  }
}
