import 'dart:async';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/services/native_ads_config.dart';
import 'package:chessever2/services/home_ad_remote_config.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/widgets/ads/today_native_ad.dart';

import 'package:chessever2/main.dart' show pageRouteObserver;
import 'package:chessever2/providers/for_you_games_logic.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/for_you/open_for_you_event.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/group_event/widget/premium_collection_cards.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/foreground_task_scheduler.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessever2/widgets/paywall/past_game_access.dart';
import 'package:chessever2/widgets/layout_swap_scroll_keeper.dart';
import 'package:flutter/material.dart';
// Stable Flutter's material.dart does not export this type (only newer SDKs
// do), so it is imported explicitly, as in lib/utils/scroll_cache.dart.
// ignore: unnecessary_import
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart' show Bone;
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';

// Cache ~1.5 viewports for the compact card feed and ~1 viewport for the
// heavier board feed. The previous fixed 360/180px extents were smaller than a
// single event section, so sections reloaded from scratch on scroll-back.
const ScrollCacheExtent _kForYouCompactCacheExtent = ScrollCacheExtent.viewport(
  1.5,
);
const ScrollCacheExtent _kForYouBoardCacheExtent = ScrollCacheExtent.viewport(
  1.0,
);

ScrollCacheExtent _forYouCacheExtentForMode(GamesListViewMode mode) {
  return mode == GamesListViewMode.gamesCard
      ? _kForYouCompactCacheExtent
      : _kForYouBoardCacheExtent;
}

LiveGamesBatchKey _forYouLiveBatchKey({
  required String eventId,
  required String tourId,
  required List<GamesTourModel> games,
}) {
  return LiveGamesBatchKey(
    scopeId: 'for_you:$eventId:$tourId',
    gameIds: games.where(shouldSubscribeToLiveGame).map((game) => game.gameId),
  );
}

Future<void> _openForYouGame(
  BuildContext context,
  WidgetRef ref,
  List<GamesTourModel> games,
  int index,
) async {
  if (index < 0 || index >= games.length || !context.mounted) return;
  final allowed = await ensurePastGameAccess(context, game: games[index]);
  if (!allowed || !context.mounted) return;
  ref
      .read(gameCardWrapperProvider)
      .navigateToChessBoard(
        context: context,
        orderedGames: games,
        gameIndex: index,
        onReturnFromChessboard: (_) {},
        viewSource: ChessboardView.forYou,
      );
}

/// For You tab widget - displays events with their top 4 games
///
/// KEY DESIGN:
/// - Events are selected by the backend feed RPC
/// - Games come from one batched highest-category latest-round top-board RPC
/// - Heart counts come from one batched event-level favorite-player RPC
/// - Always up to 4 games per event
class ForYouGamesWidget extends ConsumerStatefulWidget {
  const ForYouGamesWidget({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  ConsumerState<ForYouGamesWidget> createState() => _ForYouGamesWidgetState();
}

class _ForYouGamesWidgetState extends ConsumerState<ForYouGamesWidget>
    with WidgetsBindingObserver, RouteAware, AutomaticKeepAliveClientMixin {
  late final StateController<bool> _surfaceVisibility;
  PageRoute<dynamic>? _pageRoute;
  bool _routeSubscribed = false;
  bool _isSubscribingToRoute = false;
  bool _routeIsCurrent = true;
  bool _appIsResumed = true;
  bool _isDisposing = false;

  @override
  void initState() {
    super.initState();
    _surfaceVisibility = ref.read(forYouSurfaceVisibleProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    widget.scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _publishSurfaceVisibility();
      Future<void>.microtask(_refreshRealtimeGamesNow);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    // Subscribe to the enclosing PAGE route only. pageRouteObserver ignores
    // transient popups (the share/copy-pgn menu, dialogs, sheets) so they no
    // longer blank this tab; only a real page push (tournament/board) does.
    if (route is! PageRoute) return;
    _pageRoute = route;
    _routeIsCurrent = route.isCurrent;
    // RouteObserver.subscribe invokes didPush synchronously. Since this method
    // runs during the widget build lifecycle, publishing from that callback
    // would mutate Riverpod while the tree is building. The initState
    // post-frame callback performs the initial publication instead.
    _isSubscribingToRoute = true;
    try {
      pageRouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    } finally {
      _isSubscribingToRoute = false;
    }
  }

  @override
  void dispose() {
    _isDisposing = true;
    // Riverpod forbids provider mutations from dispose. Queue the cleanup so
    // it runs after this tree update; a replacement widget publishes its own
    // visibility in the subsequent post-frame callback.
    unawaited(
      Future<void>.microtask(() {
        if (!_surfaceVisibility.mounted) return;
        if (_surfaceVisibility.state) {
          _surfaceVisibility.state = false;
        }
      }),
    );
    widget.scrollController.removeListener(_onScroll);
    if (_routeSubscribed) {
      pageRouteObserver.unsubscribe(this);
    }
    _pageRoute = null;
    ForegroundTaskScheduler.cancel('for_you_games_route_return_$hashCode');
    ForegroundTaskScheduler.cancel('for_you_games_resume_$hashCode');
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didPush() {
    if (_isSubscribingToRoute) return;
    _setRouteActive(true, refreshNow: true);
  }

  @override
  void didPopNext() {
    _setRouteActive(true, refreshNow: true);
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
      ForegroundTaskScheduler.cancel('for_you_games_resume_$hashCode');
      _setAppResumed(false);
      return;
    }
    if (!mounted) return;

    _setAppResumed(true);
    ForegroundTaskScheduler.schedule(
      key: 'for_you_games_resume_$hashCode',
      task: _refreshRealtimeGamesNow,
    );
  }

  // Keep rendering while the app is backgrounded so the OS app-switcher
  // snapshot still shows the current cards. Route coverage is what should
  // remove this tab from the tree.
  bool get _isActiveOnScreen => _routeIsCurrent;

  void _setRouteActive(bool isActive, {bool refreshNow = false}) {
    if (!mounted) return;
    if (_routeIsCurrent != isActive) {
      setState(() => _routeIsCurrent = isActive);
    }
    _publishSurfaceVisibility();
    if (!isActive) {
      _stopTransientWork();
    } else if (refreshNow) {
      ForegroundTaskScheduler.schedule(
        key: 'for_you_games_route_return_$hashCode',
        task: () => _refreshRealtimeGamesNow(resetStreams: false),
      );
    }
  }

  void _setAppResumed(bool isResumed) {
    if (!mounted) return;
    if (_appIsResumed != isResumed) {
      setState(() => _appIsResumed = isResumed);
    }
    _publishSurfaceVisibility();
    if (!isResumed) {
      _stopTransientWork();
    }
  }

  void _stopTransientWork() {
    ForegroundTaskScheduler.cancel('for_you_games_route_return_$hashCode');
    ForegroundTaskScheduler.cancel('for_you_games_resume_$hashCode');
  }

  void _publishSurfaceVisibility() {
    if (!mounted || _isDisposing) return;
    final routeIsCurrent = _pageRoute?.isCurrent == true;
    final isVisible =
        _routeIsCurrent &&
        routeIsCurrent &&
        _appIsResumed &&
        ref.read(forYouTodayTabActiveProvider);
    if (_surfaceVisibility.state != isVisible) {
      _surfaceVisibility.state = isVisible;
    }
  }

  void _refreshRealtimeGamesNow({bool resetStreams = true}) {
    if (!mounted || _isDisposing) return;
    if (!_routeIsCurrent || !_appIsResumed) return;
    if (_pageRoute?.isCurrent != true) return;
    if (ref.read(forYouTodayTabActiveProvider)) {
      final wasStreaming = ref.read(shouldStreamProvider);
      if (!wasStreaming) {
        ref.read(shouldStreamProvider.notifier).state = true;
      }
      if (resetStreams || !wasStreaming) {
        ref.invalidate(gameUpdatesStreamProvider);
        ref.invalidate(liveGameUpdateStreamProvider);
        ref.invalidate(gameUpdatesBatchStreamProvider);
      }
      final notifier = ref.read(forYouEventsProvider.notifier);
      unawaited(notifier.refreshForVisibility());
    }
  }

  void _onScroll() {
    if (!mounted || _isDisposing) return;
    if (!widget.scrollController.hasClients) return;
    final max = widget.scrollController.position.maxScrollExtent;
    final current = widget.scrollController.position.pixels;
    if (max - current <= 300) {
      ref.read(forYouEventsProvider.notifier).loadMore();
    }
  }

  @override
  bool get wantKeepAlive => false;

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin

    // If PageView keeps this page around briefly while swiping, drop all
    // expensive provider subscriptions until For You > Today is visible again.
    final isTodayTabActive = ref.watch(forYouTodayTabActiveProvider);
    ref.listen<bool>(forYouTodayTabActiveProvider, (_, __) {
      _publishSurfaceVisibility();
    });
    if (!isTodayTabActive || !_isActiveOnScreen) {
      return const SizedBox.shrink();
    }

    final state = ref.watch(forYouEventsProvider);
    final viewMode = ref.watch(gamesListViewModeProvider);
    final events = state.events;
    final showNativeAd = NativeAdsConfig.available &&
        ref.watch(homeNativeAdEnabledProvider) &&
        events.length >= 2 &&
        !ref.watch(subscriptionProvider.select((s) => s.isLoading)) &&
        !ref.watch(premiumAccessProvider);

    if (state.isLoading && events.isEmpty) {
      return _buildLoadingState();
    }

    if (state.error != null && events.isEmpty) {
      debugPrint('[ForYouGamesWidget] Error: ${state.error}');
      final message = state.error?.trim();
      return GenericErrorWidget(
        message:
            message != null && message.isNotEmpty
                ? userFacingError(message)
                : null,
        onRetry: () => ref.read(forYouEventsProvider.notifier).refresh(),
      );
    }

    // Smart events never appear on Today, starred or filtered: My Space is
    // their only home.

    // Each event section hides itself once its boards resolve empty. When
    // nothing is left to draw and no further page can follow, the list would
    // hold only the collection cards above a blank page; say there is nothing
    // instead.
    final everyEventHidden = ref.watch(
      forYouTopGamesSnapshotCacheProvider.select(
        (snapshots) =>
            events.every((event) => snapshots[event.id]?.hasGames == false),
      ),
    );
    if (everyEventHidden && (events.isEmpty || !state.hasMore)) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(forYouEventsProvider.notifier).refresh(),
      color: context.colors.accentText,
      backgroundColor: context.colors.surface,
      // The phone list and the tablet two-column layout are separate
      // scrollables; iPhone Duo swaps them as it closes and opens.
      child: LayoutSwapScrollKeeper(
        controller: widget.scrollController,
        layout: ResponsiveHelper.isTablet,
        child: _buildEventsList(
          events,
          showNativeAd: showNativeAd,
          viewMode: viewMode,
          showLoadingMore: state.hasMore && !state.isLoading,
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    // On tablet, show grid skeleton
    if (ResponsiveHelper.isTablet) {
      return _buildTabletLoadingSkeleton();
    }

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const PremiumCollectionCards(),
        ...List.generate(
          3,
          (index) => _ForYouEventSkeleton(isFirst: index == 0),
        ),
      ],
    );
  }

  Widget _buildTabletLoadingSkeleton() {
    final horizontalPadding = ResponsiveHelper.isLandscape ? 32.sp : 24.sp;
    final columnSpacing = 16.sp;
    final eventCardAspectRatio = ResponsiveHelper.isLandscape ? 1.8 : 1.4;

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 16.sp,
      ),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const PremiumCollectionCards(),
        // 2-column skeleton rows (2 event pairs)
        ...List.generate(2, (rowIndex) {
          return Padding(
            padding: EdgeInsets.only(top: rowIndex == 0 ? 0 : 20.sp),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left column skeleton
                Expanded(
                  child: _TabletColumnSkeleton(
                    eventCardAspectRatio: eventCardAspectRatio,
                  ),
                ),
                SizedBox(width: columnSpacing),
                // Right column skeleton
                Expanded(
                  child: _TabletColumnSkeleton(
                    eventCardAspectRatio: eventCardAspectRatio,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildEventsList(
    List<GroupEventCardModel> events, {
    bool showNativeAd = false,
    required GamesListViewMode viewMode,
    bool showLoadingMore = false,
  }) {
    // On tablet, use a beautiful grid layout
    if (ResponsiveHelper.isTablet) {
      return _buildTabletGridLayout(
        events,
        showNativeAd: showNativeAd,
        viewMode: viewMode,
        showLoadingMore: showLoadingMore,
      );
    }

    // Phone: vertical list layout
    final horizontalPadding = 16.sp;

    // +1 for premium cards, +1 for loading.
    final itemCount = events.length + 1 + (showLoadingMore ? 1 : 0);

    return ListView.builder(
      key: const PageStorageKey<String>('for_you_events_list'),
      controller: widget.scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 16.sp,
      ),
      itemCount: itemCount,
      scrollCacheExtent: _forYouCacheExtentForMode(viewMode),
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      itemBuilder: (context, index) {
        // Premium collection cards at top
        if (index == 0) {
          return const PremiumCollectionCards();
        }

        // Loading indicator at bottom
        if (showLoadingMore && index == itemCount - 1) {
          return _buildLoadingMoreIndicator();
        }

        final event = events[index - 1];
        if (showNativeAd && index == 1) {
          return Column(
            key: ValueKey('event_${event.id}'),
            children: [
              _ForYouEventSection(event: event, isFirst: true),
              const TodayNativeAd(),
            ],
          );
        }
        return _ForYouEventSection(
          key: ValueKey('event_${event.id}'),
          event: event,
          isFirst: index == 1,
        );
      },
    );
  }

  Widget _buildLoadingMoreIndicator() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 16.sp),
      child: Center(
        child: SizedBox(
          width: 24.sp,
          height: 24.sp,
          child: CircularProgressIndicator(
            strokeWidth: 2.sp,
            color: context.colors.accentText,
          ),
        ),
      ),
    );
  }

  /// Tablet: 2-column grid where each column = event card + its games
  /// Creates a beautiful magazine-style layout that fills tablet width
  /// Uses ListView.builder for lazy, on-demand rendering
  Widget _buildTabletGridLayout(
    List<GroupEventCardModel> events, {
    bool showNativeAd = false,
    required GamesListViewMode viewMode,
    bool showLoadingMore = false,
  }) {
    final horizontalPadding = ResponsiveHelper.isLandscape ? 32.sp : 24.sp;
    final columnSpacing = 16.sp;

    // Number of event-pair rows (ceil division)
    final rowCount = showNativeAd
        ? 1 + events.length ~/ 2
        : (events.length + 1) ~/ 2;
    // +1 for premium cards at top, +1 for loading indicator if showing.
    final itemCount = rowCount + 1 + (showLoadingMore ? 1 : 0);

    return ListView.builder(
      key: const PageStorageKey<String>('for_you_events_tablet_grid'),
      controller: widget.scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 16.sp,
      ),
      itemCount: itemCount,
      scrollCacheExtent: _forYouCacheExtentForMode(viewMode),
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      itemBuilder: (context, index) {
        // Premium collection cards at top
        if (index == 0) {
          return const PremiumCollectionCards();
        }

        // Loading indicator at bottom
        if (showLoadingMore && index == itemCount - 1) {
          return _buildLoadingMoreIndicator();
        }

        final rowIndex = index - 1;
        if (showNativeAd && rowIndex == 0) {
          return Column(
            key: ValueKey('native_first_event_${events.first.id}'),
            children: [
              _ForYouTabletEventColumn(event: events.first),
              const TodayNativeAd(),
            ],
          );
        }
        final i = showNativeAd ? 1 + (rowIndex - 1) * 2 : rowIndex * 2;
        final event1 = events[i];
        final event2 = i + 1 < events.length ? events[i + 1] : null;

        return Padding(
          padding: EdgeInsets.only(top: rowIndex == 0 ? 0 : 20.sp),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left column: event1 + its games
              Expanded(
                child: _ForYouTabletEventColumn(
                  key: ValueKey('tablet_col_${event1.id}'),
                  event: event1,
                ),
              ),
              SizedBox(width: columnSpacing),
              // Right column: event2 + its games (or empty space)
              Expanded(
                child:
                    event2 != null
                        ? _ForYouTabletEventColumn(
                          key: ValueKey('tablet_col_${event2.id}'),
                          event: event2,
                        )
                        : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      children: [
        const PremiumCollectionCards(),
        SizedBox(height: 40.sp),
        Center(
          child: Text(
            'No events available',
            style: TextStyle(
              color: context.colors.textPrimaryMuted,
              fontSize: 14.sp,
            ),
          ),
        ),
      ],
    );
  }
}

/// Skeleton for a single column in the 2-column tablet grid
class _TabletColumnSkeleton extends StatelessWidget {
  const _TabletColumnSkeleton({required this.eventCardAspectRatio});

  final double eventCardAspectRatio;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Event card skeleton
        AspectRatio(
          aspectRatio: eventCardAspectRatio,
          child: _SkeletonBlock(radius: 12.br),
        ),
        SizedBox(height: 10.sp),
        // Game card skeletons (2 rows of 2 = 4 total, matching actual content)
        ...List.generate(2, (rowIndex) {
          return Padding(
            padding: EdgeInsets.only(bottom: 8.sp),
            child: Row(
              children: [
                Expanded(child: _SkeletonBlock(height: 72.sp)),
                SizedBox(width: 8.sp),
                Expanded(child: _SkeletonBlock(height: 72.sp)),
              ],
            ),
          );
        }),
      ],
    );
  }
}

/// Section for one event: event card + 4 game cards.
/// Owns a single shared snapshot for both visibility and content —
/// hides itself only after the snapshot resolves empty.
class _ForYouEventSection extends ConsumerWidget {
  const _ForYouEventSection({
    super.key,
    required this.event,
    required this.isFirst,
  });

  final GroupEventCardModel event;
  final bool isFirst;

  /// Builds the EventCard with proper constraints for tablet
  /// Tablet uses image-as-background layout which needs bounded height
  Widget _buildEventCard(BuildContext context, WidgetRef ref) {
    final eventCard = EventCard(
      tourEventCardModel: event,
      showHeartIndicator: true,
      favoritePlayersSource: EventFavoritePlayersSource.cacheOnly,
      heroTagSuffix: '_foryou',
      onTap:
          () => openForYouEvent(
            context,
            ref,
            eventId: event.id,
            source: ForYouEventSource.today,
          ),
    );

    // On tablet, wrap in AspectRatio to give the Stack-based layout proper height
    // This matches the aspect ratio used in CURRENT tab's SliverGrid
    if (ResponsiveHelper.isTablet) {
      return AspectRatio(
        aspectRatio: ResponsiveHelper.isLandscape ? 1.4 : 1.2,
        child: eventCard,
      );
    }

    return eventCard;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // For You board membership comes from the batched RPC cache. The cards
    // themselves stream live positions; this provider only refreshes the RPC
    // selection when a shown game finishes.
    final snapshotAsync = ref.watch(
      forYouEventGamesWithAutoRefreshProvider(event.id),
    );

    // Hide section after snapshot resolves with no games.
    final shouldHide = snapshotAsync.maybeWhen(
      data: (snapshot) => !snapshot.hasGames,
      orElse: () => false,
    );

    // No AnimatedSize: animating the section's height when its lazy games
    // snapshot resolves (loading→data) turned every reveal into a 300ms
    // expand/collapse that fought the scroll — "drawer" jank on fast up/down
    // flicks. Settle to final height in one frame instead; an instant resize
    // reads far better mid-scroll than a sustained height tween.
    return shouldHide
        ? const SizedBox.shrink()
        : _buildContent(context, ref, snapshotAsync);
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<ForYouEventGamesSnapshot> snapshotAsync,
  ) {
    final section = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Event card
        Padding(
          padding: EdgeInsets.only(top: isFirst ? 0 : 16.sp, bottom: 12.sp),
          child: _buildEventCard(context, ref),
        ),

        // Games for this event (uses same snapshot, no duplicate fetch)
        _ForYouEventGames(eventId: event.id, snapshotAsync: snapshotAsync),
      ],
    );

    return section;
  }
}

/// Single column in the 2-column tablet grid.
/// Owns a single shared snapshot for visibility and content.
class _ForYouTabletEventColumn extends ConsumerWidget {
  const _ForYouTabletEventColumn({super.key, required this.event});

  final GroupEventCardModel event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // For You board membership comes from the batched RPC cache. The cards
    // themselves stream live positions; this provider only refreshes the RPC
    // selection when a shown game finishes.
    final snapshotAsync = ref.watch(
      forYouEventGamesWithAutoRefreshProvider(event.id),
    );

    // Hide column after snapshot resolves with no games.
    final shouldHide = snapshotAsync.maybeWhen(
      data: (snapshot) => !snapshot.hasGames,
      orElse: () => false,
    );

    // See _ForYouEventSection: no AnimatedSize. Instant height settle avoids
    // the scroll-fighting "drawer" expand/collapse when games resolve lazily.
    return shouldHide
        ? const SizedBox.shrink()
        : _buildContent(context, ref, snapshotAsync);
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<ForYouEventGamesSnapshot> snapshotAsync,
  ) {
    // Aspect ratio for event card in column layout
    // Landscape: wider cards since we have 2 columns
    // Portrait: taller cards for better visual
    final eventCardAspectRatio = ResponsiveHelper.isLandscape ? 1.8 : 1.4;

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Event card
        AspectRatio(
          aspectRatio: eventCardAspectRatio,
          child: EventCard(
            tourEventCardModel: event,
            showHeartIndicator: true,
            favoritePlayersSource: EventFavoritePlayersSource.cacheOnly,
            heroTagSuffix: '_foryou_tablet_col',
            onTap:
                () => openForYouEvent(
                  context,
                  ref,
                  eventId: event.id,
                  source: ForYouEventSource.today,
                ),
          ),
        ),
        SizedBox(height: 10.sp),
        // Games for this event (uses same snapshot, no duplicate fetch)
        _ForYouTabletColumnGames(
          eventId: event.id,
          snapshotAsync: snapshotAsync,
        ),
      ],
    );

    return column;
  }
}

/// Games for a single column - shows games in 2-column grid (2 per row)
/// Receives the shared snapshot from the parent column widget.
class _ForYouTabletColumnGames extends StatelessWidget {
  const _ForYouTabletColumnGames({
    required this.eventId,
    required this.snapshotAsync,
  });

  final String eventId;
  final AsyncValue<ForYouEventGamesSnapshot> snapshotAsync;

  @override
  Widget build(BuildContext context) {
    return snapshotAsync.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: (snapshot) {
        final orderedGames = snapshot.visibleGames;
        if (orderedGames.isEmpty) {
          return const SizedBox.shrink();
        }

        final gameModels = orderedGames.take(kGamesPerEvent).toList();
        if (gameModels.isEmpty) {
          return const SizedBox.shrink();
        }

        final liveBatchKey = _forYouLiveBatchKey(
          eventId: eventId,
          tourId: snapshot.tourId,
          games: gameModels,
        );

        final List<Widget> rows = [];
        for (int i = 0; i < gameModels.length; i += 2) {
          final game1 = gameModels[i];
          final game2 = i + 1 < gameModels.length ? gameModels[i + 1] : null;

          rows.add(
            Padding(
              padding: EdgeInsets.only(bottom: 8.sp),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _TabletGameCard(
                      key: ValueKey('tablet_game_${game1.gameId}'),
                      game: game1,
                      orderedGames: orderedGames,
                      index: i,
                      eventId: eventId,
                      pinnedIds: snapshot.pinnedIds,
                      liveBatchKey: liveBatchKey,
                    ),
                  ),
                  SizedBox(width: 8.sp),
                  Expanded(
                    child:
                        game2 != null
                            ? _TabletGameCard(
                              key: ValueKey('tablet_game_${game2.gameId}'),
                              game: game2,
                              orderedGames: orderedGames,
                              index: i + 1,
                              eventId: eventId,
                              pinnedIds: snapshot.pinnedIds,
                              liveBatchKey: liveBatchKey,
                            )
                            : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(children: rows);
      },
      loading: () => _buildColumnShimmer(context),
      error: (error, stack) {
        debugPrint(
          '[_ForYouTabletColumnGames] Error loading games for $eventId: $error',
        );
        return Padding(
          padding: EdgeInsets.only(bottom: 8.sp),
          child: Text(
            'Could not load games',
            style: TextStyle(
              color: context.colors.textPrimaryMuted,
              fontSize: 12.sp,
            ),
          ),
        );
      },
    );
  }

  Widget _buildColumnShimmer(BuildContext context) {
    // Show 2 rows of 2 game cards (4 total) matching actual content
    return Column(
      children: List.generate(2, (rowIndex) {
        return Padding(
          padding: EdgeInsets.only(bottom: 8.sp),
          child: Row(
            children: [
              Expanded(child: _SkeletonBlock(height: 72.sp)),
              SizedBox(width: 8.sp),
              Expanded(child: _SkeletonBlock(height: 72.sp)),
            ],
          ),
        );
      }),
    );
  }
}

/// Clean game card for tablet grid - full game card style, not compact
class _TabletGameCard extends ConsumerWidget {
  const _TabletGameCard({
    super.key,
    required this.game,
    required this.orderedGames,
    required this.index,
    required this.eventId,
    required this.pinnedIds,
    required this.liveBatchKey,
  });

  final GamesTourModel game;
  final List<GamesTourModel> orderedGames;
  final int index;
  final String eventId;
  final List<String> pinnedIds;
  final LiveGamesBatchKey liveBatchKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridGameCardWrapperWidget(
      key: ValueKey('tablet_grid_game_${game.gameId}'),
      game: game,
      orderedGames: orderedGames,
      gameIndex: index,
      liveBatchKey: liveBatchKey,
      allowStockfishFallback: true,
      streamEnabled: true,
      viewSource: ChessboardView.forYou,
      onChangedWithLiveGames: (updatedGames) =>
          _openForYouGame(context, ref, updatedGames, index),
      pinnedIds: pinnedIds,
      onPinToggle:
          (_) => ref
              .read(forYouPinActionProvider)
              .togglePin(
                eventId: eventId,
                gameId: game.gameId,
                tourId: game.tourId,
              ),
    );
  }
}

/// Games section for one event - loads lazily with shimmer.
/// Receives the shared snapshot from the parent section widget.
class _ForYouEventGames extends ConsumerWidget {
  const _ForYouEventGames({required this.eventId, required this.snapshotAsync});

  final String eventId;
  final AsyncValue<ForYouEventGamesSnapshot> snapshotAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(gamesListViewModeProvider);

    return snapshotAsync.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: (snapshot) {
        final orderedGames = snapshot.visibleGames;
        if (orderedGames.isEmpty) {
          return const SizedBox.shrink();
        }

        final displayedGames = orderedGames.take(kGamesPerEvent).toList();
        if (displayedGames.isEmpty) {
          return const SizedBox.shrink();
        }

        final liveBatchKey = _forYouLiveBatchKey(
          eventId: eventId,
          tourId: snapshot.tourId,
          games: displayedGames,
        );

        final gamesData = GamesScreenModel(
          gamesTourModels: orderedGames,
          pinnedGamedIs: snapshot.pinnedIds,
        );

        // Grid mode: 2 games per row
        if (viewMode == GamesListViewMode.chessBoardGrid) {
          return _buildGridGames(
            context,
            ref,
            displayedGames,
            orderedGames,
            snapshot.pinnedIds,
            liveBatchKey,
          );
        }

        return Column(
          children: List.generate(displayedGames.length, (index) {
            final game = displayedGames[index];
            return _ForYouGameCard(
              key: ValueKey('game_${game.gameId}'),
              game: game,
              gamesData: gamesData,
              gameIndex: index,
              eventId: eventId,
              viewMode: viewMode,
              liveBatchKey: liveBatchKey,
            );
          }),
        );
      },
      loading: () => _buildGameShimmers(viewMode),
      error: (error, stack) {
        debugPrint(
          '[ForYouEventGames] Error loading games for $eventId: $error',
        );
        return Padding(
          padding: EdgeInsets.only(bottom: 8.sp),
          child: Text(
            'Could not load games',
            style: TextStyle(
              color: context.colors.textPrimaryMuted,
              fontSize: 12.sp,
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridGames(
    BuildContext context,
    WidgetRef ref,
    List<GamesTourModel> displayedGames,
    List<GamesTourModel> orderedGames,
    List<String> pinnedIds,
    LiveGamesBatchKey liveBatchKey,
  ) {
    final rows = <Widget>[];

    for (int i = 0; i < displayedGames.length; i += 2) {
      final game1 = displayedGames[i];
      final game2 =
          i + 1 < displayedGames.length ? displayedGames[i + 1] : null;

      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: 12.sp),
          child: Row(
            children: [
              Expanded(
                child: GridGameCardWrapperWidget(
                  key: ValueKey('grid_game_${game1.gameId}'),
                  game: game1,
                  orderedGames: orderedGames,
                  gameIndex: i,
                  liveBatchKey: liveBatchKey,
                  allowStockfishFallback: true,
                  streamEnabled: true,
                  viewSource: ChessboardView.forYou,
                  onChangedWithLiveGames: (updatedGames) =>
                      _openForYouGame(context, ref, updatedGames, i),
                  pinnedIds: pinnedIds,
                  onPinToggle:
                      (_) => ref
                          .read(forYouPinActionProvider)
                          .togglePin(
                            eventId: eventId,
                            gameId: game1.gameId,
                            tourId: game1.tourId,
                          ),
                ),
              ),
              SizedBox(width: 12.sp),
              Expanded(
                child:
                    game2 != null
                        ? GridGameCardWrapperWidget(
                          key: ValueKey('grid_game_${game2.gameId}'),
                          game: game2,
                          orderedGames: orderedGames,
                          gameIndex: i + 1,
                          liveBatchKey: liveBatchKey,
                          allowStockfishFallback: true,
                          streamEnabled: true,
                          viewSource: ChessboardView.forYou,
                          onChangedWithLiveGames: (updatedGames) =>
                              _openForYouGame(context, ref, updatedGames, i + 1),
                          pinnedIds: pinnedIds,
                          onPinToggle:
                              (_) => ref
                                  .read(forYouPinActionProvider)
                                  .togglePin(
                                    eventId: eventId,
                                    gameId: game2.gameId,
                                    tourId: game2.tourId,
                                  ),
                        )
                        : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }

    return Column(children: rows);
  }

  /// Shimmer placeholders for 4 games
  Widget _buildGameShimmers(GamesListViewMode viewMode) {
    if (viewMode == GamesListViewMode.chessBoardGrid) {
      return Column(
        children: List.generate(2, (rowIndex) {
          return Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: Row(
              children: [
                Expanded(child: _SkeletonBlock(height: 72.sp)),
                SizedBox(width: 12.sp),
                Expanded(child: _SkeletonBlock(height: 72.sp)),
              ],
            ),
          );
        }),
      );
    }

    return Column(
      children: List.generate(kGamesPerEvent, (index) {
        return Padding(
          padding: EdgeInsets.only(bottom: 12.sp),
          child: _SkeletonBlock(height: 72.sp),
        );
      }),
    );
  }
}

/// One placeholder block of the Today skeleton.
///
/// Drawn as a skeletonizer [Bone] because [SkeletonWidget] ignores
/// containers: a decorated `Container` inside it paints nothing at all, which
/// left the loading feed blank below the collection cards.
class _SkeletonBlock extends StatelessWidget {
  /// A null [height] fills the parent, e.g. an [AspectRatio].
  const _SkeletonBlock({this.height, this.radius});

  final double? height;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return SkeletonWidget(
      child: Bone(
        width: double.infinity,
        height: height,
        borderRadius: BorderRadius.circular(radius ?? 8.br),
      ),
    );
  }
}

/// Single game card.
class _ForYouGameCard extends ConsumerWidget {
  const _ForYouGameCard({
    super.key,
    required this.game,
    required this.gamesData,
    required this.gameIndex,
    required this.eventId,
    required this.viewMode,
    required this.liveBatchKey,
  });

  final GamesTourModel game;
  final GamesScreenModel gamesData;
  final int gameIndex;
  final String eventId;
  final GamesListViewMode viewMode;
  final LiveGamesBatchKey liveBatchKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isChessBoardVisible = viewMode == GamesListViewMode.chessBoard;

    return Padding(
      padding: EdgeInsets.only(bottom: 12.sp),
      child: GameCardWrapperWidget(
        game: game,
        gamesData: gamesData,
        gameIndex: gameIndex,
        isChessBoardVisible: isChessBoardVisible,
        viewSource: ChessboardView.forYou,
        liveBatchKey: liveBatchKey,
        allowStockfishFallback: true,
        streamEnabled: true,
        onBeforeOpen: () => ensurePastGameAccess(context, game: game),
        onPinToggle:
            (_) => ref
                .read(forYouPinActionProvider)
                .togglePin(
                  eventId: eventId,
                  gameId: game.gameId,
                  tourId: game.tourId,
                ),
        onReturnFromChessboard: (_) {},
      ),
    );
  }
}

/// Skeleton for entire event section (event card + 4 games)
class _ForYouEventSkeleton extends StatelessWidget {
  const _ForYouEventSkeleton({required this.isFirst});

  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Event card skeleton
        Padding(
          padding: EdgeInsets.only(top: isFirst ? 0 : 16.sp, bottom: 12.sp),
          child: _SkeletonBlock(height: 80.sp),
        ),
        ...List.generate(kGamesPerEvent, (index) {
          return Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: _SkeletonBlock(height: 72.sp),
          );
        }),
      ],
    );
  }
}
