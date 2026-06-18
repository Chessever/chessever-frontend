import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/bulk_add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/live_gamebase_search_game_card.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart'
    show PlayerProfileTab, selectedPlayerProfileTabProvider;
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/tabs/player_events_tab.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/board_game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/foreground_task_scheduler.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/scroll_to_top_button.dart';
import 'package:chessever2/widgets/simple_search_bar.dart' show SpringHintWord;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

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

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;
  Timer? _scrollIdleTimer;
  bool _routeSubscribed = false;
  bool _routeIsCurrent = true;
  bool _appIsResumed = true;
  bool _isLoadingAllPagesForSelection = false;
  bool _liveCardsPausedForScroll = false;
  late final StateController<Set<String>> _liveGameCardsPauseReasons;
  final Set<String> _selectedGameIds = <String>{};
  static const Duration _scrollIdleDelay = Duration(milliseconds: 180);

  String get _liveCardsPauseReason => 'player_games_scroll_$hashCode';
  // Keep rendering while backgrounded so the OS app-switcher snapshot is not
  // blank. Route coverage still removes the tab from active provider work.
  bool get _isActiveOnScreen => _routeIsCurrent;

  // Rotating "Search <word>" hint — mirrors the home and TWIC search bars so
  // the animated second word is consistent across the app.
  static const List<String> _rotatingHints = <String>[
    'event',
    'opponent',
    'opening',
  ];
  static const Duration _hintRotationInterval = Duration(seconds: 2);
  // Must comfortably cover SpringHintWord's 420ms spring so the last word
  // finishes animating out before we collapse back to plain "Search".
  static const Duration _hintCycleFadeOutDuration = Duration(milliseconds: 460);
  Timer? _hintRotationTimer;
  Timer? _hintFadeOutTimer;
  int _hintIndex = 0;
  // Rotation runs a single full pass, then collapses back to plain "Search".
  bool _hintCycleDone = false;
  // Transient: after the final tick we pass '' to SpringHintWord so it
  // spring-fades the last word out before the overlay disappears — fixes
  // the abrupt "snap" at cycle end.
  bool _hintCycleFadingOut = false;

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
    _searchFocusNode.addListener(_onSearchFocusChange);
    _searchController.addListener(_onSearchTextChange);
    _restartHintRotation();
  }

  void _onSearchFocusChange() {
    if (!mounted) return;
    setState(() {});
    if (_searchFocusNode.hasFocus) {
      _hintRotationTimer?.cancel();
    } else {
      _restartHintRotation();
    }
  }

  void _onSearchTextChange() {
    if (!mounted) return;
    final hasText = _searchController.text.isNotEmpty;
    final running = _hintRotationTimer?.isActive ?? false;
    if (hasText && running) {
      _hintRotationTimer?.cancel();
    } else if (!hasText && !running && !_searchFocusNode.hasFocus) {
      _restartHintRotation();
    }
  }

  void _restartHintRotation() {
    _hintRotationTimer?.cancel();
    if (_hintCycleDone || _hintCycleFadingOut || _rotatingHints.length <= 1) {
      return;
    }
    if (_searchController.text.isNotEmpty || _searchFocusNode.hasFocus) return;
    _hintRotationTimer = Timer.periodic(_hintRotationInterval, (_) {
      if (!mounted) return;
      final next = _hintIndex + 1;
      if (next >= _rotatingHints.length) {
        _hintRotationTimer?.cancel();
        setState(() => _hintCycleFadingOut = true);
        _hintFadeOutTimer?.cancel();
        _hintFadeOutTimer = Timer(_hintCycleFadeOutDuration, () {
          if (!mounted) return;
          setState(() => _hintCycleDone = true);
        });
      } else {
        setState(() => _hintIndex = next);
      }
    });
  }

  /// Get the player profile key for provider lookups
  PlayerProfileKey get _playerKey => PlayerProfileKey(
    fideId: widget.fideId,
    playerName: widget.playerName,
    source: widget.dataSource,
    gamebasePlayerId: widget.gamebasePlayerId,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    routeObserver.subscribe(this, route);
    _routeSubscribed = true;
    _routeIsCurrent = route.isCurrent;
  }

  @override
  void dispose() {
    if (_routeSubscribed) {
      routeObserver.unsubscribe(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    ForegroundTaskScheduler.cancel('player_games_resume_$hashCode');
    _debounceTimer?.cancel();
    _scrollIdleTimer?.cancel();
    _setLiveCardsPausedForScroll(false);
    _hintRotationTimer?.cancel();
    _hintFadeOutTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _searchController.removeListener(_onSearchTextChange);
    _searchController.dispose();
    _searchFocusNode.dispose();
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
    if (_routeIsCurrent != isActive) {
      setState(() => _routeIsCurrent = isActive);
    }
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

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      ref
          .read(playerProfileGamesKeyProvider(_playerKey).notifier)
          .setSearchQuery(value);
    });
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

  void _clearSearch() {
    HapticFeedback.lightImpact();
    _debounceTimer?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref
        .read(playerProfileGamesKeyProvider(_playerKey).notifier)
        .setSearchQuery('');
  }

  GameFilter _dialogFilter(GameFilter filter) {
    return playerProfileEffectiveFilter(filter);
  }

  GameFilter _storedFilter(GameFilter filter) {
    return filter.copyWith(
      minYear:
          filter.minYear == GameFilter.absoluteMinYear
              ? GameFilter.defaultMinYear
              : filter.minYear,
      minRating:
          filter.minRating == GameFilter.absoluteMinRating
              ? GameFilter.defaultMinRating
              : filter.minRating,
    );
  }

  Future<void> _showFilterDialog() async {
    HapticFeedbackService.buttonPress();
    final currentState = ref.read(playerProfileGamesKeyProvider(_playerKey));
    final result = await showGameFilterDialog(
      context: context,
      currentFilter: _dialogFilter(currentState.filter),
      showFormatFilter: widget.dataSource == PlayerProfileDataSource.twic,
      showLiveFilter: false,
    );
    if (result != null && mounted) {
      ref
          .read(playerProfileGamesKeyProvider(_playerKey).notifier)
          .applyFilter(_storedFilter(result));
    }
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
      final allFilteredIds =
          refreshed.filteredGames.map((g) => g.gameId).toSet();

      if (!mounted) return;
      setState(() {
        _selectedGameIds
          ..clear()
          ..addAll(allFilteredIds);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Selected ${allFilteredIds.length} filtered games',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to select all games: $e',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Select at least one game',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
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

    ref.listen<PlayerProfileTab>(selectedPlayerProfileTabProvider, (_, next) {
      if (next != PlayerProfileTab.games) {
        _stopLiveCardsForHiddenTab();
      }
    });

    final selectedTab = ref.watch(selectedPlayerProfileTabProvider);
    if (selectedTab != PlayerProfileTab.games || !_isActiveOnScreen) {
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
    if (!_searchFocusNode.hasFocus &&
        _searchController.text != state.searchQuery) {
      _searchController.value = TextEditingValue(
        text: state.searchQuery,
        selection: TextSelection.collapsed(offset: state.searchQuery.length),
      );
    }
    final viewMode = ref.watch(gamesListViewModeProvider);
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );
    final headerHeight =
        58.h +
        (state.hasActiveFilters ? 42.h : 0) +
        (isSelectionMode ? 136.h : 0);

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
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
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
          _buildContentSliver(
            state,
            viewMode,
            eventCardsAsync,
            eventsAsync,
            isSelectionMode,
          ),

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
    bool isSelectionMode,
  ) {
    final selectedVisibleCount =
        state.filteredGames
            .where((g) => _selectedGameIds.contains(g.gameId))
            .length;

    return Container(
      color: context.colors.background,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              2.h,
              horizontalPadding,
              4.h,
            ),
            child: _buildSearchBar(state),
          ),
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

  Widget _buildRotatingSearchHint() {
    // Pass an empty word during the fade-out phase so SpringHintWord animates
    // the final entry out instead of disappearing in a single frame.
    final word =
        _hintCycleFadingOut
            ? ''
            : _rotatingHints[_hintIndex % _rotatingHints.length];
    final style = AppTypography.textSmRegular.copyWith(
      color: context.colors.textSecondary,
    );
    return IgnorePointer(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Search ', style: style),
          Flexible(child: SpringHintWord(word: word, style: style)),
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
                    child: Builder(
                      builder: (_) {
                        final showRotating =
                            !_hintCycleDone &&
                            _searchController.text.isEmpty &&
                            !_searchFocusNode.hasFocus;
                        return Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            if (showRotating) _buildRotatingSearchHint(),
                            TextField(
                              key: e2eKey(E2eIds.playerGamesSearchField),
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              style: AppTypography.textSmRegular.copyWith(
                                color: context.colors.textPrimary,
                              ),
                              onChanged: _onSearchChanged,
                              decoration: InputDecoration(
                                isDense: true,
                                // The TextField owns the "Search" hint except
                                // while the rotating overlay is driving it.
                                hintText: showRotating ? null : 'Search',
                                hintStyle: AppTypography.textSmRegular.copyWith(
                                  color: context.colors.textSecondary,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 14.h,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (_searchController.text.isNotEmpty ||
                      state.searchQuery.isNotEmpty) ...[
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
          ),

          // Filter button
          SizedBox(width: 8.w),
          GestureDetector(
            onTap: _showFilterDialog,
            child: Container(
              key: e2eKey(E2eIds.playerGamesFilterButton),
              width: searchBarHeight,
              height: searchBarHeight,
              decoration: BoxDecoration(
                color:
                    hasActiveFilters
                        ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                        : context.colors.background,
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(
                  color:
                      hasActiveFilters
                          ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                          : context.colors.surfaceRecessed,
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
                            : context.colors.textSecondary,
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
          ),

          // Layout toggle button
          SizedBox(width: 8.w),
          GestureDetector(
            onTap: () => ref.read(gamesListViewModeSwitcher).toggleViewMode(),
            child: Container(
              width: searchBarHeight,
              height: searchBarHeight,
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(color: context.colors.surfaceRecessed),
              ),
              child: Center(
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionToolbar(
    PlayerProfileGamesState state,
    int selectedVisibleCount,
  ) {
    final title =
        selectedVisibleCount == 0
            ? 'Choose games to save'
            : '$selectedVisibleCount selected';
    final subtitle =
        _isLoadingAllPagesForSelection
            ? (state.totalCount != null &&
                    state.totalCount! > state.allGames.length
                ? 'Loading ${formatCompactCount(state.allGames.length)} of ${formatCompactCount(state.totalCount!)} games...'
                : 'Preparing your filtered game list...')
            : state.hasActiveFilters
            ? 'Selection follows current filters and search'
            : 'Tap games manually or use quick select';

    return SingleMotionBuilder(
      motion: const CupertinoMotion.bouncy(),
      value: 1.0,
      builder: (context, progress, child) {
        return Opacity(
          opacity: progress.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1.0 - progress) * -10),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(16.br),
                border: Border.all(color: kPrimaryColor.withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryColor.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: AppTypography.textSmMedium.copyWith(
                                color:
                                    selectedVisibleCount == 0
                                        ? context.colors.textPrimary.withValues(
                                          alpha: 0.75,
                                        )
                                        : kPrimaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              subtitle,
                              style: AppTypography.textXsRegular.copyWith(
                                color: context.colors.textPrimary.withValues(
                                  alpha: 0.58,
                                ),
                              ),
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 8.w),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          ref
                              .read(
                                playerGamesSelectionModeProvider(
                                  _playerKey,
                                ).notifier,
                              )
                              .state = false;
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10.w,
                            vertical: 8.h,
                          ),
                          decoration: BoxDecoration(
                            color: context.colors.textPrimary.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(10.br),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16.sp,
                            color: context.colors.textPrimary.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10.h),
                  Row(
                    children: [
                      Expanded(
                        child: _SelectionActionButton(
                          label:
                              _isLoadingAllPagesForSelection
                                  ? (state.totalCount != null &&
                                          state.totalCount! >
                                              state.allGames.length
                                      ? 'Loading ${formatCompactCount(state.allGames.length)}/${formatCompactCount(state.totalCount!)}...'
                                      : 'Selecting...')
                                  : _selectAllLabel(state),
                          icon: Icons.select_all_rounded,
                          onTap:
                              _isLoadingAllPagesForSelection
                                  ? null
                                  : () => _selectAllFilteredGames(state),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: _SelectionActionButton(
                          label:
                              selectedVisibleCount > 0
                                  ? 'Add selected'
                                  : 'Select first',
                          icon: Icons.library_add_rounded,
                          emphasized: selectedVisibleCount > 0,
                          onTap:
                              selectedVisibleCount > 0
                                  ? () => _addSelectedToLibrary(state)
                                  : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
              '${state.activeFilterCount} filter${state.activeFilterCount > 1 ? 's' : ''} active · ${formatCompactCount(state.filteredGames.length)} games',
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

  Widget _buildContentSliver(
    PlayerProfileGamesState state,
    GamesListViewMode viewMode,
    AsyncValue<Map<String, GroupEventCardModel>> eventCardsAsync,
    AsyncValue<List<PlayerEventData>> eventsAsync,
    bool isSelectionMode,
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
                  allowStockfishFallback: true,
                  streamEnabled: true,
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
            final isSelected = _selectedGameIds.contains(game.gameId);
            Widget gameCard = LiveGamebaseSearchGameCard(
              game: game,
              allGames: games,
              gameIndex: globalIndex,
              animationIndex: items.length,
              showRound: true,
              showSwipeHint: showHint,
              showGamebaseButton: false,
              playerProfileDataSource: widget.dataSource,
              streamEnabled: true,
              onAdd:
                  isSelectionMode
                      ? () => _toggleGameSelection(game.gameId)
                      : () => _showAddToFolderSheet(game),
              onLiveAdd:
                  isSelectionMode
                      ? null
                      : (liveGame) => _showAddToFolderSheet(liveGame),
              onTap:
                  isSelectionMode
                      ? () => _toggleGameSelection(game.gameId)
                      : null,
            );

            if (isSelectionMode) {
              gameCard = _buildSelectableCardWrapper(
                gameCard,
                isSelected: isSelected,
              );
            }

            items.add(
              Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 12.h),
                child: gameCard,
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
      allowStockfishFallback: true,
      streamEnabled: true,
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

  Widget _buildSelectableCardWrapper(Widget child, {required bool isSelected}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.br),
            border: Border.all(
              color:
                  isSelected
                      ? kPrimaryColor.withValues(alpha: 0.85)
                      : Colors.transparent,
              width: 1.6,
            ),
            boxShadow:
                isSelected
                    ? [
                      BoxShadow(
                        color: kPrimaryColor.withValues(alpha: 0.22),
                        blurRadius: 18,
                        spreadRadius: 0.5,
                        offset: const Offset(0, 2),
                      ),
                    ]
                    : null,
          ),
          child: child,
        ),
        Positioned(
          top: -6.h,
          right: -6.w,
          child: Container(
            width: 24.w,
            height: 24.h,
            decoration: BoxDecoration(
              color:
                  isSelected
                      ? kPrimaryColor
                      : context.colors.surface.withValues(alpha: 0.95),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: context.colors.background.withValues(alpha: 0.55),
                  blurRadius: 8,
                  spreadRadius: 0.5,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(
                color:
                    isSelected
                        ? context.colors.textPrimary
                        : context.colors.textPrimary.withValues(alpha: 0.24),
                width: 1.2,
              ),
            ),
            child: Icon(
              isSelected
                  ? Icons.check_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 14.5.sp,
              color: context.colors.textPrimary,
            ),
          ),
        ),
      ],
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
            color: context.colors.textPrimary.withValues(alpha: 0.45),
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
        child: Padding(
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
                        .read(
                          playerProfileGamesKeyProvider(_playerKey).notifier,
                        )
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
              ref
                  .read(playerProfileGamesKeyProvider(_playerKey).notifier)
                  .clearFilter();
              _clearSearch();
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

class _SelectionActionButton extends StatelessWidget {
  const _SelectionActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.emphasized = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 9.h),
        decoration: BoxDecoration(
          color:
              enabled
                  ? (emphasized
                      ? kPrimaryColor
                      : context.colors.textPrimary.withValues(alpha: 0.1))
                  : context.colors.textPrimary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10.br),
          border: Border.all(
            color:
                enabled
                    ? (emphasized
                        ? kPrimaryColor.withValues(alpha: 0.8)
                        : context.colors.textPrimary.withValues(alpha: 0.18))
                    : context.colors.textPrimary.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16.sp,
              color:
                  enabled
                      ? context.colors.textPrimary
                      : context.colors.textPrimary.withValues(alpha: 0.45),
            ),
            SizedBox(width: 6.w),
            Flexible(
              child: Text(
                label,
                style: AppTypography.textSmBold.copyWith(
                  color:
                      enabled
                          ? context.colors.textPrimary
                          : context.colors.textPrimary.withValues(alpha: 0.45),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
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
              // Embedded inside a SliverList (unbounded height) — must use
              // the compact phone layout to avoid Stack-expand crash.
              forceCompactLayout: true,
            )
          else
            _buildFallbackCard(context),

          // Player stats row
          _buildStatsRow(context),
        ],
      ),
    );
  }

  Widget _buildFallbackCard(BuildContext context) {
    final eventName = eventData?.tourName ?? _formatSlug(tourSlug ?? tourId);
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(8.br)),
      ),
      padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 16.sp),
      child: Text(
        eventName,
        style: AppTypography.textSmMedium.copyWith(
          color: context.colors.textPrimary,
          height: 1.2,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: 1.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
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
                color: context.colors.textPrimary.withValues(alpha: 0.5),
              ),
              SizedBox(width: 4.w),
              Text(
                '$gameCount ${gameCount == 1 ? 'game' : 'games'}',
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textPrimary.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          if (gameCount > 0)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
              decoration: BoxDecoration(
                color: _getScoreColor(context).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4.br),
              ),
              child: Text(
                '${_formatScore(playerScore)}/$gameCount',
                style: AppTypography.textXsBold.copyWith(
                  color: _getScoreColor(context),
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

  Color _getScoreColor(BuildContext context) {
    if (gameCount == 0) return context.colors.textPrimary;
    final percentage = playerScore / gameCount;
    if (percentage >= 0.6) return kGreenColor;
    if (percentage >= 0.4) return context.colors.textPrimary;
    return Colors.redAccent;
  }
}
