import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_display_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_tour_screen.dart';
import 'package:chessever2/screens/tour_detail/about_tour_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/views/games_tour_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
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
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
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

  /// Latched once a team event is detected. Team-ness is structural, so the
  /// tab layout (3 vs 4 tabs) must NOT flip back when `tourDetailScreenProvider`
  /// transiently re-emits loading (it recreates whenever the selected broadcast
  /// re-emits). Without this latch, `itemCount` churns 4→3→4 and the PageView +
  /// tab strip rebuild, losing page and scroll state in every tab.
  bool _isTeamEvent = false;

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
      task: () {
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
        final aboutTourModel = tourDetailAsync.valueOrNull?.aboutTourModel;
        if (aboutTourModel != null) {
          // Use refreshGames() instead of invalidate() to preserve current state
          // while fetching fresh data in the background
          try {
            ref
                .read(gamesTourProvider(aboutTourModel.id).notifier)
                .refreshGames();
          } catch (e) {
            debugPrint(
              '🔥 TournamentDetail: Error refreshing games on resume: $e',
            );
          }
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
    final initialPage = TournamentDetailScreenMode.values.indexOf(
      ref.read(selectedTourModeProvider),
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

          // Team events get a 4th ("Players") tab and a horizontally
          // scrollable tab strip. Detection keys off the format string, so it
          // resolves before games load. Latch it (see [_isTeamEvent]) so a
          // transient tourDetail reload can't collapse the layout back to 3
          // tabs and wipe every tab's state.
          final tourId = tourDetailAsync.valueOrNull?.aboutTourModel.id;
          if (!_isTeamEvent && tourId != null && tourId.isNotEmpty) {
            final detected = scopedRef.watch(isTeamEventProvider(tourId));
            if (detected) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_isTeamEvent) {
                  setState(() => _isTeamEvent = true);
                }
              });
            }
          }
          final isTeam = _isTeamEvent;
          final visibleModes = _visibleModes(isTeam);

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
                              selectedTourMode,
                              isTeam,
                            ),
                        error: (error, stackTrace) => _buildErrorAppBar(error),
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
                            itemCount: visibleModes.length,
                            onPageChanged: _handlePageChanged,
                            itemBuilder: (context, index) {
                              if (index >= visibleModes.length) {
                                return const SizedBox.shrink();
                              }
                              switch (visibleModes[index]) {
                                case TournamentDetailScreenMode.about:
                                  return AboutTourScreen();
                                case TournamentDetailScreenMode.games:
                                  return GamesTourScreen();
                                case TournamentDetailScreenMode.standings:
                                  // Team events: team table (no standings-image
                                  // share nudge — the individual standings the
                                  // nudge shares now live on the Players tab).
                                  if (isTeam) {
                                    return const TeamStandingsScreen();
                                  }
                                  return ScreenshotShareNudge(
                                    enabled:
                                        selectedTourMode ==
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
                                        selectedTourMode ==
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
    bool isTeam,
  ) {
    return Column(
      children: [
        selectedTourMode == TournamentDetailScreenMode.games
            ? const GamesAppBarWidget()
            : _TourDetailDropDownAppBar(data: data),
        SizedBox(height: 8.h),
        _PinnedEventSearchBar(
          pageController: pageController,
          fallbackPage: selectedTourMode.index.toDouble(),
        ),
        _buildSegmentedSwitcher(
          selectedTourMode,
          isTeam,
          (index) => _handleTabSelection(index),
        ),
      ],
    );
  }

  Widget _buildErrorAppBar(Object error) {
    return Column(
      children: [
        _LoadingAppBarWithTitle(title: userFacingError(error)),
        SizedBox(height: 8.h),
        _buildSegmentedSwitcher(
          TournamentDetailScreenMode.games,
          false,
          (index) {},
        ),
      ],
    );
  }

  Widget _buildSegmentedSwitcher(
    TournamentDetailScreenMode selectedTourMode,
    bool isTeam,
    ValueChanged<int> onChanged,
  ) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );
    final modes = _visibleModes(isTeam);
    final options = modes.map((m) => _mappedName[m]!).toList();
    final selectedIndex = modes.indexOf(selectedTourMode);
    final safeIndex = selectedIndex >= 0 ? selectedIndex : 0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: SegmentedSwitcher(
        // Team layouts scroll; keying by count keeps a stable element per
        // layout while `currentSelection` drives the selected tab (and its
        // auto-centering) without a per-frame UniqueKey rebuild.
        key: ValueKey('tab_switcher_${options.length}'),
        options: options,
        initialSelection: safeIndex,
        currentSelection: safeIndex,
        onSelectionChanged: onChanged,
        notifyOnReselect: true,
        isScrollable: isTeam,
      ),
    );
  }

  void _handleTabSelection(int index) {
    try {
      final currentIndex = TournamentDetailScreenMode.values.indexOf(
        ref.read(selectedTourModeProvider),
      );
      if (index == currentIndex) {
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
        ref
            .read(selectedTourModeProvider.notifier)
            .update((_) => TournamentDetailScreenMode.values[index]);
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

  void _handlePageChanged(int index) {
    try {
      // Update the selected mode when page changes (from swiping)
      final currentModeIndex = TournamentDetailScreenMode.values.indexOf(
        ref.read(selectedTourModeProvider),
      );

      if (currentModeIndex != index) {
        FocusScope.of(context).unfocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref
              .read(selectedTourModeProvider.notifier)
              .update((_) => TournamentDetailScreenMode.values[index]);
        });
      }
    } catch (e) {
      debugPrint('Error handling page change: $e');
    }
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
          const GlassBackButton(),
          Expanded(
            child: Center(child: CategoryDropdown(constrainWidth: false)),
          ),
          TournamentMenuButton(tourData: data),
        ],
      ),
    );
  }

  Widget _buildErrorAppBar(BuildContext context, String errorMessage) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: Row(
        children: [
          const GlassBackButton(),
          Expanded(
            child: Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: AppTypography.textMdRegular.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _LoadingAppBarWithTitle extends StatelessWidget {
  const _LoadingAppBarWithTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            GlassBackButton(
              onPressed: () {
                try {
                  Navigator.of(context).pop();
                } catch (e) {
                  debugPrint('Error navigating back from loading state: $e');
                }
              },
            ),
            Expanded(
              child: Center(
                child: SkeletonWidget(
                  child: Text(
                    title,
                    style: AppTypography.textMdRegular.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}

const _mappedName = {
  TournamentDetailScreenMode.about: 'About',
  TournamentDetailScreenMode.games: 'Games',
  TournamentDetailScreenMode.standings: 'Standings',
  TournamentDetailScreenMode.players: 'Players',
};

/// The tabs shown for the current event. Team events add a 4th ("Players")
/// tab; every list is a prefix of [TournamentDetailScreenMode.values] so the
/// existing `values[index]` index→mode mapping stays valid.
List<TournamentDetailScreenMode> _visibleModes(bool isTeam) =>
    isTeam
        ? const [
          TournamentDetailScreenMode.about,
          TournamentDetailScreenMode.games,
          TournamentDetailScreenMode.standings,
          TournamentDetailScreenMode.players,
        ]
        : const [
          TournamentDetailScreenMode.about,
          TournamentDetailScreenMode.games,
          TournamentDetailScreenMode.standings,
        ];

/// Search bar pinned above the About/Games/Standings tab switcher.
///
/// Hidden on About (search is a no-op there) and visible on Games/Standings.
/// Drives its height and opacity directly from [pageController.page] so the
/// reveal/collapse tracks the swipe finger in real time and smoothly chases
/// `animateToPage` when a tab is tapped — no two-stage "page settles, then
/// search bar pops" feel.
class _PinnedEventSearchBar extends StatelessWidget {
  const _PinnedEventSearchBar({
    required this.pageController,
    required this.fallbackPage,
  });

  final PageController pageController;
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
        // page 0 == About (hidden); page 1+ == Games/Standings (fully shown).
        final t = page.clamp(0.0, 1.0);
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
