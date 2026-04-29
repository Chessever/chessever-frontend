import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/favorites/player_games/provider/favorites_combined_games_provider.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/live_gamebase_search_game_card.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/board_game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/widgets/scroll_to_top_button.dart';
import 'package:intl/intl.dart';

/// Track animated game IDs for Favorites to prevent re-animation
final Set<String> _favoritesAnimatedGameIds = {};

class FavoritesGamesTab extends ConsumerStatefulWidget {
  const FavoritesGamesTab({super.key});

  @override
  ConsumerState<FavoritesGamesTab> createState() => _FavoritesGamesTabState();
}

class _FavoritesGamesTabState extends ConsumerState<FavoritesGamesTab>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;

  /// Track expanded state for date sections
  final Set<String> _collapsedDates = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _debounceTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed || !mounted) return;

    ref.invalidate(gameUpdatesStreamProvider);
    unawaited(ref.read(favoritesCombinedGamesProvider.notifier).refreshGames());
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final threshold = 200.0; // Load more when 200px from bottom

    if (maxScroll - currentScroll <= threshold) {
      final state = ref.read(favoritesCombinedGamesProvider);
      if (state.hasMore && !state.isLoading) {
        _loadMoreDays();
      }
    }
  }

  void _loadMoreDays() {
    HapticFeedback.mediumImpact();
    final state = ref.read(favoritesCombinedGamesProvider);
    if (state.isSearching) {
      ref.read(favoritesCombinedGamesProvider.notifier).loadMoreSearchResults();
    } else {
      ref.read(favoritesCombinedGamesProvider.notifier).loadMoreGames();
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      ref.read(favoritesCombinedGamesProvider.notifier).searchGames(value);
    });
  }

  void _clearSearch() {
    HapticFeedback.lightImpact();
    _debounceTimer?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(favoritesCombinedGamesProvider.notifier).clearSearch();
  }

  /// Group games by date
  Map<String, List<GamesTourModel>> _groupGamesByDate(
    List<GamesTourModel> games,
  ) {
    final grouped = <String, List<GamesTourModel>>{};
    const unknownDateKey = '0000-00-00'; // Sort to end

    for (final game in games) {
      // Bucket by dateStart (stable scheduled day) when available — last_move_time
      // can be clobbered by sync refreshes and misreport old games as "today".
      final date = game.bucketDate;
      final dateKey =
          date != null ? DateFormat('yyyy-MM-dd').format(date) : unknownDateKey;
      grouped.putIfAbsent(dateKey, () => []).add(game);
    }

    // Sort keys by date descending (most recent first)
    // Unknown dates (0000-00-00) will sort to the end
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Map.fromEntries(
      sortedKeys.map((key) => MapEntry(key, grouped[key]!)),
    );
  }

  String _formatDateHeader(String dateKey) {
    // Handle unknown date case
    if (dateKey == '0000-00-00') {
      return 'Unknown date';
    }

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
        final state = ref.read(favoritesCombinedGamesProvider);
        if (state.hasMore && !state.isLoading) {
          _loadMoreDays();
        }
      }
    });
  }

  void _togglePlayerFilter(String fideId) {
    HapticFeedback.lightImpact();
    // Trigger Supabase re-query with the selected player filter
    ref
        .read(favoritesCombinedGamesProvider.notifier)
        .togglePlayerFilter(fideId);
  }

  void _clearAllFilters() {
    HapticFeedback.mediumImpact();
    // Clear filters and re-query all favorites from Supabase
    ref.read(favoritesCombinedGamesProvider.notifier).clearPlayerFilters();
  }

  String? _extractFederation(FavoritePlayer player) {
    final metadata = player.metadata;
    if (metadata.containsKey('federation')) {
      return metadata['federation']?.toString();
    }
    if (metadata.containsKey('fed')) {
      return metadata['fed']?.toString();
    }
    if (metadata.containsKey('country')) {
      return metadata['country']?.toString();
    }
    if (metadata.containsKey('countryCode')) {
      return metadata['countryCode']?.toString();
    }
    return null;
  }

  String _getDisplayName(String fullName) {
    final parts = fullName.split(',');
    if (parts.length > 1) {
      return parts[0].trim();
    }
    final words = fullName.trim().split(' ');
    if (words.length > 1) {
      return words.last;
    }
    return fullName.length > 12 ? '${fullName.substring(0, 10)}...' : fullName;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final state = ref.watch(favoritesCombinedGamesProvider);
    final viewMode = ref.watch(gamesListViewModeProvider);
    // Watch the notifier provider for optimistic updates when favorites change
    final favoritesState = ref.watch(favoritePlayersNotifierProvider);
    final playerModels = favoritesState.valueOrNull?.players ?? [];

    // Convert PlayerStandingModel to FavoritePlayer for chip display
    final now = DateTime.now();
    final favorites =
        playerModels
            .map(
              (p) => FavoritePlayer(
                id: p.fideId?.toString() ?? p.name,
                userId: '', // Not needed for display
                playerName: p.name,
                fideId: p.fideId?.toString(),
                metadata: {
                  'countryCode': p.countryCode,
                  'federation': p.countryCode,
                },
                createdAt: now,
                updatedAt: now,
              ),
            )
            .toList();

    // Refresh games when favorites list changes
    ref.listen(favoritePlayersNotifierProvider, (prev, next) {
      final prevCount = prev?.valueOrNull?.players.length ?? 0;
      final nextCount = next.valueOrNull?.players.length ?? 0;
      if (prevCount != nextCount) {
        // Favorites changed, refresh games
        Future.microtask(() {
          ref.read(favoritesCombinedGamesProvider.notifier).refreshGames();
        });
      }
    });

    // Apply tablet max-width constraint
    Widget content = RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        await ref.read(favoritesCombinedGamesProvider.notifier).refreshGames();
      },
      color: kWhiteColor,
      backgroundColor: kBlack2Color,
      child: CustomScrollView(
        key: PageStorageKey<String>('favorites_games_list_${viewMode.index}'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // Search bar
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
              child: _buildSearchBar(state),
            ),
          ),

          // Filter chips (only show when not searching)
          if (favorites.length > 1 && !state.isSearching)
            SliverToBoxAdapter(child: _buildFilterChips(state, favorites)),

          // Content
          _buildContentSliver(state, favorites, viewMode),

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

  Widget _buildSearchBar(FavoritesCombinedGamesState state) {
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
                color: const Color(0xFF09090B),
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: Row(
                children: [
                  SizedBox(width: 12.w),
                  Icon(
                    Icons.search,
                    size: 20.sp,
                    color: const Color(0xFFA1A1AA),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: TextField(
                      key: e2eKey(E2eIds.favoritesGamesSearchField),
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: AppTypography.textSmRegular.copyWith(
                        color: const Color(0xFFFAFAFA),
                      ),
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search',
                        hintStyle: AppTypography.textSmRegular.copyWith(
                          color: const Color(0xFFA1A1AA),
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
                        color: const Color(0xFFA1A1AA),
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
              key: e2eKey(E2eIds.favoritesGamesFilterButton),
              width: searchBarHeight,
              height: searchBarHeight,
              decoration: BoxDecoration(
                color:
                    hasActiveFilters
                        ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                        : const Color(0xFF09090B),
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(
                  color:
                      hasActiveFilters
                          ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                          : const Color(0xFF27272A),
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
                            : const Color(0xFFA1A1AA),
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
                              color: kWhiteColor,
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
                color: const Color(0xFF09090B),
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: Center(
                child: SvgPicture.asset(
                  SvgAsset.chase_grid,
                  width: 20.sp,
                  height: 20.sp,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFFA1A1AA),
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

  Future<void> _showFilterDialog(FavoritesCombinedGamesState state) async {
    HapticFeedbackService.buttonPress();
    final result = await showGameFilterDialog(
      context: context,
      currentFilter: state.filter,
      showFormatFilter: false,
    );
    if (result != null && mounted) {
      ref.read(favoritesCombinedGamesProvider.notifier).applyFilter(result);
    }
  }

  Widget _buildFilterChips(
    FavoritesCombinedGamesState state,
    List<FavoritePlayer> favorites,
  ) {
    final hasSelection = state.selectedFideIds.isNotEmpty;

    return SizedBox(
      height: 48.h,
      child: ShaderMask(
        shaderCallback: (Rect bounds) {
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: const [0.0, 0.03, 0.97, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
          itemCount: favorites.length + (hasSelection ? 1 : 0),
          itemBuilder: (context, index) {
            if (hasSelection && index == favorites.length) {
              return Padding(
                padding: EdgeInsets.only(right: 8.w),
                child: GestureDetector(
                  onTap: _clearAllFilters,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 8.h,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF27272A),
                      borderRadius: BorderRadius.circular(16.br),
                      border: Border.all(
                        color: const Color(0xFF3F3F46),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.close_rounded,
                          size: 14.sp,
                          color: const Color(0xFFA1A1AA),
                        ),
                        SizedBox(width: 4.w),
                        Text(
                          'Clear',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFFA1A1AA),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final player = favorites[index];
            final fideId = player.fideId ?? '';
            final isSelected = state.selectedFideIds.contains(fideId);
            final federation = _extractFederation(player);
            final displayName = _getDisplayName(player.playerName);

            // Skip players without FIDE ID (can't filter by them)
            if (fideId.isEmpty) {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: GestureDetector(
                onTap: () => _togglePlayerFilter(fideId),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: EdgeInsets.symmetric(
                    horizontal: 10.w,
                    vertical: 8.h,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF27272A),
                    borderRadius: BorderRadius.circular(16.br),
                    border: Border.all(
                      color:
                          isSelected
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF3F3F46),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FederationFlag(
                        federation: federation,
                        width: 16.w,
                        height: 12.h,
                        borderRadius: BorderRadius.circular(2.br),
                      ),
                      SizedBox(width: 6.w),
                      Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: kWhiteColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContentSliver(
    FavoritesCombinedGamesState state,
    List<FavoritePlayer> favorites,
    GamesListViewMode viewMode,
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

    // Show empty state if filter excludes all games
    if (games.isEmpty && state.filter.hasActiveFilters) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildNoFilterResultsState(),
      );
    }

    // Group games by date
    final gamesByDate = _groupGamesByDate(games);

    // Build list items: date headers + games
    final items = <Widget>[];
    bool isFirstGameCard = true;
    final isGrid = viewMode == GamesListViewMode.chessBoardGrid;
    final isChessBoardVisible = viewMode == GamesListViewMode.chessBoard;

    // Create GamesScreenModel for GameCardWrapperWidget
    final gamesData = GamesScreenModel(
      gamesTourModels: games,
      pinnedGamedIs: const [],
    );

    // Build a mapping of game IDs to their indices for reliable lookup
    final gameIdToIndex = <String, int>{};
    for (int i = 0; i < games.length; i++) {
      gameIdToIndex[games[i].gameId] = i;
    }

    for (final entry in gamesByDate.entries) {
      final dateKey = entry.key;
      final dateGames = entry.value;
      final isCollapsed = _collapsedDates.contains(dateKey);

      // Date header
      items.add(
        Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: _DateHeader(
            dateLabel: _formatDateHeader(dateKey),
            gameCount: dateGames.length,
            isExpanded: !isCollapsed,
            onToggle: () => _toggleDateSection(dateKey),
          ),
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

            items.add(
              Padding(
                padding: EdgeInsets.only(bottom: isLast ? 16.h : 12.h),
                child: Row(
                  children: [
                    for (int j = 0; j < gridColumns; j++) ...[
                      if (j > 0) SizedBox(width: 12.sp),
                      Expanded(
                        child:
                            j < rowGames.length
                                ? _buildGridGame(
                                  rowGames[j],
                                  gameIdToIndex[rowGames[j].gameId] ?? 0,
                                  games,
                                  items.length,
                                )
                                : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
        } else {
          // Card mode or Board mode
          for (int i = 0; i < dateGames.length; i++) {
            final game = dateGames[i];
            final gameIndex = gameIdToIndex[game.gameId] ?? 0;
            final isLast = i == dateGames.length - 1;
            final showHint =
                isFirstGameCard && viewMode == GamesListViewMode.gamesCard;
            if (isFirstGameCard) isFirstGameCard = false;

            if (isChessBoardVisible) {
              // Board mode: use GameCardWrapperWidget with chessboard visible
              items.add(
                _FavoritesLiveBoardGameCard(
                  key: ValueKey('fav_game_${game.gameId}_${viewMode.index}'),
                  game: game,
                  gamesData: gamesData,
                  gameIndex: gameIndex,
                  listIndex: items.length,
                  allGames: games,
                  isChessBoardVisible: true,
                  isLast: isLast,
                  onNavigateToChessBoard: _navigateToChessBoard,
                ),
              );
            } else {
              // Card mode: use LiveGamebaseSearchGameCard for live position updates
              items.add(
                Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 16.h : 12.h),
                  child: LiveGamebaseSearchGameCard(
                    game: game,
                    allGames: games,
                    gameIndex: gameIndex,
                    animationIndex: items.length,
                    showRound: true,
                    showSwipeHint: showHint,
                    showGamebaseButton: false,
                    onAdd: () => _showAddToFolderSheet(context, game),
                    onLiveAdd:
                        (liveGame) => _showAddToFolderSheet(context, liveGame),
                    onLiveTap: (liveGame, updatedGames, liveIndex) async {
                      final hasPremium = await requirePremiumGuard(
                        context,
                        ref,
                      );
                      if (!hasPremium) return;
                      _navigateToChessBoard(liveGame, updatedGames, liveIndex);
                    },
                  ),
                ),
              );
            }
          }
        }
      }
    }

    // Loading indicator for auto-scroll loading
    if (state.isLoading && state.games.isNotEmpty) {
      items.add(
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24.h),
          child: Center(
            child: SizedBox(
              width: 24.w,
              height: 24.h,
              child: const CircularProgressIndicator(
                color: kWhiteColor,
                strokeWidth: 2,
              ),
            ),
          ),
        ),
      );
    } else if (state.hasMore && state.games.isNotEmpty) {
      // Spacer to ensure scroll triggers auto-load
      items.add(SizedBox(height: 60.h));
    } else if (!state.hasMore && state.games.isNotEmpty) {
      items.add(
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16.h),
          child: Center(
            child: Text(
              'No more games',
              style: AppTypography.textXsRegular.copyWith(
                color: const Color(0xFF52525B),
              ),
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => items[index],
          childCount: items.length,
          addAutomaticKeepAlives: false,
        ),
      ),
    );
  }

  Widget _buildGridGame(
    GamesTourModel game,
    int gameIndex,
    List<GamesTourModel> allGames,
    int listIndex,
  ) {
    return GridGameCardWrapperWidget(
      key: ValueKey('fav_grid_game_${game.gameId}'),
      game: game,
      orderedGames: allGames,
      gameIndex: gameIndex,
      onChangedWithLiveGames: (updatedGames) async {
        // Premium guard - show paywall if not subscribed
        final hasPremium = await requirePremiumGuard(context, ref);
        if (!hasPremium) return;
        if (!mounted) return;

        // Navigate to chess board with the live-updated games
        _navigateToChessBoard(updatedGames[gameIndex], updatedGames, gameIndex);
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
            child: const CircularProgressIndicator(
              color: kWhiteColor,
              strokeWidth: 2.5,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Loading games...',
            style: AppTypography.textSmRegular.copyWith(
              color: const Color(0xFFA1A1AA),
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
            style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.w),
            child: Text(
              error,
              style: AppTypography.textSmRegular.copyWith(
                color: const Color(0xFFA1A1AA),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: 24.h),
          TextButton(
            onPressed:
                () =>
                    ref
                        .read(favoritesCombinedGamesProvider.notifier)
                        .refreshGames(),
            style: TextButton.styleFrom(
              backgroundColor: kWhiteColor.withValues(alpha: 0.1),
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.br),
              ),
            ),
            child: Text(
              'Retry',
              style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildEmptyState() {
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
                  kWhiteColor.withValues(alpha: 0.15),
                  kWhiteColor.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(20.br),
            ),
            child: Icon(
              Icons.sports_esports_outlined,
              color: kWhiteColor.withValues(alpha: 0.7),
              size: 40.ic,
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            'No games found',
            style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40.w),
            child: Text(
              'Your favorite players haven\'t played any games yet.',
              style: AppTypography.textSmRegular.copyWith(
                color: const Color(0xFFA1A1AA),
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
            color: kWhiteColor.withValues(alpha: 0.4),
          ),
          SizedBox(height: 12.h),
          Text(
            'No results',
            style: AppTypography.textMdMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.85),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Try a different filter',
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.55),
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
            color: kWhiteColor.withValues(alpha: 0.4),
          ),
          SizedBox(height: 12.h),
          Text(
            'No matching games',
            style: AppTypography.textMdMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.85),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Try adjusting your filters',
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 20.h),
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              ref.read(favoritesCombinedGamesProvider.notifier).clearFilter();
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: kWhiteColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.br),
              ),
              child: Text(
                'Clear Filters',
                style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
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

  /// Navigate to chess board screen for the selected game.
  void _navigateToChessBoard(
    GamesTourModel game,
    List<GamesTourModel> allGames,
    int gameIndex,
  ) {
    // Set view source to forYou (favorites is part of For You section)
    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.forYou;

    // Disable tournament streaming while inside the chessboard
    ref.read(shouldStreamProvider.notifier).state = false;

    Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder:
            (_) =>
                ChessBoardScreenNew(games: allGames, currentIndex: gameIndex),
      ),
    ).then((_) {
      // Re-enable streaming when coming back
      if (mounted) {
        ref.read(shouldStreamProvider.notifier).state = true;
        ref.invalidate(gameUpdatesStreamProvider);
      }
    });
  }
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
          color: kDarkGreyColor,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: kWhiteColor.withValues(alpha: 0.1)),
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
                  color: kWhiteColor,
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
                color: kWhiteColor.withValues(alpha: 0.5),
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
class _FavoritesLiveBoardGameCard extends ConsumerStatefulWidget {
  const _FavoritesLiveBoardGameCard({
    super.key,
    required this.game,
    required this.gamesData,
    required this.gameIndex,
    required this.listIndex,
    required this.allGames,
    required this.isChessBoardVisible,
    required this.isLast,
    required this.onNavigateToChessBoard,
  });

  final GamesTourModel game;
  final GamesScreenModel gamesData;
  final int gameIndex;
  final int listIndex;
  final List<GamesTourModel> allGames;
  final bool isChessBoardVisible;
  final bool isLast;
  final void Function(
    GamesTourModel game,
    List<GamesTourModel> games,
    int index,
  )
  onNavigateToChessBoard;

  @override
  ConsumerState<_FavoritesLiveBoardGameCard> createState() =>
      _FavoritesLiveBoardGameCardState();
}

class _FavoritesLiveBoardGameCardState
    extends ConsumerState<_FavoritesLiveBoardGameCard> {
  Future<void> _handleNavigate(List<GamesTourModel> updatedGames) async {
    // Premium guard - show paywall if not subscribed
    final hasPremium = await requirePremiumGuard(context, ref);
    if (!hasPremium) return;
    if (!mounted) return;

    // Navigate to chess board with the live-updated games
    widget.onNavigateToChessBoard(
      updatedGames[widget.gameIndex],
      updatedGames,
      widget.gameIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final gameId = widget.game.gameId;

    // Use BoardGameCardWrapperWidget for live position updates
    final card = Padding(
      padding: EdgeInsets.only(bottom: widget.isLast ? 16.h : 12.h),
      child: BoardGameCardWrapperWidget(
        key: ValueKey('fav_board_game_${widget.game.gameId}'),
        game: widget.game,
        orderedGames: widget.allGames,
        gameIndex: widget.gameIndex,
        onChangedWithLiveGames: _handleNavigate,
        pinnedIds: widget.gamesData.pinnedGamedIs,
        onPinToggle: (_) {},
      ),
    );

    // Use global set to track animations - survives tab switches and rebuilds
    if (!_favoritesAnimatedGameIds.contains(gameId)) {
      _favoritesAnimatedGameIds.add(gameId);
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
