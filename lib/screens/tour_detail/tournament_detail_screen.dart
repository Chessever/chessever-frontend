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
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_app_bar_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/category_dropdown.dart';
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
      ref.invalidate(liveFocusSnapshotProvider);
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
                  child: Column(
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).viewPadding.top + 4.h,
                      ),
                      tourDetailAsync.when(
                        data:
                            (data) => _buildSuccessAppBar(
                              data,
                              effectiveMode,
                              visibleModes,
                            ),
                        error:
                            (error, stackTrace) => _buildErrorAppBar(
                              error,
                              effectiveMode,
                              visibleModes,
                            ),
                        loading:
                            () => const _LoadingAppBarWithTitle(
                              title: "ChessEver",
                            ),
                      ),
                      Expanded(
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
                            onPageChanged:
                                (index) =>
                                    _handlePageChanged(index, visibleModes),
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

  Widget _buildSuccessAppBar(
    TourDetailViewModel data,
    TournamentDetailScreenMode selectedTourMode,
    List<TournamentDetailScreenMode> visibleModes,
  ) {
    final writerLabel = ref.watch(
      selectedBroadcastWriterAttributionProvider,
    );
    return Column(
      children: [
        selectedTourMode == TournamentDetailScreenMode.games
            ? const GamesAppBarWidget()
            : _TourDetailDropDownAppBar(data: data),
        Padding(
          padding: EdgeInsets.only(top: 2.h),
          child: Text(
            writerLabel,
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.52),
            ),
          ),
        ),
        SizedBox(height: 8.h),
        _PinnedEventSearchBar(
          pageController: pageController,
          visibleModes: visibleModes,
          fallbackPage:
              tournamentDetailPageForMode(
                visibleModes,
                selectedTourMode,
              ).toDouble(),
        ),
        _buildSegmentedSwitcher(
          selectedTourMode,
          visibleModes,
          (index) => _handleTabSelection(index, visibleModes),
        ),
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
        _LoadingAppBarWithTitle(title: userFacingError(error)),
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
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
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
          TournamentMenuButton(tourData: data),
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
  const _LoadingAppBarWithTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
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
        SkeletonWidget(
          child: Text(
            title,
            style: AppTypography.textMdRegular.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
        ),
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

/// Search bar pinned above the tournament-detail tab switcher.
///
/// Hidden on About and Bracket; visible on Games, Standings, and Players.
/// Drives its height and opacity directly from [pageController.page] so the
/// reveal/collapse tracks the swipe finger in real time and smoothly chases
/// `animateToPage` when a tab is tapped — no two-stage "page settles, then
/// search bar pops" feel.
class _PinnedEventSearchBar extends StatelessWidget {
  const _PinnedEventSearchBar({
    required this.pageController,
    required this.visibleModes,
    required this.fallbackPage,
  });

  final PageController pageController;
  final List<TournamentDetailScreenMode> visibleModes;
  final double fallbackPage;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );
    return AnimatedBuilder(
      animation: pageController,
      builder: (context, child) {
        final page =
            pageController.hasClients
                ? (pageController.page ?? fallbackPage)
                : fallbackPage;
        final t = tournamentDetailSearchVisibility(visibleModes, page);
        if (t <= 0.0) {
          return const SizedBox.shrink();
        }
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: t,
            child: Opacity(opacity: t, child: child),
          ),
        );
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: const EventSearchBar(),
      ),
    );
  }
}
