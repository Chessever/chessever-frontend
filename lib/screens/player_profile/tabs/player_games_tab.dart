import 'dart:async';

import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/gamebase_search_game_card.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:chessever2/widgets/scroll_to_top_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// Games tab showing all games of a player with comprehensive filters
class PlayerGamesTab extends ConsumerStatefulWidget {
  const PlayerGamesTab({super.key, required this.fideId});

  final int fideId;

  @override
  ConsumerState<PlayerGamesTab> createState() => _PlayerGamesTabState();
}

class _PlayerGamesTabState extends ConsumerState<PlayerGamesTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;

  /// Track collapsed state for date sections
  final Set<String> _collapsedDates = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      ref
          .read(playerProfileGamesProvider(widget.fideId).notifier)
          .setSearchQuery(value);
    });
  }

  void _clearSearch() {
    HapticFeedback.lightImpact();
    _debounceTimer?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref
        .read(playerProfileGamesProvider(widget.fideId).notifier)
        .setSearchQuery('');
  }

  Future<void> _showFilterDialog() async {
    HapticFeedbackService.buttonPress();
    final currentState = ref.read(playerProfileGamesProvider(widget.fideId));
    final result = await showGameFilterDialog(
      context: context,
      currentFilter: currentState.filter,
    );
    if (result != null && mounted) {
      ref
          .read(playerProfileGamesProvider(widget.fideId).notifier)
          .applyFilter(result);
    }
  }

  /// Group games by date
  Map<String, List<GamesTourModel>> _groupGamesByDate(List<GamesTourModel> games) {
    final grouped = <String, List<GamesTourModel>>{};
    const unknownDateKey = '0000-00-00';

    for (final game in games) {
      final date = game.lastMoveTime;
      final dateKey = date != null
          ? DateFormat('yyyy-MM-dd').format(date)
          : unknownDateKey;
      grouped.putIfAbsent(dateKey, () => []).add(game);
    }

    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return Map.fromEntries(
      sortedKeys.map((key) => MapEntry(key, grouped[key]!)),
    );
  }

  String _formatDateHeader(String dateKey) {
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
      return DateFormat('EEEE, MMM d, yyyy').format(date);
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
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final state = ref.watch(playerProfileGamesProvider(widget.fideId));
    final viewMode = ref.watch(gamesListViewModeProvider);

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async {
            HapticFeedbackService.medium();
            await ref
                .read(playerProfileGamesProvider(widget.fideId).notifier)
                .refresh();
          },
          color: kWhiteColor,
          backgroundColor: kBlack2Color,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // Search bar with filter button
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
                  child: _buildSearchBar(state),
                ),
              ),

              // Active filters indicator
              if (state.filter.hasActiveFilters)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    child: _buildActiveFiltersChip(state),
                  ),
                ),

              // Games count
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
                  child: _buildGamesCount(state),
                ),
              ),

              // Content
              _buildContentSliver(state, viewMode),

              // Bottom padding
              SliverToBoxAdapter(child: SizedBox(height: 24.h)),
            ],
          ),
        ),

        // Scroll to top button
        Positioned(
          bottom: 0,
          right: 0,
          child: ScrollToTopButton(scrollController: _scrollController),
        ),
      ],
    );
  }

  Widget _buildSearchBar(PlayerProfileGamesState state) {
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
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: AppTypography.textSmRegular.copyWith(
                        color: const Color(0xFFFAFAFA),
                      ),
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search opponent, opening...',
                        hintStyle: AppTypography.textSmRegular.copyWith(
                          color: const Color(0xFFA1A1AA),
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty ||
                      state.searchQuery.isNotEmpty) ...[
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
            onTap: _showFilterDialog,
            child: Container(
              width: searchBarHeight,
              height: searchBarHeight,
              decoration: BoxDecoration(
                color: hasActiveFilters
                    ? kPrimaryColor.withValues(alpha: 0.15)
                    : const Color(0xFF09090B),
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(
                  color: hasActiveFilters
                      ? kPrimaryColor.withValues(alpha: 0.5)
                      : const Color(0xFF27272A),
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 20.sp,
                    color: hasActiveFilters
                        ? kPrimaryColor
                        : const Color(0xFFA1A1AA),
                  ),
                  if (hasActiveFilters)
                    Positioned(
                      right: 6.w,
                      top: 6.h,
                      child: Container(
                        width: 14.w,
                        height: 14.h,
                        decoration: const BoxDecoration(
                          color: kPrimaryColor,
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

  Widget _buildActiveFiltersChip(PlayerProfileGamesState state) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        ref
            .read(playerProfileGamesProvider(widget.fideId).notifier)
            .clearFilter();
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 8.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: kPrimaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8.br),
          border: Border.all(color: kPrimaryColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list_rounded,
              size: 16.sp,
              color: kPrimaryColor,
            ),
            SizedBox(width: 6.w),
            Text(
              '${state.filter.activeFilterCount} filter${state.filter.activeFilterCount > 1 ? 's' : ''} active',
              style: AppTypography.textXsMedium.copyWith(color: kPrimaryColor),
            ),
            SizedBox(width: 8.w),
            Icon(
              Icons.close_rounded,
              size: 14.sp,
              color: kPrimaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGamesCount(PlayerProfileGamesState state) {
    final filteredCount = state.filteredGames.length;
    final totalCount = state.allGames.length;
    final isFiltered = state.filter.hasActiveFilters || state.searchQuery.isNotEmpty;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          isFiltered
              ? '$filteredCount of $totalCount games'
              : '$totalCount games',
          style: AppTypography.textXsMedium.copyWith(
            color: kWhiteColor.withValues(alpha: 0.5),
          ),
        ),
        if (isFiltered && filteredCount != totalCount)
          Text(
            '(filtered)',
            style: AppTypography.textXsRegular.copyWith(
              color: kPrimaryColor.withValues(alpha: 0.7),
            ),
          ),
      ],
    );
  }

  Widget _buildContentSliver(PlayerProfileGamesState state, GamesListViewMode viewMode) {
    if (state.isLoading && state.allGames.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildLoadingState(),
      );
    }

    if (state.error != null && state.allGames.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildErrorState(state.error!),
      );
    }

    if (state.allGames.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(),
      );
    }

    final games = state.filteredGames;

    // Build a mapping of game IDs to their indices for reliable lookup
    final gameIdToIndex = <String, int>{};
    for (int i = 0; i < games.length; i++) {
      gameIdToIndex[games[i].gameId] = i;
    }

    if (games.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildNoFilterResultsState(),
      );
    }

    final isGridMode = viewMode == GamesListViewMode.chessBoardGrid;
    final isChessBoardVisible = viewMode == GamesListViewMode.chessBoard;

    // Create GamesScreenModel for GameCardWrapperWidget
    final gamesData = GamesScreenModel(
      gamesTourModels: games,
      pinnedGamedIs: const [],
    );

    // Group games by date
    final gamesByDate = _groupGamesByDate(games);

    // Build list items
    final items = <Widget>[];
    bool isFirstGameCard = true;

    for (final entry in gamesByDate.entries) {
      final dateKey = entry.key;
      final dateGames = entry.value;
      final isCollapsed = _collapsedDates.contains(dateKey);

      // Date header
      items.add(
        Padding(
          padding: EdgeInsets.only(bottom: 12.h, top: items.isEmpty ? 8.h : 0),
          child: _DateHeader(
            dateLabel: _formatDateHeader(dateKey),
            gameCount: dateGames.length,
            isExpanded: !isCollapsed,
            onToggle: () => _toggleDateSection(dateKey),
          ),
        ),
      );

      // Games under this date
      if (!isCollapsed) {
        if (isGridMode) {
          // Grid mode: show 2 chessboards per row
          for (int i = 0; i < dateGames.length; i += 2) {
            final game1 = dateGames[i];
            final game2 = i + 1 < dateGames.length ? dateGames[i + 1] : null;
            // Use reliable index lookup by game ID
            final gameIndex1 = gameIdToIndex[game1.gameId] ?? 0;
            final gameIndex2 = game2 != null ? (gameIdToIndex[game2.gameId] ?? 0) : 0;
            final isLast = i + 2 >= dateGames.length;

            items.add(
              Padding(
                padding: EdgeInsets.only(bottom: isLast ? 16.h : 12.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildGridGame(game1, gameIndex1, games),
                    if (game2 != null)
                      _buildGridGame(game2, gameIndex2, games),
                  ],
                ),
              ),
            );
          }
        } else {
          // Card mode or Board mode
          for (int i = 0; i < dateGames.length; i++) {
            final game = dateGames[i];
            final isLast = i == dateGames.length - 1;
            // Use reliable index lookup by game ID
            final globalIndex = gameIdToIndex[game.gameId] ?? 0;
            final showHint = isFirstGameCard && viewMode == GamesListViewMode.gamesCard;
            if (isFirstGameCard) isFirstGameCard = false;

            if (isChessBoardVisible) {
              // Board mode: use ChessBoardFromFENNew with premium-guarded navigation
              items.add(
                Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 16.h : 12.h),
                  child: ChessBoardFromFENNew(
                    key: ValueKey('player_board_game_${game.gameId}'),
                    gamesTourModel: game,
                    onChanged: () async {
                      // Premium guard - show paywall if not subscribed
                      final hasPremium = await requirePremiumGuard(context, ref);
                      if (!hasPremium) return;
                      if (!mounted) return;

                      ref.read(gameCardWrapperProvider).navigateToChessBoard(
                            context: context,
                            orderedGames: games,
                            gameIndex: globalIndex,
                            onReturnFromChessboard: (_) {},
                            viewSource: ChessboardView.playerProfile,
                          );
                    },
                    pinnedIds: gamesData.pinnedGamedIs,
                    onPinToggle: (_) {},
                  ),
                ),
              );
            } else {
              // Card mode: use GamebaseSearchGameCard
              items.add(
                Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 16.h : 12.h),
                  child: GamebaseSearchGameCard(
                    game: game,
                    allGames: games,
                    gameIndex: globalIndex,
                    animationIndex: items.length,
                    showRound: true,
                    showSwipeHint: showHint,
                    showGamebaseButton: false,
                    onAdd: () => _showAddToFolderSheet(game),
                  ),
                ),
              );
            }
          }
        }
      }
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => items[index],
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _buildGridGame(
    GamesTourModel game,
    int gameIndex,
    List<GamesTourModel> allGames,
  ) {
    return GridChessBoardFromFENNew(
      key: ValueKey('player_grid_game_${game.gameId}'),
      gamesTourModel: game,
      onChanged: () async {
        // Premium guard - show paywall if not subscribed
        final hasPremium = await requirePremiumGuard(context, ref);
        if (!hasPremium) return;
        if (!mounted) return;

        ref.read(gameCardWrapperProvider).navigateToChessBoard(
              context: context,
              orderedGames: allGames,
              gameIndex: gameIndex,
              onReturnFromChessboard: (_) {},
              viewSource: ChessboardView.playerProfile,
            );
      },
      pinnedIds: const [],
      onPinToggle: (_) {},
    );
  }

  void _showAddToFolderSheet(GamesTourModel game) {
    showAddToFolderSheet(context: context, game: game);
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
              color: Colors.redAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16.br),
            ),
            child: Icon(
              Icons.error_outline_rounded,
              color: Colors.redAccent,
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
            onPressed: () => ref
                .read(playerProfileGamesProvider(widget.fideId).notifier)
                .refresh(),
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
              'This player has no recorded games yet.',
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
              ref
                  .read(playerProfileGamesProvider(widget.fideId).notifier)
                  .clearFilter();
              _clearSearch();
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
}

/// Date section header
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
