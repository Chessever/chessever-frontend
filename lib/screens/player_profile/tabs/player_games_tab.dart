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
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/quick_list_toggles.dart';
import 'package:chessever2/widgets/ink_fab.dart' show InkFabStack;
import 'package:chessever2/widgets/search_mode/search_mode.dart'
    show SearchModeFilterButton, SearchModeListEnd, SearchModeScope;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The full-page skeleton the Games list shows only while its first answer
/// loads.
@visibleForTesting
const Key playerGamesSkeletonKey = ValueKey<String>('player_games_skeleton');

/// Games tab showing all games of a player with comprehensive filters
/// Opens the Games list's filter sheet for [playerKey]: the list toolbar's
/// Filters and the search header's open the same one.
Future<void> openPlayerGamesFilters(
  BuildContext context,
  WidgetRef ref,
  PlayerProfileKey playerKey,
) async {
  HapticFeedbackService.buttonPress();
  final current = ref.read(playerProfileGamesKeyProvider(playerKey));
  final result = await showGameFilterDialog(
    context: context,
    currentFilter: playerProfileEffectiveFilter(current.filter),
    showFormatFilter: playerKey.source == PlayerProfileDataSource.twic,
    showLiveFilter: false,
  );
  if (result == null || !context.mounted) return;
  ref
      .read(playerProfileGamesKeyProvider(playerKey).notifier)
      .applyFilter(_storedFilter(result));
}

/// The dialog speaks in absolute bounds; the list keeps its defaults, so an
/// untouched bound never reads as a filter.
GameFilter _storedFilter(GameFilter filter) {
  return filter.copyWith(
    minYear: filter.minYear == GameFilter.absoluteMinYear
        ? GameFilter.defaultMinYear
        : filter.minYear,
    minRating: filter.minRating == GameFilter.absoluteMinRating
        ? GameFilter.defaultMinRating
        : filter.minRating,
  );
}

/// The Games list's controls in its search header, as every Games search
/// header ends: the board view, then Filters (counted) on the gutter. While
/// the search is open they stand here, and the list's toolbar keeps only
/// its count line.
class PlayerGamesSearchControls extends ConsumerWidget {
  const PlayerGamesSearchControls({super.key, required this.playerKey});

  final PlayerProfileKey playerKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(
      playerProfileGamesKeyProvider(
        playerKey,
      ).select((state) => state.filterSheetCount),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The switcher gives the tap feedback.
        BoardViewToggleButton(
          onTap: () => ref.read(gamesListViewModeSwitcher).toggleViewMode(),
        ),
        SearchModeFilterButton(
          key: const ValueKey('player_games_search_filters'),
          count: count,
          onTap: () => openPlayerGamesFilters(context, ref, playerKey),
        ),
      ],
    );
  }
}

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

  /// The sections folded while the list shows a search's hits. Every
  /// section is open as the hits land, so none hides in one the reader
  /// folded before; the reader's own folds come back with the whole list.
  final Set<String> _searchCollapsedEventKeys = <String>{};
  static const Duration _scrollIdleDelay = Duration(milliseconds: 180);

  /// The profile's search is open over this tab.
  bool _searching = false;

  /// Where the list was when the search opened: the unsearched list comes
  /// back there, not wherever the shorter results left the scroll.
  double? _preSearchOffset;

  /// The query the list on screen answers ('' for the whole list).
  String _shownQuery = '';

  /// An answer has landed for this list (games, none, or an error). Only
  /// the first one waits behind the skeleton; after it a quiet line says
  /// the list is loading.
  bool _answered = false;

  String get _liveCardsPauseReason => 'player_games_scroll_$hashCode';

  /// Opening the search alone changes nothing on the list: only hits do.
  Set<String> get _activeCollapsedKeys => _searching && _shownQuery.isNotEmpty
      ? _searchCollapsedEventKeys
      : _collapsedEventKeys;

  void _toggleEventCollapsed(String eventKey) {
    HapticFeedback.lightImpact();
    final collapsed = _activeCollapsedKeys;
    setState(() {
      if (!collapsed.add(eventKey)) collapsed.remove(eventKey);
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
    final initial = ref.read(playerProfileGamesKeyProvider(_playerKey));
    _shownQuery = initial.searchQuery;
    _answered = !initial.isLoading;
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
    _followSearch(SearchModeScope.maybeOf(context)?.isSearching ?? false);
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    routeObserver.subscribe(this, route);
    _routeSubscribed = true;
  }

  /// The profile's search opened or closed over this tab. The list itself
  /// stays mounted and in place either way.
  void _followSearch(bool searching) {
    if (searching == _searching) return;
    _searching = searching;
    _searchCollapsedEventKeys.clear();
    if (searching) {
      _preSearchOffset = _scrollController.hasClients
          ? _scrollController.offset
          : null;
    }
  }

  /// The list now on screen answers [query] (its first page landed, or the
  /// unsearched list came back). Hits are read from their top; the whole
  /// list comes back where the reader left it.
  void _onListAnswers(String query) {
    if (query.isNotEmpty) {
      _jumpTo(0);
      return;
    }
    final offset = _preSearchOffset;
    if (offset != null) _jumpTo(offset, afterLayout: true);
  }

  void _jumpTo(double offset, {bool afterLayout = false}) {
    void jump() {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final target = offset
          .clamp(
            position.minScrollExtent,
            math.max(position.minScrollExtent, position.maxScrollExtent),
          )
          .toDouble();
      if ((position.pixels - target).abs() < 0.5) return;
      _scrollController.jumpTo(target);
    }

    // Mid-frame (or for an extent the new list has yet to lay out), after
    // the frame.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (afterLayout ||
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => jump());
    } else {
      jump();
    }
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
    _loadMoreNearEnd(_scrollController.position);
  }

  /// TWIC pages in as the reader nears the end. Read on every scroll and on
  /// every change of the list's own measure, as every paged list reads it:
  /// the profile's header folding away grows the viewport (and shrinks what
  /// is left below) without a scroll. The pagination footer also asks as
  /// soon as it is built ([_buildPaginationFooter]), so on this list the
  /// measure is a second line under it, not the only one.
  void _loadMoreNearEnd(ScrollMetrics metrics) {
    if (widget.dataSource != PlayerProfileDataSource.twic) return;
    if (metrics.extentAfter > 560) return;
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

    // The list now answers another query: its first page landed, or the
    // unsearched list came back as the search cleared.
    ref.listen(playerProfileGamesKeyProvider(_playerKey), (_, next) {
      if (!next.isLoading) _answered = true;
      if (next.isLoading || next.searchQuery == _shownQuery) return;
      _shownQuery = next.searchQuery;
      _onListAnswers(next.searchQuery);
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
    // (Trello #1420). At the head of the list sits its toolbar (count, what
    // narrows it, layout, filters), one height whatever it says, and the
    // picking panel while games are being picked.
    final headerHeight =
        PlayerGamesListToolbar.heightOf(context) +
        (isSelectionMode
            ? PlayerGamesSelectionToolbar.heightOf(context) + 4.h
            : 0);

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
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0 &&
              notification.metrics.axis == Axis.vertical) {
            _loadMoreNearEnd(notification.metrics);
          }
          return false;
        },
        child: CustomScrollView(
          key: PageStorageKey<String>(_scrollStorageKey),
          controller: _scrollController,
          scrollCacheExtent: kListScrollCacheExtent,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            // The list's toolbar heads the list and scrolls with it. It does
            // not float back on its own: the profile's header above already
            // comes back with the reader's direction, and a second, snapping
            // header followed the gesture's start instead and disagreed with
            // it on every short peek.
            SliverAppBar(
              primary: false,
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

            // Clear of the profile's floating search at the list's end (its
            // square, and the margin that lifts it over the home indicator);
            // the button's room gives way on the search's own timeline while
            // nothing floats.
            SearchModeListEnd.sliver(
              base: 24.h + MediaQuery.viewPaddingOf(context).bottom,
              buttons: InkFabStack.extent(),
            ),
          ],
        ),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSelectionMode)
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                0,
                horizontalPadding,
                4.h,
              ),
              child: _buildSelectionToolbar(state, selectedVisibleCount),
            ),
          _buildListToolbar(state, horizontalPadding),
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

  Widget _buildListToolbar(PlayerProfileGamesState state, double inset) {
    final total = state.totalCount;
    // TWIC counts on the server, except for the in-play filter, which the
    // app applies to what is loaded.
    final serverCounted =
        widget.dataSource != PlayerProfileDataSource.twic ||
        state.filter.live == GameLiveFilter.all;
    final int? count;
    var morePending = false;
    final empty = state.allGames.isEmpty;
    if (empty && state.error != null) {
      // The error state under it says what happened.
      count = null;
    } else if (empty && state.isLoading) {
      // Before the first answer there is nothing to count. After a search
      // that found nothing, its count (TWIC keeps it through the next load)
      // stays until the next answer lands, so the line never goes blank.
      count = serverCounted ? total : null;
    } else if (total != null && serverCounted) {
      count = total;
    } else {
      count = state.filteredGames.length;
      morePending = state.hasMorePages;
    }
    return PlayerGamesListToolbar(
      inset: inset,
      // The search header carries the board view and Filters while open.
      controlsInSearchHeader: true,
      gameCount: count,
      morePending: morePending,
      filterCount: state.filterSheetCount,
      filterButtonKey: e2eKey(E2eIds.playerGamesFilterButton),
      onClearFilters: () {
        HapticFeedback.lightImpact();
        // Only what the filter sheet set: an open search keeps its words.
        ref
            .read(playerProfileGamesKeyProvider(_playerKey).notifier)
            .clearFilter(keepSearchQuery: true);
      },
      onOpenFilters: _openFilters,
      // The switcher gives the tap feedback.
      onToggleLayout: () =>
          ref.read(gamesListViewModeSwitcher).toggleViewMode(),
    );
  }

  Future<void> _openFilters() =>
      openPlayerGamesFilters(context, ref, _playerKey);

  Widget _buildContentSliver(
    PlayerProfileGamesState state,
    GamesListViewMode viewMode,
    AsyncValue<List<PlayerEventData>> eventsAsync,
    bool isSelectionMode,
    double availableWidth,
  ) {
    // TWIC narrows on the server, so its list can come back empty for a
    // query or a filter while the player has games. Locally narrowed lists
    // keep every game in [allGames].
    final narrowedOnServer =
        widget.dataSource == PlayerProfileDataSource.twic &&
        state.hasActiveFilters;

    if (state.allGames.isEmpty) {
      if (state.isLoading) {
        // Only the whole list's first answer waits behind the skeleton. A
        // new search or filter keeps the list it replaces on screen (the
        // header's progress line says it is working) until its own first
        // page lands; when what it replaces held nothing (a search that
        // found nothing), a quiet line says it is working instead.
        if (!_answered && !narrowedOnServer) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: _buildLoadingState(),
          );
        }
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _buildSearchingMoreState(
            label: narrowedOnServer ? 'Searching games...' : 'Loading games...',
          ),
        );
      }
      if (state.error != null) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _buildErrorState(userFacingError(state.error)),
        );
      }
      if (!narrowedOnServer) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _buildEmptyState(),
        );
      }
      // A query or a filter that matched nothing: "No matching games"
      // below, with the Clear that also empties an open search field.
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
      // What is loaded shows nothing (the in-play filter is applied here)
      // and a new answer is on its way: say it is searching, not that
      // nothing matches, until it lands.
      if (state.isLoading) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _buildSearchingMoreState(label: 'Searching games...'),
        );
      }
      // Where the first row would have been, as every Games list says it.
      return SliverToBoxAdapter(child: _buildNoFilterResultsState(state));
    }

    final isGridMode = viewMode == GamesListViewMode.chessBoardGrid;
    final isChessBoardVisible = viewMode == GamesListViewMode.chessBoard;

    // Group games by event (tourId)
    final gamesByEvent = _groupGamesByEvent(games);
    final collapsedKeys = _activeCollapsedKeys;
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
          isCollapsed: collapsedKeys.contains(tourId),
        ),
      );
      isFirstEvent = false;

      if (collapsedKeys.contains(tourId)) {
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
      key: playerGamesSkeletonKey,
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
    );
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
    );
  }

  /// No game for the filters or the words. Its action clears what it
  /// names (and plays the tap's haptic itself): the filters, keeping an
  /// open search's words, or the words, which an open field follows.
  Widget _buildNoFilterResultsState(PlayerProfileGamesState state) {
    final filtered = state.filterSheetCount > 0;
    final games = ref.read(playerProfileGamesKeyProvider(_playerKey).notifier);
    return PlayerGamesNoMatches(
      query: state.searchQuery,
      filtered: filtered,
      onClear: filtered
          ? () => games.clearFilter(keepSearchQuery: true)
          : () => games.setSearchQuery(''),
    );
  }

  Widget _buildSearchingMoreState({String label = 'Searching more games...'}) {
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
            label,
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimaryMuted,
            ),
          ),
        ],
      ),
    );
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
