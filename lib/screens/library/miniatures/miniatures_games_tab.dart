import 'dart:async';

import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/library/miniatures/miniature_game_launcher.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/miniatures_filter_dialog.dart';
import 'package:chessever2/screens/library/widgets/swipe_action_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/scroll_to_top_button.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// Miniatures browsed as collapsible day sections, matching the Favorites and
/// Countrymen games tabs. Cards honour the app-wide games list view mode, so
/// switching to grid or board here switches it everywhere.
class MiniaturesGamesTab extends ConsumerStatefulWidget {
  const MiniaturesGamesTab({super.key});

  @override
  ConsumerState<MiniaturesGamesTab> createState() => _MiniaturesGamesTabState();
}

class _MiniaturesGamesTabState extends ConsumerState<MiniaturesGamesTab>
    with AutomaticKeepAliveClientMixin, ScrollToTopListenerMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 350);
  static const String _unknownDateKey = '0000-00-00';

  /// Collapsed (not expanded) day keys. Empty means every section is open.
  final Set<String> _collapsedDates = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void onScrollToTopRequested() {
    animateScrollControllerToTop(_scrollController);
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

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
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final state = ref.read(miniaturesPaginatedProvider);
      if (!state.isLoading && state.hasMore) {
        ref.read(miniaturesPaginatedProvider.notifier).loadNextPage();
      }
    }
  }

  void _onSearchChanged(String query) {
    final trimmed = query.trim();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      if (!mounted) return;
      final current = ref.read(miniaturesFilterProvider);
      ref.read(miniaturesFilterProvider.notifier).state = current.copyWith(
        search: trimmed.isEmpty ? null : trimmed,
        clearSearch: trimmed.isEmpty,
      );
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  Future<void> _openFilters() async {
    HapticFeedbackService.buttonPress();
    if (!mounted) return;

    final newFilter = await showMiniaturesFilterDialog(
      context: context,
      currentFilter: ref.read(miniaturesFilterProvider),
    );
    if (newFilter != null && mounted) {
      ref.read(miniaturesFilterProvider.notifier).state = newFilter;
    }
  }

  void _toggleDateSection(String dateKey) {
    HapticFeedbackService.light();
    setState(() {
      if (!_collapsedDates.remove(dateKey)) _collapsedDates.add(dateKey);
    });
    _checkScrollAfterLayoutChange();
  }

  /// Collapsing a section can shrink the list below the viewport, which would
  /// otherwise strand pagination with no scroll event left to fire.
  void _checkScrollAfterLayoutChange() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.maxScrollExtent - position.pixels < 200) {
        final state = ref.read(miniaturesPaginatedProvider);
        if (!state.isLoading && state.hasMore) {
          ref.read(miniaturesPaginatedProvider.notifier).loadNextPage();
        }
      }
    });
  }

  /// Miniature dates come from PGN headers and are stored as bare calendar
  /// days at UTC midnight, so they must be read back in UTC. Converting to
  /// local would shift every game a day backwards west of Greenwich.
  Map<String, List<GamesTourModel>> _groupGamesByDate(
    List<GamesTourModel> games,
  ) {
    final grouped = <String, List<GamesTourModel>>{};
    for (final game in games) {
      final raw = game.lastMoveTime;
      final key =
          raw == null
              ? _unknownDateKey
              : DateFormat('yyyy-MM-dd').format(raw.toUtc());
      grouped.putIfAbsent(key, () => <GamesTourModel>[]).add(game);
    }

    final sortedKeys =
        grouped.keys.toList()..sort((a, b) {
          if (a == _unknownDateKey) return 1;
          if (b == _unknownDateKey) return -1;
          return b.compareTo(a);
        });

    return {for (final key in sortedKeys) key: grouped[key]!};
  }

  String _formatDateHeader(String dateKey) {
    if (dateKey == _unknownDateKey) return 'Unknown date';
    final date = DateTime.tryParse(dateKey);
    if (date == null) return dateKey;

    // The key is a wall-clock day, so it is compared against the viewer's own
    // calendar day rather than a UTC instant.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final deltaDays = today.difference(target).inDays;
    if (deltaDays == 0) return 'Today';
    if (deltaDays == 1) return 'Yesterday';
    return DateFormat('EEEE, MMM d, y').format(target);
  }

  /// Footer line for a miniature card. The list already carries the date in its
  /// section header, so the strip earns its space with what is specific to the
  /// game: where it was played, the opening code, and how short it was.
  /// [GamesTourModel.boardNr] holds the final move number for miniatures.
  String? _footerDetail(GamesTourModel game) {
    final parts = <String>[];

    final event = game.tourId.trim();
    if (event.isNotEmpty && event.toLowerCase() != 'miniatures') {
      parts.add(event);
    }

    final eco = game.eco?.trim() ?? '';
    if (eco.isNotEmpty) parts.add(eco);

    final moves = game.boardNr;
    if (moves != null && moves > 0) {
      parts.add('$moves ${moves == 1 ? 'move' : 'moves'}');
    }

    return parts.isEmpty ? null : parts.join('  ·  ');
  }

  Future<void> _openGame(List<GamesTourModel> games, int index) {
    return openMiniatureGame(
      context: context,
      ref: ref,
      games: games,
      index: index,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Deliberately no "is this tab selected" early return. Miniatures carry no
    // live streams to pause, and skipping the watches would let the
    // autoDispose list provider tear down on every tab switch, throwing away
    // every loaded page and the scroll position.
    final state = ref.watch(miniaturesPaginatedProvider);
    final games = ref.watch(miniatureGamesProvider);
    final filter = ref.watch(miniaturesFilterProvider);
    final viewMode = ref.watch(gamesListViewModeProvider);
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    Widget content = RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        await ref.read(miniaturesPaginatedProvider.notifier).refresh();
      },
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      child: CustomScrollView(
        key: PageStorageKey<String>('miniatures_games_list_${viewMode.index}'),
        controller: _scrollController,
        scrollCacheExtent: kListScrollCacheExtent,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                12.h,
                horizontalPadding,
                8.h,
              ),
              child: _buildSearchBar(filter),
            ),
          ),
          _buildContentSliver(state, games, filter, viewMode),
          SliverToBoxAdapter(child: SizedBox(height: 24.h)),
        ],
      ),
    );

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
        Positioned(
          bottom: 0,
          right: 0,
          child: ScrollToTopButton(scrollController: _scrollController),
        ),
      ],
    );
  }

  Widget _buildSearchBar(MiniatureGamesFilter filter) {
    final hasActiveFilters = filter.dialogActiveCount > 0;
    final activeFilterCount = filter.dialogActiveCount;
    final searchBarHeight = 48.h;

    Widget searchField = Container(
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: context.colors.surfaceRecessed),
      ),
      child: Row(
        children: [
          SizedBox(width: 12.w),
          Icon(Icons.search, size: 20.sp, color: context.colors.textSecondary),
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
                hintText: 'Search player, event or opening',
                hintStyle: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14.h),
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty) ...[
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
    );

    return SizedBox(
      height: searchBarHeight,
      child: Row(
        children: [
          Expanded(child: searchField),
          SizedBox(width: 8.w),
          _SquareIconButton(
            size: searchBarHeight,
            onTap: _openFilters,
            isActive: hasActiveFilters,
            badgeCount: activeFilterCount,
            child: Icon(
              Icons.tune_rounded,
              size: 20.sp,
              color:
                  hasActiveFilters
                      ? const Color(0xFFEF4444)
                      : context.colors.textSecondary,
            ),
          ),
          SizedBox(width: 8.w),
          _SquareIconButton(
            size: searchBarHeight,
            onTap: () {
              ref.read(gamesListViewModeSwitcher).toggleViewMode();
            },
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
        ],
      ),
    );
  }

  Widget _buildContentSliver(
    MiniaturesPaginationState state,
    List<GamesTourModel> games,
    MiniatureGamesFilter filter,
    GamesListViewMode viewMode,
  ) {
    if (state.isLoading && games.isEmpty) {
      return SliverToBoxAdapter(child: _buildSkeletonList());
    }

    if (state.error != null && games.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _MiniaturesMessage(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load miniatures',
          subtitle: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: () {
            ref.read(miniaturesPaginatedProvider.notifier).refresh();
          },
        ),
      );
    }

    if (games.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _MiniaturesMessage(
          icon: Icons.bolt_outlined,
          title: 'No miniatures found',
          subtitle:
              filter.hasActiveFilters
                  ? 'Try widening your filters or clearing the search.'
                  : null,
          actionLabel: filter.hasActiveFilters ? 'Clear filters' : null,
          onAction:
              filter.hasActiveFilters
                  ? () {
                    _searchController.clear();
                    ref.read(miniaturesFilterProvider.notifier).state =
                        MiniatureGamesFilter.defaultFilter;
                  }
                  : null,
        ),
      );
    }

    final gameIdToIndex = <String, int>{
      for (var i = 0; i < games.length; i++) games[i].gameId: i,
    };

    final isGrid = viewMode == GamesListViewMode.chessBoardGrid;
    final isChessBoardVisible = viewMode == GamesListViewMode.chessBoard;

    // Pinning is meaningless outside a tour scope; the wrappers still require
    // the plumbing, so it is stubbed out.
    final gamesData = GamesScreenModel(
      gamesTourModels: games,
      pinnedGamedIs: const [],
    );

    // Cheap row descriptors only. Cards are built lazily for visible rows.
    final listEntries = <_MiniatureListEntry>[];
    for (final entry in _groupGamesByDate(games).entries) {
      final dateKey = entry.key;
      final dateGames = entry.value;
      final isCollapsed = _collapsedDates.contains(dateKey);

      listEntries.add(
        _MiniatureDateHeaderEntry(
          dateKey: dateKey,
          gameCount: dateGames.length,
          isExpanded: !isCollapsed,
        ),
      );
      if (isCollapsed) continue;

      if (isGrid) {
        final gridColumns =
            ResponsiveHelper.isTablet && ResponsiveHelper.isLandscape ? 4 : 2;
        for (var i = 0; i < dateGames.length; i += gridColumns) {
          listEntries.add(
            _MiniatureGridRowEntry(
              games: dateGames.sublist(
                i,
                (i + gridColumns).clamp(0, dateGames.length),
              ),
              gridColumns: gridColumns,
              isLast: i + gridColumns >= dateGames.length,
            ),
          );
        }
      } else {
        for (var i = 0; i < dateGames.length; i++) {
          final game = dateGames[i];
          listEntries.add(
            _MiniatureGameEntry(
              game: game,
              gameIndex: gameIdToIndex[game.gameId] ?? 0,
              isBoard: isChessBoardVisible,
              isLast: i == dateGames.length - 1,
            ),
          );
        }
      }
    }

    if (state.isLoading) {
      listEntries.add(
        const _MiniatureFooterEntry(_MiniatureFooterType.loading),
      );
    } else if (state.hasMore) {
      listEntries.add(const _MiniatureFooterEntry(_MiniatureFooterType.spacer));
    } else {
      listEntries.add(const _MiniatureFooterEntry(_MiniatureFooterType.end));
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
          ),
          childCount: listEntries.length,
          addAutomaticKeepAlives: false,
        ),
      ),
    );
  }

  Widget _buildListEntry(
    _MiniatureListEntry entry, {
    required List<GamesTourModel> games,
    required GamesScreenModel gamesData,
    required Map<String, int> gameIdToIndex,
    required GamesListViewMode viewMode,
  }) {
    if (entry is _MiniatureDateHeaderEntry) {
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

    if (entry is _MiniatureGridRowEntry) {
      return Padding(
        padding: EdgeInsets.only(bottom: entry.isLast ? 16.h : 12.h),
        child: Row(
          children: [
            for (var j = 0; j < entry.gridColumns; j++) ...[
              if (j > 0) SizedBox(width: 12.sp),
              Expanded(
                child:
                    j < entry.games.length
                        ? _buildGridGame(
                          entry.games[j],
                          gameIdToIndex[entry.games[j].gameId] ?? 0,
                          games,
                        )
                        : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }

    if (entry is _MiniatureGameEntry) {
      // Same card as the tournament Games tab. GameCardWrapperWidget renders
      // the canonical GameCard, whose header and footer are fixed-height, so a
      // row can never re-measure when async data (eval, flags, result) lands
      // and the list never reflows under the user.
      //
      // Miniatures need their PGN fetched before the board can replay them, so
      // the wrapper's own navigation is declined and the launcher takes over.
      Widget card = GameCardWrapperWidget(
        key: ValueKey(
          'mini_${entry.isBoard ? 'board' : 'card'}_${entry.game.gameId}',
        ),
        game: entry.game,
        gamesData: gamesData,
        gameIndex: entry.gameIndex,
        isChessBoardVisible: entry.isBoard,
        streamEnabled: false,
        footerDetail: _footerDetail(entry.game),
        // Pinning is meaningless outside a tour scope, so the long-press menu
        // drops the item rather than offering a tap that does nothing.
        showPin: false,
        onPinToggle: (_) async {},
        onBeforeOpen: () async {
          await _openGame(games, entry.gameIndex);
          return false;
        },
      );

      // Swipe-to-add stays on the card rows only; board rows are already a
      // full-width interactive board with no room for a drag affordance.
      if (!entry.isBoard) {
        card = SwipeActionCard(
          dismissKey: ValueKey('mini_add_${entry.game.gameId}'),
          icon: Icons.add_rounded,
          label: 'Add',
          backgroundColor: kGreenColor,
          onAction: () async {
            if (!mounted) return;
            HapticFeedbackService.medium();
            showAddToFolderSheet(context: context, game: entry.game);
          },
          child: card,
        );
      }

      return Padding(
        padding: EdgeInsets.only(bottom: entry.isLast ? 16.h : 12.h),
        child: card,
      );
    }

    if (entry is _MiniatureFooterEntry) {
      switch (entry.type) {
        case _MiniatureFooterType.loading:
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
        case _MiniatureFooterType.spacer:
          return SizedBox(height: 60.h);
        case _MiniatureFooterType.end:
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 16.h),
            child: Center(
              child: Text(
                'No more miniatures',
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
  ) {
    return GridGameCardWrapperWidget(
      key: ValueKey('mini_grid_${game.gameId}'),
      game: game,
      orderedGames: allGames,
      gameIndex: gameIndex,
      streamEnabled: false,
      pinnedIds: const [],
      onPinToggle: (_) {},
      onChangedWithLiveGames: (_) => _openGame(allGames, gameIndex),
    );
  }

  Widget _buildSkeletonList() {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        8.h,
        horizontalPadding,
        24.h,
      ),
      child: Column(
        children: List.generate(
          6,
          (index) => Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: SkeletonWidget(
              child: Container(
                // Matches GameCard exactly (60.h header + 24.h footer) so the
                // swap from skeleton to real rows does not jump.
                height: 84.h,
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(12.br),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Row descriptors ----

sealed class _MiniatureListEntry {
  const _MiniatureListEntry();
}

class _MiniatureDateHeaderEntry extends _MiniatureListEntry {
  const _MiniatureDateHeaderEntry({
    required this.dateKey,
    required this.gameCount,
    required this.isExpanded,
  });

  final String dateKey;
  final int gameCount;
  final bool isExpanded;
}

class _MiniatureGridRowEntry extends _MiniatureListEntry {
  const _MiniatureGridRowEntry({
    required this.games,
    required this.gridColumns,
    required this.isLast,
  });

  final List<GamesTourModel> games;
  final int gridColumns;
  final bool isLast;
}

class _MiniatureGameEntry extends _MiniatureListEntry {
  const _MiniatureGameEntry({
    required this.game,
    required this.gameIndex,
    required this.isBoard,
    required this.isLast,
  });

  final GamesTourModel game;
  final int gameIndex;
  final bool isBoard;
  final bool isLast;
}

enum _MiniatureFooterType { loading, spacer, end }

class _MiniatureFooterEntry extends _MiniatureListEntry {
  const _MiniatureFooterEntry(this.type);

  final _MiniatureFooterType type;
}

// ---- Widgets ----

class _DateHeader extends StatelessWidget {
  const _DateHeader({
    required this.dateLabel,
    required this.gameCount,
    required this.isExpanded,
    this.onToggle,
  });

  final String dateLabel;
  final int gameCount;
  final bool isExpanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(12.br),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color: context.colors.textPrimary.withValues(alpha: 0.1),
          ),
          // Matches the day headers in Favorites and Countrymen exactly.
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
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
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              isExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 20.sp,
              color: context.colors.textPrimary.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({
    required this.size,
    required this.onTap,
    required this.child,
    this.isActive = false,
    this.badgeCount = 0,
  });

  final double size;
  final VoidCallback onTap;
  final Widget child;
  final bool isActive;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFFEF4444);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color:
              isActive
                  ? activeColor.withValues(alpha: 0.15)
                  : context.colors.background,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color:
                isActive
                    ? activeColor.withValues(alpha: 0.5)
                    : context.colors.surfaceRecessed,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            child,
            if (isActive && badgeCount > 0)
              Positioned(
                right: 6.w,
                top: 6.h,
                child: Container(
                  width: 14.w,
                  height: 14.h,
                  decoration: const BoxDecoration(
                    color: activeColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$badgeCount',
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
    );
  }
}

class _MiniaturesMessage extends StatelessWidget {
  const _MiniaturesMessage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 48.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40.sp, color: context.colors.textSecondary),
            SizedBox(height: 16.h),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            if (subtitle != null) ...[
              SizedBox(height: 8.h),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: 20.h),
              GestureDetector(
                onTap: onAction,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 20.w,
                    vertical: 10.h,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceRecessed,
                    borderRadius: BorderRadius.circular(10.br),
                  ),
                  child: Text(
                    actionLabel!,
                    style: AppTypography.textXsMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
