import 'package:chessever2/screens/favorites/widgets/games_list_refetch_line.dart';
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
import 'package:chessever2/widgets/ink_fab.dart' show InkFabStack;
import 'package:chessever2/widgets/list_search_scroll_memory.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessever2/widgets/search_no_matches.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// Miniatures browsed as collapsible day sections, matching the Favorites and
/// Countrymen games tabs. Cards honour the app-wide games list view mode, so
/// switching to grid or board here switches it everywhere.
///
/// The list is all the tab draws: its search opens from the screen's
/// floating search button ([applyMiniaturesGamesSearch]), its filters and
/// layout from the screen's header ([openMiniaturesGamesFilters]).
///
/// A search is this same list, narrowed: while a new search's first page is
/// read the rows on screen stay, under a quiet line, and every day opens so
/// the hits show; the reader's own folds and place come back with the full
/// list.
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

  /// Days folded while a search's hits are listed. Every day opens with the
  /// hits, so none hides behind a fold made before searching; the folds in
  /// [_collapsedDates] come back with the full list.
  final Set<String> _searchCollapsedDates = {};
  bool _listedHits = false;

  /// The list as it last settled, shown while a new filter or search reads
  /// its first page: the provider starts each one empty.
  _ShownMiniatures? _settled;

  final ListSearchScrollMemory _place = ListSearchScrollMemory();

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
    _loadMoreNearEnd(_scrollController.position);
  }

  /// The next page, once the reader is near the end. Read on every scroll
  /// and on every change of the list's own measure: the header folding away
  /// grows the viewport (and shrinks what is left below) without a scroll.
  void _loadMoreNearEnd(ScrollMetrics metrics) {
    if (metrics.extentAfter > 200) return;
    final state = ref.read(miniaturesPaginatedProvider);
    if (!state.isLoading && state.hasMore) {
      ref.read(miniaturesPaginatedProvider.notifier).loadNextPage();
    }
  }

  Set<String> get _folds =>
      _listedHits ? _searchCollapsedDates : _collapsedDates;

  void _toggleDateSection(String dateKey) {
    HapticFeedbackService.light();
    setState(() {
      final folds = _folds;
      if (!folds.remove(dateKey)) folds.add(dateKey);
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

    // Each filter and each search is a new list, read from its first page.
    // Until that page lands the list on screen stays: only a first read,
    // with nothing on screen yet, draws the skeleton.
    final reading = state.isLoading && state.items.isEmpty;
    final current = _ShownMiniatures(
      state: state,
      games: games,
      filter: filter,
    );
    if (!reading) _settled = current;
    final shown = reading ? _settled : current;
    final held = reading && shown != null;

    // Every day opens while hits are listed, and the reader's folds come
    // back with the full list.
    final listedHits = (shown?.filter.search ?? '').isNotEmpty;
    if (listedHits != _listedHits) {
      _listedHits = listedHits;
      _searchCollapsedDates.clear();
    }
    _place.follow(_scrollController, shown?.filter.search);

    Widget content = RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        await ref.read(miniaturesPaginatedProvider.notifier).refresh();
      },
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0 &&
              notification.metrics.axis == Axis.vertical) {
            _loadMoreNearEnd(notification.metrics);
          }
          return false;
        },
        child: CustomScrollView(
          key: PageStorageKey<String>(
            'miniatures_games_list_${viewMode.index}',
          ),
          controller: _scrollController,
          scrollCacheExtent: kListScrollCacheExtent,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: 4.h)),
            SliverLayoutBuilder(
              builder: (context, constraints) => shown == null
                  ? SliverToBoxAdapter(child: _buildSkeletonList())
                  : _buildContentSliver(
                      shown,
                      viewMode,
                      constraints.crossAxisExtent,
                      held: held,
                    ),
            ),
            // Clear of the floating search button at the list's end (its
            // square, and the margin that lifts it over the home indicator);
            // the button's room gives way on the search's own timeline while
            // nothing floats there.
            SearchModeListEnd.sliver(
              base: 24.h + MediaQuery.viewPaddingOf(context).bottom,
              buttons: InkFabStack.extent(),
            ),
          ],
        ),
      ),
    );

    // The Games lists' quiet line, in their gutters, over the list's top.
    content = Stack(
      children: [
        content,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: GamesListRefetchLine(active: held),
        ),
      ],
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

  /// The rows for [shown]. [held] while it is the list a new read replaces
  /// once its first page lands: it pages no further meanwhile.
  Widget _buildContentSliver(
    _ShownMiniatures shown,
    GamesListViewMode viewMode,
    double availableWidth, {
    required bool held,
  }) {
    final state = shown.state;
    final games = shown.games;
    final filter = shown.filter;
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

    final words = filter.search?.trim() ?? '';
    if (games.isEmpty && (filter.hasActiveFilters || words.isNotEmpty)) {
      // Narrowed to nothing: the one no-hits state every Games list shows,
      // where the first row would have been. Its action clears what it
      // names (and plays the tap's haptic itself): the filters, keeping an
      // open search's words, or the words, which the open field follows.
      final filtered = filter.dialogActiveCount > 0;
      return SearchNoMatches.sliver(
        query: words,
        filtered: filtered,
        onClear: () {
          final notifier = ref.read(miniaturesFilterProvider.notifier);
          final now = notifier.state;
          notifier.state = filtered
              ? MiniatureGamesFilter.defaultFilter.copyWith(
                  window: now.window,
                  sort: now.sort,
                  order: now.order,
                  search: now.search,
                )
              : now.copyWith(clearSearch: true);
        },
      );
    }

    if (games.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _MiniaturesMessage(
          icon: Icons.bolt_outlined,
          title: 'No miniatures found',
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
    final folds = _folds;
    for (final entry in _groupGamesByDate(games).entries) {
      final dateKey = entry.key;
      final dateGames = entry.value;
      final isCollapsed = folds.contains(dateKey);

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

    if (held) {
      // The read in flight shows as the line over the list's top.
      listEntries.add(const _MiniatureFooterEntry(_MiniatureFooterType.spacer));
    } else if (state.isLoading) {
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
      // One slot whatever it holds (room, the spinner, the end), as tall as
      // the tallest of them: the list's end never moves as a page starts or
      // lands, so the bars and the reader's place hold still at the very
      // point the next page is asked for.
      final Widget? shown = switch (entry.type) {
        _MiniatureFooterType.loading => SizedBox(
          width: 24.w,
          height: 24.h,
          child: CircularProgressIndicator(
            color: context.colors.textPrimary,
            strokeWidth: 2,
          ),
        ),
        _MiniatureFooterType.spacer => null,
        _MiniatureFooterType.end => Text(
          'No more miniatures',
          style: AppTypography.textXsRegular.copyWith(
            color: const Color(0xFF52525B),
          ),
        ),
      };
      return ConstrainedBox(
        key: const ValueKey('miniatures_games_list_end'),
        // Grows past it only for text scaled beyond what it was sized for.
        constraints: BoxConstraints(minHeight: 72.h),
        child: Center(child: shown),
      );
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

/// Narrows the Games list to [query], trimmed; empty clears the search. The
/// filter is the list's own ([miniaturesFilterProvider]), so the list
/// narrows under the screen's search header as the reader types. An equal
/// filter (a trailing space) leaves the list, and its read, alone.
void applyMiniaturesGamesSearch(WidgetRef ref, String query) {
  final trimmed = query.trim();
  final current = ref.read(miniaturesFilterProvider);
  final next = current.copyWith(
    search: trimmed.isEmpty ? null : trimmed,
    clearSearch: trimmed.isEmpty,
  );
  if (next == current) return;
  ref.read(miniaturesFilterProvider.notifier).state = next;
}

/// The Games list's filters, from the screen's header or its search.
Future<void> openMiniaturesGamesFilters(
  BuildContext context,
  WidgetRef ref,
) async {
  HapticFeedbackService.buttonPress();
  final next = await showMiniaturesFilterDialog(
    context: context,
    currentFilter: ref.read(miniaturesFilterProvider),
  );
  if (next == null || !context.mounted) return;
  ref.read(miniaturesFilterProvider.notifier).state = next;
}

/// What the Games list draws: one read's rows, its state and the filter
/// it answers.
class _ShownMiniatures {
  const _ShownMiniatures({
    required this.state,
    required this.games,
    required this.filter,
  });

  final MiniaturesPaginationState state;
  final List<GamesTourModel> games;
  final MiniatureGamesFilter filter;
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
