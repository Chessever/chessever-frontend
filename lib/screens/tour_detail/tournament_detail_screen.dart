import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/chat/botvinnik_chat_button.dart';
import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
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
import 'package:chessever2/screens/tour_detail/widgets/event_search_bar.dart';
import 'package:chessever2/screens/tour_detail/widgets/tournament_menu_button.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
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
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/ink_fab.dart';
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
  /// tab under it, filtered, with nothing else around it.
  bool _searching = false;
  final FocusNode _searchFocus = FocusNode();

  void _openSearch() {
    if (_searching) return;
    setState(() => _searching = true);
    _chrome.show();
  }

  void _closeSearch() {
    if (!_searching) return;
    _searchFocus.unfocus();
    ref.read(standingsSearchQueryProvider.notifier).state = '';
    ref.read(gamesTourScreenProvider.notifier).clearSearch();
    setState(() => _searching = false);
    _chrome.show();
  }

  void _holdChromeWhileTyping() => _chrome.held = _searchFocus.hasFocus;
  late final String _scrollScopeId;
  final ScrollToTopBus _scrollToTopBus = ScrollToTopBus();

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
    _searchFocus.addListener(_holdChromeWhileTyping);
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
    _searchFocus
      ..removeListener(_holdChromeWhileTyping)
      ..dispose();
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

          return PopScope(
            // Back from the search closes it, back to the tab it searched.
            canPop: !_searching,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _closeSearch();
            },
            child: ScreenWrapper(
              child: Scaffold(
                key: e2eKey(E2eIds.tournamentDetailRoot),
                // Per tab, in the thumb's reach: Games has its search and,
                // while something is live, Live first; Standings its search
                // and Botvinnik; About Botvinnik. The Bracket canvas keeps its
                // corner for its own zoom controls. Searching, nothing floats.
                floatingActionButton: SlidingFabs(
                  controller: _chrome,
                  child: _EventFabs(
                    mode: effectiveMode,
                    searching: _searching,
                    onSearch: _openSearch,
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
                    child: Column(
                      children: [
                        SizedBox(
                          height: MediaQuery.viewPaddingOf(context).top + 4.h,
                        ),
                        // Folds up under the status bar as the list scrolls
                        // down, comes back as it scrolls up.
                        CollapsingChrome(
                          controller: _chrome,
                          child: tourDetailAsync.when(
                            data: (data) => _buildSuccessAppBar(
                              data,
                              effectiveMode,
                              visibleModes,
                            ),
                            error: (error, stackTrace) => _buildErrorAppBar(
                              error,
                              effectiveMode,
                              visibleModes,
                            ),
                            loading: () => const _LoadingAppBarWithTitle(
                              title: "ChessEver",
                            ),
                          ),
                        ),
                        Expanded(
                          child: ScrollChromeRegion(
                            controller: _chrome,
                            // The Bracket is a canvas, not a list.
                            enabled:
                                effectiveMode !=
                                TournamentDetailScreenMode.bracket,
                            child: ScrollToTopScope(
                              bus: _scrollToTopBus,
                              child: PageView.builder(
                                controller: pageController,
                                // Searching holds the tab: the search belongs
                                // to it.
                                physics:
                                    _searching ||
                                        effectiveMode ==
                                            TournamentDetailScreenMode.bracket
                                    ? const NeverScrollableScrollPhysics()
                                    : null,
                                itemCount: visibleModes.length,
                                onPageChanged: (index) =>
                                    _handlePageChanged(index, visibleModes),
                                itemBuilder: (context, index) {
                                  if (index >= visibleModes.length) {
                                    return const SizedBox.shrink();
                                  }
                                  switch (visibleModes[index]) {
                                    case TournamentDetailScreenMode.about:
                                      return AboutTourScreen();
                                    case TournamentDetailScreenMode.games:
                                      // PageView keeps this tab mounted. Release
                                      // card hydration, clocks and live listeners
                                      // while another tab is selected, preserving
                                      // its scroll/expansion state for the return.
                                      return TickerMode(
                                        enabled:
                                            effectiveMode ==
                                            TournamentDetailScreenMode.games,
                                        // Combined swaps the list, not the tab:
                                        // every category's rounds in one place.
                                        child: combinedSelected
                                            ? const CombinedGamesScreen()
                                            : const GamesTourScreen(),
                                      );
                                    case TournamentDetailScreenMode.bracket:
                                      return const KnockoutBracketScreen();
                                    case TournamentDetailScreenMode.standings:
                                      // Combined swaps the table, not the tab:
                                      // every category's own standings in one
                                      // list, team tables for team categories.
                                      if (combinedSelected) {
                                        return ScreenshotShareNudge(
                                          enabled:
                                              effectiveMode ==
                                              TournamentDetailScreenMode
                                                  .standings,
                                          onShare: () =>
                                              shareTournamentStandings(
                                                context,
                                                scopedRef,
                                              ),
                                          child:
                                              const CombinedStandingsScreen(),
                                        );
                                      }
                                      // Team events: team table (no standings-image
                                      // share nudge — the individual standings the
                                      // nudge shares now live on the Players tab).
                                      if (isTeam) {
                                        return const TeamStandingsScreen();
                                      }
                                      return ScreenshotShareNudge(
                                        enabled:
                                            effectiveMode ==
                                            TournamentDetailScreenMode
                                                .standings,
                                        onShare: () => shareTournamentStandings(
                                          context,
                                          scopedRef,
                                        ),
                                        child: PlayerTourScreen(),
                                      );
                                    case TournamentDetailScreenMode.players:
                                      // Individual standings for team events; the
                                      // share nudge follows them here.
                                      return ScreenshotShareNudge(
                                        enabled:
                                            effectiveMode ==
                                            TournamentDetailScreenMode.players,
                                        onShare: () => shareTournamentStandings(
                                          context,
                                          scopedRef,
                                        ),
                                        child: combinedSelected
                                            ? const CombinedStandingsScreen(
                                                view: CombinedStandingsView
                                                    .players,
                                              )
                                            : PlayerTourScreen(),
                                      );
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
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

  Widget _buildSuccessAppBar(
    TourDetailViewModel data,
    TournamentDetailScreenMode selectedTourMode,
    List<TournamentDetailScreenMode> visibleModes,
  ) {
    if (_searching) {
      return KeyedSubtree(
        key: tournamentDetailSuccessAppBarKey,
        child: _EventSearchHeader(
          focusNode: _searchFocus,
          onClose: _closeSearch,
        ),
      );
    }
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
      ],
    );
  }

  Widget _buildSegmentedSwitcher(
    TournamentDetailScreenMode selectedTourMode,
    List<TournamentDetailScreenMode> modes,
    ValueChanged<int> onChanged,
  ) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );
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
      // Animate to the selected page first
      pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
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
      return _buildErrorAppBar(context, 'No tournaments available');
    }

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    return Padding(
      // The bare ⋮ (Trello #1420) has a 44pt target that reaches past its old
      // tile; the end inset gives that back so the glyph stays put.
      padding: EdgeInsetsDirectional.only(
        start: horizontalPadding,
        end: math.max(0, horizontalPadding - AppBarIconSurface.bareReach),
      ),
      child: Row(
        children: [
          IconButton(
            iconSize: 24.ic,
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_back_ios_new_outlined, size: 24.ic),
          ),
          Expanded(
            child: Center(child: CategoryDropdown(constrainWidth: false)),
          ),
          TournamentMenuButton(tourData: data, boxed: false),
        ],
      ),
    );
  }

  Widget _buildErrorAppBar(BuildContext context, String errorMessage) {
    return Row(
      children: [
        SizedBox(width: 16.w),
        IconButton(
          iconSize: 24.ic,
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_ios_new_outlined, size: 24.ic),
        ),
        const Spacer(),
        Text(
          errorMessage,
          style: AppTypography.textMdRegular.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
        const Spacer(),
        SizedBox(width: 44.w),
      ],
    );
  }
}

class _LoadingAppBarWithTitle extends StatelessWidget {
  const _LoadingAppBarWithTitle({required this.title, this.loading = true});

  final String title;

  /// False for the error bar, which must read as text, not a shimmer.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.textMdRegular.copyWith(
        color: context.colors.textPrimary,
      ),
    );
    return Row(
      children: [
        SizedBox(width: 20.ic),
        IconButton(
          iconSize: 24.ic,
          padding: EdgeInsets.zero,
          onPressed: () {
            try {
              Navigator.of(context).pop();
            } catch (e) {
              debugPrint('Error navigating back from loading state: $e');
            }
          },
          icon: Icon(Icons.arrow_back_ios_new_outlined, size: 24.ic),
        ),
        SizedBox(width: 44.w),
        Flexible(child: loading ? SkeletonWidget(child: text) : text),
        SizedBox(width: 44.w),
      ],
    );
  }
}

const _mappedName = {
  TournamentDetailScreenMode.about: 'About',
  TournamentDetailScreenMode.games: 'Games',
  TournamentDetailScreenMode.bracket: 'Bracket',
  TournamentDetailScreenMode.standings: 'Standings',
  TournamentDetailScreenMode.players: 'Players',
};

/// The header while a tab is being searched: a way back and the field, and
/// nothing else. The tab itself fills the page under it, filtered as the
/// reader types (Games by players, openings and rounds; Standings and
/// Players by name).
class _EventSearchHeader extends StatelessWidget {
  const _EventSearchHeader({required this.focusNode, required this.onClose});

  final FocusNode focusNode;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final side = ResponsiveHelper.adaptive(phone: 20.sp, tablet: 32.sp);
    return Padding(
      // The chevron's glyph lands on the gutter; its 44pt target reaches
      // into it.
      // Never negative: a folded Duo pane is narrower than the gutter.
      padding: EdgeInsetsDirectional.fromSTEB(
        math.max(0.0, side - 12),
        4.h,
        side,
        10.h,
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 44,
            child: IconButton(
              key: const ValueKey('event_search_close'),
              tooltip: 'Close search',
              padding: EdgeInsets.zero,
              onPressed: () {
                HapticFeedbackService.navigation();
                onClose();
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
                child: EventSearchBar(focusNode: focusNode, autofocus: true),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The single-category Games list still shows a search's hits. Closing the
/// search leaves them up until the list of every game is rebuilt; Combined
/// drops its search with the query, at once.
bool _listHoldsSearchHits(EventProviderReader read) =>
    !read(combinedCategorySelectedProvider) &&
    read(
      gamesTourScreenProvider.select(
        (screen) => screen.valueOrNull?.isSearchMode ?? false,
      ),
    );

/// The event's floating buttons for the tab in view.
///
/// Games: the search (the tab's full-page search) and, above it only while
/// a game is in play, Live first. Standings: the search and
/// Botvinnik above it. Players: the search. About: Botvinnik. Bracket keeps
/// its corner for the canvas's zoom controls. Botvinnik stays on About and
/// Standings only (Trello #1420); everywhere else it has its own tab.
class _EventFabs extends ConsumerWidget {
  const _EventFabs({
    required this.mode,
    required this.searching,
    required this.onSearch,
    required this.chatContext,
  });

  final TournamentDetailScreenMode mode;
  final bool searching;
  final VoidCallback onSearch;
  final ChatScreenContext chatContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (searching) return const SizedBox.shrink();
    final botvinnik = ref.watch(botvinnikTabAvailableProvider);
    Widget chat() => BotvinnikChatButton(
      heroTag: 'botvinnik-tournament',
      screenContext: chatContext,
      iconOnly: true,
    );
    final search = SearchInkFab(
      key: const ValueKey('event_search_fab'),
      label: mode == TournamentDetailScreenMode.games
          ? 'Search games'
          : 'Search players',
      onTap: onSearch,
    );
    switch (mode) {
      case TournamentDetailScreenMode.bracket:
        return const SizedBox.shrink();
      case TournamentDetailScreenMode.about:
        return botvinnik ? chat() : const SizedBox.shrink();
      case TournamentDetailScreenMode.players:
        return search;
      case TournamentDetailScreenMode.standings:
        return InkFabStack(children: [if (botvinnik) chat(), search]);
      case TournamentDetailScreenMode.games:
        final liveFirst = ref.watch(eventGamesLiveFirstProvider);
        final anyLive = ref.watch(eventGamesAnyLiveProvider);
        // Just after the search closes the list still holds its hits. Live
        // first waits for every game: what is live among the hits says
        // nothing of the event, and a press would run the closed query again.
        final holdsHits = _listHoldsSearchHits(ref.watch);
        // Here Live first hides the finished games. Left on after the last
        // live game ended, it would keep them hidden behind a button that is
        // no longer shown: once the list has loaded with nothing live, it
        // turns itself off.
        if (!holdsHits && ref.watch(eventGamesLiveFirstStrandedProvider)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted &&
                !_listHoldsSearchHits(ref.read) &&
                ref.read(eventGamesLiveFirstStrandedProvider)) {
              pressEventGamesLiveFirst(ref.read);
            }
          });
        }
        return InkFabStack(
          children: [
            // Only while a game is in play (Trello #1420).
            if (anyLive && !holdsHits)
              LiveFirstInkFab(
                key: const ValueKey('event_live_first_fab'),
                on: liveFirst,
                onTap: () {
                  if (pressEventGamesLiveFirst(ref.read) ==
                      EventLiveFirstPress.nothingLive) {
                    showAppSnack(context, kNoLiveGamesRightNowMessage);
                  }
                },
              ),
            search,
          ],
        );
    }
  }
}
