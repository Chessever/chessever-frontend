import 'dart:async';

import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/liquid_glass/glass_nav_icon.dart';
import 'package:chessever2/widgets/liquid_glass/home_search_providers.dart';
import 'package:flutter/cupertino.dart';
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

/// Canonical iOS-26 liquid-glass navigation: a single floating [GlassTabBar]
/// pill whose tabs morph into a search bar. This is the package's own
/// Apple Music / Apple News pattern — no custom island stack, no hand-rolled
/// morph physics. The bar samples the content scrolling behind it and flips
/// its icon/label brightness automatically.
class BottomNavBar extends ConsumerStatefulWidget {
  const BottomNavBar({super.key});

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
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// The searchable pill toggled expanded / collapsed. Collapsing clears the
  /// shared query so subscribed destinations (Events) reset their filter.
  void _onSearchToggle(bool active) {
    ref.read(homeBottomSearchExpandedProvider.notifier).state = active;
    if (!active) {
      _searchController.clear();
      ref.read(homeBottomSearchTextProvider.notifier).state = '';
      ref.read(homeBottomSearchFilterVisibleProvider.notifier).state = false;
      _searchFocus.unfocus();
    } else {
      ref.read(homeBottomSearchFilterVisibleProvider.notifier).state = true;
    }
  }

  void _onTabSelected(int index) {
    final previous = ref.read(selectedBottomNavBarItemProvider);
    final next = BottomNavBarItem.values[index];
    if (previous == next) {
      ref.read(bottomNavBarReTapRequestProvider.notifier).request(next);
      return;
    }

    ref.read(selectedBottomNavBarItemProvider.notifier).state = next;
    // Collapse search when switching tabs.
    if (ref.read(homeBottomSearchExpandedProvider)) {
      _onSearchToggle(false);
    }

    unawaited(
      AnalyticsService.instance.trackEvent(
        'Bottom Nav Changed',
        properties: {'previous_tab': previous.name, 'tab': next.name},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selectedItem = ref.watch(selectedBottomNavBarItemProvider);
    final selectedIndex = BottomNavBarItem.values.indexOf(selectedItem);
    final searchActive = ref.watch(homeBottomSearchExpandedProvider);

    // Bold dark glass bar with a vivid brand "jelly" indicator. The indicator's
    // refraction physics are left to the package defaults on purpose — giving it
    // a custom LiquidGlassSettings makes its lens sample the wrong backdrop and
    // paint a stray reflection while it slides. We only tint it via
    // indicatorColor and let GlassScaffold.bottomBar wire the backdrop sampling.
    final brand = colors.brand;
    return GlassTabBar.searchable(
      selectedIndex: selectedIndex,
      onTabSelected: _onTabSelected,
      isSearchActive: searchActive,
      verticalPadding: 28,
      // Give the bar its OWN richer glass (thicker, deeper) so it reads as a
      // distinct premium surface, not the same flat tint as page chrome.
      settings: const LiquidGlassSettings(
        glassColor: Color(0xA62A2A2E),
        thickness: 26,
        blur: 14,
        lightIntensity: 0,
        ambientStrength: 0,
        glowIntensity: 0,
        ambientRim: 0,
        chromaticAberration: 0,
      ),
      // Selected item wears the brand — a brand-lit icon/label reading through a
      // glass lens is what sells "premium", not a painted-in bubble.
      selectedIconColor: brand,
      unselectedIconColor: colors.tabInactive,
      selectedLabelColor: brand,
      unselectedLabelColor: colors.tabInactive,
      // Clean brand pill — NO glow halo (that was the "reflection around it")
      // and the indicator's own glass edges are zeroed so it has no rim either.
      indicatorColor: brand.withValues(alpha: 0.26),
      indicatorSettings: const LiquidGlassSettings(
        thickness: 10,
        blur: 8,
        lightIntensity: 0,
        ambientStrength: 0,
        glowIntensity: 0,
        ambientRim: 0,
        chromaticAberration: 0,
      ),
      indicatorPinchStrength: 0.3,
      magnification: 1.0,
      glowBlurRadius: 0,
      glowSpreadRadius: 0,
      glowOpacity: 0,
      tabs: [
        for (final item in BottomNavBarItem.values)
          GlassTab(
            label: namesBottomNavBarIcons[item],
            semanticLabel: namesBottomNavBarIcons[item],
            icon: GlassNavIcon(bottomNavBarIcons[item]!, size: 22),
          ),
      ],
      searchConfig: GlassSearchBarConfig(
        controller: _searchController,
        focusNode: _searchFocus,
        hintText: 'Search',
        // In-place search: expand → keyboard → the active page filters itself
        // from homeBottomSearchTextProvider. No dedicated search screen.
        autoFocusOnExpand: true,
        onSearchToggle: _onSearchToggle,
        onChanged: (value) {
          ref.read(homeBottomSearchTextProvider.notifier).state = value;
        },
        onCancelTap: () => _onSearchToggle(false),
      ),
      // The filter action only applies to search results, so it stays visible
      // while typing instead of collapsing with the keyboard.
      extraButton:
          searchActive
              ? GlassTabBarExtraButton(
                icon: const Icon(CupertinoIcons.slider_horizontal_3),
                label: 'Filter',
                iconColor: colors.textPrimary,
                position: GlassExtraButtonPosition.afterSearch,
                collapseOnSearchFocus: false,
                onTap: () {
                  final request = ref.read(
                    homeBottomSearchFilterRequestProvider,
                  );
                  ref
                      .read(homeBottomSearchFilterRequestProvider.notifier)
                      .state = request + 1;
                },
              )
              : null,
    );
  }
}
