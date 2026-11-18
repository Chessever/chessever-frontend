import 'dart:async';

import 'package:chessever2/screens/library/miniatures/miniatures_share.dart';

import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/library/miniatures/miniature_game_launcher.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_day_list_utils.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
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
import 'package:chessever2/screens/tour_detail/widgets/event_search_bar.dart'
    show EventSearchBarFrame;
import 'package:chessever2/widgets/ink_fab.dart' show InkFabSize;
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// Miniatures browsed as collapsible day sections, matching the Favorites and
/// Countrymen games tabs. Cards honour the app-wide games list view mode, so
/// switching to grid or board here switches it everywhere.
///
/// The list is all the tab draws: its search and filters open from the
/// screen's floating search button ([MiniaturesGamesSearchField]), and the
/// layout toggle sits in the screen's header.
///
/// Everyone browses the same list: every day, every filter. Only opening a
/// game, including Today, goes through the Premium guard (see
/// miniature_game_launcher.dart).
class MiniaturesGamesTab extends ConsumerStatefulWidget {
  const MiniaturesGamesTab({super.key, this.now});

  /// Pins "today" in tests.
  final DateTime? now;

  @override
  ConsumerState<MiniaturesGamesTab> createState() => _MiniaturesGamesTabState();
}

class _MiniaturesGamesTabState extends ConsumerState<MiniaturesGamesTab>
    with AutomaticKeepAliveClientMixin, ScrollToTopListenerMixin {
  final ScrollController _scrollController = ScrollController();

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
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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

  void _toggleDateSection(String dateKey) {
    HapticFeedbackService.light();
    setState(() {
      if (!_collapsedDates.remove(dateKey)) _collapsedDates.add(dateKey);
    });
    // Same as Countrymen / Favorites Games: collapsing can leave content
    // shorter than the viewport with hasMore still true — keep paging.
    _checkScrollAfterLayoutChange();
  }

  /// Collapsing a section can shrink the list below the viewport, which would
  /// otherwise strand pagination with no scroll event left to fire.
  /// Chains another page load when the list is still short after a fetch.
  void _checkScrollAfterLayoutChange() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_scrollController.hasClients) return;

      final position = _scrollController.position;
      final needsMore = miniaturesListNeedsMoreAfterLayout(
        maxScrollExtent: position.maxScrollExtent,
        pixels: position.pixels,
        viewportDimension: position.viewportDimension,
      );
      if (!needsMore) return;

      final state = ref.read(miniaturesPaginatedProvider);
      if (!state.hasMore || state.isLoading) return;

      final beforeCount = state.items.length;
      await ref.read(miniaturesPaginatedProvider.notifier).loadNextPage();
      if (!mounted) return;

      final afterCount = ref.read(miniaturesPaginatedProvider).items.length;
      // Only recurse when the page actually grew — avoids a tight loop if the
      // backend returns empty while hasMore is still true.
      if (afterCount > beforeCount) {
        _checkScrollAfterLayoutChange();
      }
    });
  }

  /// Day key of a miniature's section ('yyyy-MM-dd', or the unknown key).
  String _dateKeyOf(GamesTourModel game) {
    final raw = game.lastMoveTime;
    return raw == null
        ? _unknownDateKey
        : DateFormat('yyyy-MM-dd').format(raw.toUtc());
  }

  /// Miniature dates come from PGN headers and are stored as bare calendar
  /// days at UTC midnight, so they must be read back in UTC. Converting to
  /// local would shift every game a day backwards west of Greenwich.
  Map<String, List<GamesTourModel>> _groupGamesByDate(
    List<GamesTourModel> games,
  ) {
    final grouped = <String, List<GamesTourModel>>{};
    for (final game in games) {
      grouped.putIfAbsent(_dateKeyOf(game), () => <GamesTourModel>[]).add(game);
    }

    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
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
    final now = widget.now ?? DateTime.now();
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
  ///
  /// [hydratedEvent] is the tournament read off the full game, for a row whose
  /// index entry names none (see [miniatureRowNamesEvent]).
  String? _footerDetail(GamesTourModel game, {String? hydratedEvent}) {
    final parts = <String>[];

    final event = miniatureRowNamesEvent(game)
        ? game.tourId.trim()
        : (hydratedEvent ?? '');
    if (event.isNotEmpty) parts.add(event);

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
          SliverToBoxAdapter(child: SizedBox(height: 4.h)),
          SliverLayoutBuilder(
            builder: (context, constraints) => _buildContentSliver(
              state,
              games,
              filter,
              viewMode,
              constraints.crossAxisExtent,
            ),
          ),
          // Clear of the floating search button at the list's end.
          SliverToBoxAdapter(
            child: SizedBox(height: 24.h + InkFabSize.regular.side),
          ),
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

    return content;
  }

  Widget _buildContentSliver(
    MiniaturesPaginationState state,
    List<GamesTourModel> games,
    MiniatureGamesFilter filter,
    GamesListViewMode viewMode,
    double availableWidth,
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
          subtitle: filter.hasActiveFilters
              ? 'Try widening your filters or clearing the search.'
              : null,
          actionLabel: filter.hasActiveFilters ? 'Clear filters' : null,
          onAction: filter.hasActiveFilters
              // The search field, when open, follows (see
              // MiniaturesGamesSearchField).
              ? () => ref.read(miniaturesFilterProvider.notifier).state =
                    MiniatureGamesFilter.defaultFilter
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
        _MiniatureDateHeaderEntry(dateKey: dateKey, isExpanded: !isCollapsed),
      );
      if (isCollapsed) continue;

      if (isGrid) {
        final gridColumns = ResponsiveHelper.columnsForWidth(
          availableWidth -
              2 * ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w),
          minItemWidth: 220,
          spacing: 16.sp,
          minColumns: 2,
          maxColumns: 4,
        );
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
        child: MiniaturesDateShareHeader(
          date: entry.dateKey == _unknownDateKey ? null : entry.dateKey,
          dateLabel: miniatureDateHeaderLabel(_formatDateHeader(entry.dateKey)),
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
                child: j < entry.games.length
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
      // Same wrappers as tournament Games tab / For You:
      // - list: GameCard (fixed 60.h + 24.h; result chip for finished games)
      // - board: ChessBoardFromFENNew via isChessBoardVisible
      //
      // For You / tournament cards already have fen+lastMove from the API, so
      // the side eval bar is present on first paint. Miniatures are header-only
      // until per-card gamebase hydration; the shared board path still mounts
      // the eval bar for finished games immediately (geometry reserved; text
      // fills later) so board width never jumps the way it did when the bar
      // was gated on hasStarted/lastMove.
      //
      // List-level skeleton above is only for an empty loading list (same as
      // For You) — not a per-card shimmer while waiting for eval/hydration.
      //
      // Miniatures need their PGN fetched before the board can replay them, so
      // the wrapper's own navigation is declined and the launcher takes over.
      //
      // The footer's event is the one line that can arrive late: a broadcast
      // game's index row names only its pairing, so the tournament comes off
      // the full game the card is already fetching. The strip is one fixed
      // line, so filling it in moves nothing.
      Widget card = Consumer(
        builder: (context, ref, _) {
          final hydratedEvent = miniatureRowNamesEvent(entry.game)
              ? null
              : ref.watch(gamebaseGameEventTitleProvider(entry.game.gameId));
          return GameCardWrapperWidget(
            key: ValueKey(
              'mini_${entry.isBoard ? 'board' : 'card'}_${entry.game.gameId}',
            ),
            game: entry.game,
            gamesData: gamesData,
            gameIndex: entry.gameIndex,
            isChessBoardVisible: entry.isBoard,
            streamEnabled: false,
            playerProfileDataSource: PlayerProfileDataSource.twic,
            footerDetail: _footerDetail(
              entry.game,
              hydratedEvent: hydratedEvent,
            ),
            // Pinning is meaningless outside a tour scope, so the long-press
            // menu drops the item rather than offering a tap that does nothing.
            showPin: false,
            onPinToggle: (_) async {},
            onBeforeOpen: () async {
              await _openGame(games, entry.gameIndex);
              return false;
            },
          );
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
    // Same GridChessBoardFromFENNew path as For You / tournament grid. Eval
    // bar geometry is reserved on first paint for finished archive games even
    // before fen/lastMove hydration (see _shouldShowEvalBarForGame).
    return GridGameCardWrapperWidget(
      key: ValueKey('mini_grid_${game.gameId}'),
      game: game,
      orderedGames: allGames,
      gameIndex: gameIndex,
      streamEnabled: false,
      playerProfileDataSource: PlayerProfileDataSource.twic,
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

/// The Games list's search, typed in the Miniatures screen's search header:
/// players, events and openings, with the filters behind its glyph. The
/// filter it writes is the list's own ([miniaturesFilterProvider]), so the
/// list narrows under it as the reader types.
class MiniaturesGamesSearchField extends ConsumerStatefulWidget {
  const MiniaturesGamesSearchField({super.key, required this.focusNode});

  final FocusNode focusNode;

  @override
  ConsumerState<MiniaturesGamesSearchField> createState() =>
      _MiniaturesGamesSearchFieldState();
}

class _MiniaturesGamesSearchFieldState
    extends ConsumerState<MiniaturesGamesSearchField> {
  // Opens on what the list is narrowed to, so reopening the search shows it.
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(miniaturesFilterProvider).search ?? '',
  );
  Timer? _debounce;
  static const Duration _debounceDuration = Duration(milliseconds: 350);

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _apply(String query) {
    final trimmed = query.trim();
    final current = ref.read(miniaturesFilterProvider);
    final next = current.copyWith(
      search: trimmed.isEmpty ? null : trimmed,
      clearSearch: trimmed.isEmpty,
    );
    // An equal filter (e.g. a trailing space) must not rebuild the list.
    if (next == current) return;
    ref.read(miniaturesFilterProvider.notifier).state = next;
  }

  void _changed(String query) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      if (mounted) _apply(query);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    widget.focusNode.unfocus();
    _apply('');
  }

  Future<void> _openFilters() async {
    HapticFeedbackService.buttonPress();
    widget.focusNode.unfocus();
    final next = await showMiniaturesFilterDialog(
      context: context,
      currentFilter: ref.read(miniaturesFilterProvider),
    );
    if (next == null || !mounted) return;
    ref.read(miniaturesFilterProvider.notifier).state = next;
  }

  @override
  Widget build(BuildContext context) {
    // The list's own "Clear filters" empties the search too.
    ref.listen<String?>(miniaturesFilterProvider.select((f) => f.search), (
      _,
      next,
    ) {
      if ((next ?? '') != _controller.text.trim()) {
        _controller.text = next ?? '';
      }
    });
    final applied = ref.watch(
      miniaturesFilterProvider.select((f) => f.dialogActiveCount),
    );
    return EventSearchBarFrame(
      compact: true,
      child: SimpleSearchBar(
        controller: _controller,
        focusNode: widget.focusNode,
        // Built only as the search opens: the cursor goes straight in.
        autofocus: true,
        hintText: 'Search player, event or opening',
        textFieldKey: const ValueKey('miniatures_games_search'),
        filterButtonKey: const ValueKey('miniatures_games_filters'),
        compactFilter: true,
        filterBadgeCount: applied,
        onChanged: _changed,
        onOpenFilter: _openFilters,
        onCloseTap: _clear,
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
    required this.isExpanded,
  });

  final String dateKey;
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
