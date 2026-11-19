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
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/home_top_bar.dart' show PageTitle;
import 'package:chessever2/widgets/page_back_row.dart';
import 'package:chessever2/widgets/quick_list_toggles.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/page_spring.dart';
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
/// scroll up. Games and Players search from a floating button whose glass
/// becomes the field in the header's place ([SearchModeHost]), over the same
/// tab, narrowed. Their filters sit at the header's end in both states, so
/// the glyph holds still as the header turns into the search.
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
  /// tab under it, narrowed, with nothing else around it.
  final SearchModeController _search = SearchModeController();

  /// The query, typed in the search header, for the tab it was opened on.
  void _onQuery(String query) {
    switch (ref.read(selectedMiniaturesModeProvider)) {
      case MiniaturesScreenMode.games:
        applyMiniaturesGamesSearch(ref, query);
      case MiniaturesScreenMode.players:
        applyMiniaturePlayersSearch(ref, query);
      case MiniaturesScreenMode.about:
        break;
    }
  }

  /// Back from the search clears what the tab searched for; its filters
  /// stay, counted on the header's Filters (the header is in view whenever
  /// the search button is, so the button carries no count).
  void _onClose() {
    applyMiniaturesGamesSearch(ref, '');
    applyMiniaturePlayersSearch(ref, '');
  }

  Future<void> _openFilters(MiniaturesScreenMode mode) async {
    // The keyboard steps aside for the sheet; the field stays as typed.
    _search.focusNode.unfocus();
    switch (mode) {
      case MiniaturesScreenMode.games:
        await openMiniaturesGamesFilters(context, ref);
      case MiniaturesScreenMode.players:
        await openMiniaturePlayersFilters(context, ref);
      case MiniaturesScreenMode.about:
        break;
    }
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
  }

  @override
  void dispose() {
    _playersWarmup?.close();
    _pageController.dispose();
    _scrollToTopBus.dispose();
    _search.dispose();
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
    _pageController.springTo(index, context: context);
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
    // "Clear search" on an empty list empties the tab's search: the open
    // field follows, so it never names a search the list no longer runs.
    void followCleared(MiniaturesScreenMode mode, String? next) {
      if (next == null &&
          _search.isSearching &&
          ref.read(selectedMiniaturesModeProvider) == mode &&
          _search.text.text.trim().isNotEmpty) {
        _search.text.clear();
      }
    }

    ref.listen<String?>(
      miniaturesFilterProvider.select((f) => f.search),
      (_, next) => followCleared(MiniaturesScreenMode.games, next),
    );
    ref.listen<String?>(
      miniaturePlayersQueryProvider.select((q) => q.search),
      (_, next) => followCleared(MiniaturesScreenMode.players, next),
    );

    final players = selectedMode == MiniaturesScreenMode.players;
    final header = SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(selectedMode),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: SearchHeaderMetrics.gutter,
            ),
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
          SizedBox(height: SearchHeaderMetrics.bottomGap),
        ],
      ),
    );
    final filters = _filterButton(selectedMode, inSearch: true);
    final search = SearchModeHeader(
      hintText: players ? 'Search players' : 'Search player, event or opening',
      textFieldKey: ValueKey(
        players ? 'miniatures_players_search' : 'miniatures_games_search',
      ),
      closeKey: const ValueKey('miniatures_search_close'),
      trailing: [?filters],
    );

    return SearchModeHost(
      controller: _search,
      chrome: _chrome,
      debounce: const Duration(milliseconds: 350),
      onQuery: _onQuery,
      onClose: _onClose,
      child: Scaffold(
        backgroundColor: context.colors.background,
        floatingActionButton: SlidingFabs(
          controller: _chrome,
          child: _MiniaturesSearchFab(mode: selectedMode),
        ),
        body: ScreenWrapper(
          child: Column(
            children: [
              // The status bar's inset stays put: the bars fold up to it,
              // never into it.
              SizedBox(height: MediaQuery.viewPaddingOf(context).top + 4.h),
              CollapsingChrome(
                controller: _chrome,
                child: SearchModeHeaderSlot(header: header, search: search),
              ),
              Expanded(
                child: ScrollChromeRegion(
                  controller: _chrome,
                  child: ScrollToTopScope(
                    bus: _scrollToTopBus,
                    child: ListenableBuilder(
                      listenable: _search,
                      builder: (context, _) => PageView(
                        controller: _pageController,
                        onPageChanged: _handlePageChanged,
                        // Searching holds the tab: the search belongs to it.
                        physics: _search.pagePhysics(),
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The tab's Filters with the filters on it counted, or null on About.
  /// The same glyph ends the header and the search header, on the gutter,
  /// and holds still there as the search opens and closes.
  Widget? _filterButton(MiniaturesScreenMode mode, {bool inSearch = false}) {
    final button = _filterGlyph(mode, inSearch: inSearch);
    return button == null
        ? null
        : SearchModeShared(id: SearchModeFilterButton, child: button);
  }

  Widget? _filterGlyph(MiniaturesScreenMode mode, {required bool inSearch}) {
    return switch (mode) {
      MiniaturesScreenMode.about => null,
      MiniaturesScreenMode.games => SearchModeFilterButton(
        key: inSearch ? const ValueKey('miniatures_games_filters') : null,
        label: 'Filter games',
        count: ref.watch(
          miniaturesFilterProvider.select((f) => f.dialogActiveCount),
        ),
        onTap: () => _openFilters(mode),
      ),
      MiniaturesScreenMode.players => SearchModeFilterButton(
        key: inSearch ? const ValueKey('miniatures_players_filters') : null,
        label: 'Filter players',
        count: ref.watch(
          miniaturePlayersQueryProvider.select((q) => q.activeFilterCount),
        ),
        onTap: () => _openFilters(mode),
      ),
    };
  }

  /// The back row: the chevron where the search header's is, the title
  /// lockup, and the tab's controls ending on the gutter with its Filters.
  Widget _buildHeader(MiniaturesScreenMode mode) {
    final filters = _filterButton(mode);
    final controls = <Widget>[
      // The Games list's layout, in the header as on an event's Games tab:
      // the list's top is the list's own.
      if (mode == MiniaturesScreenMode.games)
        // Every Games list's own board-view button; the switcher gives the
        // tap feedback.
        BoardViewToggleButton(
          onTap: () => ref.read(gamesListViewModeSwitcher).toggleViewMode(),
        ),
      _buildSpaceButton(),
      ?filters,
    ];
    return PageBackRow(
      // Named as every pushed page is: the one title voice, its bare mark.
      title: const PageTitle('Miniatures', mark: Icon(Icons.bolt_rounded)),
      // Three controls on Games: the most any tab shows, so the title sits
      // at one place on every tab.
      reservedEnd: 3 * _kControl,
      actions: controls,
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
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: _kControl,
        height: _kControl,
      ),
      onPressed: () =>
          toggleSpaceShortcut(context: context, ref: ref, draft: draft),
      icon: Icon(
        inSpace
            ? Icons.dashboard_customize
            : Icons.dashboard_customize_outlined,
        size: 20.ic,
        color: context.colors.textPrimary,
      ),
    );
  }
}

/// A header control's square target: a 20pt glyph in it, as the toolbar
/// and the search header draw theirs.
const double _kControl = 44;

/// The floating search over the tab in view: Games and Players each search
/// their own list; About has nothing to search. Their Filters stand in the
/// header, counted there, so the button carries no count of its own. It
/// stays while searching: the search's glass flies back into it.
class _MiniaturesSearchFab extends StatelessWidget {
  const _MiniaturesSearchFab({required this.mode});

  final MiniaturesScreenMode mode;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      MiniaturesScreenMode.about => const SizedBox.shrink(),
      MiniaturesScreenMode.games => const InkFabStack(
        children: [
          SearchInkFab(
            key: ValueKey('miniatures_search_fab'),
            label: 'Search games',
          ),
        ],
      ),
      MiniaturesScreenMode.players => const InkFabStack(
        children: [
          SearchInkFab(
            key: ValueKey('miniatures_search_fab'),
            label: 'Search players',
          ),
        ],
      ),
    };
  }
}
