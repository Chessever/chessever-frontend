import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:chessever2/widgets/liquid_glass/glass_nav_icon.dart';
import 'package:chessever2/widgets/liquid_glass/home_search_providers.dart';
import 'package:chessever2/widgets/liquid_glass/scroll_chrome_provider.dart';
import 'package:cue/cue.dart';
import 'package:flutter/cupertino.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:motor/motor.dart';

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

  /// Per-tab slot width for [GlassTabBar.searchable] (pill ≈ this × tab count).
  static const double tabWidth = 72;

  /// Visual width of the compact tab pill island (not full-bleed).
  static double pillWidthFor(int tabCount) => tabWidth * tabCount;

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

    // Package owns multi-axis pill morph (tab shrink + search widen leftward).
    // springDescription is motor Cupertino widen physics (shared with cue).
    final bar = GlassTabBar.searchable(
      tabs: tabs,
      selectedIndex: selectedIndex.clamp(0, tabs.length - 1),
      onTabSelected: _onTabSelected,
      isSearchActive: searchActive,
      springDescription: GlassMotion.searchMorphSpring,
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
      // Per-tab slot width (package: pill ≈ tabWidth × tabCount). Keep ~70–88
      // so 3 tabs stay a compact floating island, not a full-bleed slab.
      tabWidth: BottomNavBar.tabWidth,
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

    // Unique e2e keys on translucent hit targets sized to the compact pill
    // only (tabWidth × tabCount). Must NOT span the gap between pill and
    // search circle — otherwise taps in empty space change tabs.
    final tabCount = BottomNavBarItem.values.length;
    final pillW = BottomNavBar.pillWidthFor(tabCount);
    final island = Stack(
      alignment: Alignment.bottomCenter,
      children: [
        bar,
        if (!searchActive)
          Positioned(
            left: BottomNavBar.horizontalPadding,
            width: pillW,
            bottom: BottomNavBar.verticalPadding,
            height: BottomNavBar.barHeight,
            child: Row(
              children: [
                for (var i = 0; i < tabCount; i++)
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

    // Motion stack (Apple Music widen forward / snappy back):
    // 1) cue — mid-morph scale pulse (1 → peak → 1; both rests identity)
    // 2) motor morph progress — continuous breathe + lift (directional springs)
    // 3) motor scroll chrome — minimize on scroll (separate axis)
    // Package springDescription already widens the search pill itself.
    //
    // Important: resting collapsed/expanded must be identity transforms so
    // e2e hit slots and layout stay exact (no permanent 0.94 scale).
    return Cue.onToggle(
      toggled: searchActive,
      motion: GlassMotion.cueWiden,
      reverseMotion: GlassMotion.cueCollapse,
      acts: [
        // Soft inflate mid-open; ends match so collapsed layout is unscaled.
        ScaleAct.keyframed(
          alignment: Alignment.bottomCenter,
          frames: Keyframes.fractional(
            const [
              FKeyframe.key(1.0, at: 0.0),
              FKeyframe.key(1.04, at: 0.42),
              FKeyframe.key(1.0, at: 1.0),
            ],
            duration: GlassMotion.widenDuration,
          ),
        ),
      ],
      child: SingleMotionBuilder(
        motion: GlassMotion.searchDirection(searchActive),
        value: searchActive ? 1.0 : 0.0,
        builder: (context, morphT, child) {
          final breathe = GlassMotion.morphBreathe(morphT);
          final lift = GlassMotion.morphLift(morphT);
          return Transform.translate(
            offset: Offset(0, lift),
            child: Transform.scale(
              scale: breathe,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          );
        },
        child: SingleMotionBuilder(
          motion: GlassMotion.scrollChrome,
          value: chrome.scale,
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              alignment: Alignment.bottomCenter,
              child: child,
            );
          },
          child: island,
        ),
      ),
    );
  }
}
