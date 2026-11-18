import 'dart:math' as math;
import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/bulk_add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/live_gamebase_search_game_card.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/utils/twic_event_identity.dart';
import 'package:chessever2/screens/player_profile/widgets/player_games_event_section.dart';
import 'package:chessever2/screens/player_profile/widgets/player_games_selection.dart';
import 'package:chessever2/screens/player_profile/widgets/player_games_toolbar.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart'
    show PlayerProfileTab, selectedPlayerProfileTabProvider;
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/board_game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_search_bar.dart'
    show EventSearchBarFrame;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/widgets/paywall/past_game_access.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/utils/foreground_task_scheduler.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Games tab showing all games of a player with comprehensive filters
class PlayerGamesTab extends ConsumerStatefulWidget {
  const PlayerGamesTab({
    super.key,
    this.fideId,
    required this.playerName,
    this.dataSource = PlayerProfileDataSource.supabase,
    this.gamebasePlayerId,
    this.memorialSourceIdentity,
  });

  final int? fideId;
  final String playerName;
  final PlayerProfileDataSource dataSource;
  final String? gamebasePlayerId;
  final String? memorialSourceIdentity;

  @override
  ConsumerState<PlayerGamesTab> createState() => _PlayerGamesTabState();
}

class _PlayerGamesTabState extends ConsumerState<PlayerGamesTab>
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

  Timer? _scrollIdleTimer;
  bool _routeSubscribed = false;
  bool _appIsResumed = true;
  bool _isLoadingAllPagesForSelection = false;
  bool _liveCardsPausedForScroll = false;
  late final StateController<Set<String>> _liveGameCardsPauseReasons;
  final Set<String> _selectedGameIds = <String>{};
  final Set<String> _collapsedEventKeys = <String>{};
  static const Duration _scrollIdleDelay = Duration(milliseconds: 180);

  String get _liveCardsPauseReason => 'player_games_scroll_$hashCode';

  void _toggleEventCollapsed(String eventKey) {
    HapticFeedback.lightImpact();
    setState(() {
      if (!_collapsedEventKeys.add(eventKey)) {
        _collapsedEventKeys.remove(eventKey);
      }
    });
  }

  String get _scrollStorageKey =>
      'player_games:${widget.dataSource.name}:${widget.fideId ?? ''}:'
      '${widget.gamebasePlayerId ?? ''}:'
      '${widget.memorialSourceIdentity ?? ''}:${widget.playerName}';

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

  /// Get the player profile key for provider lookups
  PlayerProfileKey get _playerKey => PlayerProfileKey(
    fideId: widget.fideId,
    playerName: widget.playerName,
    source: widget.dataSource,
    gamebasePlayerId: widget.gamebasePlayerId,
    memorialSourceIdentity: widget.memorialSourceIdentity,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    routeObserver.subscribe(this, route);
    _routeSubscribed = true;
  }

  @override
  void dispose() {
    if (_routeSubscribed) {
      routeObserver.unsubscribe(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    ForegroundTaskScheduler.cancel('player_games_resume_$hashCode');
    _scrollIdleTimer?.cancel();
    _setLiveCardsPausedForScroll(false);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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
      ForegroundTaskScheduler.cancel('player_games_resume_$hashCode');
      _setAppResumed(false);
      return;
    }
    if (!mounted) return;

    _setAppResumed(true);
    ForegroundTaskScheduler.schedule(
      key: 'player_games_resume_$hashCode',
      task: () {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route?.isCurrent != true) return;
        if (ref.read(selectedPlayerProfileTabProvider) !=
            PlayerProfileTab.games) {
          return;
        }

        ref.invalidate(gameUpdatesStreamProvider);
        ref.invalidate(liveGameUpdateStreamProvider);
        ref.invalidate(gameUpdatesBatchStreamProvider);
        unawaited(
          ref
              .read(playerProfileGamesKeyProvider(_playerKey).notifier)
              .refresh(),
        );
      },
    );
  }

  void _setRouteActive(bool isActive) {
    if (!mounted) return;
    if (!isActive) {
      ForegroundTaskScheduler.cancel('player_games_resume_$hashCode');
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
    if (widget.dataSource != PlayerProfileDataSource.twic) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 560) return;
    ref.read(playerProfileGamesKeyProvider(_playerKey).notifier).loadMore();
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

  int _resolveBulkMaxPages(PlayerProfileGamesState state) {
    const defaultMaxPages = 250;
    const fallbackPageSize = 50;
    final totalCount = state.totalCount;
    if (totalCount == null || totalCount <= 0) return defaultMaxPages;
    final remaining = totalCount - state.allGames.length;
    if (remaining <= 0) return defaultMaxPages;
    final estimatedPages = (remaining / fallbackPageSize).ceil();
    final safeWithBuffer = estimatedPages + 10;
    return safeWithBuffer.clamp(defaultMaxPages, 5000);
  }

  void _toggleGameSelection(String gameId) {
    if (!ref.read(playerGamesSelectionModeProvider(_playerKey))) return;
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedGameIds.contains(gameId)) {
        _selectedGameIds.remove(gameId);
      } else {
        _selectedGameIds.add(gameId);
      }
    });
  }

  Future<void> _selectAllFilteredGames(PlayerProfileGamesState state) async {
    if (_isLoadingAllPagesForSelection) return;
    final totalCount = state.totalCount ?? state.filteredGames.length;
    if (totalCount > 1) {
      final hasPremium = await requirePremiumGuard(context, ref);
      if (!hasPremium || !mounted) return;
    }

    setState(() => _isLoadingAllPagesForSelection = true);
    try {
      if (widget.dataSource == PlayerProfileDataSource.twic &&
          state.hasMorePages) {
        await ref
            .read(playerProfileGamesKeyProvider(_playerKey).notifier)
            .loadAllRemainingPages(maxPages: _resolveBulkMaxPages(state));
      }

      final refreshed = ref.read(playerProfileGamesKeyProvider(_playerKey));
      final allFilteredIds = refreshed.filteredGames
          .map((g) => g.gameId)
          .toSet();

      if (!mounted) return;
      setState(() {
        _selectedGameIds
          ..clear()
          ..addAll(allFilteredIds);
      });
      showAppSnack(context, 'Selected ${allFilteredIds.length} filtered games');
    } catch (e, st) {
      talker.handle(e, st);
      if (!mounted) return;
      showAppSnack(
        context,
        userFacingError(
          e,
          fallback: 'Could not select all games. Please try again.',
        ),
        tone: AppSnackTone.danger,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingAllPagesForSelection = false);
      }
    }
  }

  String _selectAllLabel(PlayerProfileGamesState state) {
    final total = state.totalCount;
    if (state.hasActiveFilters) {
      return 'Select filtered';
    }
    if (total != null && total > 0) {
      return 'Select all (${formatCompactCount(total)})';
    }
    return 'Select all';
  }

  Future<void> _addSelectedToLibrary(PlayerProfileGamesState state) async {
    final selectedGames = state.filteredGames
        .where((g) => _selectedGameIds.contains(g.gameId))
        .toList(growable: false);

    if (selectedGames.isEmpty) {
      showAppSnack(context, 'Select at least one game');
      return;
    }

    if (selectedGames.length > 1) {
      final hasPremium = await requirePremiumGuard(context, ref);
      if (!hasPremium || !mounted) return;
    }

    await showBulkAddToFolderSheet(
      context: context,
      games: selectedGames,
      sourceLabel: widget.playerName,
    );
  }

  /// Group games by event (tourId).
  /// Input games are already sorted by date descending, so insertion order
  /// in the LinkedHashMap gives events ordered by most-recent game first.
  Map<String, List<GamesTourModel>> _groupGamesByEvent(
    List<GamesTourModel> games,
  ) {
    final grouped = <String, List<GamesTourModel>>{};
    for (final game in games) {
      final eventKey = widget.dataSource == PlayerProfileDataSource.twic
          ? twicCanonicalEventTitleForGame(game)
          : game.tourId;
      grouped.putIfAbsent(eventKey, () => []).add(game);
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

  @override
  Widget build(BuildContext context) {
    super.build(context);

    ref.listen<PlayerProfileTab>(selectedPlayerProfileTabProvider, (_, next) {
      if (next != PlayerProfileTab.games) {
        _stopLiveCardsForHiddenTab();
      }
    });

    final selectedTab = ref.watch(selectedPlayerProfileTabProvider);
    if (selectedTab != PlayerProfileTab.games) {
      return const SizedBox.shrink();
    }

    final isSelectionMode = ref.watch(
      playerGamesSelectionModeProvider(_playerKey),
    );

    // Listen for selection mode cancellation to clear local selections
    ref.listen(playerGamesSelectionModeProvider(_playerKey), (previous, next) {
      if (previous == true && next == false) {
        if (mounted) {
          setState(() {
            _selectedGameIds.clear();
            _isLoadingAllPagesForSelection = false;
          });
        }
      }
    });

    ref.listen(playerProfileGamesKeyProvider(_playerKey), (previous, next) {
      if (!isSelectionMode || !mounted || _selectedGameIds.isEmpty) return;
      final visibleIds = next.filteredGames.map((game) => game.gameId).toSet();
      final retained = _selectedGameIds.where(visibleIds.contains).toSet();
      if (retained.length == _selectedGameIds.length) return;
      setState(() {
        _selectedGameIds
          ..clear()
          ..addAll(retained);
      });
    });

    final state = ref.watch(playerProfileGamesKeyProvider(_playerKey));
    final viewMode = ref.watch(gamesListViewModeProvider);
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );
    // The search row left the list for the profile's own search page
    // (Trello #1420). What stays floats over the list only while it has
    // something to say: the picking panel, and what narrows the list.
    final hasStickyHeader = isSelectionMode || state.hasActiveFilters;
    final headerHeight =
        8.h +
        (state.hasActiveFilters
            ? PlayerGamesActiveFiltersChip.heightOf(context)
            : 0) +
        (isSelectionMode ? PlayerGamesSelectionToolbar.heightOf(context) : 0);

    final eventsAsync = ref.watch(playerEventsKeyProvider(_playerKey));

    Widget content = RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        await ref
            .read(playerProfileGamesKeyProvider(_playerKey).notifier)
            .refresh();
      },
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      child: CustomScrollView(
        key: PageStorageKey<String>(_scrollStorageKey),
        controller: _scrollController,
        scrollCacheExtent: kListScrollCacheExtent,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          if (hasStickyHeader)
            SliverAppBar(
              primary: false,
              floating: true,
              snap: true,
              pinned: false,
              elevation: 0,
              backgroundColor: Colors.transparent,
              automaticallyImplyLeading: false,
              toolbarHeight: headerHeight,
              flexibleSpace: FlexibleSpaceBar(
                background: Align(
                  alignment: Alignment.bottomCenter,
                  child: _buildStickyHeader(
                    state,
                    horizontalPadding,
                    isSelectionMode,
                  ),
                ),
              ),
            ),

          // Content
          SliverLayoutBuilder(
            builder: (context, constraints) => _buildContentSliver(
              state,
              viewMode,
              eventsAsync,
              isSelectionMode,
              constraints.crossAxisExtent,
            ),
          ),

          // Bottom padding
          SliverToBoxAdapter(child: SizedBox(height: 24.h)),
        ],
      ),
    );

    // Cap the width on tablets (contentMaxWidth is unbounded on phones). The
    // wrapper is always present so folding or unfolding an iPhone Duo between
    // phone and tablet widths keeps the same tree, and the list keeps its
    // scroll position instead of remounting at the top.
    // The corner the scroll-to-top arrow held is the profile's floating
    // search now; a reselected Games tab still scrolls the list to the top.
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ResponsiveHelper.contentMaxWidth),
        child: SizedBox.expand(child: content),
      ),
    );
  }

  Widget _buildStickyHeader(
    PlayerProfileGamesState state,
    double horizontalPadding,
    bool isSelectionMode,
  ) {
    final selectedVisibleCount = state.filteredGames
        .where((g) => _selectedGameIds.contains(g.gameId))
        .length;

    return Container(
      color: context.colors.background,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (isSelectionMode)
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                0,
                horizontalPadding,
                state.hasActiveFilters ? 4.h : 6.h,
              ),
              child: _buildSelectionToolbar(state, selectedVisibleCount),
            ),
          if (state.hasActiveFilters)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: _buildActiveFiltersChip(state),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionToolbar(
    PlayerProfileGamesState state,
    int selectedVisibleCount,
  ) {
    return PlayerGamesSelectionToolbar(
      selectedCount: selectedVisibleCount,
      subtitle: _isLoadingAllPagesForSelection
          ? (state.totalCount != null &&
                    state.totalCount! > state.allGames.length
                ? 'Loading ${formatCompactCount(state.allGames.length)} of ${formatCompactCount(state.totalCount!)} games...'
                : 'Preparing your filtered game list...')
          : state.hasActiveFilters
          ? 'Selection follows current filters and search'
          : 'Tap games manually or use quick select',
      selectAllLabel: _isLoadingAllPagesForSelection
          ? (state.totalCount != null &&
                    state.totalCount! > state.allGames.length
                ? 'Loading ${formatCompactCount(state.allGames.length)}/${formatCompactCount(state.totalCount!)}...'
                : 'Selecting...')
          : _selectAllLabel(state),
      onSelectAll: _isLoadingAllPagesForSelection
          ? null
          : () => _selectAllFilteredGames(state),
      onAddSelected: () => _addSelectedToLibrary(state),
      onClose: () {
        HapticFeedback.lightImpact();
        ref.read(playerGamesSelectionModeProvider(_playerKey).notifier).state =
            false;
      },
    );
  }

  Widget _buildActiveFiltersChip(PlayerProfileGamesState state) {
    return PlayerGamesActiveFiltersChip(
      activeFilterCount: state.activeFilterCount,
      gameCount: state.filteredGames.length,
      resultLabel: state.playerResultFilter != PlayerResultFilter.all
          ? state.playerResultFilter.label
          : null,
      onClear: () {
        HapticFeedback.lightImpact();
        ref
            .read(playerProfileGamesKeyProvider(_playerKey).notifier)
            .clearFilter();
      },
    );
  }

  Widget _buildContentSliver(
    PlayerProfileGamesState state,
    GamesListViewMode viewMode,
    AsyncValue<List<PlayerEventData>> eventsAsync,
    bool isSelectionMode,
    double availableWidth,
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
        child: _buildErrorState(userFacingError(state.error)),
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
    final eventDataList = eventsAsync.valueOrNull ?? [];
    final eventDataMap = {for (final e in eventDataList) e.tourId: e};

    // Build cheap row descriptors only. The actual card widgets are created
    // lazily by SliverChildBuilderDelegate for visible rows.
    final listEntries = <_PlayerGamesListEntry>[];
    bool isFirstGameCard = true;
    bool isFirstEvent = true;

    for (final entry in gamesByEvent.entries) {
      final tourId = entry.key;
      final eventGames = entry.value;
      final eventData = eventDataMap[tourId];
      final playerScore = _computePlayerScore(eventGames);

      // Event header (card + stats row)
      listEntries.add(
        _PlayerEventHeaderEntry(
          eventData: eventData,
          tourId: tourId,
          tourSlug: widget.dataSource == PlayerProfileDataSource.twic
              ? tourId
              : eventGames.first.tourSlug,
          gameCount: eventGames.length,
          playerScore: playerScore,
          site: eventData?.site ?? siteFromPgn(eventGames.first.pgn),
          isFirstEvent: isFirstEvent,
          isCollapsed: _collapsedEventKeys.contains(tourId),
        ),
      );
      isFirstEvent = false;

      if (_collapsedEventKeys.contains(tourId)) {
        continue;
      }

      // Games under this event
      if (isGridMode) {
        final int gridColumns = ResponsiveHelper.columnsForWidth(
          availableWidth -
              2 * ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w),
          minItemWidth: 220,
          spacing: 16.sp,
          minColumns: 2,
          maxColumns: 4,
        );

        for (int i = 0; i < eventGames.length; i += gridColumns) {
          final isLast = i + gridColumns >= eventGames.length;

          final rowGames = <GamesTourModel>[];
          for (int j = 0; j < gridColumns && i + j < eventGames.length; j++) {
            rowGames.add(eventGames[i + j]);
          }

          listEntries.add(
            _PlayerGridRowEntry(
              games: rowGames,
              gridColumns: gridColumns,
              isLast: isLast,
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
            listEntries.add(
              _PlayerBoardGameEntry(
                game: game,
                gameIndex: globalIndex,
                isLast: isLast,
              ),
            );
          } else {
            listEntries.add(
              _PlayerCardGameEntry(
                game: game,
                gameIndex: globalIndex,
                animationIndex: listEntries.length,
                showHint: showHint,
                isLast: isLast,
              ),
            );
          }
        }
      }
    }

    if (state.isLoadingMore ||
        state.hasMorePages ||
        (state.totalCount != null && state.totalCount! > 0)) {
      listEntries.add(const _PlayerPaginationFooterEntry());
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
            state: state,
            games: games,
            isSelectionMode: isSelectionMode,
            gameIdToIndex: gameIdToIndex,
          ),
          childCount: listEntries.length,
        ),
      ),
    );
  }

  Widget _buildListEntry(
    _PlayerGamesListEntry entry, {
    required PlayerProfileGamesState state,
    required List<GamesTourModel> games,
    required bool isSelectionMode,
    required Map<String, int> gameIdToIndex,
  }) {
    if (entry is _PlayerEventHeaderEntry) {
      return Padding(
        padding: EdgeInsets.only(
          top: entry.isFirstEvent ? 8.h : 20.h,
          bottom: 12.h,
        ),
        child: PlayerGamesEventSection(
          eventData: entry.eventData,
          dataSource: widget.dataSource,
          tourId: entry.tourId,
          tourSlug: entry.tourSlug,
          site: entry.site,
          gameCount: entry.gameCount,
          playerScore: entry.playerScore,
          isCollapsed: entry.isCollapsed,
          onToggleCollapsed: () => _toggleEventCollapsed(entry.tourId),
        ),
      );
    }

    if (entry is _PlayerGridRowEntry) {
      return Padding(
        padding: EdgeInsets.only(bottom: entry.isLast ? 0 : 12.h),
        child: Row(
          children: [
            for (int j = 0; j < entry.gridColumns; j++) ...[
              if (j > 0) SizedBox(width: 12.sp),
              Expanded(
                child: j < entry.games.length
                    ? _buildGridGame(
                        entry.games[j],
                        gameIdToIndex[entry.games[j].gameId] ?? 0,
                        games,
                        isSelectionMode: isSelectionMode,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }

    if (entry is _PlayerBoardGameEntry) {
      Widget boardCard = BoardGameCardWrapperWidget(
        key: ValueKey('player_board_game_${entry.game.gameId}'),
        game: entry.game,
        orderedGames: games,
        gameIndex: entry.gameIndex,
        viewSource: ChessboardView.playerProfile,
        playerProfileDataSource: widget.dataSource,
        allowStockfishFallback: true,
        streamEnabled: true,
        onChangedWithLiveGames: (updatedGames) async {
          final allowed = await ensurePastGameAccess(
            context,
            game: updatedGames[entry.gameIndex],
          );
          if (!allowed || !mounted) return;

          ref
              .read(gameCardWrapperProvider)
              .navigateToChessBoard(
                context: context,
                orderedGames: updatedGames,
                gameIndex: entry.gameIndex,
                onReturnFromChessboard: (_) {},
                viewSource: ChessboardView.playerProfile,
                playerProfileDataSource: widget.dataSource,
              );
        },
        pinnedIds: const [],
        onPinToggle: (_) {},
      );

      if (isSelectionMode) {
        boardCard = _buildSelectableCardWrapper(
          boardCard,
          isSelected: _selectedGameIds.contains(entry.game.gameId),
          onTap: () => _toggleGameSelection(entry.game.gameId),
        );
      }

      return Padding(
        padding: EdgeInsets.only(bottom: entry.isLast ? 0 : 12.h),
        child: boardCard,
      );
    }

    if (entry is _PlayerCardGameEntry) {
      final isSelected = _selectedGameIds.contains(entry.game.gameId);
      Widget gameCard = LiveGamebaseSearchGameCard(
        game: entry.game,
        allGames: games,
        gameIndex: entry.gameIndex,
        animationIndex: entry.animationIndex,
        showRound: true,
        showSwipeHint: entry.showHint,
        showGamebaseButton: false,
        playerProfileDataSource: widget.dataSource,
        streamEnabled: true,
        viewSource: ChessboardView.playerProfile,
        onAdd: isSelectionMode
            ? () => _toggleGameSelection(entry.game.gameId)
            : () => _showAddToFolderSheet(entry.game),
        onLiveAdd: isSelectionMode
            ? null
            : (liveGame) => _showAddToFolderSheet(liveGame),
        onTap: isSelectionMode
            ? () => _toggleGameSelection(entry.game.gameId)
            : null,
      );

      if (isSelectionMode) {
        gameCard = _buildSelectableCardWrapper(
          gameCard,
          isSelected: isSelected,
        );
      }

      return Padding(
        padding: EdgeInsets.only(bottom: entry.isLast ? 0 : 12.h),
        child: gameCard,
      );
    }

    if (entry is _PlayerPaginationFooterEntry) {
      return Padding(
        padding: EdgeInsets.only(top: 12.h),
        child: _buildPaginationFooter(state),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildGridGame(
    GamesTourModel game,
    int gameIndex,
    List<GamesTourModel> allGames, {
    required bool isSelectionMode,
  }) {
    final Widget gridCard = GridGameCardWrapperWidget(
      key: ValueKey('player_grid_game_${game.gameId}'),
      game: game,
      orderedGames: allGames,
      gameIndex: gameIndex,
      allowStockfishFallback: true,
      streamEnabled: true,
      viewSource: ChessboardView.playerProfile,
      playerProfileDataSource: widget.dataSource,
      onChangedWithLiveGames: (updatedGames) async {
        final allowed = await ensurePastGameAccess(
          context,
          game: updatedGames[gameIndex],
        );
        if (!allowed || !mounted) return;

        ref
            .read(gameCardWrapperProvider)
            .navigateToChessBoard(
              context: context,
              orderedGames: updatedGames,
              gameIndex: gameIndex,
              onReturnFromChessboard: (_) {},
              viewSource: ChessboardView.playerProfile,
              playerProfileDataSource: widget.dataSource,
            );
      },
      pinnedIds: const [],
      onPinToggle: (_) {},
    );

    if (!isSelectionMode) return gridCard;

    // Same corner overhang as the full-width card: the 12px gutter between the
    // two columns (and the sliver's side padding on the outer edge) absorbs it,
    // so the badge never covers the cell's own player row.
    return _buildSelectableCardWrapper(
      gridCard,
      isSelected: _selectedGameIds.contains(game.gameId),
      onTap: () => _toggleGameSelection(game.gameId),
      cornerRadius: 12,
    );
  }

  Widget _buildSelectableCardWrapper(
    Widget card, {
    required bool isSelected,
    VoidCallback? onTap,
    double cornerRadius = 14,
  }) {
    return PlayerGamesSelectableCard(
      card: card,
      isSelected: isSelected,
      onTap: onTap,
      cornerRadius: cornerRadius,
    );
  }

  Widget _buildPaginationFooter(PlayerProfileGamesState state) {
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
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.colors.textPrimaryMuted,
              ),
            ),
            SizedBox(width: 10.w),
            Text(
              'Loading more games...',
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.textPrimaryMuted,
              ),
            ),
          ],
        ),
      );
    }

    if (state.hasMorePages) {
      if (widget.dataSource == PlayerProfileDataSource.twic) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref
              .read(playerProfileGamesKeyProvider(_playerKey).notifier)
              .loadMore();
        });
      }

      return GestureDetector(
        onTap: () => ref
            .read(playerProfileGamesKeyProvider(_playerKey).notifier)
            .loadMore(),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 14.h),
          alignment: Alignment.center,
          child: Text(
            'Load more games',
            style: AppTypography.textXsMedium.copyWith(
              color: context.colors.textPrimaryMuted,
            ),
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
            color: context.textInk(0.45),
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
    // Shimmer is decorative; exclude from semantics and isolate paint so the
    // repeating animation can't dirty the parent semantics tree mid-frame
    // (was throwing `!semantics.parentDataDirty` on tablet under
    // SliverFillRemaining + Center/ConstrainedBox wrap).
    return ExcludeSemantics(
      child: RepaintBoundary(
        child:
            Padding(
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
                            color: context.colors.surface,
                            borderRadius: BorderRadius.circular(12.br),
                          ),
                        ),
                      ],
                      SizedBox(height: 16.h),
                      Text(
                        'Loading games...',
                        style: AppTypography.textSmRegular.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
                .animate(onPlay: (controller) => controller.repeat())
                .shimmer(
                  duration: 1400.ms,
                  color: context.colors.textPrimary.withValues(alpha: 0.1),
                ),
      ),
    );
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
              color: context.colors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16.br),
            ),
            child: Icon(
              Icons.error_outline_rounded,
              color: context.colors.danger,
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
            onPressed: () => ref
                .read(playerProfileGamesKeyProvider(_playerKey).notifier)
                .refresh(),
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
              'This player has no recorded games yet.',
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

  Widget _buildNoFilterResultsState() {
    return PlayerGamesNoMatches(
      onClear: () {
        HapticFeedback.mediumImpact();
        // Clears the search too; an open search field follows.
        ref
            .read(playerProfileGamesKeyProvider(_playerKey).notifier)
            .clearFilter();
      },
    );
  }

  Widget _buildSearchingMoreState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 24.w,
            height: 24.h,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.colors.textPrimaryMuted,
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            'Searching more games...',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimaryMuted,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 220.ms);
  }
}

abstract class _PlayerGamesListEntry {
  const _PlayerGamesListEntry();
}

class _PlayerEventHeaderEntry extends _PlayerGamesListEntry {
  const _PlayerEventHeaderEntry({
    required this.eventData,
    required this.tourId,
    required this.tourSlug,
    required this.gameCount,
    required this.playerScore,
    required this.site,
    required this.isFirstEvent,
    required this.isCollapsed,
  });

  final PlayerEventData? eventData;
  final String tourId;
  final String? tourSlug;
  final int gameCount;
  final double playerScore;
  final String? site;
  final bool isFirstEvent;
  final bool isCollapsed;
}

class _PlayerGridRowEntry extends _PlayerGamesListEntry {
  const _PlayerGridRowEntry({
    required this.games,
    required this.gridColumns,
    required this.isLast,
  });

  final List<GamesTourModel> games;
  final int gridColumns;
  final bool isLast;
}

class _PlayerBoardGameEntry extends _PlayerGamesListEntry {
  const _PlayerBoardGameEntry({
    required this.game,
    required this.gameIndex,
    required this.isLast,
  });

  final GamesTourModel game;
  final int gameIndex;
  final bool isLast;
}

class _PlayerCardGameEntry extends _PlayerGamesListEntry {
  const _PlayerCardGameEntry({
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

class _PlayerPaginationFooterEntry extends _PlayerGamesListEntry {
  const _PlayerPaginationFooterEntry();
}

/// The profile's header while its Games tab is searched (Trello #1420): a
/// way back, the field, and the list's own controls, filters and layout,
/// as bare glyphs (they used to sit beside the field above the list). The
/// tab fills the page under it, filtered as the reader types.
class PlayerGamesSearchHeader extends ConsumerStatefulWidget {
  const PlayerGamesSearchHeader({
    super.key,
    required this.playerKey,
    required this.focusNode,
    required this.onClose,
  });

  /// The list it searches: the Games tab's own key.
  final PlayerProfileKey playerKey;

  /// The page's node, so the page can hold its chrome while the keyboard
  /// is up.
  final FocusNode focusNode;
  final VoidCallback onClose;

  @override
  ConsumerState<PlayerGamesSearchHeader> createState() =>
      _PlayerGamesSearchHeaderState();
}

class _PlayerGamesSearchHeaderState
    extends ConsumerState<PlayerGamesSearchHeader> {
  static const List<String> _hintWords = ['event', 'opponent', 'opening'];

  late final TextEditingController _controller;
  Timer? _debounce;

  /// The query this field last handed the list. A different one arriving
  /// from the list (Clear Filters, the filters strip) is written into the
  /// field; this one is not, as the field may hold more typed since.
  late String _applied;

  PlayerProfileGamesNotifier get _games =>
      ref.read(playerProfileGamesKeyProvider(widget.playerKey).notifier);

  @override
  void initState() {
    super.initState();
    // A query set before the search opened (an About stat) is in the field.
    _applied = ref
        .read(playerProfileGamesKeyProvider(widget.playerKey))
        .searchQuery;
    _controller = TextEditingController(text: _applied);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // TWIC searches on the server: one query per pause, not per keystroke.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _applied = value;
      _games.setSearchQuery(value);
    });
  }

  void _clear() {
    HapticFeedback.lightImpact();
    _debounce?.cancel();
    _controller.clear();
    widget.focusNode.unfocus();
    _applied = '';
    _games.setSearchQuery('');
  }

  Future<void> _openFilters() async {
    final current = ref.read(playerProfileGamesKeyProvider(widget.playerKey));
    final result = await showGameFilterDialog(
      context: context,
      currentFilter: playerProfileEffectiveFilter(current.filter),
      showFormatFilter: widget.playerKey.source == PlayerProfileDataSource.twic,
      showLiveFilter: false,
    );
    if (result == null || !mounted) return;
    _games.applyFilter(_storedFilter(result));
  }

  /// The dialog speaks in absolute bounds; the list keeps its defaults, so
  /// an untouched bound never reads as a filter.
  static GameFilter _storedFilter(GameFilter filter) {
    return filter.copyWith(
      minYear: filter.minYear == GameFilter.absoluteMinYear
          ? GameFilter.defaultMinYear
          : filter.minYear,
      minRating: filter.minRating == GameFilter.absoluteMinRating
          ? GameFilter.defaultMinRating
          : filter.minRating,
    );
  }

  @override
  Widget build(BuildContext context) {
    final games = playerProfileGamesKeyProvider(widget.playerKey);
    ref.listen<String>(games.select((s) => s.searchQuery), (_, next) {
      if (next == _applied) return;
      _debounce?.cancel();
      _applied = next;
      if (_controller.text == next) return;
      _controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    });
    // The field shows the query; the glyph counts what else narrows the list.
    final filters = ref.watch(
      games.select(
        (s) =>
            s.filter.activeFilterCount +
            (s.playerResultFilter != PlayerResultFilter.all ? 1 : 0),
      ),
    );
    final side = ResponsiveHelper.adaptive(phone: 20.sp, tablet: 32.sp);
    return Padding(
      // The chevron's and the last glyph's 44pt targets reach into the
      // gutter, so the glyphs themselves land on it.
      // Never negative: a folded Duo pane is narrower than the gutter.
      padding: EdgeInsetsDirectional.fromSTEB(
        math.max(0.0, side - 12),
        4.h,
        math.max(0.0, side - 12),
        10.h,
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 44,
            child: IconButton(
              key: const ValueKey('player_games_search_close'),
              tooltip: 'Close search',
              padding: EdgeInsets.zero,
              onPressed: () {
                HapticFeedbackService.navigation();
                widget.onClose();
              },
              icon: Icon(
                Icons.arrow_back_ios_new_outlined,
                size: 22,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Center(
                child: EventSearchBarFrame(
                  compact: true,
                  child: SimpleSearchBar(
                    textFieldKey: e2eKey(E2eIds.playerGamesSearchField),
                    controller: _controller,
                    focusNode: widget.focusNode,
                    autofocus: true,
                    hintText: 'Search',
                    rotatingHints: _hintWords,
                    onChanged: _onChanged,
                    onCloseTap: _clear,
                    onOpenFilter: null,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _SearchHeaderGlyph(
            buttonKey: e2eKey(E2eIds.playerGamesFilterButton),
            label: filters > 0
                ? 'Filter and sort games, $filters applied'
                : 'Filter and sort games',
            onTap: _openFilters,
            child: _FilterGlyph(count: filters),
          ),
          _SearchHeaderGlyph(
            label: 'Change games layout',
            onTap: () => ref.read(gamesListViewModeSwitcher).toggleViewMode(),
            child: SvgPicture.asset(
              SvgAsset.chase_grid,
              width: 20,
              height: 20,
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
}

/// A bare control in the search header: the glyph alone on a 44pt target,
/// with no tile and no splash drawn around it.
class _SearchHeaderGlyph extends StatelessWidget {
  const _SearchHeaderGlyph({
    required this.label,
    required this.onTap,
    required this.child,
    this.buttonKey,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;
  final Key? buttonKey;

  void _activate() {
    HapticFeedbackService.buttonPress();
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        button: true,
        label: label,
        onTap: _activate,
        excludeSemantics: true,
        child: GestureDetector(
          key: buttonKey,
          behavior: HitTestBehavior.opaque,
          onTap: _activate,
          child: SizedBox.square(dimension: 44, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// The filters glyph, lit with the count of what narrows the list. The
/// count is the floating search's own badge (teal disc, ink figure), so the
/// number the reader tapped through reads the same up here.
class _FilterGlyph extends StatelessWidget {
  const _FilterGlyph({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(
          Icons.tune_rounded,
          size: 22,
          color: active
              ? context.colors.textPrimary
              : context.colors.textSecondary,
        ),
        if (active)
          Positioned(
            top: -6,
            right: -8,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              // The filter count, as the floating buttons wear it: the
              // brand's tonal blue (clears contrast on paper too) with the
              // page's colour for its number.
              decoration: BoxDecoration(
                color: context.colors.accentText,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: context.colors.background,
                  width: 1.5,
                ),
              ),
              child: Text(
                count > 9 ? '9+' : '$count',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: context.colors.background,
                  fontSize: 10,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
