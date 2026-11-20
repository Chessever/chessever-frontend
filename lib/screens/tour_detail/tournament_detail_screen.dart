import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/chat/botvinnik_chat_button.dart';
import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/favorites/widgets/games_list_refetch_line.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_display_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_stage_round_resolver.dart';
import 'package:chessever2/screens/tour_detail/bracket/views/knockout_bracket_screen.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_tour_screen.dart';
import 'package:chessever2/screens/tour_detail/about_tour_screen.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_games_provider.dart'
    show combinedRoundsProvider, combinedRoundsKey;
import 'package:chessever2/screens/tour_detail/combined/combined_games_screen.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_standings.dart'
    show CombinedStandingsView;
import 'package:chessever2/screens/tour_detail/combined/combined_standings_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/views/games_tour_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_tabs.dart';
import 'package:chessever2/utils/share_standings.dart';
import 'package:chessever2/widgets/screenshot_share_nudge.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_app_bar_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/category_dropdown.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_games_quick_actions.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_search_placeholder.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/foreground_task_scheduler.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:chessever2/providers/game_list_live_first_provider.dart'
    show kNoLiveGamesRightNowMessage;
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart'
    show botvinnikTabAvailableProvider;
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/home_top_bar.dart'
    show HomeTopBarMetrics, PageTitle;
import 'package:chessever2/widgets/live_first_capsule.dart';
import 'package:chessever2/widgets/page_spring.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/widgets/page_back_float.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Success-path tournament-detail chrome: title/dropdown, search, tab switcher.
/// Widget tests scope writer-attribution assertions to this column so About
/// footer copy cannot satisfy them.
@visibleForTesting
const tournamentDetailSuccessAppBarKey = ValueKey<String>(
  'tournament-detail-success-appbar',
);

class TournamentDetailScreen extends ConsumerStatefulWidget {
  const TournamentDetailScreen({super.key});

  @override
  ConsumerState<TournamentDetailScreen> createState() =>
      _TournamentDetailViewState();
}

class _TournamentDetailViewState extends ConsumerState<TournamentDetailScreen>
    with RouteAware, WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late PageController pageController;

  /// The header (title row and tabs) and the floating buttons scroll away
  /// with the list and come back as it scrolls up (X-style).
  late final ScrollChromeController _chrome = ScrollChromeController(
    vsync: this,
  );

  /// The tab's full-page search: the field in the header's place, the same
  /// tab under it, filtered, with nothing else around it. The host runs the
  /// morph, back, focus, the chrome and the query; the tab under it is the
  /// tab itself (same list, cards, grouping and view mode).
  final SearchModeController _search = SearchModeController();

  /// Which example the Games search's hint gives ("Search by opening: Ruy
  /// Lopez"): a different one each time the search opens.
  final math.Random _hintRandom = math.Random();
  late int _hintIndex = _hintRandom.nextInt(eventSearchPlaceholderCount);

  void _onSearchOpen() {
    // Swapped while the field's words are still out of sight (or, with
    // reduced motion, before they are first drawn); a close turned round
    // mid-flight keeps the hint it was showing.
    final t = _search.timeline.value;
    if (t > 0 && t < 1) return;
    setState(() {
      _hintIndex =
          (_hintIndex +
              1 +
              _hintRandom.nextInt(eventSearchPlaceholderCount - 1)) %
          eventSearchPlaceholderCount;
    });
  }

  /// Every keystroke: Standings, Players and Combined filter what they hold
  /// at once.
  void _onSearchChanged(String query) =>
      ref.read(standingsSearchQueryProvider.notifier).state = query;

  /// The settled query: the Games tab of one category searches the event's
  /// games (the list keeps what it shows until the hits land).
  void _onSearchQuery(String query) {
    final games = ref.read(gamesTourScreenProvider.notifier);
    if (query.isEmpty) {
      // Emptied in the field: every game again. A close clears in
      // [_onSearchClose].
      if (_search.isSearching && _searchesEventGames()) games.clearSearch();
      return;
    }
    if (!_searchesEventGames()) return;
    unawaited(games.searchGamesEnhanced(query));
  }

  void _onSearchClose() {
    ref.read(standingsSearchQueryProvider.notifier).state = '';
    final searchedGames =
        ref.read(gamesTourScreenProvider).valueOrNull?.isSearchMode ?? false;
    if (searchedGames || _searchesEventGames()) {
      ref.read(gamesTourScreenProvider.notifier).clearSearch();
    }
  }

  /// The search runs against the event's games: the Games tab of a single
  /// category. Combined filters its own list; the other tabs filter theirs.
  bool _searchesEventGames() =>
      ref.read(selectedTourModeProvider) == TournamentDetailScreenMode.games &&
      !ref.read(combinedCategorySelectedProvider);

  /// The Games list is rebuilt from scratch (a refresh, the category's
  /// identity settling) while its search is open: the hits go with it, so
  /// run the query again once it is back.
  void _researchAfterRebuild(
    GamesTourScreenProvider? previous,
    GamesTourScreenProvider next,
  ) {
    if (previous == null || identical(previous, next)) return;
    final query = _search.query;
    if (query.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _search.query != query || !_searchesEventGames()) return;
      unawaited(
        ref.read(gamesTourScreenProvider.notifier).searchGamesEnhanced(query),
      );
    });
  }

  /// Live first turned on: the live games lead, so the list goes to its top
  /// to show them.
  void _showLiveFirst() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _gamesTopBus.request();
    });
  }

  late final String _scrollScopeId;
  final ScrollToTopBus _scrollToTopBus = ScrollToTopBus();

  /// The Games tab alone (Live first). A reselected tab fires both buses, so
  /// every tab still goes to its top as before.
  final ScrollToTopBus _gamesTopBus = ScrollToTopBus();

  final TournamentDetailLayoutTracker _layoutTracker =
      TournamentDetailLayoutTracker();
  late List<TournamentDetailScreenMode> _renderedModes;
  String? _scheduledReferencedRoundId;

  /// Reads the viewer's saved choice for this event, so one left in Combined
  /// opens in Combined again. Nothing is asked on the way in: Combined is
  /// turned on from the category picker or the menu.
  void _restoreCombinedSelection(WidgetRef scopedRef) {
    final groupId = scopedRef.watch(combinedCategoryGroupIdProvider);
    // An event with one category never reads storage for this.
    if (groupId == null ||
        !scopedRef.watch(combinedCategoriesProvider).canCombine) {
      return;
    }
    unawaited(
      scopedRef
          .read(combinedCategoryPrefsProvider.notifier)
          .ensureLoaded(groupId),
    );
  }

  /// Combined changes the Games, Standings and Players tabs. Opened from one
  /// of them it turns that tab Combined in place; opened from About or
  /// Bracket, which it leaves alone, it brings Games forward.
  void _showGamesTab() {
    if (!mounted) return;
    final index = _renderedModes.indexOf(TournamentDetailScreenMode.games);
    if (index < 0 ||
        combinedAppliesToMode(ref.read(selectedTourModeProvider))) {
      return;
    }
    _handleTabSelection(index, _renderedModes);
  }

  void _scheduleReferencedRoundSelection(
    WidgetRef scopedRef,
    String? roundId,
    AsyncValue<GamesAppBarViewModel> roundsAsync,
  ) {
    if (roundId == null ||
        roundId.isEmpty ||
        _scheduledReferencedRoundId == roundId) {
      return;
    }
    final rounds = roundsAsync.valueOrNull;
    if (rounds?.selectedId != roundId || rounds?.userSelectedId != true) return;
    _scheduledReferencedRoundId = roundId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = scopedRef.read(gamesAppBarProvider).valueOrNull;
      if (current?.selectedId != roundId || current?.userSelectedId != true) {
        _scheduledReferencedRoundId = null;
        return;
      }
      scrollToRoundFromTournamentContext(scopedRef, roundId);
      scopedRef.read(pendingRoundNavigationProvider.notifier).state = null;
      _scheduledReferencedRoundId = null;
    });
  }

  void _setRouteActive(bool active) {
    final visibility = ref.read(tournamentDetailVisibleProvider.notifier);
    final streaming = ref.read(shouldStreamProvider.notifier);
    Future.microtask(() {
      if (active && !mounted) return;
      visibility.state = active;
      streaming.state = active;
    });
  }

  @override
  void didPush() {
    markGamesTourScrollScopeActive(_scrollScopeId);
    _setRouteActive(true);
    super.didPush();
  }

  @override
  void didPop() {
    clearGamesTourScrollScopeActive(_scrollScopeId);
    _setRouteActive(false);
    super.didPop();
  }

  @override
  void didPopNext() {
    markGamesTourScrollScopeActive(_scrollScopeId);
    _setRouteActive(true);
    super.didPopNext();
  }

  @override
  void didPushNext() {
    clearGamesTourScrollScopeActive(_scrollScopeId);
    _setRouteActive(false);
    super.didPushNext();
  }

  @override
  void didChangeDependencies() {
    routeObserver.subscribe(this, ModalRoute.of(context)!);
    super.didChangeDependencies();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;

    if (state == AppLifecycleState.resumed) {
      _handleAppResumed();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ForegroundTaskScheduler.cancel('tournament_detail_resume_$hashCode');
      _handleAppPaused();
    } else {
      ForegroundTaskScheduler.cancel('tournament_detail_resume_$hashCode');
    }
  }

  void _handleAppResumed() {
    ForegroundTaskScheduler.schedule(
      key: 'tournament_detail_resume_$hashCode',
      task: () async {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route?.isCurrent != true) return;

        markGamesTourScrollScopeActive(_scrollScopeId);
        debugPrint('🔥 TournamentDetail: App resumed - refreshing games');
        // Re-enable streaming when app comes back to foreground
        ref.read(shouldStreamProvider.notifier).state = true;
        ref.invalidate(gameUpdatesStreamProvider);
        ref.invalidate(liveGameUpdateStreamProvider);
        ref.invalidate(gameUpdatesBatchStreamProvider);

        // Refresh games data while preserving current UI state
        // This avoids showing "no games" during the refresh
        final tourDetailAsync = ref.read(tourDetailScreenProvider);
        final tourDetail = tourDetailAsync.valueOrNull;
        final aboutTourModel = tourDetail?.aboutTourModel;
        if (aboutTourModel != null) {
          // Use refreshGames() instead of invalidate() to preserve current state
          // while fetching fresh data in the background
          final rounds =
              ref.read(gamesAppBarProvider).valueOrNull?.gamesAppBarModels ??
              const <GamesAppBarModel>[];
          final representedTourIds = <String>{
            ...representedTournamentIdsForDisplayRounds(
              rounds: rounds,
              selectedTourId: aboutTourModel.id,
              knownTourIds:
                  tourDetail?.tours.map((tour) => tour.tour.id) ??
                  const <String>[],
            ),
            // The Combined list shows every category, not just the selected
            // one, so all of them catch up after a background spell.
            ...ref.read(combinedLiveTourIdsProvider),
          };
          // Combined also re-reads its round names and start times, so a
          // round published or rescheduled meanwhile lands in place.
          final combinedTourIds = ref.read(combinedLiveTourIdsProvider);
          if (combinedTourIds.isNotEmpty) {
            ref.invalidate(
              combinedRoundsProvider(
                combinedRoundsKey(ref.read(combinedCategoriesProvider).tourIds),
              ),
            );
          }
          await Future.wait(
            representedTourIds.map((tourId) async {
              try {
                await ref
                    .read(gamesTourProvider(tourId).notifier)
                    .refreshGames();
              } catch (e) {
                debugPrint(
                  '🔥 TournamentDetail: Error refreshing tour $tourId on resume: $e',
                );
              }
            }),
          );
        }
      },
    );
  }

  void _handleAppPaused() {
    debugPrint('🔥 TournamentDetail: App paused - stopping streaming');
    clearGamesTourScrollScopeActive(_scrollScopeId);
    // Stop streaming when app goes to background to save resources
    ref.read(shouldStreamProvider.notifier).state = false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initialMode = ref.read(selectedTourModeProvider);
    _renderedModes = tournamentDetailModesFor(
      provisionalTournamentDetailLayoutForMode(initialMode),
    );
    final initialPage = tournamentDetailPageForMode(
      _renderedModes,
      initialMode,
    );
    pageController = PageController(initialPage: initialPage);
    _scrollScopeId = 'games_scroll_${UniqueKey()}';
    markGamesTourScrollScopeActive(_scrollScopeId);
  }

  @override
  void deactivate() {
    _cleanupProviders();
    super.deactivate();
  }

  void _cleanupProviders() {
    try {
      ref.invalidate(selectedTourModeProvider);
      ref.invalidate(gamesTourProvider);
      ref.invalidate(userSelectedRoundProvider);
      ref.invalidate(pendingRoundNavigationProvider);
      ref.invalidate(tourDetailScreenProvider);
      ref.invalidate(gamesAppBarProvider);
      ref.invalidate(gamesTourScreenProvider);
      ref.invalidate(gameDisplayModeProvider);
      ref.invalidate(playerTourScreenProvider);
      ref.invalidate(searchQueryProvider);
      // Scroll provider is scoped per screen; it will dispose with the ProviderScope below.
    } catch (e) {
      // Ignore errors during cleanup
      debugPrint('Error during provider cleanup: $e');
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    clearGamesTourScrollScopeActive(_scrollScopeId);
    ForegroundTaskScheduler.cancel('tournament_detail_resume_$hashCode');
    pageController.dispose();
    _scrollToTopBus.dispose();
    _gamesTopBus.dispose();
    _search.dispose();
    _chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        gamesTourScrollScopeProvider.overrideWithValue(_scrollScopeId),
      ],
      child: Consumer(
        builder: (context, scopedRef, _) {
          final selectedTourMode = scopedRef.watch(selectedTourModeProvider);
          final tourDetailAsync = scopedRef.watch(tourDetailScreenProvider);
          final roundsAsync = scopedRef.watch(gamesAppBarProvider);
          final pendingRoundId = scopedRef.watch(
            pendingRoundNavigationProvider,
          );
          _scheduleReferencedRoundSelection(
            scopedRef,
            pendingRoundId,
            roundsAsync,
          );
          final tourId = tourDetailAsync.valueOrNull?.aboutTourModel.id;
          final previousTourId = _layoutTracker.activeTourId;
          final knockoutState = tourId == null || tourId.isEmpty
              ? null
              : scopedRef.watch(knockoutTournamentStateProvider(tourId));
          final resolvedLayout = _layoutTracker.resolve(
            tourId: tourId,
            isTeam: knockoutState?.isTeamEvent ?? false,
            isKnockout: knockoutState?.isKnockout ?? false,
            isDetectionPending: knockoutState?.isDetectionPending ?? false,
            unresolvedLayout: provisionalTournamentDetailLayoutForMode(
              selectedTourMode,
            ),
          );
          final hasResolvedTour = _layoutTracker.activeTourId != null;
          final layout = hasResolvedTour
              ? resolvedLayout
              : provisionalTournamentDetailLayoutForMode(selectedTourMode);
          final visibleModes = tournamentDetailModesFor(layout);
          final activeTourChanged =
              tourId != null &&
              tourId.isNotEmpty &&
              previousTourId != _layoutTracker.activeTourId;
          final layoutChanged = !listEquals(_renderedModes, visibleModes);
          if (activeTourChanged || layoutChanged) {
            _renderedModes = visibleModes;
            _alignNavigationToVisibleModes(visibleModes, selectedTourMode);
          }
          final effectiveMode = normalizeTournamentDetailMode(
            visibleModes,
            selectedTourMode,
          );
          final isTeam = layout == TournamentDetailLayout.team;
          final selectedBroadcast = scopedRef.watch(
            selectedBroadcastModelProvider,
          );
          final selectedTour = tourDetailAsync.valueOrNull?.aboutTourModel;
          final combinedSelected = scopedRef.watch(
            combinedCategorySelectedProvider,
          );
          scopedRef.listen<int>(
            combinedGamesTabRequestProvider,
            (_, __) => _showGamesTab(),
          );
          _restoreCombinedSelection(scopedRef);

          scopedRef.listen<GamesTourScreenProvider>(
            gamesTourScreenProvider.notifier,
            _researchAfterRebuild,
          );
          final gamesTab = effectiveMode == TournamentDetailScreenMode.games;
          final searchLabel = _searchLabel(
            effectiveMode,
            teamStandings: isTeam && !combinedSelected,
          );

          // Back from the search closes it, back to the tab it searched; the
          // host owns that, the morph, the field and the query.
          return SearchModeHost(
            controller: _search,
            chrome: _chrome,
            debounce: const Duration(milliseconds: 200),
            onOpen: _onSearchOpen,
            onChanged: _onSearchChanged,
            onQuery: _onSearchQuery,
            onClose: _onSearchClose,
            child: ScreenWrapper(
              child: Scaffold(
                key: e2eKey(E2eIds.tournamentDetailRoot),
                // Per tab, in the thumb's reach: Games has its search and,
                // while something is live, Live first; Standings its search
                // and Botvinnik; About Botvinnik. The Bracket canvas keeps its
                // corner for its own zoom controls. Searching, the search
                // button's glass becomes the field and the others step back.
                floatingActionButton: SlidingFabs(
                  controller: _chrome,
                  child: _EventFabs(
                    mode: effectiveMode,
                    searchLabel: searchLabel,
                    onLiveFirstOn: _showLiveFirst,
                    chatContext: ChatScreenContext(
                      screen: 'tournament',
                      eventId: selectedBroadcast?.id,
                      eventName: selectedBroadcast?.name,
                      tournamentId: selectedTour?.id,
                      tournamentName: selectedTour?.name,
                    ),
                  ),
                ),
                body: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: ResponsiveHelper.isTablet
                          ? ResponsiveHelper.contentMaxWidth
                          : double.infinity,
                    ),
                    child: Stack(
                      fit: StackFit.passthrough,
                      children: [
                        Column(
                          children: [
                            SizedBox(
                              height:
                                  MediaQuery.viewPaddingOf(context).top + 4.h,
                            ),
                            // Folds up under the status bar as the list scrolls
                            // down, comes back as it scrolls up. Searching, the
                            // search header takes the header's place whatever
                            // state the event is in (loaded, loading, failed).
                            CollapsingChrome(
                              controller: _chrome,
                              child: SearchModeHeaderSlot(
                                header: tourDetailAsync.when(
                                  data: (data) => _buildSuccessAppBar(
                                    data,
                                    effectiveMode,
                                    visibleModes,
                                  ),
                                  error: (error, stackTrace) =>
                                      _buildErrorAppBar(
                                        error,
                                        effectiveMode,
                                        visibleModes,
                                      ),
                                  loading: () => const _LoadingAppBarWithTitle(
                                    title: "ChessEver",
                                  ),
                                ),
                                search: _EventSearchHeader(
                                  gamesTab: gamesTab,
                                  label: searchLabel,
                                  hintIndex: _hintIndex,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ScrollChromeRegion(
                                    controller: _chrome,
                                    // The Bracket is a canvas, not a list.
                                    enabled:
                                        effectiveMode !=
                                        TournamentDetailScreenMode.bracket,
                                    child: ScrollToTopScope(
                                      bus: _scrollToTopBus,
                                      child: ListenableBuilder(
                                        listenable: _search,
                                        builder: (context, _) => _buildPages(
                                          scopedRef,
                                          effectiveMode: effectiveMode,
                                          visibleModes: visibleModes,
                                          isTeam: isTeam,
                                          combinedSelected: combinedSelected,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Along the list's top while the Games search
                                  // runs, as on every other Games list: the list
                                  // keeps what it shows meanwhile.
                                  PositionedDirectional(
                                    top: 0,
                                    start: 0,
                                    end: 0,
                                    child: _SearchProgress(
                                      search: _search,
                                      active: gamesTab && !combinedSelected,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        // The way back while the header is folded away.
                        PageBackFloat(controller: _chrome),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// The tabs, swiped between while no search is open (a search belongs to
  /// the tab it opened on).
  Widget _buildPages(
    WidgetRef scopedRef, {
    required TournamentDetailScreenMode effectiveMode,
    required List<TournamentDetailScreenMode> visibleModes,
    required bool isTeam,
    required bool combinedSelected,
  }) {
    return PageView.builder(
      controller: pageController,
      physics: _search.pagePhysics(
        effectiveMode == TournamentDetailScreenMode.bracket
            ? const NeverScrollableScrollPhysics()
            : null,
      ),
      itemCount: visibleModes.length,
      onPageChanged: (index) => _handlePageChanged(index, visibleModes),
      itemBuilder: (context, index) {
        if (index >= visibleModes.length) {
          return const SizedBox.shrink();
        }
        switch (visibleModes[index]) {
          case TournamentDetailScreenMode.about:
            return AboutTourScreen();
          case TournamentDetailScreenMode.games:
            // PageView keeps this tab mounted. Release card hydration, clocks
            // and live listeners while another tab is selected, preserving
            // its scroll/expansion state for the return.
            return TickerMode(
              enabled: effectiveMode == TournamentDetailScreenMode.games,
              // Its own top: Live first takes the Games list there alone.
              child: ScrollToTopScope(
                bus: _gamesTopBus,
                // Combined swaps the list, not the tab: every category's
                // rounds in one place.
                child: combinedSelected
                    ? const CombinedGamesScreen()
                    : const GamesTourScreen(),
              ),
            );
          case TournamentDetailScreenMode.bracket:
            return const KnockoutBracketScreen();
          case TournamentDetailScreenMode.standings:
            // Combined swaps the table, not the tab: every category's own
            // standings in one list, team tables for team categories.
            if (combinedSelected) {
              return ScreenshotShareNudge(
                enabled: effectiveMode == TournamentDetailScreenMode.standings,
                onShare: () => shareTournamentStandings(context, scopedRef),
                child: const CombinedStandingsScreen(),
              );
            }
            // Team events: team table (no standings-image share nudge; the
            // individual standings the nudge shares now live on the Players
            // tab).
            if (isTeam) {
              return const TeamStandingsScreen();
            }
            return ScreenshotShareNudge(
              enabled: effectiveMode == TournamentDetailScreenMode.standings,
              onShare: () => shareTournamentStandings(context, scopedRef),
              child: PlayerTourScreen(),
            );
          case TournamentDetailScreenMode.players:
            // Individual standings for team events; the share nudge follows
            // them here.
            return ScreenshotShareNudge(
              enabled: effectiveMode == TournamentDetailScreenMode.players,
              onShare: () => shareTournamentStandings(context, scopedRef),
              child: combinedSelected
                  ? const CombinedStandingsScreen(
                      view: CombinedStandingsView.players,
                    )
                  : PlayerTourScreen(),
            );
        }
      },
    );
  }

  Widget _buildSuccessAppBar(
    TourDetailViewModel data,
    TournamentDetailScreenMode selectedTourMode,
    List<TournamentDetailScreenMode> visibleModes,
  ) {
    return Column(
      key: tournamentDetailSuccessAppBarKey,
      children: [
        selectedTourMode == TournamentDetailScreenMode.games
            ? const GamesAppBarWidget()
            : _TourDetailDropDownAppBar(data: data),
        SizedBox(height: 8.h),
        _buildSegmentedSwitcher(
          selectedTourMode,
          visibleModes,
          (index) => _handleTabSelection(index, visibleModes),
        ),
        SizedBox(height: 4.h),
      ],
    );
  }

  Widget _buildErrorAppBar(
    Object error,
    TournamentDetailScreenMode selectedTourMode,
    List<TournamentDetailScreenMode> visibleModes,
  ) {
    return Column(
      children: [
        _LoadingAppBarWithTitle(title: userFacingError(error), loading: false),
        SizedBox(height: 8.h),
        _buildSegmentedSwitcher(
          selectedTourMode,
          visibleModes,
          (index) => _handleTabSelection(index, visibleModes),
        ),
        // The success header's gap under its tabs: the slot is the same
        // height whichever state it shows.
        SizedBox(height: 4.h),
      ],
    );
  }

  Widget _buildSegmentedSwitcher(
    TournamentDetailScreenMode selectedTourMode,
    List<TournamentDetailScreenMode> modes,
    ValueChanged<int> onChanged,
  ) {
    // The header and the tabs read as one column: the strip starts at the
    // chevron's point and ends at the ⋮'s outer edge, which mirrors it, and
    // its middle tab sits under the category chip (EventHeaderMetrics).
    final horizontalPadding = EventHeaderMetrics.backInk;
    final options = modes.map((m) => _mappedName[m]!).toList();
    final selectedIndex = modes.indexOf(selectedTourMode);
    final safeIndex = selectedIndex >= 0 ? selectedIndex : 0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: SegmentedSwitcher(
        dotScope: 'event.tab',
        // Four-tab layouts scroll with exactly three segments visible. The
        // mode signature distinguishes team and knockout lists of equal size.
        key: ValueKey(
          'tab_switcher_${modes.map((mode) => mode.name).join('_')}',
        ),
        backgroundColor: context.colors.popup,
        selectedBackgroundColor: context.colors.popup,
        options: options,
        initialSelection: safeIndex,
        currentSelection: safeIndex,
        onSelectionChanged: onChanged,
        notifyOnReselect: true,
        isScrollable: modes.length > 3,
      ),
    );
  }

  void _handleTabSelection(
    int index,
    List<TournamentDetailScreenMode> visibleModes,
  ) {
    try {
      final selectedMode = tournamentDetailModeForPage(visibleModes, index);
      final currentMode = ref.read(selectedTourModeProvider);
      if (selectedMode == currentMode) {
        _scrollToTopBus.request();
        _gamesTopBus.request();
        return;
      }
      // Drop the keyboard when leaving the search-enabled tabs so the field
      // and the keyboard collapse together, instead of the keyboard hovering
      // over About after a swipe.
      FocusScope.of(context).unfocus();
      _chrome.show();
      // Schedule the state change to avoid mutating provider state during
      // layout/semantics passes, which can trigger parentDataDirty assertions.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(selectedTourModeProvider.notifier).update((_) => selectedMode);
      });
      // The page moves on the spring the morph and the chrome move on:
      // driven by the spring itself, so a finger or another tab takes over
      // mid-flight, and it jumps with reduced motion.
      unawaited(pageController.springTo(index, context: context));
    } catch (e) {
      debugPrint('Error handling tab selection: $e');
    }
  }

  void _handlePageChanged(
    int index,
    List<TournamentDetailScreenMode> visibleModes,
  ) {
    try {
      // Update the selected mode when page changes (from swiping)
      final nextMode = tournamentDetailModeForPage(visibleModes, index);
      final currentMode = ref.read(selectedTourModeProvider);

      if (currentMode != nextMode) {
        FocusScope.of(context).unfocus();
        _chrome.show();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(selectedTourModeProvider.notifier).update((_) => nextMode);
        });
      }
    } catch (e) {
      debugPrint('Error handling page change: $e');
    }
  }

  void _alignNavigationToVisibleModes(
    List<TournamentDetailScreenMode> visibleModes,
    TournamentDetailScreenMode selectedMode,
  ) {
    final normalizedMode = normalizeTournamentDetailMode(
      visibleModes,
      selectedMode,
    );
    final targetPage = tournamentDetailPageForMode(
      visibleModes,
      normalizedMode,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(selectedTourModeProvider) != normalizedMode) {
        ref.read(selectedTourModeProvider.notifier).state = normalizedMode;
      }
      if (!pageController.hasClients) return;
      final currentPage =
          pageController.page?.round() ?? pageController.initialPage;
      if (currentPage != targetPage) {
        pageController.jumpToPage(targetPage);
      }
    });
  }
}

class _TourDetailDropDownAppBar extends ConsumerWidget {
  const _TourDetailDropDownAppBar({required this.data});

  final TourDetailViewModel data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.tours.isEmpty) {
      return const _LoadingAppBarWithTitle(
        title: 'No tournaments available',
        loading: false,
      );
    }

    // The Games header's row without the board view: the back, the chip
    // and the ⋮ exactly where Games puts them, so switching tabs moves
    // nothing.
    return EventHeaderRow(middle: const CategoryDropdown(), tourData: data);
  }
}

/// The header's title row while the event has no name of its own to show:
/// loading (a stand-in name, shimmering) or failed (what went wrong, read
/// whole). The back sits where every header of the event, and its search,
/// puts it; the words are centred on the screen in the pushed-page title
/// voice ([PageTitle]), as every pushed page names itself.
class _LoadingAppBarWithTitle extends StatelessWidget {
  const _LoadingAppBarWithTitle({required this.title, this.loading = true});

  final String title;

  /// False for the error bar, which must read as text, not a shimmer.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final Widget words = loading
        ? SkeletonWidget(child: PageTitle(title))
        // A failure may need a second line to be read whole.
        : MediaQuery.withClampedTextScaling(
            maxScaleFactor: HomeTopBarMetrics.maxTextScale,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: PageTitle.style(context),
            ),
          );
    // The loaded header's row: the back in place, the words centred on the
    // screen, kept clear of the back on both sides.
    return EventHeaderRow(middle: words, reserveControls: false);
  }
}

const _mappedName = {
  TournamentDetailScreenMode.about: 'About',
  TournamentDetailScreenMode.games: 'Games',
  TournamentDetailScreenMode.bracket: 'Bracket',
  TournamentDetailScreenMode.standings: 'Standings',
  TournamentDetailScreenMode.players: 'Players',
};

/// What a tab's search looks for, on its button and in its empty field.
String _searchLabel(
  TournamentDetailScreenMode mode, {
  required bool teamStandings,
}) => switch (mode) {
  TournamentDetailScreenMode.games => 'Search games',
  TournamentDetailScreenMode.standings when teamStandings => 'Search teams',
  _ => 'Search players',
};

/// The header while a tab is being searched: the canonical search header (a
/// way back and the field, nothing else), the tab itself filling the page
/// under it as the reader types. Games searches players, openings, ECO,
/// countries, titles and results, so its hint gives one of those as an
/// example; Standings and Players search by name.
class _EventSearchHeader extends ConsumerWidget {
  const _EventSearchHeader({
    required this.gamesTab,
    required this.label,
    required this.hintIndex,
  });

  final bool gamesTab;
  final String label;
  final int hintIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hint = gamesTab
        ? eventSearchPlaceholderForIndex(
            hintIndex,
            countryCode: ref
                .watch(countryDropdownProvider)
                .valueOrNull
                ?.countryCode,
          )
        : label;
    return SearchModeHeader(
      hintText: hint,
      closeKey: const ValueKey('event_search_close'),
    );
  }
}

/// While the Games search runs: the Games lists' quiet line
/// ([GamesListRefetchLine]) along the top of the list. The list keeps what
/// it shows (every game, or the last hits) until the new hits land, so
/// nothing on the page is wiped or replaced by a spinner.
class _SearchProgress extends ConsumerWidget {
  const _SearchProgress({required this.search, required this.active});

  final SearchModeController search;

  /// The tab in view searches the event's games (one category's Games).
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = active && ref.watch(gamesTourSearchPendingProvider);
    return ListenableBuilder(
      listenable: search,
      builder: (context, _) =>
          GamesListRefetchLine(active: pending && search.isSearching),
    );
  }
}

/// The single-category Games list still shows a search's hits. Closing the
/// search puts back the list the hits replaced in the same frame, or, when
/// there was none, leaves the hits up until the list of every game is
/// rebuilt; Combined drops its search with the query, at once.
bool _listHoldsSearchHits(EventProviderReader read) =>
    !read(combinedCategorySelectedProvider) &&
    read(
      gamesTourScreenProvider.select(
        (screen) => screen.valueOrNull?.isSearchMode ?? false,
      ),
    );

/// The event's floating buttons for the tab in view.
///
/// Games: the search (the tab's full-page search) and, above it while a
/// game is in play or while it is on, Live first. Standings: the search and
/// Botvinnik above it, the smaller button over the main one as everywhere.
/// Players: the search. About: Botvinnik, the page's main button. Bracket
/// keeps its corner for the canvas's zoom controls. Botvinnik stays on
/// About and Standings only (Trello #1420); everywhere else it has its own
/// tab.
///
/// Searching, they all stay: the search page's host flies the search
/// button's glass into the field (and back on close) and steps the others
/// back meanwhile.
///
/// Every button sits on the same right edge, the search at the foot, so the
/// search holds its corner whichever tab is in view and whatever floats
/// above it: the wide Live first capsule grows leftward from that edge
/// instead of pulling the disc off it.
class _EventFabs extends ConsumerWidget {
  const _EventFabs({
    required this.mode,
    required this.searchLabel,
    required this.onLiveFirstOn,
    required this.chatContext,
  });

  final TournamentDetailScreenMode mode;
  final String searchLabel;

  /// Live first was turned on: the list goes to its top, where the live
  /// games now lead.
  final VoidCallback onLiveFirstOn;
  final ChatScreenContext chatContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The Games list's live-game polls (Live first keeps them running from
    // its kept-alive tab) wait while another tab is in front or a board
    // covers the event, whichever tab it was opened from.
    syncEventGamesLiveIdsVisibility(
      context,
      ref,
      gamesInView: mode == TournamentDetailScreenMode.games,
    );
    final botvinnik = ref.watch(botvinnikTabAvailableProvider);
    Widget chat(InkFabSize size) => BotvinnikChatButton(
      screenContext: chatContext,
      iconOnly: true,
      size: size,
    );
    // The host opens the search from it: no tap of its own.
    final search = SearchInkFab(
      key: const ValueKey('event_search_fab'),
      label: searchLabel,
    );
    switch (mode) {
      case TournamentDetailScreenMode.bracket:
        return const SizedBox.shrink();
      case TournamentDetailScreenMode.about:
        // Through the same stack as on Standings, so Botvinnik stays the
        // same button as the reader moves between the two.
        return botvinnik
            ? InkFabStack(children: [chat(InkFabSize.regular)])
            : const SizedBox.shrink();
      case TournamentDetailScreenMode.players:
        return InkFabStack(children: [search]);
      case TournamentDetailScreenMode.standings:
        return InkFabStack(
          children: [if (botvinnik) chat(InkFabSize.small), search],
        );
      case TournamentDetailScreenMode.games:
        final liveFirst = ref.watch(eventGamesLiveFirstProvider);
        final anyLive = ref.watch(eventGamesAnyLiveProvider);
        // Just after the search closes the list still holds its hits. Live
        // first waits for every game: what is live among the hits says
        // nothing of the event, and a press would run the closed query again.
        final holdsHits = _listHoldsSearchHits(ref.watch);
        // As on every list with Live first: there while a game is in play
        // (Trello #1420), or while it is on, so a Live first left on can
        // always be seen and turned off. It only reorders (every game stays
        // listed), so left on with nothing live it changes nothing.
        final offered = (anyLive || liveFirst) && !holdsHits;
        // The tooltip and accessibility label use the server's live count
        // once it arrives.
        final liveCount = offered
            ? ref.watch(eventGamesLiveCountProvider)
            : null;
        return InkFabStack(
          children: [
            if (offered)
              LiveFirstCapsule(
                key: const ValueKey('event_live_first_fab'),
                on: liveFirst,
                liveCount: liveCount,
                mode: LiveFirstMode.reorder,
                onTap: () {
                  switch (pressEventGamesLiveFirst(ref.read)) {
                    case EventLiveFirstPress.nothingLive:
                      showAppSnack(context, kNoLiveGamesRightNowMessage);
                    case EventLiveFirstPress.turnedOn:
                      onLiveFirstOn();
                    case EventLiveFirstPress.turnedOff:
                      break;
                  }
                },
              ),
            search,
          ],
        );
    }
  }
}
