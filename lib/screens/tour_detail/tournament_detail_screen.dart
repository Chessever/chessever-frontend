import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
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
import 'package:chessever2/screens/tour_detail/games_tour/views/games_tour_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_tabs.dart';
import 'package:chessever2/utils/share_standings.dart';
import 'package:chessever2/widgets/screenshot_share_nudge.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/category_dropdown.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_search_bar.dart';
import 'package:chessever2/screens/tour_detail/widgets/tournament_menu_button.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/foreground_task_scheduler.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/liquid_glass/chrome_scroll_collapse.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/liquid_tab_bar.dart';
import 'package:chessever2/widgets/liquid_glass/liquid_glass_halo.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TournamentDetailScreen extends ConsumerStatefulWidget {
  const TournamentDetailScreen({super.key});

  @override
  ConsumerState<TournamentDetailScreen> createState() =>
      _TournamentDetailViewState();
}

class _TournamentDetailViewState extends ConsumerState<TournamentDetailScreen>
    with RouteAware, WidgetsBindingObserver {
  late PageController pageController;
  late final String _scrollScopeId;
  final ScrollToTopBus _scrollToTopBus = ScrollToTopBus();
  final ChromeScrollCollapse _chromeCollapse = ChromeScrollCollapse();

  final TournamentDetailLayoutTracker _layoutTracker =
      TournamentDetailLayoutTracker();
  late List<TournamentDetailScreenMode> _renderedModes;

  @override
  void didPush() {
    markGamesTourScrollScopeActive(_scrollScopeId);
    Future.microtask(() {
      debugPrint('🔥 TournamentDetail: didPush - enabling streaming');
      ref.read(shouldStreamProvider.notifier).state = true;
    });
    super.didPush();
  }

  @override
  void didPop() {
    clearGamesTourScrollScopeActive(_scrollScopeId);
    Future.microtask(() {
      debugPrint('🔥 TournamentDetail: didPop - disabling streaming');
      ref.read(shouldStreamProvider.notifier).state = false;
    });
    super.didPop();
  }

  @override
  void didPopNext() {
    markGamesTourScrollScopeActive(_scrollScopeId);
    Future.microtask(() {
      debugPrint('🔥 TournamentDetail: didPopNext - enabling streaming');
      ref.read(shouldStreamProvider.notifier).state = true;
      ref.invalidate(gameUpdatesStreamProvider);
      ref.invalidate(liveGameUpdateStreamProvider);
      ref.invalidate(gameUpdatesBatchStreamProvider);
    });
    super.didPopNext();
  }

  @override
  void didPushNext() {
    clearGamesTourScrollScopeActive(_scrollScopeId);
    Future.microtask(() {
      debugPrint(
        '🔥 TournamentDetail: didPushNext - disabling streaming while off-screen',
      );
      // Disable streaming when navigating to sub-screens (e.g., chessboard)
      // to prevent unnecessary periodic fetches and logs.
      ref.read(shouldStreamProvider.notifier).state = false;
    });
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
          final representedTourIds = representedTournamentIdsForDisplayRounds(
            rounds: rounds,
            selectedTourId: aboutTourModel.id,
            knownTourIds:
                tourDetail?.tours.map((tour) => tour.tour.id) ??
                const <String>[],
          );
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
      ref.invalidate(tourDetailScreenProvider);
      ref.invalidate(gamesAppBarProvider);
      ref.invalidate(gamesTourScreenProvider);
      ref.invalidate(gameDisplayModeProvider);
      ref.invalidate(playerTourScreenProvider);
      ref.invalidate(searchQueryProvider);
      ref.invalidate(eventBottomSearchExpandedProvider);
      // Scroll provider is scoped per screen; it will dispose with the ProviderScope below.
    } catch (e) {
      // Ignore errors during cleanup
      debugPrint('Error during provider cleanup: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    clearGamesTourScrollScopeActive(_scrollScopeId);
    ForegroundTaskScheduler.cancel('tournament_detail_resume_$hashCode');
    pageController.dispose();
    _scrollToTopBus.dispose();
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
          final tourId = tourDetailAsync.valueOrNull?.aboutTourModel.id;
          final previousTourId = _layoutTracker.activeTourId;
          final knockoutState =
              tourId == null || tourId.isEmpty
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
          final layout =
              hasResolvedTour
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

          final topInset = MediaQuery.of(context).viewPadding.top;
          final bottomInset = MediaQuery.of(context).viewPadding.bottom;
          return ScreenWrapper(
            child: Scaffold(
              key: e2eKey(E2eIds.tournamentDetailRoot),
              body: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth:
                        ResponsiveHelper.isTablet
                            ? ResponsiveHelper.contentMaxWidth
                            : double.infinity,
                  ),
                  child: Stack(
                    children: [
                      // Content owns the WHOLE screen and scrolls UNDER the
                      // floating chrome (each tab list carries its own top/bottom
                      // scroll padding so the first/last rows rest clear).
                      Positioned.fill(
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification is! ScrollUpdateNotification) {
                              return false;
                            }
                            if (_chromeCollapse.onScrollUpdate(notification) &&
                                mounted) {
                              setState(() {});
                            }
                            return false;
                          },
                          child: ScrollToTopScope(
                            bus: _scrollToTopBus,
                            child: PageView.builder(
                              controller: pageController,
                              physics:
                                  effectiveMode ==
                                          TournamentDetailScreenMode.bracket
                                      ? const NeverScrollableScrollPhysics()
                                      : null,
                              itemCount: visibleModes.length,
                              onPageChanged: (index) {
                                _handlePageChanged(index, visibleModes);
                                if (!_chromeCollapse.expanded) {
                                  setState(_chromeCollapse.reset);
                                }
                              },
                              itemBuilder: (context, index) {
                                if (index >= visibleModes.length) {
                                  return const SizedBox.shrink();
                                }
                                switch (visibleModes[index]) {
                                  case TournamentDetailScreenMode.about:
                                    return AboutTourScreen();
                                  case TournamentDetailScreenMode.games:
                                    return GamesTourScreen();
                                  case TournamentDetailScreenMode.bracket:
                                    return const KnockoutBracketScreen();
                                  case TournamentDetailScreenMode.standings:
                                    // Team events: team table (no standings-image
                                    // share nudge — the individual standings the
                                    // nudge shares now live on the Players tab).
                                    if (isTeam) {
                                      return const TeamStandingsScreen();
                                    }
                                    return ScreenshotShareNudge(
                                      enabled:
                                          effectiveMode ==
                                          TournamentDetailScreenMode.standings,
                                      onShare:
                                          () => shareTournamentStandings(
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
                                      onShare:
                                          () => shareTournamentStandings(
                                            context,
                                            scopedRef,
                                          ),
                                      child: PlayerTourScreen(),
                                    );
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      // Readability scrims. The content scrolls edge-to-edge
                      // under the floating chrome; these soft gradient bands sit
                      // between the page and the glass so the top (back/tabs) and
                      // bottom (category pill + search) islands never dissolve
                      // into bright board rows behind them.
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Container(
                            height:
                                topInset +
                                MediaQuery.of(context).size.height * 0.10,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  context.colors.background.withValues(
                                    alpha: 0.9,
                                  ),
                                  context.colors.background.withValues(
                                    alpha: 0.0,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Container(
                            height: MediaQuery.of(context).size.height * 0.15,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  context.colors.background.withValues(
                                    alpha: 0.0,
                                  ),
                                  context.colors.background.withValues(
                                    alpha: 0.92,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Top floating bar: back + mode tabs + menu (one line).
                      Positioned(
                        top: topInset + 8,
                        left: 0,
                        right: 0,
                        child: _buildTopFloating(
                          tourDetailAsync,
                          effectiveMode,
                          visibleModes,
                        ),
                      ),
                      // Bottom floating: category pill (centre) + search (right).
                      Positioned(
                        bottom: bottomInset + 16,
                        left: 0,
                        right: 0,
                        child: _buildBottomFloating(
                          tourDetailAsync,
                          effectiveMode,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Top floating bar — back button, the About/Games/Standings tabs, and the
  /// tournament menu. One line.
  Widget _buildTopFloating(
    AsyncValue<TourDetailViewModel> async,
    TournamentDetailScreenMode selectedTourMode,
    List<TournamentDetailScreenMode> visibleModes,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: Row(
        children: [
          // Left cluster: back + menu. Kept together so the mode chips own the
          // right corner (consistent with the home header's top-right tabs).
          const LiquidGlassHalo(borderRadius: 20, child: GlassBackButton()),
          async.maybeWhen(
            data: (data) {
              if (data.tours.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: LiquidGlassHalo(
                  borderRadius: 20,
                  child: TournamentMenuButton(tourData: data),
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
          const Spacer(),
          // Mode chips, shrink-wrapped and pinned to the right corner.
          _buildSegmentedSwitcher(
            selectedTourMode,
            visibleModes,
            (index) => _handleTabSelection(index, visibleModes),
          ),
        ],
      ),
    );
  }

  /// Bottom floating chrome — the bulky category-selector pill (centre) and the
  /// search button (right, Games tab only). Scales down while scrolling, like
  /// the bottom nav.
  Widget _buildBottomFloating(
    AsyncValue<TourDetailViewModel> async,
    TournamentDetailScreenMode selectedTourMode,
  ) {
    final showSearch = selectedTourMode == TournamentDetailScreenMode.games;
    // Home-style in-place morph: while the search is open the category pill
    // collapses out and the search field spans the whole bottom width.
    final searchExpanded =
        showSearch && ref.watch(eventBottomSearchExpandedProvider);
    final categorySelector = async.maybeWhen(
      data: (data) {
        if (data.tours.isEmpty) return const SizedBox.shrink();
        return const LiquidGlassHalo(
          borderRadius: 20,
          child: CategoryDropdown(constrainWidth: true),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );

    return AnimatedScale(
      scale: _chromeCollapse.expanded ? 1.0 : 0.9,
      alignment: Alignment.bottomCenter,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        child: Row(
          children: [
            if (!searchExpanded) ...[
              // Left spacer balances the trailing search button so the pill
              // stays visually centred. Matches the bulky 64px search circle.
              const SizedBox(width: 64),
              Expanded(child: Center(child: categorySelector)),
            ],
            if (showSearch)
              searchExpanded
                  ? const Expanded(
                      child: LiquidGlassHalo(
                        borderRadius: 25,
                        child: EventSearchBar(),
                      ),
                    )
                  : const SizedBox(
                      width: 64,
                      child: LiquidGlassHalo(
                        borderRadius: 32,
                        child: EventSearchBar(),
                      ),
                    ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentedSwitcher(
    TournamentDetailScreenMode selectedTourMode,
    List<TournamentDetailScreenMode> modes,
    ValueChanged<int> onChanged,
  ) {
    final options = modes.map((m) => _mappedName[m]!).toList();
    final icons = modes.map((m) => _modeIcon[m] ?? CupertinoIcons.circle).toList();
    final selectedIndex = modes.indexOf(selectedTourMode);
    final safeIndex = selectedIndex >= 0 ? selectedIndex : 0;
    // Identical to the home header tabs: bare LiquidTabBar — glued at the top of
    // the list, loosening into gapped icon chips on scroll-down. Same widget,
    // same motion, same brand-bubble selection.
    return LiquidTabBar(
      key: ValueKey('tab_switcher_${modes.map((mode) => mode.name).join('_')}'),
      options: options,
      icons: icons,
      selectedIndex: safeIndex,
      onSelected: onChanged,
      separated: !_chromeCollapse.expanded,
    );
  }

  void _handleTabSelection(
    int index,
    List<TournamentDetailScreenMode> visibleModes,
  ) {
    try {
      final selectedMode = tournamentDetailModeForPage(visibleModes, index);
      final currentMode = ref.read(selectedTourModeProvider);
      // Collapse the search morph when leaving Games so it doesn't linger open.
      if (selectedMode != TournamentDetailScreenMode.games) {
        ref.read(eventBottomSearchExpandedProvider.notifier).state = false;
      }
      if (selectedMode == currentMode) {
        _scrollToTopBus.request();
        if (!_chromeCollapse.expanded) {
          setState(_chromeCollapse.reset);
        }
        return;
      }
      if (!_chromeCollapse.expanded) {
        setState(_chromeCollapse.reset);
      }
      // Drop the keyboard when leaving the search-enabled tabs so the field
      // and the keyboard collapse together, instead of the keyboard hovering
      // over About after a swipe.
      FocusScope.of(context).unfocus();
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

      if (nextMode != TournamentDetailScreenMode.games) {
        ref.read(eventBottomSearchExpandedProvider.notifier).state = false;
      }
      if (currentMode != nextMode) {
        FocusScope.of(context).unfocus();
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

const _mappedName = {
  TournamentDetailScreenMode.about: 'About',
  TournamentDetailScreenMode.games: 'Games',
  TournamentDetailScreenMode.bracket: 'Bracket',
  TournamentDetailScreenMode.standings: 'Standings',
  TournamentDetailScreenMode.players: 'Players',
};

/// Per-mode icon revealed when the tabs separate on scroll (mirrors the home
/// header's `_categoryIcon`).
const _modeIcon = {
  TournamentDetailScreenMode.about: CupertinoIcons.info,
  TournamentDetailScreenMode.games: CupertinoIcons.square_grid_2x2,
  TournamentDetailScreenMode.bracket: CupertinoIcons.square_split_1x2,
  TournamentDetailScreenMode.standings: CupertinoIcons.list_number,
  TournamentDetailScreenMode.players: CupertinoIcons.person_2,
};
