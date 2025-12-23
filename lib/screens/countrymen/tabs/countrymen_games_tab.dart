import 'dart:async';

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/countrymen/provider/countrymen_combined_games_provider.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/gamebase_search_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
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
    with AutomaticKeepAliveClientMixin {
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
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _debounceTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

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

  void _loadMoreDays() {
    HapticFeedback.mediumImpact();
    final state = ref.read(countrymenCombinedGamesProvider);
    if (state.isSearching) {
      ref.read(countrymenCombinedGamesProvider.notifier).loadMoreSearchResults();
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
  Map<String, List<GamesTourModel>> _groupGamesByDate(List<GamesTourModel> games) {
    final grouped = <String, List<GamesTourModel>>{};

    for (final game in games) {
      final date = game.lastMoveTime ?? DateTime.now();
      final dateKey = DateFormat('yyyy-MM-dd').format(date);
      grouped.putIfAbsent(dateKey, () => []).add(game);
    }

    // Sort keys by date descending (most recent first)
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) => b.compareTo(a));

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
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final state = ref.watch(countrymenCombinedGamesProvider);
    final viewMode = ref.watch(gamesListViewModeProvider);

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async {
            HapticFeedbackService.medium();
            await ref.read(countrymenCombinedGamesProvider.notifier).refreshGames();
          },
          color: kWhiteColor,
          backgroundColor: kBlack2Color,
          child: CustomScrollView(
            key: PageStorageKey<String>('countrymen_games_list_${viewMode.index}'),
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
                        hintText: 'Search games',
                        hintStyle: AppTypography.textSmRegular.copyWith(
                          color: const Color(0xFFA1A1AA),
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
              width: searchBarHeight,
              height: searchBarHeight,
              decoration: BoxDecoration(
                color: hasActiveFilters
                    ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                    : const Color(0xFF09090B),
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(
                  color: hasActiveFilters
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
                    color: hasActiveFilters ? const Color(0xFFEF4444) : const Color(0xFFA1A1AA),
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

  Future<void> _showFilterDialog(CountrymenCombinedGamesState state) async {
    HapticFeedbackService.buttonPress();
    final result = await showGameFilterDialog(
      context: context,
      currentFilter: state.filter,
    );
    if (result != null && mounted) {
      ref.read(countrymenCombinedGamesProvider.notifier).applyFilter(result);
    }
  }

  Widget _buildContentSliver(
    CountrymenCombinedGamesState state,
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
          // Grid mode: pair games side by side
          for (int i = 0; i < dateGames.length; i += 2) {
            final game1 = dateGames[i];
            final game2 = i + 1 < dateGames.length ? dateGames[i + 1] : null;
            final isLast = i + 2 >= dateGames.length;

            items.add(
              Padding(
                padding: EdgeInsets.only(bottom: isLast ? 16.h : 12.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildGridGame(game1, games.indexOf(game1), games, items.length),
                    if (game2 != null)
                      _buildGridGame(game2, games.indexOf(game2), games, items.length),
                  ],
                ),
              ),
            );
          }
        } else {
          // Card mode or Board mode
          for (int i = 0; i < dateGames.length; i++) {
            final game = dateGames[i];
            final gameIndex = games.indexOf(game);
            final isLast = i == dateGames.length - 1;
            final showHint = isFirstGameCard && viewMode == GamesListViewMode.gamesCard;
            if (isFirstGameCard) isFirstGameCard = false;

            if (isChessBoardVisible) {
              // Board mode: use GameCardWrapperWidget with chessboard visible
              items.add(
                _CountrymenKeepAliveGameCard(
                  key: ValueKey('cmen_game_${game.gameId}_${viewMode.index}'),
                  game: game,
                  gamesData: gamesData,
                  gameIndex: gameIndex,
                  listIndex: items.length,
                  allGames: games,
                  isChessBoardVisible: true,
                  isLast: isLast,
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
                    gameIndex: gameIndex,
                    animationIndex: items.length,
                    showRound: true,
                    showSwipeHint: showHint,
                    showGamebaseButton: false,
                    onAdd: () => _showAddToFolderSheet(context, game),
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
          addAutomaticKeepAlives: true,
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
    return GridChessBoardFromFENNew(
      key: ValueKey('cmen_grid_game_${game.gameId}'),
      gamesTourModel: game,
      onChanged: () => ref
          .read(gameCardWrapperProvider)
          .navigateToChessBoard(
            context: context,
            orderedGames: allGames,
            gameIndex: gameIndex,
            onReturnFromChessboard: (_) {},
          ),
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
            onPressed: () =>
                ref.read(countrymenCombinedGamesProvider.notifier).refreshGames(),
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
                  kWhiteColor.withValues(alpha: 0.15),
                  kWhiteColor.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(20.br),
            ),
            child: Icon(
              Icons.public_outlined,
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
              'No recent games found for players from $countryName',
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
            'Try a different search term',
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
              ref.read(countrymenCombinedGamesProvider.notifier).clearFilter();
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: kWhiteColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.br),
              ),
              child: Text(
                'Clear Filters',
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor,
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

/// StatefulWidget that uses AutomaticKeepAliveClientMixin to keep game cards alive
/// This prevents the card from being disposed when scrolled off-screen
class _CountrymenKeepAliveGameCard extends StatefulWidget {
  const _CountrymenKeepAliveGameCard({
    super.key,
    required this.game,
    required this.gamesData,
    required this.gameIndex,
    required this.listIndex,
    required this.allGames,
    required this.isChessBoardVisible,
    required this.isLast,
  });

  final GamesTourModel game;
  final GamesScreenModel gamesData;
  final int gameIndex;
  final int listIndex;
  final List<GamesTourModel> allGames;
  final bool isChessBoardVisible;
  final bool isLast;

  @override
  State<_CountrymenKeepAliveGameCard> createState() => _CountrymenKeepAliveGameCardState();
}

class _CountrymenKeepAliveGameCardState extends State<_CountrymenKeepAliveGameCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final gameId = widget.game.gameId;

    final card = Padding(
      padding: EdgeInsets.only(bottom: widget.isLast ? 16.h : 12.h),
      child: GameCardWrapperWidget(
        game: widget.game,
        gamesData: widget.gamesData,
        gameIndex: widget.gameIndex,
        isChessBoardVisible: widget.isChessBoardVisible,
        onReturnFromChessboard: (_) {},
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
