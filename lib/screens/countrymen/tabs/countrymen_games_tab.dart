import 'dart:async';

import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/screens/countrymen/provider/countrymen_mode_provider.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/countrymen/provider/countrymen_combined_games_provider.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/live_gamebase_search_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/utils/foreground_task_scheduler.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/scroll_to_top_button.dart';
import 'package:intl/intl.dart';

/// Track animated game IDs for Countrymen to prevent re-animation
final Set<String> _countrymenAnimatedGameIds = {};

class CountrymenGamesTab extends ConsumerStatefulWidget {
  const CountrymenGamesTab({super.key});

  @override
  ConsumerState<CountrymenGamesTab> createState() => _CountrymenGamesTabState();
}

class _CountrymenGamesTabState extends ConsumerState<CountrymenGamesTab>
    with
        WidgetsBindingObserver,
        RouteAware,
        AutomaticKeepAliveClientMixin,
        ScrollToTopListenerMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  void onScrollToTopRequested() {
    animateScrollControllerToTop(_scrollController);
  }

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;
  Timer? _scrollIdleTimer;
  bool _routeSubscribed = false;
  bool _routeIsCurrent = true;
  bool _appIsResumed = true;
  bool _liveCardsPausedForScroll = false;
  late final StateController<Set<String>> _liveGameCardsPauseReasons;
  static const Duration _scrollIdleDelay = Duration(milliseconds: 180);

  String get _liveCardsPauseReason => 'countrymen_games_scroll_$hashCode';
  // Keep the scrollable subtree mounted while a game route covers this tab so
  // the ScrollController and provider state survive returning from the board.
  bool get _isActiveOnScreen => _routeIsCurrent;

  /// Track expanded state for date sections
  final Set<String> _collapsedDates = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _liveGameCardsPauseReasons = ref.read(
      liveGameCardsPauseReasonsProvider.notifier,
    );
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    routeObserver.subscribe(this, route);
    _routeSubscribed = true;
    _routeIsCurrent = route.isCurrent;
  }

  @override
  void dispose() {
    if (_routeSubscribed) {
      routeObserver.unsubscribe(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    ForegroundTaskScheduler.cancel('countrymen_games_resume_$hashCode');
    _scrollController.removeListener(_onScroll);
    _debounceTimer?.cancel();
    _scrollIdleTimer?.cancel();
    _setLiveCardsPausedForScroll(false);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didPush() {
    _setRouteActive(true);
  }

  @override
  void didPopNext() {
    _setRouteActive(true);
  }

  @override
  void didPushNext() {
    _setRouteActive(false);
  }

  @override
  void didPop() {
    _setRouteActive(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) {
      ForegroundTaskScheduler.cancel('countrymen_games_resume_$hashCode');
      _setAppResumed(false);
      return;
    }
    if (!mounted) return;

    _setAppResumed(true);
    ForegroundTaskScheduler.schedule(
      key: 'countrymen_games_resume_$hashCode',
      task: () {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route?.isCurrent != true) return;
        if (ref.read(selectedCountrymenModeProvider) !=
            CountrymenScreenMode.games) {
          return;
        }

        ref.invalidate(gameUpdatesStreamProvider);
        ref.invalidate(liveGameUpdateStreamProvider);
        ref.invalidate(gameUpdatesBatchStreamProvider);
        unawaited(
          ref.read(countrymenCombinedGamesProvider.notifier).refreshGames(),
        );
      },
    );
  }

  void _setRouteActive(bool isActive) {
    if (!mounted) return;
    if (_routeIsCurrent != isActive) {
      setState(() => _routeIsCurrent = isActive);
    }
    if (!isActive) {
      ForegroundTaskScheduler.cancel('countrymen_games_resume_$hashCode');
      _stopLiveCardsForHiddenTab();
    }
  }

  void _setAppResumed(bool isResumed) {
    if (!mounted) return;
    if (_appIsResumed != isResumed) {
      setState(() => _appIsResumed = isResumed);
    }
    if (!isResumed) {
      _stopLiveCardsForHiddenTab();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    _markLiveCardsScrolling();

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final threshold = 200.0; // Load more when 200px from bottom

    if (maxScroll - currentScroll <= threshold) {
      final state = ref.read(countrymenCombinedGamesProvider);
      if (state.hasMore && !state.isLoading) {
        _loadMoreDays();
      }
    }
  }

  void _markLiveCardsScrolling() {
    _setLiveCardsPausedForScroll(true);
    _scrollIdleTimer?.cancel();
    _scrollIdleTimer = Timer(_scrollIdleDelay, _markLiveCardsIdle);
  }

  void _markLiveCardsIdle() {
    _setLiveCardsPausedForScroll(false);
  }

  void _stopLiveCardsForHiddenTab() {
    _scrollIdleTimer?.cancel();
    _setLiveCardsPausedForScroll(false);
  }

  void _setLiveCardsPausedForScroll(bool paused) {
    if (_liveCardsPausedForScroll == paused) return;
    _liveCardsPausedForScroll = paused;
    setLiveGameCardsPausedWithNotifier(
      _liveGameCardsPauseReasons,
      reason: _liveCardsPauseReason,
      paused: paused,
    );
  }

  void _loadMoreDays() {
    HapticFeedback.mediumImpact();
    final state = ref.read(countrymenCombinedGamesProvider);
    if (state.isSearching) {
      ref
          .read(countrymenCombinedGamesProvider.notifier)
          .loadMoreSearchResults();
    } else {
      ref.read(countrymenCombinedGamesProvider.notifier).loadMoreGames();
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      ref.read(countrymenCombinedGamesProvider.notifier).searchGames(value);
    });
  }

  void _clearSearch() {
    HapticFeedback.lightImpact();
    _debounceTimer?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(countrymenCombinedGamesProvider.notifier).clearSearch();
  }

  /// Group games by date
  Map<String, List<GamesTourModel>> _groupGamesByDate(
    List<GamesTourModel> games,
  ) {
    final grouped = <String, List<GamesTourModel>>{};

    for (final game in games) {
      final date = game.lastMoveTime ?? DateTime.now();
      final dateKey = DateFormat('yyyy-MM-dd').format(date);
      grouped.putIfAbsent(dateKey, () => []).add(game);
    }

    // Sort keys by date descending (most recent first)
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Map.fromEntries(
      sortedKeys.map((key) => MapEntry(key, grouped[key]!)),
    );
  }

  String _formatDateHeader(String dateKey) {
    final date = DateTime.parse(dateKey);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final gameDate = DateTime(date.year, date.month, date.day);

    if (gameDate == today) {
      return 'Today';
    } else if (gameDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('EEEE, MMM d').format(date);
    }
  }

  void _toggleDateSection(String dateKey) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_collapsedDates.contains(dateKey)) {
        _collapsedDates.remove(dateKey);
      } else {
        _collapsedDates.add(dateKey);
      }
    });
    // After collapsing sections, check if we need to load more content
    // This handles the case where collapsing reduces content height
    // and the user is suddenly at/near the end of the list
    _checkScrollAfterLayoutChange();
  }

  /// Check if we need to load more content after a layout change
  /// (e.g., collapsing date sections reduces content height)
  void _checkScrollAfterLayoutChange() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final position = _scrollController.position;
      final maxScroll = position.maxScrollExtent;
      final currentScroll = position.pixels;
      final viewportHeight = position.viewportDimension;

      // If content is shorter than viewport, or we're near the end, load more
      // We use a larger threshold here since collapsing can dramatically reduce height
      final needsMore =
          maxScroll <= 0 || // Content fits in viewport
          maxScroll - currentScroll <=
              viewportHeight; // Within one screen of end

      if (needsMore) {
        final state = ref.read(countrymenCombinedGamesProvider);
        if (state.hasMore && !state.isLoading) {
          _loadMoreDays();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    ref.listen<CountrymenScreenMode>(selectedCountrymenModeProvider, (_, next) {
      if (next != CountrymenScreenMode.games) {
        _stopLiveCardsForHiddenTab();
      }
    });

    final selectedMode = ref.watch(selectedCountrymenModeProvider);
    if (selectedMode != CountrymenScreenMode.games) {
      return const SizedBox.shrink();
    }

    final state = ref.watch(countrymenCombinedGamesProvider);
    final viewMode = ref.watch(gamesListViewModeProvider);
    final streamEnabled = _isActiveOnScreen && _appIsResumed;
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    Widget content = RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        await ref.read(countrymenCombinedGamesProvider.notifier).refreshGames();
      },
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      child: CustomScrollView(
        key: PageStorageKey<String>('countrymen_games_list_${viewMode.index}'),
        controller: _scrollController,
        scrollCacheExtent: kListScrollCacheExtent,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // Search bar
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                12.h,
                horizontalPadding,
                8.h,
              ),
              child: _buildSearchBar(state),
            ),
          ),

          // Content
          _buildContentSliver(state, viewMode, streamEnabled),

          // Bottom padding
          SliverToBoxAdapter(child: SizedBox(height: 24.h)),
        ],
      ),
    );

    // Apply tablet max-width constraint
    if (ResponsiveHelper.isTablet) {
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: content,
        ),
      );
    }

    return Stack(
      children: [
        content,
        // Scroll to top button
        Positioned(
          bottom: 0,
          right: 0,
          child: ScrollToTopButton(scrollController: _scrollController),
        ),
      ],
    );
  }

  Widget _buildSearchBar(CountrymenCombinedGamesState state) {
    final hasActiveFilters = state.filter.hasActiveFilters;
    final activeFilterCount = state.filter.activeFilterCount;
    final searchBarHeight = 48.h;

    return SizedBox(
      height: searchBarHeight,
      child: Row(
        children: [
          // Search field
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(color: context.colors.surfaceRecessed),
              ),
              child: Row(
                children: [
                  SizedBox(width: 12.w),
                  Icon(
                    Icons.search,
                    size: 20.sp,
                    color: context.colors.textSecondary,
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: AppTypography.textSmRegular.copyWith(
                        color: context.colors.textPrimary,
                      ),
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search',
                        hintStyle: AppTypography.textSmRegular.copyWith(
                          color: context.colors.textSecondary,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty ||
                      state.isSearching) ...[
                    GestureDetector(
                      onTap: _clearSearch,
                      child: Icon(
                        Icons.close,
                        size: 20.sp,
                        color: context.colors.textSecondary,
                      ),
                    ),
                    SizedBox(width: 8.w),
                  ],
                  SizedBox(width: 8.w),
                ],
              ),
            ),
          ),
          // Filter button
          SizedBox(width: 8.w),
          GestureDetector(
            onTap: () => _showFilterDialog(state),
            child: Container(
              width: searchBarHeight,
              height: searchBarHeight,
              decoration: BoxDecoration(
                color:
                    hasActiveFilters
                        ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                        : context.colors.background,
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(
                  color:
                      hasActiveFilters
                          ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                          : context.colors.surfaceRecessed,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 20.sp,
                    color:
                        hasActiveFilters
                            ? const Color(0xFFEF4444)
                            : context.colors.textSecondary,
                  ),
                  // Badge showing active filter count
                  if (hasActiveFilters)
                    Positioned(
                      right: 6.w,
                      top: 6.h,
                      child: Container(
                        width: 14.w,
                        height: 14.h,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$activeFilterCount',
                            style: AppTypography.textXsBold.copyWith(
                              color: context.colors.textPrimary,
                              fontSize: 9.sp,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Layout toggle button
          SizedBox(width: 8.w),
          GestureDetector(
            onTap: () => ref.read(gamesListViewModeSwitcher).toggleViewMode(),
            child: Container(
              width: searchBarHeight,
              height: searchBarHeight,
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(color: context.colors.surfaceRecessed),
              ),
              child: Center(
                child: SvgPicture.asset(
                  SvgAsset.chase_grid,
                  width: 20.sp,
                  height: 20.sp,
                  colorFilter: ColorFilter.mode(
                    context.colors.textSecondary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFilterDialog(CountrymenCombinedGamesState state) async {
    HapticFeedbackService.buttonPress();
    final result = await showGameFilterDialog(
      context: context,
      currentFilter: state.filter,
      showFormatFilter: false,
    );
    if (result != null && mounted) {
      ref.read(countrymenCombinedGamesProvider.notifier).applyFilter(result);
    }
  }

  Widget _buildContentSliver(
    CountrymenCombinedGamesState state,
    GamesListViewMode viewMode,
    bool streamEnabled,
  ) {
    if (state.isLoading && state.games.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildLoadingState(),
      );
    }

    if (state.error != null && state.games.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildErrorState(state.error!),
      );
    }

    if (state.games.isEmpty) {
      if (state.isSearching) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _buildNoSearchResultsState(),
        );
      }
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(),
      );
    }

    // Use filtered games based on filter settings
    final games = state.filteredGames;

    // Build a mapping of game IDs to their indices for reliable lookup
    final gameIdToIndex = <String, int>{};
    for (int i = 0; i < games.length; i++) {
      gameIdToIndex[games[i].gameId] = i;
    }

    // Show empty state if filter excludes all games
    if (games.isEmpty && state.filter.hasActiveFilters) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildNoFilterResultsState(),
      );
    }

    // Group games by date
    final gamesByDate = _groupGamesByDate(games);

    // Build cheap row descriptors only. The actual cards are created lazily
    // for visible rows by SliverChildBuilderDelegate.
    final listEntries = <_CountrymenGamesListEntry>[];
    bool isFirstGameCard = true;
    final isGrid = viewMode == GamesListViewMode.chessBoardGrid;
    final isChessBoardVisible = viewMode == GamesListViewMode.chessBoard;

    // Create GamesScreenModel for GameCardWrapperWidget
    final gamesData = GamesScreenModel(
      gamesTourModels: games,
      pinnedGamedIs: const [],
    );

    for (final entry in gamesByDate.entries) {
      final dateKey = entry.key;
      final dateGames = entry.value;
      final isCollapsed = _collapsedDates.contains(dateKey);

      // Date header
      listEntries.add(
        _CountrymenDateHeaderEntry(
          dateKey: dateKey,
          gameCount: dateGames.length,
          isExpanded: !isCollapsed,
        ),
      );

      // Games under this date (only if expanded)
      if (!isCollapsed) {
        if (isGrid) {
          // Grid mode: dynamic columns based on device/orientation
          // Tablet landscape: 4 columns, Tablet portrait: 2 columns, Phone: 2 columns
          final int gridColumns =
              ResponsiveHelper.isTablet && ResponsiveHelper.isLandscape ? 4 : 2;

          for (int i = 0; i < dateGames.length; i += gridColumns) {
            final isLast = i + gridColumns >= dateGames.length;

            // Gather games for this row
            final rowGames = <GamesTourModel>[];
            for (int j = 0; j < gridColumns && i + j < dateGames.length; j++) {
              rowGames.add(dateGames[i + j]);
            }

            listEntries.add(
              _CountrymenGridRowEntry(
                games: rowGames,
                gridColumns: gridColumns,
                isLast: isLast,
                listIndex: listEntries.length,
              ),
            );
          }
        } else {
          // Card mode or Board mode
          for (int i = 0; i < dateGames.length; i++) {
            final game = dateGames[i];
            // Use reliable index lookup by game ID
            final gameIndex = gameIdToIndex[game.gameId] ?? 0;
            final isLast = i == dateGames.length - 1;
            final showHint =
                isFirstGameCard && viewMode == GamesListViewMode.gamesCard;
            if (isFirstGameCard) isFirstGameCard = false;

            if (isChessBoardVisible) {
              // Board mode: use GameCardWrapperWidget with chessboard visible
              listEntries.add(
                _CountrymenBoardGameEntry(
                  game: game,
                  gameIndex: gameIndex,
                  listIndex: listEntries.length,
                  isLast: isLast,
                ),
              );
            } else {
              // Card mode: use LiveGamebaseSearchGameCard for live position updates
              listEntries.add(
                _CountrymenCardGameEntry(
                  game: game,
                  gameIndex: gameIndex,
                  animationIndex: listEntries.length,
                  showHint: showHint,
                  isLast: isLast,
                ),
              );
            }
          }
        }
      }
    }

    // Loading indicator for auto-scroll loading
    if (state.isLoading && state.games.isNotEmpty) {
      listEntries.add(const _CountrymenFooterEntry.loading());
    } else if (state.hasMore && state.games.isNotEmpty) {
      // Spacer to ensure scroll triggers auto-load
      listEntries.add(const _CountrymenFooterEntry.spacer());
    } else if (!state.hasMore && state.games.isNotEmpty) {
      listEntries.add(const _CountrymenFooterEntry.end());
    }

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );
    return SliverPadding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 8.h,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildListEntry(
            listEntries[index],
            games: games,
            gamesData: gamesData,
            gameIdToIndex: gameIdToIndex,
            viewMode: viewMode,
            streamEnabled: streamEnabled,
          ),
          childCount: listEntries.length,
          addAutomaticKeepAlives: false,
        ),
      ),
    );
  }

  Widget _buildListEntry(
    _CountrymenGamesListEntry entry, {
    required List<GamesTourModel> games,
    required GamesScreenModel gamesData,
    required Map<String, int> gameIdToIndex,
    required GamesListViewMode viewMode,
    required bool streamEnabled,
  }) {
    if (entry is _CountrymenDateHeaderEntry) {
      return Padding(
        padding: EdgeInsets.only(bottom: 12.h),
        child: _DateHeader(
          dateLabel: _formatDateHeader(entry.dateKey),
          gameCount: entry.gameCount,
          isExpanded: entry.isExpanded,
          onToggle: () => _toggleDateSection(entry.dateKey),
        ),
      );
    }

    if (entry is _CountrymenGridRowEntry) {
      return Padding(
        padding: EdgeInsets.only(bottom: entry.isLast ? 16.h : 12.h),
        child: Row(
          children: [
            for (int j = 0; j < entry.gridColumns; j++) ...[
              if (j > 0) SizedBox(width: 12.sp),
              Expanded(
                child:
                    j < entry.games.length
                        ? _buildGridGame(
                          entry.games[j],
                          gameIdToIndex[entry.games[j].gameId] ?? 0,
                          games,
                          entry.listIndex,
                          streamEnabled,
                        )
                        : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }

    if (entry is _CountrymenBoardGameEntry) {
      return _CountrymenLiveBoardGameCard(
        key: ValueKey('cmen_game_${entry.game.gameId}_${viewMode.index}'),
        game: entry.game,
        gamesData: gamesData,
        gameIndex: entry.gameIndex,
        listIndex: entry.listIndex,
        allGames: games,
        isChessBoardVisible: true,
        isLast: entry.isLast,
        streamEnabled: streamEnabled,
      );
    }

    if (entry is _CountrymenCardGameEntry) {
      return Padding(
        padding: EdgeInsets.only(bottom: entry.isLast ? 16.h : 12.h),
        child: LiveGamebaseSearchGameCard(
          game: entry.game,
          allGames: games,
          gameIndex: entry.gameIndex,
          animationIndex: entry.animationIndex,
          showRound: true,
          showSwipeHint: entry.showHint,
          showGamebaseButton: false,
          streamEnabled: streamEnabled,
          onAdd: () => _showAddToFolderSheet(context, entry.game),
          onLiveAdd: (liveGame) => _showAddToFolderSheet(context, liveGame),
          onLiveTap: (liveGame, updatedGames, liveIndex) async {
            final hasPremium = await requirePremiumGuard(context, ref);
            if (!hasPremium) return;
            _navigateToChessBoard(liveGame, updatedGames, liveIndex);
          },
        ),
      );
    }

    if (entry is _CountrymenFooterEntry) {
      switch (entry.type) {
        case _CountrymenFooterType.loading:
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 24.h),
            child: Center(
              child: SizedBox(
                width: 24.w,
                height: 24.h,
                child: CircularProgressIndicator(
                  color: context.colors.textPrimary,
                  strokeWidth: 2,
                ),
              ),
            ),
          );
        case _CountrymenFooterType.spacer:
          return SizedBox(height: 60.h);
        case _CountrymenFooterType.end:
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 16.h),
            child: Center(
              child: Text(
                'No more games',
                style: AppTypography.textXsRegular.copyWith(
                  color: const Color(0xFF52525B),
                ),
              ),
            ),
          );
      }
    }

    return const SizedBox.shrink();
  }

  Widget _buildGridGame(
    GamesTourModel game,
    int gameIndex,
    List<GamesTourModel> allGames,
    int listIndex,
    bool streamEnabled,
  ) {
    return GridGameCardWrapperWidget(
      key: ValueKey('cmen_grid_game_${game.gameId}'),
      game: game,
      orderedGames: allGames,
      gameIndex: gameIndex,
      allowStockfishFallback: true,
      streamEnabled: streamEnabled,
      onChangedWithLiveGames: (updatedGames) async {
        // Premium guard - show paywall if not subscribed
        final hasPremium = await requirePremiumGuard(context, ref);
        if (!hasPremium) return;
        if (!mounted) return;

        ref
            .read(gameCardWrapperProvider)
            .navigateToChessBoard(
              context: context,
              orderedGames: updatedGames,
              gameIndex: gameIndex,
              onReturnFromChessboard: (_) {},
              viewSource: ChessboardView.countryman,
            );
      },
      pinnedIds: const [],
      onPinToggle: (_) {},
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48.w,
            height: 48.h,
            child: CircularProgressIndicator(
              color: context.colors.textPrimary,
              strokeWidth: 2.5,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Loading games...',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64.w,
            height: 64.h,
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16.br),
            ),
            child: Icon(
              Icons.error_outline_rounded,
              color: const Color(0xFFEF4444),
              size: 32.ic,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Failed to load games',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.w),
            child: Text(
              error,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: 24.h),
          TextButton(
            onPressed:
                () =>
                    ref
                        .read(countrymenCombinedGamesProvider.notifier)
                        .refreshGames(),
            style: TextButton.styleFrom(
              backgroundColor: context.colors.textPrimary.withValues(
                alpha: 0.1,
              ),
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.br),
              ),
            ),
            child: Text(
              'Retry',
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildEmptyState() {
    final countryAsync = ref.watch(effectiveCountryProvider);
    final countryName = countryAsync.valueOrNull?.name ?? 'your country';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80.w,
            height: 80.h,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  context.colors.textPrimary.withValues(alpha: 0.15),
                  context.colors.textPrimary.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(20.br),
            ),
            child: Icon(
              Icons.public_outlined,
              color: context.colors.textPrimary.withValues(alpha: 0.7),
              size: 40.ic,
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            'No games found',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40.w),
            child: Text(
              'No recent games found for players from $countryName',
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildNoSearchResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_outlined,
            size: 56.sp,
            color: context.colors.textPrimary.withValues(alpha: 0.4),
          ),
          SizedBox(height: 12.h),
          Text(
            'No results',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.85),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Try a different search term',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildNoFilterResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.filter_alt_off_outlined,
            size: 56.sp,
            color: context.colors.textPrimary.withValues(alpha: 0.4),
          ),
          SizedBox(height: 12.h),
          Text(
            'No matching games',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.85),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Try adjusting your filters',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 20.h),
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              ref.read(countrymenCombinedGamesProvider.notifier).clearFilter();
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: context.colors.textPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.br),
              ),
              child: Text(
                'Clear Filters',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  void _showAddToFolderSheet(BuildContext context, GamesTourModel game) {
    showAddToFolderSheet(context: context, game: game);
  }

  void _navigateToChessBoard(
    GamesTourModel game,
    List<GamesTourModel> allGames,
    int gameIndex,
  ) {
    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.countryman;
    ref.read(shouldStreamProvider.notifier).state = false;

    Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder:
            (_) =>
                ChessBoardScreenNew(games: allGames, currentIndex: gameIndex),
      ),
    ).then((_) {
      if (mounted) {
        ref.read(shouldStreamProvider.notifier).state = true;
        ref.invalidate(gameUpdatesStreamProvider);
        ref.invalidate(liveGameUpdateStreamProvider);
        ref.invalidate(gameUpdatesBatchStreamProvider);
      }
    });
  }
}

abstract class _CountrymenGamesListEntry {
  const _CountrymenGamesListEntry();
}

class _CountrymenDateHeaderEntry extends _CountrymenGamesListEntry {
  const _CountrymenDateHeaderEntry({
    required this.dateKey,
    required this.gameCount,
    required this.isExpanded,
  });

  final String dateKey;
  final int gameCount;
  final bool isExpanded;
}

class _CountrymenGridRowEntry extends _CountrymenGamesListEntry {
  const _CountrymenGridRowEntry({
    required this.games,
    required this.gridColumns,
    required this.isLast,
    required this.listIndex,
  });

  final List<GamesTourModel> games;
  final int gridColumns;
  final bool isLast;
  final int listIndex;
}

class _CountrymenBoardGameEntry extends _CountrymenGamesListEntry {
  const _CountrymenBoardGameEntry({
    required this.game,
    required this.gameIndex,
    required this.listIndex,
    required this.isLast,
  });

  final GamesTourModel game;
  final int gameIndex;
  final int listIndex;
  final bool isLast;
}

class _CountrymenCardGameEntry extends _CountrymenGamesListEntry {
  const _CountrymenCardGameEntry({
    required this.game,
    required this.gameIndex,
    required this.animationIndex,
    required this.showHint,
    required this.isLast,
  });

  final GamesTourModel game;
  final int gameIndex;
  final int animationIndex;
  final bool showHint;
  final bool isLast;
}

enum _CountrymenFooterType { loading, spacer, end }

class _CountrymenFooterEntry extends _CountrymenGamesListEntry {
  const _CountrymenFooterEntry.loading() : type = _CountrymenFooterType.loading;

  const _CountrymenFooterEntry.spacer() : type = _CountrymenFooterType.spacer;

  const _CountrymenFooterEntry.end() : type = _CountrymenFooterType.end;

  final _CountrymenFooterType type;
}

/// Date section header - similar to RoundHeader
class _DateHeader extends StatelessWidget {
  final String dateLabel;
  final int gameCount;
  final bool isExpanded;
  final VoidCallback? onToggle;

  const _DateHeader({
    required this.dateLabel,
    required this.gameCount,
    required this.isExpanded,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(12.br),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 14.sp),
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color: context.colors.textPrimary.withValues(alpha: 0.1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 4.w,
              height: 20.h,
              decoration: BoxDecoration(
                color: kPrimaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                '$dateLabel • $gameCount ${gameCount == 1 ? 'game' : 'games'}',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onToggle != null) ...[
              SizedBox(width: 12.w),
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: context.colors.textPrimary.withValues(alpha: 0.5),
                size: 20.sp,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Adds premium guard for navigation while allowing offscreen live streams to
/// auto-dispose.
class _CountrymenLiveBoardGameCard extends ConsumerStatefulWidget {
  const _CountrymenLiveBoardGameCard({
    super.key,
    required this.game,
    required this.gamesData,
    required this.gameIndex,
    required this.listIndex,
    required this.allGames,
    required this.isChessBoardVisible,
    required this.isLast,
    required this.streamEnabled,
  });

  final GamesTourModel game;
  final GamesScreenModel gamesData;
  final int gameIndex;
  final int listIndex;
  final List<GamesTourModel> allGames;
  final bool isChessBoardVisible;
  final bool isLast;
  final bool streamEnabled;

  @override
  ConsumerState<_CountrymenLiveBoardGameCard> createState() =>
      _CountrymenLiveBoardGameCardState();
}

class _CountrymenLiveBoardGameCardState
    extends ConsumerState<_CountrymenLiveBoardGameCard> {
  Future<void> _handleNavigate(List<GamesTourModel> updatedGames) async {
    // Premium guard - show paywall if not subscribed
    final hasPremium = await requirePremiumGuard(context, ref);
    if (!hasPremium) return;
    if (!mounted) return;

    ref
        .read(gameCardWrapperProvider)
        .navigateToChessBoard(
          context: context,
          orderedGames: updatedGames,
          gameIndex: widget.gameIndex,
          onReturnFromChessboard: (_) {},
          viewSource: ChessboardView.countryman,
        );
  }

  @override
  Widget build(BuildContext context) {
    // Watch live game updates for ongoing games
    // Use gameId as the stable key to prevent provider recreation
    final liveBatchKey = liveContextBatchKeyForGame(
      game: widget.game,
      contextGames: widget.allGames,
      scopePrefix: 'countrymen_tab_board',
    );
    final liveGame = watchLiveGame(
      ref,
      widget.game,
      batchKey: liveBatchKey,
      streamEnabled: widget.streamEnabled,
    );
    final gameId = liveGame.gameId;
    final updatedGames = List<GamesTourModel>.from(widget.allGames);
    if (widget.gameIndex >= 0 && widget.gameIndex < updatedGames.length) {
      updatedGames[widget.gameIndex] = liveGame;
    }

    // Use ChessBoardFromFENNew directly with premium-guarded navigation
    final card = Padding(
      padding: EdgeInsets.only(bottom: widget.isLast ? 16.h : 12.h),
      child: ChessBoardFromFENNew(
        key: ValueKey('cmen_board_game_${liveGame.gameId}'),
        gamesTourModel: liveGame,
        onChanged: () => _handleNavigate(updatedGames),
        pinnedIds: widget.gamesData.pinnedGamedIs,
        allowStockfishFallback:
            widget.streamEnabled &&
            !ref.watch(liveGameCardsPausedProvider) &&
            ref.watch(shouldStreamProvider),
        onPinToggle: (_) {},
      ),
    );

    // Use global set to track animations - survives tab switches and rebuilds
    if (!_countrymenAnimatedGameIds.contains(gameId)) {
      _countrymenAnimatedGameIds.add(gameId);
      return card
          .animate()
          .fadeIn(
            duration: 200.ms,
            delay: Duration(milliseconds: (widget.listIndex % 10) * 30),
          )
          .slideY(begin: 0.05, end: 0, duration: 200.ms, curve: Curves.easeOut);
    }

    return card;
  }
}
