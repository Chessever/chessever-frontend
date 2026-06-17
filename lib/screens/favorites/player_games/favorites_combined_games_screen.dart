import 'dart:async';

import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/favorites/player_games/provider/favorites_combined_games_provider.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/live_gamebase_search_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/foreground_task_scheduler.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class FavoritesCombinedGamesScreen extends ConsumerStatefulWidget {
  const FavoritesCombinedGamesScreen({super.key});

  @override
  ConsumerState<FavoritesCombinedGamesScreen> createState() =>
      _FavoritesCombinedGamesScreenState();
}

class _FavoritesCombinedGamesScreenState
    extends ConsumerState<FavoritesCombinedGamesScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;
  Timer? _scrollIdleTimer;
  bool _isScrolling = false;
  static const Duration _scrollIdleDelay = Duration(milliseconds: 180);

  /// Selected player IDs for filtering - empty means show all
  final Set<String> _selectedPlayerIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ForegroundTaskScheduler.cancel('favorites_combined_resume_$hashCode');
    _debounceTimer?.cancel();
    _scrollIdleTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) {
      ForegroundTaskScheduler.cancel('favorites_combined_resume_$hashCode');
      return;
    }
    if (!mounted) return;

    ForegroundTaskScheduler.schedule(
      key: 'favorites_combined_resume_$hashCode',
      task: () {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route?.isCurrent != true) return;

        ref.invalidate(gameUpdatesStreamProvider);
        ref.invalidate(liveGameUpdateStreamProvider);
        ref.invalidate(gameUpdatesBatchStreamProvider);
        unawaited(
          ref.read(favoritesCombinedGamesProvider.notifier).refreshGames(),
        );
      },
    );
  }

  void _onScroll() {
    _markLiveCardsScrolling();
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final state = ref.read(favoritesCombinedGamesProvider);
      if (state.isSearching) {
        ref
            .read(favoritesCombinedGamesProvider.notifier)
            .loadMoreSearchResults();
      } else {
        ref.read(favoritesCombinedGamesProvider.notifier).loadMoreGames();
      }
    }
  }

  void _markLiveCardsScrolling() {
    if (!_isScrolling && mounted) {
      setState(() => _isScrolling = true);
    }
    _scrollIdleTimer?.cancel();
    _scrollIdleTimer = Timer(_scrollIdleDelay, _markLiveCardsIdle);
  }

  void _markLiveCardsIdle() {
    if (!mounted || !_isScrolling) return;
    setState(() => _isScrolling = false);
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

  List<GamesTourModel> _filterGames(
    List<GamesTourModel> games,
    List<FavoritePlayer> favorites,
  ) {
    var filtered = games;

    // Filter by selected players if any are selected
    if (_selectedPlayerIds.isNotEmpty) {
      final selectedFavorites =
          favorites.where((f) => _selectedPlayerIds.contains(f.id)).toList();

      // Stale selection (favorite removed while chip still tracked) — skip
      // filtering rather than nuking the list to an empty state. Pruning of
      // the underlying Set happens out-of-band via post-frame callback.
      if (selectedFavorites.isEmpty) return filtered;

      filtered =
          filtered.where((game) {
            for (final favorite in selectedFavorites) {
              // 1. Try FIDE ID match first (most reliable)
              if (favorite.fideId != null && favorite.fideId!.isNotEmpty) {
                final favFideId = int.tryParse(favorite.fideId!);
                if (favFideId != null) {
                  final whiteId = game.whitePlayer.fideId;
                  final blackId = game.blackPlayer.fideId;
                  if (whiteId == favFideId || blackId == favFideId) {
                    return true;
                  }
                }
              }

              // 2. Fall back to name matching
              final favName = _normalizeNameForMatch(favorite.playerName);
              final whiteName = _normalizeNameForMatch(game.whitePlayer.name);
              final blackName = _normalizeNameForMatch(game.blackPlayer.name);

              if (_namesMatch(favName, whiteName) ||
                  _namesMatch(favName, blackName)) {
                return true;
              }
            }
            return false;
          }).toList();
    }

    return filtered;
  }

  /// Drop any tracked selection IDs that no longer correspond to a current
  /// favorite (e.g. user unfavorited a player while their chip was selected).
  void _pruneStaleSelections(List<FavoritePlayer> favorites) {
    if (_selectedPlayerIds.isEmpty) return;
    final liveIds = favorites.map((f) => f.id).toSet();
    final stale = _selectedPlayerIds.difference(liveIds);
    if (stale.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selectedPlayerIds.removeAll(stale));
    });
  }

  /// Normalize name for matching: lowercase, remove titles, handle "Last, First" format
  String _normalizeNameForMatch(String name) {
    var normalized = name.toLowerCase().trim();
    // Remove extra whitespace
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ');
    // Remove common chess title prefixes (GM, IM, FM, WGM, WIM, WFM, CM, WCM, NM)
    normalized = normalized.replaceFirst(
      RegExp(r'^(gm|im|fm|wgm|wim|wfm|cm|wcm|nm)\s+'),
      '',
    );
    return normalized;
  }

  /// Check if two names match (handles "Last, First" vs "First Last" formats)
  bool _namesMatch(String name1, String name2) {
    // Direct match
    if (name1 == name2) return true;

    // Extract last name (before comma or last word)
    final lastName1 = _extractLastName(name1);
    final lastName2 = _extractLastName(name2);

    // If last names match, it's likely the same person
    if (lastName1.isNotEmpty && lastName1 == lastName2) {
      return true;
    }

    // Check if one contains the other (for partial matches)
    if (name1.contains(name2) || name2.contains(name1)) {
      return true;
    }

    return false;
  }

  /// Extract last name from a player name
  String _extractLastName(String name) {
    // Handle "Last, First" format
    if (name.contains(',')) {
      return name.split(',').first.trim();
    }
    // Handle "First Last" format
    final parts = name.split(' ');
    if (parts.length > 1) {
      return parts.last.trim();
    }
    return name;
  }

  void _togglePlayerFilter(String playerId) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedPlayerIds.contains(playerId)) {
        _selectedPlayerIds.remove(playerId);
      } else {
        _selectedPlayerIds.add(playerId);
      }
    });
  }

  void _clearAllFilters() {
    HapticFeedback.mediumImpact();
    setState(() {
      _selectedPlayerIds.clear();
    });
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
    final state = ref.watch(favoritesCombinedGamesProvider);
    final favoritesAsync = ref.watch(favoritePlayersProviderNew);
    final favorites = favoritesAsync.valueOrNull ?? [];
    final favoriteCount = favorites.length;
    _pruneStaleSelections(favorites);

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                ResponsiveHelper.isTablet
                    ? ResponsiveHelper.contentMaxWidth
                    : double.infinity,
          ),
          child: RefreshIndicator(
            onRefresh: () async {
              HapticFeedbackService.medium();
              await ref
                  .read(favoritesCombinedGamesProvider.notifier)
                  .refreshGames();
            },
            color: context.colors.textPrimary,
            backgroundColor: context.colors.surface,
            edgeOffset: 120,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                // Pinned app bar that floats
                _buildPinnedAppBar(context, favoriteCount, state),

                // Pinned search bar
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverSearchBarDelegate(
                    child: _buildSearchBar(state),
                    height: 68.h,
                  ),
                ),

                // Filter chips — compose with search & filter dialog
                if (favorites.length > 1)
                  SliverToBoxAdapter(child: _buildFilterChips(favorites)),

                // Content
                _buildContentSliver(state, favorites),

                // Bottom padding
                SliverToBoxAdapter(child: SizedBox(height: 24.h)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinnedAppBar(
    BuildContext context,
    int favoriteCount,
    FavoritesCombinedGamesState state,
  ) {
    final hasActiveFilters = state.filter.hasActiveFilters;
    final activeFilterCount = state.filter.activeFilterCount;

    return SliverAppBar(
      pinned: true,
      floating: false,
      backgroundColor: context.colors.background,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      toolbarHeight: 56.h,
      titleSpacing: 0,
      title: Row(
        children: [
          SizedBox(width: 12.w),
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.all(4.w),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 20.sp,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          SizedBox(width: 8.w),
          // Heart icon
          Container(
            width: 28.w,
            height: 28.h,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFEF4444).withValues(alpha: 0.18),
                  const Color(0xFFDC2626).withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(7.br),
            ),
            child: Center(
              child: Icon(
                Icons.favorite_rounded,
                size: 16.sp,
                color: const Color(0xFFF87171),
              ),
            ),
          ),
          SizedBox(width: 10.w),
          // Title
          Expanded(
            child: Row(
              children: [
                Text(
                  'Favorites',
                  style: AppTypography.textLgBold.copyWith(
                    color: context.colors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(width: 8.w),
                // Count badge
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceRecessed,
                    borderRadius: BorderRadius.circular(10.br),
                  ),
                  child: Text(
                    '$favoriteCount',
                    style: AppTypography.textXsMedium.copyWith(
                      color: context.colors.textSecondary,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Filter button
          GestureDetector(
            onTap: () => _showFilterDialog(state),
            child: Container(
              padding: EdgeInsets.all(8.w),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 22.ic,
                    color:
                        hasActiveFilters
                            ? context.colors.textPrimary
                            : context.colors.textSecondary,
                  ),
                  // Badge showing active filter count
                  if (hasActiveFilters)
                    Positioned(
                      right: -4.w,
                      top: -4.h,
                      child: Container(
                        padding: EdgeInsets.all(4.w),
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                        constraints: BoxConstraints(
                          minWidth: 16.w,
                          minHeight: 16.h,
                        ),
                        child: Text(
                          '$activeFilterCount',
                          style: AppTypography.textXsBold.copyWith(
                            color: context.colors.textPrimary,
                            fontSize: 10.sp,
                            height: 1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(width: 12.w),
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

  Widget _buildSearchBar(FavoritesCombinedGamesState state) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
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
            if (_searchController.text.isNotEmpty || state.isSearching) ...[
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
    );
  }

  Widget _buildFilterChips(List<FavoritePlayer> favorites) {
    final hasSelection = _selectedPlayerIds.isNotEmpty;

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
            // Clear button at the end when there's a selection
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
                      color: context.colors.surfaceRecessed,
                      borderRadius: BorderRadius.circular(16.br),
                      border: Border.all(
                        color: context.colors.divider,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.close_rounded,
                          size: 14.sp,
                          color: context.colors.textSecondary,
                        ),
                        SizedBox(width: 4.w),
                        Text(
                          'Clear',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final player = favorites[index];
            final isSelected = _selectedPlayerIds.contains(player.id);
            final federation = _extractFederation(player);
            final displayName = _getDisplayName(player.playerName);

            return Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: GestureDetector(
                onTap: () => _togglePlayerFilter(player.id),
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
                            : context.colors.surfaceRecessed,
                    borderRadius: BorderRadius.circular(16.br),
                    border: Border.all(
                      color:
                          isSelected
                              ? const Color(0xFFEF4444)
                              : context.colors.divider,
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
                          color:
                              isSelected
                                  ? kWhiteColor
                                  : context.colors.textPrimary,
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

    // Apply local favorite player chip filter — composes with search results
    var filteredGames = _filterGames(state.games, favorites);

    // Then apply the game filter (result, color, time control, year, rating)
    if (state.filter.hasActiveFilters) {
      filteredGames = GameFilterHelper.applyFilter(filteredGames, state.filter);
    }

    if (filteredGames.isEmpty && _selectedPlayerIds.isNotEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildNoChipResultsState(),
      );
    }

    // Show filter empty state when game filter excludes all games
    if (filteredGames.isEmpty && state.filter.hasActiveFilters) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildNoFilterResultsState(),
      );
    }

    // Show loading indicator when fetching more
    final showLoadingIndicator =
        (state.hasMore || state.isLoading) && filteredGames.isNotEmpty;

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index >= filteredGames.length) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 24.h),
              child: Center(
                child:
                    state.isLoading
                        ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 24.w,
                              height: 24.h,
                              child: CircularProgressIndicator(
                                color: context.colors.textPrimary,
                                strokeWidth: 2,
                              ),
                            ),
                            SizedBox(height: 8.h),
                            Text(
                              'Loading more games...',
                              style: AppTypography.textXsRegular.copyWith(
                                color: context.colors.textTertiary,
                              ),
                            ),
                          ],
                        )
                        : state.hasMore
                        ? const SizedBox.shrink()
                        : Text(
                          'No more games',
                          style: AppTypography.textXsRegular.copyWith(
                            color: const Color(0xFF52525B),
                          ),
                        ),
              ),
            );
          }

          final game = filteredGames[index];
          return Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: LiveGamebaseSearchGameCard(
              game: game,
              allGames: filteredGames,
              gameIndex: index,
              animationIndex: index,
              showRound: true,
              streamEnabled: !_isScrolling,
              onAdd: () => _showAddToFolderSheet(context, game),
              onLiveAdd: (liveGame) => _showAddToFolderSheet(context, liveGame),
            ),
          );
        }, childCount: filteredGames.length + (showLoadingIndicator ? 1 : 0)),
      ),
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
          SizedBox(height: 8.h),
          Text(
            'Fetching from multiple sources',
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textTertiary,
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
                        .read(favoritesCombinedGamesProvider.notifier)
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
              Icons.sports_esports_outlined,
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
              'Your favorite players haven\'t played any games yet, or add some favorite players first.',
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: 24.h),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
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
              'Add favorites',
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
              ),
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
            'Try a different filter',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildNoChipResultsState() {
    final selectedCount = _selectedPlayerIds.length;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_off_outlined,
            size: 56.sp,
            color: context.colors.textPrimary.withValues(alpha: 0.4),
          ),
          SizedBox(height: 12.h),
          Text(
            selectedCount == 1
                ? 'No games for this player'
                : 'No games for these players',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.85),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Clear chips or load more games',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 20.h),
          GestureDetector(
            onTap: _clearAllFilters,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: context.colors.textPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.br),
              ),
              child: Text(
                'Clear Chips',
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
              ref.read(favoritesCombinedGamesProvider.notifier).clearFilter();
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
}

/// Delegate for pinned search bar in sliver list
class _SliverSearchBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverSearchBarDelegate({required this.child, required this.height});

  final Widget child;
  final double height;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Use SizedBox to ensure the child respects the exact height
    // This prevents layoutExtent from exceeding paintExtent
    return SizedBox(
      height: maxExtent,
      child: Container(color: context.colors.background, child: child),
    );
  }

  @override
  bool shouldRebuild(_SliverSearchBarDelegate oldDelegate) {
    return child != oldDelegate.child || height != oldDelegate.height;
  }
}
