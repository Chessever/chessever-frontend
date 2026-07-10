import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/liquid_glass/glass_nav_icon.dart';
import 'package:chessever2/widgets/liquid_glass/home_search_providers.dart';
import 'package:chessever2/widgets/liquid_glass/scroll_chrome_provider.dart';
import 'package:flutter/cupertino.dart';
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

/// Floating liquid-glass searchable bottom island (Apple Music morph).
///
/// Circular search control + tab pill; search expands horizontally with
/// package jelly morph and takes width from the pill.
class BottomNavBar extends ConsumerStatefulWidget {
  const BottomNavBar({super.key});

  static const double barHeight = 64;
  static const double verticalPadding = 12;
  static const double horizontalPadding = 16;

  @override
  ConsumerState<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends ConsumerState<BottomNavBar> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocus;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocus = FocusNode();
    _searchController.addListener(_onSearchText);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchText);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchText() {
    ref.read(homeBottomSearchTextProvider.notifier).state =
        _searchController.text;
  }

  void _onTabSelected(int index) {
    final previous = ref.read(selectedBottomNavBarItemProvider);
    final next = BottomNavBarItem.values[index];
    if (previous == next) {
      ref.read(bottomNavBarReTapRequestProvider.notifier).request(next);
      return;
    }

    ref.read(selectedBottomNavBarItemProvider.notifier).state = next;
    ref.read(homeScrollChromeProvider.notifier).reset();
    // Collapse search when switching tabs.
    if (ref.read(homeBottomSearchExpandedProvider)) {
      ref.read(homeBottomSearchExpandedProvider.notifier).state = false;
      _searchFocus.unfocus();
    }

    unawaited(
      AnalyticsService.instance.trackEvent(
        'Bottom Nav Changed',
        properties: {'previous_tab': previous.name, 'tab': next.name},
      ),
    );
  }

  void _setSearchActive(bool active) {
    ref.read(homeBottomSearchExpandedProvider.notifier).state = active;
    if (active) {
      // Jump to Events for global search results surface when expanding.
      final tab = ref.read(selectedBottomNavBarItemProvider);
      if (tab == BottomNavBarItem.tournaments) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _searchFocus.requestFocus();
        });
      }
    } else {
      _searchFocus.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedItem = ref.watch(selectedBottomNavBarItemProvider);
    final chrome = ref.watch(homeScrollChromeProvider);
    final searchActive = ref.watch(homeBottomSearchExpandedProvider);
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
          glowColor: selectedColor.withValues(alpha: 0.35),
        ),
    ];

    // Package searchable morph: search circle + tab pill jelly expand.
    // tabWidth keeps the pill a tight island (avoids full-width left slab).
    final bar = GlassTabBar.searchable(
      tabs: tabs,
      selectedIndex: selectedIndex.clamp(0, tabs.length - 1),
      onTabSelected: _onTabSelected,
      isSearchActive: searchActive,
      searchConfig: GlassSearchBarConfig(
        onSearchToggle: _setSearchActive,
        hintText: 'Search',
        controller: _searchController,
        focusNode: _searchFocus,
        autoFocusOnExpand: true,
        expandWhenActive: true,
        showsCancelButton: true,
        onChanged: (_) => _onSearchText(),
        onCancelTap: () {
          _searchController.clear();
          ref.read(homeBottomSearchTextProvider.notifier).state = '';
          _setSearchActive(false);
        },
        searchIcon: KeyedSubtree(
          key: e2eKey(E2eIds.eventsSearchField),
          child: Icon(
            CupertinoIcons.search,
            color: inactiveColor,
            size: 22,
          ),
        ),
        textColor: context.colors.textPrimary,
        cursorColor: selectedColor,
        searchIconColor: inactiveColor,
      ),
      barHeight: BottomNavBar.barHeight,
      searchBarHeight: 50,
      verticalPadding: BottomNavBar.verticalPadding,
      horizontalPadding: BottomNavBar.horizontalPadding,
      // Tight floating pill — not a full-bleed left edge slab.
      tabWidth: 210,
      tabPillAnchor: GlassTabPillAnchor.start,
      enableBlend: false,
      showIndicator: true,
      selectedIconColor: selectedColor,
      unselectedIconColor: inactiveColor,
      selectedLabelColor: selectedColor,
      unselectedLabelColor: inactiveColor,
      iconSize: 22,
      labelFontSize: 11,
      quality: GlassQuality.standard,
    );

    // Unique e2e keys on translucent hit targets over the tab pill only
    // (search morph owns the right circle).
    final island = Stack(
      alignment: Alignment.bottomCenter,
      children: [
        bar,
        if (!searchActive)
          Positioned(
            left: BottomNavBar.horizontalPadding,
            // Leave room for the search circle on the right.
            right: BottomNavBar.horizontalPadding + 64,
            bottom: BottomNavBar.verticalPadding,
            height: BottomNavBar.barHeight,
            child: Row(
              children: [
                for (var i = 0; i < BottomNavBarItem.values.length; i++)
                  Expanded(
                    child: GestureDetector(
                      key: switch (BottomNavBarItem.values[i]) {
                        BottomNavBarItem.tournaments =>
                          e2eKey(E2eIds.navEvents),
                        BottomNavBarItem.calendar =>
                          e2eKey(E2eIds.navCalendar),
                        BottomNavBarItem.library => e2eKey(E2eIds.navLibrary),
                      },
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _onTabSelected(i),
                      child: const SizedBox.expand(),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );

    return AnimatedScale(
      scale: chrome.scale,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: island,
    );
  }
}
