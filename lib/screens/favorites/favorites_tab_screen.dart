import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/favorites/player_games/provider/favorites_combined_games_provider.dart';
import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_games_tab.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_list_tab.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/favorites/widgets/collection_inks.dart';
import 'package:chessever2/screens/favorites/widgets/games_search_header.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/quick_list_toggles.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
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

  /// The Games page's full-page search (Trello #1420): the field in the
  /// header's place, the same Games list under it, filtered, with nothing
  /// else around it.
  bool _searching = false;
  final FocusNode _searchFocus = FocusNode();

  void _openSearch() {
    if (_searching) return;
    setState(() => _searching = true);
    _chrome.show();
  }

  /// Leaves the search with the query cleared. Classical and Filters stay,
  /// counted on the floating search.
  void _closeSearch() {
    if (!_searching) return;
    _searchFocus.unfocus();
    setState(() => _searching = false);
    _chrome.show();
    // Cleared after the frame that takes the field away: a keystroke still
    // waiting on its debounce dies with the field, so it cannot run the
    // search again behind the closed header.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(favoritesCombinedGamesProvider.notifier).clearSearch(),
      );
    });
  }

  /// A field with the keyboard keeps the header on screen.
  void _holdChromeWhileTyping() => _chrome.held = _searchFocus.hasFocus;

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
    _searchFocus.addListener(_holdChromeWhileTyping);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollToTopBus.dispose();
    _searchFocus
      ..removeListener(_holdChromeWhileTyping)
      ..dispose();
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
      // The Favorites and Rankings pages carry fields of their own: their
      // keyboard goes with the page.
      FocusScope.of(context).unfocus();
      _chrome.show();
      ref
          .read(selectedFavoritesModeProvider.notifier)
          .update((_) => FavoritesScreenMode.values[index]);
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
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
        FocusScope.of(context).unfocus();
        _chrome.show();
        ref
            .read(selectedFavoritesModeProvider.notifier)
            .update((_) => FavoritesScreenMode.values[index]);
      }
    } catch (e) {
      debugPrint('Error handling page change: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedMode = ref.watch(selectedFavoritesModeProvider);
    // Until the opening page reaches the provider, the header and the
    // floating buttons follow it: a screen opened on another page never
    // mounts the Games controls, which would start a games fetch.
    final shownMode = _pendingInitialMode ?? selectedMode;

    return PopScope(
      // Back from the search closes it, back to the list it searched.
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: Scaffold(
        key: e2eKey(E2eIds.favoritesRoot),
        backgroundColor: context.colors.background,
        // Games keeps its search, and Live first while a game is in play, in
        // the thumb's reach (Trello #1420). Searching, nothing floats.
        floatingActionButton: SlidingFabs(
          controller: _chrome,
          child: shownMode == FavoritesScreenMode.games && !_searching
              ? FavoritesGamesFabs(onSearch: _openSearch)
              : const SizedBox.shrink(),
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
                  child: _searching
                      ? GamesSearchHeader(
                          onClose: _closeSearch,
                          field: FavoritesGamesSearchField(
                            focusNode: _searchFocus,
                          ),
                          trailing: const [FavoritesGamesSearchControls()],
                        )
                      : Column(
                          children: [
                            _buildAppBar(context, shownMode),
                            SizedBox(height: 8.h),
                            _buildSegmentedSwitcher(selectedMode),
                            SizedBox(height: 4.h),
                          ],
                        ),
                ),
                Expanded(
                  child: ScrollChromeRegion(
                    controller: _chrome,
                    child: ScrollToTopScope(
                      bus: _scrollToTopBus,
                      child: PageView.builder(
                        controller: _pageController,
                        // Searching holds the page: the search belongs to
                        // Games.
                        physics: _searching
                            ? const NeverScrollableScrollPhysics()
                            : null,
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Back, the centred title, and on the Games page its board view at the
  /// far end (Trello #1420). The end slot is as wide as back's on every page,
  /// so the title stays centred and never moves when the page changes. The
  /// list's other controls live in its search; Live first floats.
  Widget _buildAppBar(BuildContext context, FavoritesScreenMode selectedMode) {
    final isGames = selectedMode == FavoritesScreenMode.games;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        children: [
          IconButton(
            iconSize: 24.ic,
            padding: EdgeInsets.zero,
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.arrow_back_ios_new_outlined,
              size: 24.ic,
              color: context.colors.textPrimary,
            ),
          ),
          const Expanded(
            child: Center(child: _FavoritesTitle(dropHeartWhenTight: true)),
          ),
          SizedBox(
            // Back's 48pt target; never narrower than the toggle's 44.
            width: math.max(48.w, 44),
            child: isGames
                ? Align(
                    // The glyph lands where back's does, mirrored.
                    alignment: AlignmentDirectional.centerEnd,
                    child: BoardViewToggleButton(
                      onTap: () =>
                          ref.read(gamesListViewModeSwitcher).toggleViewMode(),
                    ),
                  )
                : null,
          ),
        ],
      ),
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

/// The heart and "Favorites". The title ellipsizes rather than overflow, and
/// with [dropHeartWhenTight] the heart (the least important piece) goes first
/// when the row cannot hold both at the reader's text size.
class _FavoritesTitle extends StatelessWidget {
  const _FavoritesTitle({this.dropHeartWhenTight = false});

  final bool dropHeartWhenTight;

  static const String _title = 'Favorites';

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.textLgBold.copyWith(
      color: context.colors.textPrimary,
    );
    final heartSize = 20.ic;
    final gap = 8.w;

    Widget row({required bool showHeart}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeart) ...[
          Icon(
            Icons.favorite,
            color: context.collectionAlertInk,
            size: heartSize,
          ),
          SizedBox(width: gap),
        ],
        Flexible(
          child: Text(
            _title,
            style: style,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    if (!dropHeartWhenTight) return row(showHeart: true);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: _title, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final fits = heartSize + gap + painter.width <= constraints.maxWidth;
        painter.dispose();
        return row(showHeart: fits);
      },
    );
  }
}
