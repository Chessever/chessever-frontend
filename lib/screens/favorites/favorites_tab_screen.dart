import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/favorites/player_games/provider/favorites_combined_games_provider.dart';
import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_games_tab.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_list_tab.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/favorites/widgets/collection_inks.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart' show PageTitle;
import 'package:chessever2/widgets/ink_fab.dart' show SearchInkFab;
import 'package:chessever2/widgets/page_back_row.dart';
import 'package:chessever2/widgets/page_spring.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class FavoritesTabScreen extends ConsumerStatefulWidget {
  const FavoritesTabScreen({super.key, this.initialMode});

  final FavoritesScreenMode? initialMode;

  @override
  ConsumerState<FavoritesTabScreen> createState() => _FavoritesTabScreenState();
}

class _FavoritesTabScreenState extends ConsumerState<FavoritesTabScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  final ScrollToTopBus _scrollToTopBus = ScrollToTopBus();

  /// The header (title row and tabs) and the floating buttons scroll away
  /// with the list and come back as it scrolls up (X-style).
  late final ScrollChromeController _chrome = ScrollChromeController(
    vsync: this,
  );

  /// The page's full-page search (Trello #1420), one on every tab: the
  /// floating button's glass becomes the field in the header's place, over
  /// the same list, which the query narrows. The host ([SearchModeHost]) runs
  /// the morph, back, focus and the query; the page sends the query to the
  /// tab it was opened on ([_searchedMode]).
  final SearchModeController _search = SearchModeController();

  /// The tab the open search belongs to: set as it opens, and the pages hold
  /// still while it is open ([SearchModeController.pagePhysics]).
  FavoritesScreenMode? _searchedMode;

  FavoritesCombinedGamesNotifier get _games =>
      ref.read(favoritesCombinedGamesProvider.notifier);

  /// [FavoritesTabScreen.initialMode] until it reaches the mode provider after
  /// the first frame. The title row reads it so a screen opened on another
  /// page never mounts the Games controls, which would start a games fetch.
  FavoritesScreenMode? _pendingInitialMode;

  @override
  void initState() {
    super.initState();
    final initialMode = widget.initialMode;
    final FavoritesScreenMode mode =
        initialMode ?? ref.read(selectedFavoritesModeProvider);
    _pendingInitialMode = initialMode;
    if (initialMode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pendingInitialMode = null;
        ref
            .read(selectedFavoritesModeProvider.notifier)
            .update((_) => initialMode);
      });
    }
    _pageController = PageController(
      initialPage: FavoritesScreenMode.values.indexOf(mode),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollToTopBus.dispose();
    _search.dispose();
    _chrome.dispose();
    super.dispose();
  }

  void _handleTabSelection(int index) {
    try {
      final currentIndex = FavoritesScreenMode.values.indexOf(
        ref.read(selectedFavoritesModeProvider),
      );
      if (index == currentIndex) {
        _scrollToTopBus.request();
        return;
      }
      _chrome.show();
      ref
          .read(selectedFavoritesModeProvider.notifier)
          .update((_) => FavoritesScreenMode.values[index]);
      // On the spring every part of the page's chrome moves on.
      _pageController.springTo(index, context: context);
    } catch (e) {
      debugPrint('Error handling tab selection: $e');
    }
  }

  void _handlePageChanged(int index) {
    try {
      final currentModeIndex = FavoritesScreenMode.values.indexOf(
        ref.read(selectedFavoritesModeProvider),
      );
      if (currentModeIndex != index) {
        _chrome.show();
        ref
            .read(selectedFavoritesModeProvider.notifier)
            .update((_) => FavoritesScreenMode.values[index]);
      }
    } catch (e) {
      debugPrint('Error handling page change: $e');
    }
  }

  /// The tab on screen: until the opening page reaches the provider, the
  /// one the screen was opened on.
  FavoritesScreenMode get _currentMode =>
      _pendingInitialMode ?? ref.read(selectedFavoritesModeProvider);

  /// Every keystroke: the followed players filter as typed, on the device.
  void _onSearchChanged(String query) {
    if (_searchedMode != FavoritesScreenMode.favorites) return;
    ref.read(favoritesListSearchQueryProvider.notifier).state = query;
  }

  /// The settled query: Games and Rankings ask the server.
  void _onSearchQuery(String query) {
    switch (_searchedMode) {
      case FavoritesScreenMode.games:
        if (query.isNotEmpty) {
          unawaited(_games.searchGames(query));
        } else if (_search.isSearching) {
          // The field emptied while still searching: the plain list again.
          unawaited(_games.clearSearch());
        }
      case FavoritesScreenMode.players:
        unawaited(ref.read(worldPlayersSearchProvider.notifier).search(query));
      case FavoritesScreenMode.favorites:
      case null:
        break;
    }
  }

  /// In the tap's tick, once: only the query goes with the search, and only
  /// on the tab it searched (reading another tab's list would start its
  /// fetch). Classical and Filters stay applied, on the toolbar the Games
  /// page keeps.
  void _onSearchClosed() {
    final mode = _searchedMode;
    _searchedMode = null;
    switch (mode) {
      case FavoritesScreenMode.games:
        unawaited(_games.clearSearch());
      case FavoritesScreenMode.favorites:
        ref.read(favoritesListSearchQueryProvider.notifier).state = '';
      case FavoritesScreenMode.players:
        unawaited(ref.read(worldPlayersSearchProvider.notifier).clearSearch());
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedMode = ref.watch(selectedFavoritesModeProvider);
    // Until the opening page reaches the provider, the header and the
    // floating buttons follow it: a screen opened on another page never
    // mounts the Games controls, which would start a games fetch.
    final shownMode = _pendingInitialMode ?? selectedMode;

    return SearchModeHost(
      controller: _search,
      chrome: _chrome,
      debounce: const Duration(milliseconds: 400),
      onOpen: () => _searchedMode = _currentMode,
      onChanged: _onSearchChanged,
      onQuery: _onSearchQuery,
      onClose: _onSearchClosed,
      child: Scaffold(
        key: e2eKey(E2eIds.favoritesRoot),
        backgroundColor: context.colors.background,
        // Every tab floats its search in the thumb's reach, and Games Live
        // first above it while a game is in play (Trello #1420). They stay
        // mounted while searching: the host steps them back, and the glass
        // flies back into the search as it closes.
        floatingActionButton: SlidingFabs(
          controller: _chrome,
          child: _FavoritesFabs(mode: shownMode),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: Column(
              children: [
                SizedBox(height: MediaQuery.viewPaddingOf(context).top + 4.h),
                // Folds up under the status bar as the list scrolls down,
                // comes back as it scrolls up.
                CollapsingChrome(
                  controller: _chrome,
                  child: SearchModeHeaderSlot(
                    header: Column(
                      children: [
                        _buildAppBar(context, shownMode),
                        SizedBox(height: 8.h),
                        _buildSegmentedSwitcher(selectedMode),
                        SizedBox(height: 4.h),
                      ],
                    ),
                    // The chevron (and on Games, Classical and Filters) stay
                    // where the title row has them; the title and the board
                    // view give way to the field.
                    search: _buildSearchHeader(shownMode),
                  ),
                ),
                Expanded(
                  child: ScrollChromeRegion(
                    controller: _chrome,
                    child: ScrollToTopScope(
                      bus: _scrollToTopBus,
                      // Searching holds the page: the search belongs to the
                      // tab it opened on.
                      child: ListenableBuilder(
                        listenable: _search,
                        builder: (context, _) => PageView.builder(
                          controller: _pageController,
                          physics: _search.pagePhysics(),
                          itemCount: 3,
                          onPageChanged: _handlePageChanged,
                          itemBuilder: (context, index) {
                            switch (index) {
                              case 0:
                                return const FavoritesListTab();
                              case 1:
                                return const FavoritesGamesTab();
                              case 2:
                                return const FavoritesPlayersTab();
                              default:
                                return Center(
                                  child: Text(
                                    'Invalid page index: $index',
                                    style: TextStyle(
                                      color: context.colors.textPrimary,
                                    ),
                                  ),
                                );
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The search header for the tab it opens on: the field searches that
  /// tab's list. Games keeps Classical and Filters beside it, held still
  /// where the title row has them.
  Widget _buildSearchHeader(FavoritesScreenMode mode) {
    return switch (mode) {
      FavoritesScreenMode.games => SearchModeHeader(
        hintText: 'Search',
        rotatingHints: FavoritesGamesToolbar.searchHints,
        textFieldKey: e2eKey(E2eIds.favoritesGamesSearchField),
        closeKey: const ValueKey('games_search_close'),
        trailing: const [FavoritesGamesToolbar.inSearch],
      ),
      FavoritesScreenMode.favorites => const SearchModeHeader(
        hintText: 'Search favorites',
        textFieldKey: ValueKey('favorites_list_search_field'),
        closeKey: ValueKey('favorites_search_close'),
      ),
      FavoritesScreenMode.players => const SearchModeHeader(
        hintText: 'Search players',
        textFieldKey: ValueKey('favorites_players_search_field'),
        closeKey: ValueKey('favorites_search_close'),
      ),
    };
  }

  /// Back, the heart and "Favorites" centred on the screen in the pushed
  /// page's title voice ([PageTitle]), and on the Games page the list's
  /// toolbar at the far end (board view, Classical, Filters). Back,
  /// Classical and Filters sit exactly where the search header puts its
  /// chevron and its Classical and Filters, and hold still there as the
  /// search opens: only the title (and the board view) give way to the
  /// field. The toolbar's room is kept on every page, so the title never
  /// moves when the page changes.
  Widget _buildAppBar(BuildContext context, FavoritesScreenMode selectedMode) {
    final isGames = selectedMode == FavoritesScreenMode.games;
    return PageBackRow(
      title: PageTitle(
        'Favorites',
        mark: Icon(Icons.favorite, color: context.collectionAlertInk),
      ),
      reservedEnd: FavoritesGamesToolbar.width,
      actions: [if (isGames) const FavoritesGamesToolbar()],
    );
  }

  Widget _buildSegmentedSwitcher(FavoritesScreenMode selectedMode) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: SegmentedSwitcher(
        dotScope: 'favorites.tab',
        backgroundColor: context.colors.popup,
        selectedBackgroundColor: context.colors.popup,
        options: favoritesModeNames.values.toList(),
        initialSelection: favoritesModeNames.values.toList().indexOf(
          favoritesModeNames[selectedMode]!,
        ),
        currentSelection: FavoritesScreenMode.values.indexOf(selectedMode),
        onSelectionChanged: _handleTabSelection,
        notifyOnReselect: true,
      ),
    );
  }
}

/// The floating buttons over the tab in view: Games floats its own (Live
/// first above the search, [FavoritesGamesFabs]); the Favorites list and
/// Rankings float the search alone, searching their own list. One test id
/// on every tab's search button, so a flow finds it wherever it is.
class _FavoritesFabs extends StatelessWidget {
  const _FavoritesFabs({required this.mode});

  final FavoritesScreenMode mode;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      FavoritesScreenMode.games => const FavoritesGamesFabs(),
      FavoritesScreenMode.favorites => SearchInkFab(
        key: e2eKey(E2eIds.favoritesSearchFab),
        label: 'Search favorites',
      ),
      FavoritesScreenMode.players => SearchInkFab(
        key: e2eKey(E2eIds.favoritesSearchFab),
        label: 'Search players',
      ),
    };
  }
}
