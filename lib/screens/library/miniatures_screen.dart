import 'dart:math' as math;

import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_share.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_about_tab.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_games_tab.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_mode_provider.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_players_tab.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/destination_title.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/search_page_header.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Miniatures community database: short decisive master games ending by
/// move 25, served by the gamebase `/api/miniatures` index.
///
/// Laid out like Favorites and Countrymen — a Games / Players / About tab
/// triple over a shared page view. Everyone browses every day and filter.
/// Opening any game requires a subscription or rewarded Premium access.
///
/// The header and the tabs scroll away with the lists and come back as they
/// scroll up. Games and Players search from a floating button that opens the
/// tab's search in the header's place, filters behind the field's glyph.
class MiniaturesScreen extends ConsumerStatefulWidget {
  const MiniaturesScreen({super.key});

  @override
  ConsumerState<MiniaturesScreen> createState() => _MiniaturesScreenState();
}

class _MiniaturesScreenState extends ConsumerState<MiniaturesScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  final ScrollToTopBus _scrollToTopBus = ScrollToTopBus();
  ProviderSubscription<MiniaturePlayersState>? _playersWarmup;

  /// The header and the tabs, pushed away by the lists' scrolls (X style).
  late final ScrollChromeController _chrome = ScrollChromeController(
    vsync: this,
  );

  /// The tab's full-page search: its field in the header's place, the same
  /// tab under it, filtered, with nothing else around it.
  bool _searching = false;
  final FocusNode _searchFocus = FocusNode();

  void _holdChromeWhileTyping() => _chrome.held = _searchFocus.hasFocus;

  void _openSearch() {
    if (_searching) return;
    setState(() => _searching = true);
    _chrome.show();
  }

  /// Back from the search clears what the tab searched for; its filters
  /// stay, counted on the search button.
  void _closeSearch() {
    if (!_searching) return;
    _searchFocus.unfocus();
    switch (ref.read(selectedMiniaturesModeProvider)) {
      case MiniaturesScreenMode.games:
        final filter = ref.read(miniaturesFilterProvider);
        if (filter.search != null) {
          ref.read(miniaturesFilterProvider.notifier).state = filter.copyWith(
            clearSearch: true,
          );
        }
      case MiniaturesScreenMode.players:
        final query = ref.read(miniaturePlayersQueryProvider);
        if (query.search != null) {
          ref.read(miniaturePlayersQueryProvider.notifier).state = query
              .copyWith(clearSearch: true);
        }
      case MiniaturesScreenMode.about:
        break;
    }
    setState(() => _searching = false);
    _chrome.show();
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: MiniaturesScreenMode.values.indexOf(
        ref.read(selectedMiniaturesModeProvider),
      ),
    );
    // Warm the Players ranking while the user is reading Games or About: one
    // small Supabase page, held alive for as long as this screen is, so opening
    // that tab finds its rows already there instead of a shimmer. The per-row
    // gamebase W-L lookups stay lazy — no card is built while the tab is
    // off-screen, so this costs exactly one query even if Players is never
    // opened.
    _playersWarmup = ref.listenManual(
      miniaturePlayersPaginatedProvider,
      (_, __) {},
    );
    _searchFocus.addListener(_holdChromeWhileTyping);
  }

  @override
  void dispose() {
    _playersWarmup?.close();
    _pageController.dispose();
    _scrollToTopBus.dispose();
    _searchFocus
      ..removeListener(_holdChromeWhileTyping)
      ..dispose();
    _chrome.dispose();
    super.dispose();
  }

  void _handleTabSelection(int index) {
    final current = ref.read(selectedMiniaturesModeProvider);
    final target = MiniaturesScreenMode.values[index];
    if (target == current) {
      // Re-tapping the active tab scrolls it back to the top.
      _scrollToTopBus.request();
      return;
    }
    HapticFeedbackService.selection();
    _chrome.show();
    ref.read(selectedMiniaturesModeProvider.notifier).state = target;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _handlePageChanged(int index) {
    final target = MiniaturesScreenMode.values[index];
    if (ref.read(selectedMiniaturesModeProvider) == target) return;
    _chrome.show();
    ref.read(selectedMiniaturesModeProvider.notifier).state = target;
  }

  @override
  Widget build(BuildContext context) {
    final selectedMode = ref.watch(selectedMiniaturesModeProvider);
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );

    final bars = _searching
        ? SearchPageHeader(
            closeKey: const ValueKey('miniatures_search_close'),
            onClose: _closeSearch,
            field: selectedMode == MiniaturesScreenMode.players
                ? MiniaturePlayersSearchField(focusNode: _searchFocus)
                : MiniaturesGamesSearchField(focusNode: _searchFocus),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(selectedMode),
              SizedBox(height: 12.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Builder(
                  builder: (tabContext) => SegmentedSwitcher(
                    longPressFor: (index) =>
                        () => showMiniaturesShareMenu(
                          tabContext,
                          MiniaturesScreenMode.values[index],
                        ),
                    longPressHint: (_) => 'Share tab',
                    dotScope: 'miniatures.tab',
                    backgroundColor: context.colors.popup,
                    selectedBackgroundColor: context.colors.popup,
                    options: miniaturesModeNames.values.toList(),
                    currentSelection: MiniaturesScreenMode.values.indexOf(
                      selectedMode,
                    ),
                    onSelectionChanged: _handleTabSelection,
                    notifyOnReselect: true,
                  ),
                ),
              ),
            ],
          );

    return PopScope(
      // Back from the search closes it, back to the tab it searched.
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: Scaffold(
        backgroundColor: context.colors.background,
        floatingActionButton: SlidingFabs(
          controller: _chrome,
          child: _MiniaturesSearchFab(
            mode: selectedMode,
            searching: _searching,
            onSearch: _openSearch,
          ),
        ),
        body: ScreenWrapper(
          child: Column(
            children: [
              // The status bar's inset stays put: the bars fold up to it,
              // never into it.
              SizedBox(height: MediaQuery.viewPaddingOf(context).top + 8.h),
              CollapsingChrome(
                controller: _chrome,
                child: SizedBox(width: double.infinity, child: bars),
              ),
              Expanded(
                child: ScrollChromeRegion(
                  controller: _chrome,
                  child: ScrollToTopScope(
                    bus: _scrollToTopBus,
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: _handlePageChanged,
                      // Searching holds the tab: the search belongs to it.
                      physics: _searching
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      // Order must track MiniaturesScreenMode.
                      children: const [
                        MiniaturesAboutTab(),
                        MiniaturesGamesTab(),
                        MiniaturesPlayersTab(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(MiniaturesScreenMode mode) {
    return SizedBox(
      height: 44.h,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18.sp,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          // Icon and title travel as one centred lockup. The horizontal
          // padding keeps that lockup clear of the back button and of the
          // two buttons on the right on the narrowest phones instead of
          // letting them overlap.
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal:
                  math.max(AppBarIconSurface.minTapTarget, 32.w) +
                  kMinInteractiveDimension +
                  4,
            ),
            child: const DestinationTitle(
              title: 'Miniatures',
              icon: Icon(Icons.bolt_rounded),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The Games list's layout, in the header as on an event's
                // Games tab: the list's top is the list's own.
                if (mode == MiniaturesScreenMode.games)
                  Semantics(
                    label: 'Toggle chessboard view',
                    child: AppBarIcons(
                      image: SvgAsset.chase_grid,
                      boxed: false,
                      // The switcher gives its own tap feedback.
                      onTap: () =>
                          ref.read(gamesListViewModeSwitcher).toggleViewMode(),
                    ),
                  ),
                _buildSpaceButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Pins today's miniatures to My Space; filled once it is there.
  Widget _buildSpaceButton() {
    final draft = SpaceShortcut.draft(
      kind: SpaceShortcutKind.miniatures,
      targetId: 'today',
      title: 'Miniatures',
      subtitle: 'Short decisive games',
    );
    final inSpace = ref.watch(spaceShortcutExistsProvider(draft.key));
    if (!inSpace && !draft.canAddToMySpace) return const SizedBox.shrink();
    return IconButton(
      tooltip: inSpace ? 'Remove from My Space' : 'Add to My Space',
      onPressed: () =>
          toggleSpaceShortcut(context: context, ref: ref, draft: draft),
      icon: Icon(
        inSpace
            ? Icons.dashboard_customize
            : Icons.dashboard_customize_outlined,
        size: 18.sp,
        color: context.colors.textPrimary,
      ),
    );
  }
}

/// The floating search over the tab in view: Games and Players each search
/// their own list, counting the filters on it; About has nothing to search.
/// Searching, nothing floats.
class _MiniaturesSearchFab extends ConsumerWidget {
  const _MiniaturesSearchFab({
    required this.mode,
    required this.searching,
    required this.onSearch,
  });

  final MiniaturesScreenMode mode;
  final bool searching;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (searching) return const SizedBox.shrink();
    return switch (mode) {
      MiniaturesScreenMode.about => const SizedBox.shrink(),
      MiniaturesScreenMode.games => SearchInkFab(
        key: const ValueKey('miniatures_search_fab'),
        label: 'Search games',
        badgeCount: ref.watch(
          miniaturesFilterProvider.select((f) => f.dialogActiveCount),
        ),
        onTap: onSearch,
      ),
      MiniaturesScreenMode.players => SearchInkFab(
        key: const ValueKey('miniatures_search_fab'),
        label: 'Search players',
        badgeCount: ref.watch(
          miniaturePlayersQueryProvider.select((q) => q.activeFilterCount),
        ),
        onTap: onSearch,
      ),
    };
  }
}
