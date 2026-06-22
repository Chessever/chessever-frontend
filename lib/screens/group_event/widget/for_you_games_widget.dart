import 'dart:async';

import 'package:chessever2/main.dart' show pageRouteObserver;
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/for_you_games_logic.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/widget/premium_collection_cards.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/foreground_task_scheduler.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/smart_event_card.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';

// Cache ~1.5 viewports for the compact card feed and ~1 viewport for the
// heavier board feed. The previous fixed 360/180px extents were smaller than a
// single event section, so sections reloaded from scratch on scroll-back.
const ScrollCacheExtent _kForYouCompactCacheExtent =
    ScrollCacheExtent.viewport(1.5);
const ScrollCacheExtent _kForYouBoardCacheExtent =
    ScrollCacheExtent.viewport(1.0);
const Duration _kForYouScrollIdleDelay = Duration(milliseconds: 180);

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
    gameIds: games.map((game) => game.gameId),
  );
}

/// For You tab widget - displays events with their top 4 games
///
/// KEY DESIGN:
/// - Events load IMMEDIATELY (same source as Current tab)
/// - Games load LAZILY per event (with shimmer)
/// - Always exactly 4 games per event (hardcoded)
/// - Favorite players get priority in game selection
class ForYouGamesWidget extends ConsumerStatefulWidget {
  const ForYouGamesWidget({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  ConsumerState<ForYouGamesWidget> createState() => _ForYouGamesWidgetState();
}

class _ForYouGamesWidgetState extends ConsumerState<ForYouGamesWidget>
    with WidgetsBindingObserver, RouteAware, AutomaticKeepAliveClientMixin {
  final Set<String> _animatedEventIds = <String>{};
  final Set<String> _animatedGameIds = <String>{};
  Timer? _scrollIdleTimer;
  bool _routeSubscribed = false;
  bool _routeIsCurrent = true;
  bool _appIsResumed = true;
  bool _liveCardsPausedForScroll = false;
  bool _isDisposing = false;
  late final StateController<Set<String>> _liveGameCardsPauseReasons;

  String get _liveCardsPauseReason => 'for_you_scroll_$hashCode';

  @override
  void initState() {
    super.initState();
    _liveGameCardsPauseReasons = ref.read(
      liveGameCardsPauseReasonsProvider.notifier,
    );
    WidgetsBinding.instance.addObserver(this);
    widget.scrollController.addListener(_onScroll);
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
    pageRouteObserver.subscribe(this, route);
    _routeSubscribed = true;
    _routeIsCurrent = route.isCurrent;
  }

  @override
  void dispose() {
    _isDisposing = true;
    widget.scrollController.removeListener(_onScroll);
    _animatedEventIds.clear();
    _animatedGameIds.clear();
    if (_routeSubscribed) {
      pageRouteObserver.unsubscribe(this);
    }
    ForegroundTaskScheduler.cancel('for_you_games_resume_$hashCode');
    _scrollIdleTimer?.cancel();
    _setLiveCardsPausedForScroll(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didPush() {
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
    if (!isActive) {
      _stopTransientWork();
    } else if (refreshNow) {
      _refreshRealtimeGamesNow();
    }
  }

  void _setAppResumed(bool isResumed) {
    if (!mounted) return;
    if (_appIsResumed != isResumed) {
      setState(() => _appIsResumed = isResumed);
    }
    if (!isResumed) {
      _stopTransientWork();
    }
  }

  void _stopTransientWork() {
    ForegroundTaskScheduler.cancel('for_you_games_resume_$hashCode');
    _scrollIdleTimer?.cancel();
    _setLiveCardsPausedForScroll(false);
  }

  void _refreshRealtimeGamesNow() {
    if (!mounted || _isDisposing) return;
    if (!_routeIsCurrent || !_appIsResumed) return;
    final route = ModalRoute.of(context);
    if (route?.isCurrent != true) return;
    final selected = ref.read(selectedGroupCategoryProvider);
    if (selected == GroupEventCategory.forYou) {
      ref.invalidate(gameUpdatesStreamProvider);
      ref.invalidate(liveGameUpdateStreamProvider);
      ref.invalidate(gameUpdatesBatchStreamProvider);
      unawaited(
        ref
            .read(forYouEventsProvider.notifier)
            .refreshIfStale(maxAge: Duration.zero),
      );
    }
  }

  void _onScroll() {
    if (!mounted || _isDisposing) return;
    if (!widget.scrollController.hasClients) return;
    _markLiveCardsScrolling();
    final max = widget.scrollController.position.maxScrollExtent;
    final current = widget.scrollController.position.pixels;
    if (max - current <= 300) {
      ref.read(forYouEventsProvider.notifier).loadMore();
    }
  }

  void _markLiveCardsScrolling() {
    _setLiveCardsPausedForScroll(true);
    _scrollIdleTimer?.cancel();
    _scrollIdleTimer = Timer(_kForYouScrollIdleDelay, _markLiveCardsIdle);
  }

  void _markLiveCardsIdle() {
    if (!mounted || _isDisposing) return;
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

  @override
  bool get wantKeepAlive => false;

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin

    // If PageView keeps this page around briefly while swiping, drop all
    // expensive provider subscriptions until For You is visible again.
    final selectedCategory = ref.watch(selectedGroupCategoryProvider);
    if (selectedCategory != GroupEventCategory.forYou || !_isActiveOnScreen) {
      return const SizedBox.shrink();
    }

    final state = ref.watch(forYouEventsProvider);
    final viewMode = ref.watch(gamesListViewModeProvider);
    final events = state.events;
    final favoriteEvents = ref.watch(favoriteEventsProvider).valueOrNull ?? [];
    final dismissedSmartEventCardKeys = ref.watch(
      dismissedSmartEventCardKeysProvider,
    );
    final liveIds =
        ref.watch(liveGroupBroadcastIdsProvider).valueOrNull ??
        const <String>[];
    final smartFavoriteEventIds = _smartFavoriteEventIds(favoriteEvents);
    final currentSmartEventIdsAsync = ref.watch(
      smartCurrentEventIdsProvider(
        SmartCurrentEventIdsQuery(smartFavoriteEventIds),
      ),
    );
    final savedSmartData = currentSmartEventIdsAsync.maybeWhen(
      data:
          (currentEventIds) =>
              _savedSmartCards(favoriteEvents, liveIds, currentEventIds),
      orElse: () => const <SmartEventCardData>[],
    );

    if (state.isLoading && events.isEmpty) {
      return _buildLoadingState();
    }

    if (state.error != null && events.isEmpty) {
      debugPrint('[ForYouGamesWidget] Error: ${state.error}');
      final message = state.error?.trim();
      return GenericErrorWidget(
        message: message != null && message.isNotEmpty
            ? userFacingError(message)
            : null,
        onRetry: () => ref.read(forYouEventsProvider.notifier).refresh(),
      );
    }

    if (events.isEmpty && savedSmartData.isEmpty) {
      return _buildEmptyState();
    }

    // The smart "Convergence" event only materialises when an ELO/tier filter
    // is applied — it gathers the strongest live games across every broadcast
    // into one card, pinned top-most.
    final smartData = visibleSmartEventCardData(
      SmartEventCardData.fromState(
        filter: ref.watch(forYouAppliedFilterProvider),
        events: events,
        source: SmartEventSource.forYou,
      ),
      dismissedSmartEventCardKeys,
    );
    final visibleSavedSmartData =
        smartData == null
            ? savedSmartData
                .where(
                  (saved) =>
                      !dismissedSmartEventCardKeys.contains(
                        saved.request.cardDismissKey,
                      ),
                )
                .toList(growable: false)
            : savedSmartData
                .where(
                  (saved) =>
                      saved.request.favoriteEventId !=
                          smartData.request.favoriteEventId &&
                      !dismissedSmartEventCardKeys.contains(
                        saved.request.cardDismissKey,
                      ),
                )
                .toList(growable: false);

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(forYouEventsProvider.notifier).refresh();
      },
      color: kPrimaryColor,
      backgroundColor: context.colors.surface,
      child: _buildEventsList(
        events,
        viewMode: viewMode,
        showLoadingMore: state.hasMore && !state.isLoading,
        smartData: smartData,
        savedSmartData: visibleSavedSmartData,
      ),
    );
  }

  List<String> _smartFavoriteEventIds(List<FavoriteEvent> favoriteEvents) {
    final ids = <String>{};
    for (final favorite in favoriteEvents) {
      if (!isSmartFavoriteEvent(favorite)) continue;
      final request = SmartEventRequest.fromFavoriteEvent(favorite);
      ids.addAll(request.eventIds);
    }
    return ids.toList(growable: false);
  }

  List<SmartEventCardData> _savedSmartCards(
    List<FavoriteEvent> favoriteEvents,
    List<String> liveIds,
    Set<String> currentEventIds,
  ) {
    final cards = <SmartEventCardData>[];
    for (final favorite in favoriteEvents) {
      if (!isSmartFavoriteEvent(favorite)) continue;
      final request = SmartEventRequest.fromFavoriteEvent(favorite);
      if (request.events.isEmpty) continue;
      if (!smartEventHasCurrentEvents(request, currentEventIds)) {
        unawaited(
          Future.microtask(
            () => ref
                .read(favoriteEventsProvider.notifier)
                .removeFavorite(request.favoriteEventId),
          ),
        );
        continue;
      }
      if (!smartEventHasUnfinishedEvents(request, liveIds)) {
        unawaited(
          Future.microtask(
            () => ref
                .read(favoriteEventsProvider.notifier)
                .removeFavorite(request.favoriteEventId),
          ),
        );
        continue;
      }
      final elos =
          request.events
              .map((event) => event.maxAvgElo)
              .where((elo) => elo > 0)
              .toList();
      cards.add(
        SmartEventCardData(
          request: request,
          eventCount: request.events.length,
          avgElo:
              elos.isEmpty
                  ? 0
                  : (elos.reduce((a, b) => a + b) / elos.length).round(),
        ),
      );
    }
    cards.sort((a, b) {
      final ad = a.request.savedAt ?? DateTime(0);
      final bd = b.request.savedAt ?? DateTime(0);
      return bd.compareTo(ad);
    });
    return cards;
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
    required GamesListViewMode viewMode,
    bool showLoadingMore = false,
    SmartEventCardData? smartData,
    List<SmartEventCardData> savedSmartData = const [],
  }) {
    // On tablet, use a beautiful grid layout
    if (ResponsiveHelper.isTablet) {
      return _buildTabletGridLayout(
        events,
        viewMode: viewMode,
        showLoadingMore: showLoadingMore,
        smartData: smartData,
        savedSmartData: savedSmartData,
      );
    }

    // Phone: vertical list layout
    final horizontalPadding = 16.sp;

    // Pinned right under the premium cards, above the first event.
    final smartCards = <SmartEventCardData>[
      ...savedSmartData,
      if (smartData != null) smartData,
    ];
    final smartOffset = smartCards.length;

    // +1 for premium cards, +smartOffset for the smart card, +1 for loading.
    final itemCount =
        events.length + 1 + smartOffset + (showLoadingMore ? 1 : 0);

    return ListView.builder(
      key: const PageStorageKey<String>('for_you_events_list'),
      controller: widget.scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 16.sp,
      ),
      itemCount: itemCount,
      scrollCacheExtent: _forYouCacheExtentForMode(viewMode),
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      itemBuilder: (context, index) {
        // Premium collection cards at top
        if (index == 0) {
          return const PremiumCollectionCards();
        }

        if (index > 0 && index <= smartCards.length) {
          final cardData = smartCards[index - 1];
          return Padding(
            padding: EdgeInsets.only(bottom: 16.sp),
            child: _buildSmartEventCard(cardData),
          );
        }

        // Loading indicator at bottom
        if (showLoadingMore && index == itemCount - 1) {
          return _buildLoadingMoreIndicator();
        }

        final event = events[index - 1 - smartOffset];
        return _ForYouEventSection(
          key: ValueKey('event_${event.id}'),
          event: event,
          isFirst: index == 1 + smartOffset,
          animatedEventIds: _animatedEventIds,
          animatedGameIds: _animatedGameIds,
        );
      },
    );
  }

  Widget _buildSmartEventCard(SmartEventCardData smartData) {
    // Subtract tournaments the user hid from this smart event so the card
    // count matches the About tab (and survives restarts via the same store).
    final hidden = ref.watch(
      smartEventDismissedEventIdsProvider(smartData.request.dismissScopeId),
    );
    final visibleCount =
        smartData.request.events.where((e) => !hidden.contains(e.id)).length;
    return SmartEventCard(
      tierLabel: smartData.request.tierLabel,
      minElo: smartData.request.minElo,
      liveCount: visibleCount,
      avgElo: smartData.avgElo,
      titleSuffix: smartData.request.titleSuffix,
      caption: smartData.request.caption,
      countSingular: smartData.request.countSingular,
      countPlural: smartData.request.countPlural,
      accentColor: smartEventAccentColor(smartData.request.scopeId),
      onTap:
          () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SmartEventScreen(request: smartData.request),
            ),
          ),
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
            color: kPrimaryColor,
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
    required GamesListViewMode viewMode,
    bool showLoadingMore = false,
    SmartEventCardData? smartData,
    List<SmartEventCardData> savedSmartData = const [],
  }) {
    final horizontalPadding = ResponsiveHelper.isLandscape ? 32.sp : 24.sp;
    final columnSpacing = 16.sp;
    final smartCards = <SmartEventCardData>[
      ...savedSmartData,
      if (smartData != null) smartData,
    ];
    final smartOffset = smartCards.length;

    // Number of event-pair rows (ceil division)
    final rowCount = (events.length + 1) ~/ 2;
    // +1 for premium cards at top, +smartOffset for the smart card,
    // +1 for loading indicator if showing.
    final itemCount = rowCount + 1 + smartOffset + (showLoadingMore ? 1 : 0);

    return ListView.builder(
      key: const PageStorageKey<String>('for_you_events_tablet_grid'),
      controller: widget.scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 16.sp,
      ),
      itemCount: itemCount,
      scrollCacheExtent: _forYouCacheExtentForMode(viewMode),
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      itemBuilder: (context, index) {
        // Premium collection cards at top
        if (index == 0) {
          return const PremiumCollectionCards();
        }

        if (index > 0 && index <= smartCards.length) {
          final cardData = smartCards[index - 1];
          return Padding(
            padding: EdgeInsets.only(bottom: 16.sp),
            child: _buildSmartEventCard(cardData),
          );
        }

        // Loading indicator at bottom
        if (showLoadingMore && index == itemCount - 1) {
          return _buildLoadingMoreIndicator();
        }

        final rowIndex = index - 1 - smartOffset;
        final i = rowIndex * 2;
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
                  animatedEventIds: _animatedEventIds,
                  animatedGameIds: _animatedGameIds,
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
                          animatedEventIds: _animatedEventIds,
                          animatedGameIds: _animatedGameIds,
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
        SkeletonWidget(
          child: AspectRatio(
            aspectRatio: eventCardAspectRatio,
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.surfaceRecessed,
                borderRadius: BorderRadius.circular(12.br),
              ),
            ),
          ),
        ),
        SizedBox(height: 10.sp),
        // Game card skeletons (2 rows of 2 = 4 total, matching actual content)
        ...List.generate(2, (rowIndex) {
          return Padding(
            padding: EdgeInsets.only(bottom: 8.sp),
            child: Row(
              children: [
                Expanded(
                  child: SkeletonWidget(
                    ignoreContainers: true,
                    child: Container(
                      height: 72.sp,
                      decoration: BoxDecoration(
                        color: context.colors.surfaceRecessed,
                        borderRadius: BorderRadius.circular(8.br),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8.sp),
                Expanded(
                  child: SkeletonWidget(
                    ignoreContainers: true,
                    child: Container(
                      height: 72.sp,
                      decoration: BoxDecoration(
                        color: context.colors.surfaceRecessed,
                        borderRadius: BorderRadius.circular(8.br),
                      ),
                    ),
                  ),
                ),
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
    required this.animatedEventIds,
    required this.animatedGameIds,
  });

  final GroupEventCardModel event;
  final bool isFirst;
  final Set<String> animatedEventIds;
  final Set<String> animatedGameIds;

  /// Builds the EventCard with proper constraints for tablet
  /// Tablet uses image-as-background layout which needs bounded height
  Widget _buildEventCard(BuildContext context, WidgetRef ref) {
    final eventCard = EventCard(
      tourEventCardModel: event,
      showHeartIndicator: true,
      favoritePlayersSource: EventFavoritePlayersSource.cacheOnly,
      heroTagSuffix: '_foryou',
      onTap: () {
        ref
            .read(groupEventScreenProvider.notifier)
            .onSelectTournament(context: context, id: event.id);
      },
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
    // Single shared snapshot drives both visibility and content.
    final snapshotAsync = ref.watch(forYouEventSnapshotProvider(event.id));

    // Hide section after snapshot resolves with no games.
    final shouldHide = snapshotAsync.maybeWhen(
      data: (snapshot) => !snapshot.hasGames,
      orElse: () => false,
    );

    // AnimatedSize smoothly collapses the section when it resolves empty,
    // avoiding visual jumps when multiple sections disappear in sequence.
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child:
          shouldHide
              ? const SizedBox.shrink()
              : _buildContent(context, ref, snapshotAsync),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<ForYouEventGamesSnapshot> snapshotAsync,
  ) {
    final shouldAnimate = !animatedEventIds.contains(event.id);
    if (shouldAnimate) {
      animatedEventIds.add(event.id);
    }

    final section = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Event card
        Padding(
          padding: EdgeInsets.only(top: isFirst ? 0 : 16.sp, bottom: 12.sp),
          child: _buildEventCard(context, ref),
        ),

        // Games for this event (uses same snapshot, no duplicate fetch)
        _ForYouEventGames(
          eventId: event.id,
          snapshotAsync: snapshotAsync,
          animatedGameIds: animatedGameIds,
        ),
      ],
    );

    // Entrance animation removed: fading whole event sections on first paint
    // forced a saveLayer per section across the cold-open viewport — the main
    // source of "awful perf the moment For You opens". Sections now appear
    // instantly; new live games still animate via the motor _AnimatedGameCardSlot.
    return section;
  }
}

/// Single column in the 2-column tablet grid.
/// Owns a single shared snapshot for visibility and content.
class _ForYouTabletEventColumn extends ConsumerWidget {
  const _ForYouTabletEventColumn({
    super.key,
    required this.event,
    required this.animatedEventIds,
    required this.animatedGameIds,
  });

  final GroupEventCardModel event;
  final Set<String> animatedEventIds;
  final Set<String> animatedGameIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Single shared snapshot drives both visibility and content.
    final snapshotAsync = ref.watch(forYouEventSnapshotProvider(event.id));

    // Hide column after snapshot resolves with no games.
    final shouldHide = snapshotAsync.maybeWhen(
      data: (snapshot) => !snapshot.hasGames,
      orElse: () => false,
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child:
          shouldHide
              ? const SizedBox.shrink()
              : _buildContent(context, ref, snapshotAsync),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<ForYouEventGamesSnapshot> snapshotAsync,
  ) {
    final shouldAnimate = !animatedEventIds.contains(event.id);
    if (shouldAnimate) {
      animatedEventIds.add(event.id);
    }

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
            onTap: () {
              ref
                  .read(groupEventScreenProvider.notifier)
                  .onSelectTournament(context: context, id: event.id);
            },
          ),
        ),
        SizedBox(height: 10.sp),
        // Games for this event (uses same snapshot, no duplicate fetch)
        _ForYouTabletColumnGames(
          eventId: event.id,
          snapshotAsync: snapshotAsync,
          animatedGameIds: animatedGameIds,
        ),
      ],
    );

    // Entrance animation removed (see phone section) — instant paint over fade.
    return column;
  }
}

/// Games for a single column - shows games in 2-column grid (2 per row)
/// Receives the shared snapshot from the parent column widget.
class _ForYouTabletColumnGames extends StatelessWidget {
  const _ForYouTabletColumnGames({
    required this.eventId,
    required this.snapshotAsync,
    required this.animatedGameIds,
  });

  final String eventId;
  final AsyncValue<ForYouEventGamesSnapshot> snapshotAsync;
  final Set<String> animatedGameIds;

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

        // Build 2-column grid of games (2 per row, max 2 rows = 4 games)
        // Wrap with animated slots for smooth transitions when games change
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
                    child: _AnimatedGameCardSlot(
                      key: ValueKey('tablet_slot_$i'),
                      gameId: game1.gameId,
                      child: _TabletGameCard(
                        game: game1,
                        orderedGames: orderedGames,
                        index: i,
                        eventId: eventId,
                        pinnedIds: snapshot.pinnedIds,
                        liveBatchKey: liveBatchKey,
                      ),
                    ),
                  ),
                  SizedBox(width: 8.sp),
                  Expanded(
                    child:
                        game2 != null
                            ? _AnimatedGameCardSlot(
                              key: ValueKey('tablet_slot_${i + 1}'),
                              gameId: game2.gameId,
                              child: _TabletGameCard(
                                game: game2,
                                orderedGames: orderedGames,
                                index: i + 1,
                                eventId: eventId,
                                pinnedIds: snapshot.pinnedIds,
                                liveBatchKey: liveBatchKey,
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
              Expanded(
                child: SkeletonWidget(
                  ignoreContainers: true,
                  child: Container(
                    height: 72.sp,
                    decoration: BoxDecoration(
                      color: context.colors.surfaceRecessed,
                      borderRadius: BorderRadius.circular(8.br),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8.sp),
              Expanded(
                child: SkeletonWidget(
                  ignoreContainers: true,
                  child: Container(
                    height: 72.sp,
                    decoration: BoxDecoration(
                      color: context.colors.surfaceRecessed,
                      borderRadius: BorderRadius.circular(8.br),
                    ),
                  ),
                ),
              ),
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
      allowStockfishFallback: false,
      streamEnabled: true,
      onChangedWithLiveGames:
          (updatedGames) => ref
              .read(gameCardWrapperProvider)
              .navigateToChessBoard(
                context: context,
                orderedGames: updatedGames,
                gameIndex: index,
                onReturnFromChessboard: (_) {},
                viewSource: ChessboardView.forYou,
              ),
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
  const _ForYouEventGames({
    required this.eventId,
    required this.snapshotAsync,
    required this.animatedGameIds,
  });

  final String eventId;
  final AsyncValue<ForYouEventGamesSnapshot> snapshotAsync;
  final Set<String> animatedGameIds;

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

        // List mode: one game per row with smooth transition animation
        return Column(
          children: List.generate(displayedGames.length, (index) {
            final game = displayedGames[index];
            return _AnimatedGameCardSlot(
              key: ValueKey('slot_$index'),
              gameId: game.gameId,
              child: _ForYouGameCard(
                key: ValueKey('game_${game.gameId}'),
                game: game,
                gamesData: gamesData,
                gameIndex: index,
                eventId: eventId,
                animatedGameIds: animatedGameIds,
                viewMode: viewMode,
                liveBatchKey: liveBatchKey,
              ),
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
                child: _AnimatedGameCardSlot(
                  key: ValueKey('grid_slot_$i'),
                  gameId: game1.gameId,
                  child: GridGameCardWrapperWidget(
                    key: ValueKey('grid_game_${game1.gameId}'),
                    game: game1,
                    orderedGames: orderedGames,
                    gameIndex: i,
                    liveBatchKey: liveBatchKey,
                    allowStockfishFallback: false,
                    streamEnabled: true,
                    onChangedWithLiveGames:
                        (updatedGames) => ref
                            .read(gameCardWrapperProvider)
                            .navigateToChessBoard(
                              context: context,
                              orderedGames: updatedGames,
                              gameIndex: i,
                              onReturnFromChessboard: (_) {},
                              viewSource: ChessboardView.forYou,
                            ),
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
              ),
              SizedBox(width: 12.sp),
              Expanded(
                child:
                    game2 != null
                        ? _AnimatedGameCardSlot(
                          key: ValueKey('grid_slot_${i + 1}'),
                          gameId: game2.gameId,
                          child: GridGameCardWrapperWidget(
                            key: ValueKey('grid_game_${game2.gameId}'),
                            game: game2,
                            orderedGames: orderedGames,
                            gameIndex: i + 1,
                            liveBatchKey: liveBatchKey,
                            allowStockfishFallback: false,
                            streamEnabled: true,
                            onChangedWithLiveGames:
                                (updatedGames) => ref
                                    .read(gameCardWrapperProvider)
                                    .navigateToChessBoard(
                                      context: context,
                                      orderedGames: updatedGames,
                                      gameIndex: i + 1,
                                      onReturnFromChessboard: (_) {},
                                      viewSource: ChessboardView.forYou,
                                    ),
                            pinnedIds: pinnedIds,
                            onPinToggle:
                                (_) => ref
                                    .read(forYouPinActionProvider)
                                    .togglePin(
                                      eventId: eventId,
                                      gameId: game2.gameId,
                                      tourId: game2.tourId,
                                    ),
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
    final mockPlayer = PlayerCard(
      name: 'Loading...',
      federation: '',
      title: 'GM',
      rating: 2700,
      countryCode: 'USA',
      team: '',
    );

    final mockGame = GamesTourModel(
      roundId: 'roundId',
      tourId: 'tourId',
      gameId: 'gameId',
      whitePlayer: mockPlayer,
      blackPlayer: mockPlayer,
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.ongoing,
    );

    if (viewMode == GamesListViewMode.chessBoardGrid) {
      // 2 rows of 2 games each
      return Column(
        children: List.generate(2, (rowIndex) {
          return Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: Row(
              children: [
                Expanded(child: _GameShimmer(mockGame: mockGame)),
                SizedBox(width: 12.sp),
                Expanded(child: _GameShimmer(mockGame: mockGame)),
              ],
            ),
          );
        }),
      );
    }

    // List mode: 4 shimmer cards
    return Column(
      children: List.generate(kGamesPerEvent, (index) {
        return Padding(
          padding: EdgeInsets.only(bottom: 12.sp),
          child: _GameShimmer(mockGame: mockGame),
        );
      }),
    );
  }
}

/// Shimmer for a single game card
class _GameShimmer extends StatelessWidget {
  const _GameShimmer({required this.mockGame});

  final GamesTourModel mockGame;

  @override
  Widget build(BuildContext context) {
    return SkeletonWidget(
      ignoreContainers: true,
      child: GameCard(
        onTap: () {},
        matchComparison: MatchWithComparison(
          game: mockGame,
          comparison: MatchComparison.sameOrder,
        ),
        onPinToggle: (_) {},
        pinnedIds: const [],
      ),
    );
  }
}

/// Single game card with animation
class _ForYouGameCard extends ConsumerWidget {
  const _ForYouGameCard({
    super.key,
    required this.game,
    required this.gamesData,
    required this.gameIndex,
    required this.eventId,
    required this.animatedGameIds,
    required this.viewMode,
    required this.liveBatchKey,
  });

  final GamesTourModel game;
  final GamesScreenModel gamesData;
  final int gameIndex;
  final String eventId;
  final Set<String> animatedGameIds;
  final GamesListViewMode viewMode;
  final LiveGamesBatchKey liveBatchKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isChessBoardVisible = viewMode == GamesListViewMode.chessBoard;
    final shouldAnimate = !animatedGameIds.contains(game.gameId);

    if (shouldAnimate) {
      animatedGameIds.add(game.gameId);
    }

    final card = Padding(
      padding: EdgeInsets.only(bottom: 12.sp),
      child: GameCardWrapperWidget(
        game: game,
        gamesData: gamesData,
        gameIndex: gameIndex,
        isChessBoardVisible: isChessBoardVisible,
        viewSource: ChessboardView.forYou,
        liveBatchKey: liveBatchKey,
        allowStockfishFallback: false,
        streamEnabled: true,
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

    // Staggered fadeIn/slideY per card removed: it ran an animated Opacity
    // (saveLayer) per card with a gameIndex*50ms stagger, cascading jank right
    // when the list first populates. Cards paint instantly now.
    return card;
  }
}

/// Skeleton for entire event section (event card + 4 games)
class _ForYouEventSkeleton extends StatelessWidget {
  const _ForYouEventSkeleton({required this.isFirst});

  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final mockPlayer = PlayerCard(
      name: 'Loading...',
      federation: '',
      title: 'GM',
      rating: 2700,
      countryCode: 'USA',
      team: '',
    );

    final mockGame = GamesTourModel(
      roundId: 'roundId',
      tourId: 'tourId',
      gameId: 'gameId',
      whitePlayer: mockPlayer,
      blackPlayer: mockPlayer,
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.ongoing,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Event card skeleton
        SkeletonWidget(
          child: Container(
            margin: EdgeInsets.only(top: isFirst ? 0 : 16.sp, bottom: 12.sp),
            height: 80.sp,
            decoration: BoxDecoration(
              color: context.colors.surfaceRecessed,
              borderRadius: BorderRadius.circular(8.br),
            ),
          ),
        ),
        // Game card skeletons
        ...List.generate(kGamesPerEvent, (index) {
          return Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: SkeletonWidget(
              ignoreContainers: true,
              child: GameCard(
                onTap: () {},
                matchComparison: MatchWithComparison(
                  game: mockGame,
                  comparison: MatchComparison.sameOrder,
                ),
                onPinToggle: (_) {},
                pinnedIds: const [],
              ),
            ),
          );
        }),
      ],
    );
  }
}

// ============================================================================
// ANIMATED GAME CARD TRANSITION
// ============================================================================

/// Animated wrapper for game cards using motor springs
/// Provides smooth crossfade with scale when game at a slot changes
class _AnimatedGameCardSlot extends StatefulWidget {
  const _AnimatedGameCardSlot({
    super.key,
    required this.gameId,
    required this.child,
  });

  final String gameId;
  final Widget child;

  @override
  State<_AnimatedGameCardSlot> createState() => _AnimatedGameCardSlotState();
}

class _AnimatedGameCardSlotState extends State<_AnimatedGameCardSlot> {
  double _animationProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _animationProgress = 1.0; // Start fully visible
  }

  @override
  void didUpdateWidget(covariant _AnimatedGameCardSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If game changed, trigger animation
    if (oldWidget.gameId != widget.gameId) {
      _animationProgress = 0.0;
      // Animate to 1.0
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _animationProgress = 1.0;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      motion: const CupertinoMotion.bouncy(),
      value: _animationProgress,
      builder: (context, value, child) {
        // Scale and fade in effect
        final scale = 0.92 + (0.08 * value);
        final opacity = value.clamp(0.0, 1.0);

        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: widget.child,
          ),
        );
      },
    );
  }
}
