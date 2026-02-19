import 'dart:async';

import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/live_gamebase_search_game_card.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/tabs/player_events_tab.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/board_game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
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

/// Games tab showing all games of a player with comprehensive filters
class PlayerGamesTab extends ConsumerStatefulWidget {
  const PlayerGamesTab({
    super.key,
    this.fideId,
    required this.playerName,
    this.dataSource = PlayerProfileDataSource.supabase,
    this.gamebasePlayerId,
  });

  final int? fideId;
  final String playerName;
  final PlayerProfileDataSource dataSource;
  final String? gamebasePlayerId;

  @override
  ConsumerState<PlayerGamesTab> createState() => _PlayerGamesTabState();
}

class _PlayerGamesTabState extends ConsumerState<PlayerGamesTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  /// Get the player profile key for provider lookups
  PlayerProfileKey get _playerKey => PlayerProfileKey(
    fideId: widget.fideId,
    playerName: widget.playerName,
    source: widget.dataSource,
    gamebasePlayerId: widget.gamebasePlayerId,
  );

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (widget.dataSource != PlayerProfileDataSource.twic) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 560) return;
    ref.read(playerProfileGamesKeyProvider(_playerKey).notifier).loadMore();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      ref
          .read(playerProfileGamesKeyProvider(_playerKey).notifier)
          .setSearchQuery(value);
    });
  }

  void _clearSearch() {
    HapticFeedback.lightImpact();
    _debounceTimer?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref
        .read(playerProfileGamesKeyProvider(_playerKey).notifier)
        .setSearchQuery('');
  }

  Future<void> _showFilterDialog() async {
    HapticFeedbackService.buttonPress();
    final currentState = ref.read(playerProfileGamesKeyProvider(_playerKey));
    final result = await showGameFilterDialog(
      context: context,
      currentFilter: currentState.filter,
    );
    if (result != null && mounted) {
      ref
          .read(playerProfileGamesKeyProvider(_playerKey).notifier)
          .applyFilter(result);
    }
  }

  /// Group games by event (tourId).
  /// Input games are already sorted by date descending, so insertion order
  /// in the LinkedHashMap gives events ordered by most-recent game first.
  Map<String, List<GamesTourModel>> _groupGamesByEvent(
    List<GamesTourModel> games,
  ) {
    final grouped = <String, List<GamesTourModel>>{};
    for (final game in games) {
      grouped.putIfAbsent(game.tourId, () => []).add(game);
    }
    return grouped;
  }

  /// Compute the player's score in a set of games (wins=1, draws=0.5).
  double _computePlayerScore(List<GamesTourModel> eventGames) {
    double score = 0;
    final fideId = widget.fideId;
    final playerName = widget.playerName.trim().toLowerCase();

    for (final game in eventGames) {
      bool isWhite = false;
      bool isBlack = false;

      if (fideId != null) {
        isWhite = game.whitePlayer.fideId == fideId;
        isBlack = game.blackPlayer.fideId == fideId;
      }
      if (!isWhite && !isBlack) {
        isWhite = game.whitePlayer.name.toLowerCase().contains(playerName);
        isBlack = game.blackPlayer.name.toLowerCase().contains(playerName);
      }
      if (!isWhite && !isBlack) continue;

      if ((isWhite && game.gameStatus == GameStatus.whiteWins) ||
          (isBlack && game.gameStatus == GameStatus.blackWins)) {
        score += 1.0;
      } else if (game.gameStatus == GameStatus.draw) {
        score += 0.5;
      }
    }
    return score;
  }

  Future<void> _navigateToEvent(String tourId) async {
    HapticFeedbackService.buttonPress();
    try {
      final broadcast = await ref
          .read(groupBroadcastRepositoryProvider)
          .getGroupBroadcastById(tourId);
      ref.read(selectedBroadcastModelProvider.notifier).state = broadcast;
      if (!mounted) return;
      if (ref.read(selectedBroadcastModelProvider) != null) {
        Navigator.pushNamed(context, '/tournament_detail_screen');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open event')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final state = ref.watch(playerProfileGamesKeyProvider(_playerKey));
    final viewMode = ref.watch(gamesListViewModeProvider);
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    // Watch event data for event-grouped display
    final eventCardsAsync =
        widget.dataSource == PlayerProfileDataSource.twic
            ? ref.watch(playerTwicEventCardsProvider(_playerKey))
            : widget.fideId != null
            ? ref.watch(playerEventCardsProvider(widget.fideId!))
            : const AsyncValue<Map<String, GroupEventCardModel>>.data({});
    final eventsAsync = ref.watch(playerEventsKeyProvider(_playerKey));

    Widget content = RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        await ref
            .read(playerProfileGamesKeyProvider(_playerKey).notifier)
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
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedHeaderDelegate(
              minExtent: state.hasActiveFilters ? 130.h : 94.h,
              maxExtent: state.hasActiveFilters ? 130.h : 94.h,
              child: _buildStickyHeader(state, horizontalPadding),
            ),
          ),

          // Content
          _buildContentSliver(state, viewMode, eventCardsAsync, eventsAsync),

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

  Widget _buildStickyHeader(
    PlayerProfileGamesState state,
    double horizontalPadding,
  ) {
    return Container(
      color: kBackgroundColor,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12.h,
              horizontalPadding,
              8.h,
            ),
            child: _buildSearchBar(state),
          ),
          if (state.hasActiveFilters)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: _buildActiveFiltersChip(state),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              8.h,
              horizontalPadding,
              0,
            ),
            child: _buildGamesCount(state),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(PlayerProfileGamesState state) {
    final hasActiveFilters = state.hasActiveFilters;
    final activeFilterCount = state.activeFilterCount;
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

  Widget _buildActiveFiltersChip(PlayerProfileGamesState state) {
    const filterRedColor = Color(0xFFEF4444);
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        ref
            .read(playerProfileGamesKeyProvider(_playerKey).notifier)
            .clearFilter();
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 8.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: filterRedColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8.br),
          border: Border.all(color: filterRedColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list_rounded, size: 16.sp, color: filterRedColor),
            SizedBox(width: 6.w),
            Text(
              '${state.activeFilterCount} filter${state.activeFilterCount > 1 ? 's' : ''} active',
              style: AppTypography.textXsMedium.copyWith(color: filterRedColor),
            ),
            if (state.playerResultFilter != PlayerResultFilter.all) ...[
              SizedBox(width: 8.w),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: filterRedColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6.br),
                ),
                child: Text(
                  state.playerResultFilter.label,
                  style: AppTypography.textXsRegular.copyWith(
                    color: filterRedColor,
                  ),
                ),
              ),
            ],
            SizedBox(width: 8.w),
            Icon(Icons.close_rounded, size: 14.sp, color: filterRedColor),
          ],
        ),
      ),
    );
  }

  Widget _buildGamesCount(PlayerProfileGamesState state) {
    final isTwic = widget.dataSource == PlayerProfileDataSource.twic;
    final isTwicLoading = isTwic && state.isLoading && state.allGames.isEmpty;
    final filteredCount = state.filteredGames.length;
    final totalCount = state.allGames.length;
    final isFiltered = state.hasActiveFilters || state.searchQuery.isNotEmpty;
    final serverTotal = state.totalCount;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          isTwicLoading
              ? 'Loading games...'
              : isTwic
              ? (isFiltered
                  ? '$filteredCount shown • $totalCount loaded'
                  : (serverTotal != null
                      ? '$totalCount of $serverTotal games loaded'
                      : '$totalCount games'))
              : (isFiltered
                  ? '$filteredCount of $totalCount games'
                  : '$totalCount games'),
          style: AppTypography.textXsMedium.copyWith(
            color: kWhiteColor.withValues(alpha: 0.5),
          ),
        ),
        if (isFiltered && filteredCount != totalCount && !isTwic)
          Text(
            '(filtered)',
            style: AppTypography.textXsRegular.copyWith(
              color: const Color(0xFFEF4444).withValues(alpha: 0.7),
            ),
          ),
      ],
    );
  }

  Widget _buildContentSliver(
    PlayerProfileGamesState state,
    GamesListViewMode viewMode,
    AsyncValue<Map<String, GroupEventCardModel>> eventCardsAsync,
    AsyncValue<List<PlayerEventData>> eventsAsync,
  ) {
    final isTwicBlockingLoading =
        widget.dataSource == PlayerProfileDataSource.twic && state.isLoading;
    if (isTwicBlockingLoading || (state.isLoading && state.allGames.isEmpty)) {
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
      final isTwic = widget.dataSource == PlayerProfileDataSource.twic;
      if (isTwic &&
          state.searchQuery.trim().isNotEmpty &&
          (state.hasMorePages || state.isLoadingMore)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref
              .read(playerProfileGamesKeyProvider(_playerKey).notifier)
              .loadMore();
        });
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _buildSearchingMoreState(),
        );
      }
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildNoFilterResultsState(),
      );
    }

    final isGridMode = viewMode == GamesListViewMode.chessBoardGrid;
    final isChessBoardVisible = viewMode == GamesListViewMode.chessBoard;

    // Group games by event (tourId)
    final gamesByEvent = _groupGamesByEvent(games);
    final eventCards = eventCardsAsync.valueOrNull ?? {};
    final eventDataList = eventsAsync.valueOrNull ?? [];
    final eventDataMap = {for (final e in eventDataList) e.tourId: e};

    // Build list items
    final items = <Widget>[];
    bool isFirstGameCard = true;
    bool isFirstEvent = true;

    for (final entry in gamesByEvent.entries) {
      final tourId = entry.key;
      final eventGames = entry.value;
      final eventCard = eventCards[tourId];
      final eventData = eventDataMap[tourId];
      final playerScore = _computePlayerScore(eventGames);

      // Event header (card + stats row)
      items.add(
        Padding(
          padding: EdgeInsets.only(
            top: isFirstEvent ? 8.h : 20.h,
            bottom: 12.h,
          ),
          child: _EventSection(
            eventCard: eventCard,
            eventData: eventData,
            tourId: tourId,
            tourSlug: eventGames.first.tourSlug,
            gameCount: eventGames.length,
            playerScore: playerScore,
            onTap: () => _navigateToEvent(tourId),
          ),
        ),
      );
      isFirstEvent = false;

      // Games under this event
      if (isGridMode) {
        final int gridColumns =
            ResponsiveHelper.isTablet && ResponsiveHelper.isLandscape ? 4 : 2;

        for (int i = 0; i < eventGames.length; i += gridColumns) {
          final isLast = i + gridColumns >= eventGames.length;

          final rowGames = <GamesTourModel>[];
          for (int j = 0; j < gridColumns && i + j < eventGames.length; j++) {
            rowGames.add(eventGames[i + j]);
          }

          items.add(
            Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12.h),
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
        for (int i = 0; i < eventGames.length; i++) {
          final game = eventGames[i];
          final isLast = i == eventGames.length - 1;
          final globalIndex = gameIdToIndex[game.gameId] ?? 0;
          final showHint =
              isFirstGameCard && viewMode == GamesListViewMode.gamesCard;
          if (isFirstGameCard) isFirstGameCard = false;

          if (isChessBoardVisible) {
            items.add(
              Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 12.h),
                child: BoardGameCardWrapperWidget(
                  key: ValueKey('player_board_game_${game.gameId}'),
                  game: game,
                  orderedGames: games,
                  gameIndex: globalIndex,
                  onChangedWithLiveGames: (updatedGames) async {
                    final hasPremium = await requirePremiumGuard(context, ref);
                    if (!hasPremium) return;
                    if (!mounted) return;

                    ref
                        .read(gameCardWrapperProvider)
                        .navigateToChessBoard(
                          context: context,
                          orderedGames: updatedGames,
                          gameIndex: globalIndex,
                          onReturnFromChessboard: (_) {},
                          viewSource: ChessboardView.playerProfile,
                        );
                  },
                  pinnedIds: const [],
                  onPinToggle: (_) {},
                ),
              ),
            );
          } else {
            items.add(
              Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 12.h),
                child: LiveGamebaseSearchGameCard(
                  game: game,
                  allGames: games,
                  gameIndex: globalIndex,
                  animationIndex: items.length,
                  showRound: true,
                  showSwipeHint: showHint,
                  showGamebaseButton: false,
                  playerProfileDataSource: widget.dataSource,
                  onAdd: () => _showAddToFolderSheet(game),
                ),
              ),
            );
          }
        }
      }
    }

    if (widget.dataSource == PlayerProfileDataSource.twic) {
      items.add(
        Padding(
          padding: EdgeInsets.only(top: 12.h),
          child: _buildTwicPaginationFooter(state),
        ),
      );
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
    return GridGameCardWrapperWidget(
      key: ValueKey('player_grid_game_${game.gameId}'),
      game: game,
      orderedGames: allGames,
      gameIndex: gameIndex,
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
              viewSource: ChessboardView.playerProfile,
            );
      },
      pinnedIds: const [],
      onPinToggle: (_) {},
    );
  }

  Widget _buildTwicPaginationFooter(PlayerProfileGamesState state) {
    if (state.isLoadingMore) {
      return Container(
        padding: EdgeInsets.symmetric(vertical: 14.h),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16.w,
              height: 16.h,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                color: kWhiteColor70,
              ),
            ),
            SizedBox(width: 10.w),
            Text(
              'Loading more games...',
              style: AppTypography.textXsRegular.copyWith(color: kWhiteColor70),
            ),
          ],
        ),
      );
    }

    if (state.hasMorePages) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(playerProfileGamesKeyProvider(_playerKey).notifier).loadMore();
      });

      return GestureDetector(
        onTap:
            () =>
                ref
                    .read(playerProfileGamesKeyProvider(_playerKey).notifier)
                    .loadMore(),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 14.h),
          alignment: Alignment.center,
          child: Text(
            'Load more games',
            style: AppTypography.textXsMedium.copyWith(color: kWhiteColor70),
          ),
        ),
      );
    }

    if (state.totalCount != null && state.totalCount! > 0) {
      return Container(
        padding: EdgeInsets.symmetric(vertical: 14.h),
        alignment: Alignment.center,
        child: Text(
          'Loaded all ${state.totalCount} games',
          style: AppTypography.textXsRegular.copyWith(
            color: kWhiteColor.withValues(alpha: 0.45),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  void _showAddToFolderSheet(GamesTourModel game) {
    showAddToFolderSheet(context: context, game: game);
  }

  Widget _buildLoadingState() {
    return Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < 4; i++) ...[
                Container(
                  width: double.infinity,
                  height: 96.h,
                  margin: EdgeInsets.only(bottom: i == 3 ? 0 : 12.h),
                  decoration: BoxDecoration(
                    color: kBlack2Color,
                    borderRadius: BorderRadius.circular(12.br),
                  ),
                ),
              ],
              SizedBox(height: 16.h),
              Text(
                'Loading games...',
                style: AppTypography.textSmRegular.copyWith(
                  color: const Color(0xFFA1A1AA),
                ),
              ),
            ],
          ),
        )
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(duration: 1400.ms, color: kWhiteColor.withValues(alpha: 0.1));
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
            onPressed:
                () =>
                    ref
                        .read(
                          playerProfileGamesKeyProvider(_playerKey).notifier,
                        )
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
                  .read(playerProfileGamesKeyProvider(_playerKey).notifier)
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

  Widget _buildSearchingMoreState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 24.w,
            height: 24.h,
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              color: kWhiteColor70,
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            'Searching more games...',
            style: AppTypography.textSmRegular.copyWith(color: kWhiteColor70),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 220.ms);
  }
}

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedHeaderDelegate({
    required this.minExtent,
    required this.maxExtent,
    required this.child,
  });

  @override
  final double minExtent;

  @override
  final double maxExtent;

  final Widget child;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) {
    return minExtent != oldDelegate.minExtent ||
        maxExtent != oldDelegate.maxExtent ||
        child != oldDelegate.child;
  }
}

/// Event section header: EventCard (or fallback) + player stats row
class _EventSection extends StatelessWidget {
  const _EventSection({
    this.eventCard,
    this.eventData,
    required this.tourId,
    this.tourSlug,
    required this.gameCount,
    required this.playerScore,
    this.onTap,
  });

  final GroupEventCardModel? eventCard;
  final PlayerEventData? eventData;
  final String tourId;
  final String? tourSlug;
  final int gameCount;
  final double playerScore;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Event card or fallback
          if (eventCard != null)
            EventCard(
              tourEventCardModel: eventCard!,
              heroTagSuffix: '_player_games_$tourId',
            )
          else
            _buildFallbackCard(),

          // Player stats row
          _buildStatsRow(),
        ],
      ),
    );
  }

  Widget _buildFallbackCard() {
    final eventName = eventData?.tourName ?? _formatSlug(tourSlug ?? tourId);
    return Container(
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.vertical(top: Radius.circular(8.br)),
      ),
      padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 16.sp),
      child: Text(
        eventName,
        style: AppTypography.textSmMedium.copyWith(
          color: kWhiteColor,
          height: 1.2,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildStatsRow() {
    return Container(
      margin: EdgeInsets.only(top: 1.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(8.br),
          bottomRight: Radius.circular(8.br),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.sports_esports_outlined,
                size: 14.sp,
                color: kWhiteColor.withValues(alpha: 0.5),
              ),
              SizedBox(width: 4.w),
              Text(
                '$gameCount ${gameCount == 1 ? 'game' : 'games'}',
                style: AppTypography.textXsRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          if (gameCount > 0)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
              decoration: BoxDecoration(
                color: _getScoreColor().withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4.br),
              ),
              child: Text(
                '${_formatScore(playerScore)}/$gameCount',
                style: AppTypography.textXsBold.copyWith(
                  color: _getScoreColor(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatScore(double score) {
    if (score == score.truncateToDouble()) {
      return score.toInt().toString();
    }
    return score.toStringAsFixed(1);
  }

  String _formatSlug(String slug) {
    return slug
        .split('-')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  Color _getScoreColor() {
    if (gameCount == 0) return kWhiteColor;
    final percentage = playerScore / gameCount;
    if (percentage >= 0.6) return kGreenColor;
    if (percentage >= 0.4) return kWhiteColor;
    return Colors.redAccent;
  }
}
