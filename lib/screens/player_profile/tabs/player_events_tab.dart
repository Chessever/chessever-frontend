import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/utils/twic_event_navigation.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart' hide ShimmerEffect;
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Events tab showing tournaments the player has participated in
class PlayerEventsTab extends ConsumerStatefulWidget {
  const PlayerEventsTab({
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
  ConsumerState<PlayerEventsTab> createState() => _PlayerEventsTabState();
}

class _PlayerEventsTabState extends ConsumerState<PlayerEventsTab>
    with AutomaticKeepAliveClientMixin, ScrollToTopListenerMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  void onScrollToTopRequested() {
    animateScrollControllerToTop(_scrollController);
  }

  static const int _twicPageSize = 24;
  List<PlayerEventData> _twicEvents = const [];
  bool _twicIsLoading = false;
  bool _twicIsLoadingMore = false;
  bool _twicHasMore = true;
  int _twicNextPage = 0;
  int? _twicTotalEvents;
  String? _twicError;
  int _loadToken = 0;

  @override
  bool get wantKeepAlive => true;

  /// Get the player profile key for provider lookups
  PlayerProfileKey get _playerKey => PlayerProfileKey(
    fideId: widget.fideId,
    playerName: widget.playerName,
    source: widget.dataSource,
    gamebasePlayerId: widget.gamebasePlayerId,
  );

  bool get _isTwic => widget.dataSource == PlayerProfileDataSource.twic;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (_isTwic) {
      _loadTwicEvents(reset: true);
    }
  }

  @override
  void didUpdateWidget(covariant PlayerEventsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKey = PlayerProfileKey(
      fideId: oldWidget.fideId,
      playerName: oldWidget.playerName,
      source: oldWidget.dataSource,
      gamebasePlayerId: oldWidget.gamebasePlayerId,
    );
    if (oldKey != _playerKey && _isTwic) {
      _loadTwicEvents(reset: true);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_isTwic || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 520) return;
    _loadTwicEvents();
  }

  Future<void> _loadTwicEvents({bool reset = false}) async {
    if (!_isTwic) return;
    if (reset) {
      _loadToken += 1;
      _twicNextPage = 0;
      _twicHasMore = true;
      _twicTotalEvents = null;
      _twicError = null;
      _twicEvents = const [];
      _twicIsLoading = true;
      _twicIsLoadingMore = false;
      if (mounted) setState(() {});
    } else {
      if (_twicIsLoading || _twicIsLoadingMore || !_twicHasMore) return;
      _twicIsLoadingMore = true;
      _twicError = null;
      if (mounted) setState(() {});
    }

    // Load events straight from the paginated /events endpoint, page by page.
    // Do NOT derive events by downloading the player's entire game history
    // (playerEventsKeyProvider -> playerGamesDataKeyProvider pages through
    // every game) — that is what made this tab spin forever. The events
    // endpoint returns the exact `game.event` names, which also match what
    // /api/event expects when an event card is tapped.
    final token = _loadToken;
    final repo = ref.read(gamebaseRepositoryProvider);
    final playerId = await ref.read(twicPlayerIdProvider(_playerKey).future);
    if (!mounted || token != _loadToken) return;
    if (playerId == null || playerId.isEmpty) {
      _twicIsLoading = false;
      _twicIsLoadingMore = false;
      _twicHasMore = false;
      if (mounted) setState(() {});
      return;
    }

    try {
      final response = await repo.getPlayerEvents(
        playerId: playerId,
        pageNumber: _twicNextPage,
        pageSize: _twicPageSize,
      );
      if (!mounted || token != _loadToken) return;

      final incoming = response.events
          .where((item) => item.event.trim().isNotEmpty)
          .map(playerEventDataFromGamebaseEvent)
          .toList(growable: false);

      // The /events endpoint groups by raw `g.event`, so broadcast-ingested
      // events arrive as one row per "Round N: A - B" pairing. Merge by the
      // canonical event identity (recovered from the Site slug) so the list
      // shows real events, not rounds. Merging across pages is safe because we
      // re-merge the full accumulated set each page.
      _twicEvents = mergePlayerEventsByCanonical([..._twicEvents, ...incoming])
        ..sort((a, b) {
          final aDate = a.endDate ?? a.startDate ?? DateTime(1900);
          final bDate = b.endDate ?? b.startDate ?? DateTime(1900);
          return bDate.compareTo(aDate);
        });

      _twicHasMore = response.metadata.hasMore;
      // Server totalCount counts raw per-pairing rows; show the distinct merged
      // event count instead so the header isn't inflated.
      _twicTotalEvents = _twicEvents.length;
      if (response.events.isEmpty) {
        _twicHasMore = false;
      }
      _twicNextPage += 1;
      _twicIsLoading = false;
      _twicIsLoadingMore = false;
      setState(() {});
    } catch (e, st) {
      talker.handle(e, st);
      if (!mounted || token != _loadToken) return;
      _twicError = userFacingError(e);
      _twicIsLoading = false;
      _twicIsLoadingMore = false;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Watch the current time control filter
    final gamesState = ref.watch(playerProfileGamesKeyProvider(_playerKey));
    final currentTimeControl = gamesState.filter.timeControl;
    final hasActiveFilter = currentTimeControl != GameTimeControlFilter.all;

    Widget content;
    if (_isTwic) {
      content = RefreshIndicator(
        onRefresh: () async {
          HapticFeedbackService.medium();
          ref.invalidate(
            twicPlayerStatsProvider(
              TwicPlayerStatsRequest(
                playerKey: _playerKey,
                scope: TwicStatsScope.filtered,
              ),
            ),
          );
          await _loadTwicEvents(reset: true);
        },
        color: context.colors.textPrimary,
        backgroundColor: context.colors.surface,
        child:
            _twicIsLoading && _twicEvents.isEmpty
                ? _buildLoadingState()
                : (_twicError != null && _twicEvents.isEmpty)
                ? _buildErrorState(_twicError!)
                : (_twicEvents.isEmpty)
                ? _buildEmptyState()
                : _EventsListContent(
                  events: _twicEvents,
                  playerKey: _playerKey,
                  dataSource: widget.dataSource,
                  timeControlFilter: currentTimeControl,
                  hasActiveFilter: hasActiveFilter,
                  scrollController: _scrollController,
                  hasMorePages: _twicHasMore,
                  isLoadingMore: _twicIsLoadingMore,
                  totalEventsOverride: _twicTotalEvents,
                  onLoadMore: () => _loadTwicEvents(),
                ),
      );
    } else {
      final eventsAsync = ref.watch(playerEventsKeyProvider(_playerKey));
      content = RefreshIndicator(
        onRefresh: () async {
          HapticFeedbackService.medium();
          ref.invalidate(playerEventsKeyProvider(_playerKey));
          ref.invalidate(playerEventCardProvider);
        },
        color: context.colors.textPrimary,
        backgroundColor: context.colors.surface,
        child: eventsAsync.when(
          data: (events) {
            if (events.isEmpty) {
              return _buildEmptyState();
            }

            final sortedEvents = List<PlayerEventData>.from(events)
              ..sort((a, b) {
                final aDate = a.endDate ?? a.startDate ?? DateTime(1900);
                final bDate = b.endDate ?? b.startDate ?? DateTime(1900);
                return bDate.compareTo(aDate);
              });

            return _EventsListContent(
              events: sortedEvents,
              playerKey: _playerKey,
              dataSource: widget.dataSource,
              timeControlFilter: currentTimeControl,
              hasActiveFilter: hasActiveFilter,
            );
          },
          loading: () => _buildLoadingState(),
          error: (error, _) => _buildErrorState(userFacingError(error)),
        ),
      );
    }

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

    return content;
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Center(
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
                  Icons.emoji_events_outlined,
                  color: context.colors.textPrimary.withValues(alpha: 0.7),
                  size: 40.ic,
                ),
              ),
              SizedBox(height: 20.h),
              Text(
                'No tournaments found',
                style: AppTypography.textMdMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
              SizedBox(height: 8.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 40.w),
                child: Text(
                  'This player has no recorded tournament participations.',
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48.w,
            height: 48.h,
            child: CircularProgressIndicator(
              color: context.colors.textPrimary,
              strokeWidth: 2.5,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Loading tournaments...',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildErrorState(String error) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Center(
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
                'Failed to load tournaments',
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
                    color: context.colors.textPrimary.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: 24.h),
              GestureDetector(
                onTap: () {
                  HapticFeedbackService.buttonPress();
                  if (_isTwic) {
                    _loadTwicEvents(reset: true);
                  } else {
                    ref.invalidate(playerEventsKeyProvider(_playerKey));
                  }
                },
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 24.w,
                    vertical: 12.h,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.textPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8.br),
                  ),
                  child: Text(
                    'Retry',
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

/// Content widget that shows statistics and event list
class _EventsListContent extends ConsumerWidget {
  const _EventsListContent({
    required this.events,
    required this.playerKey,
    required this.dataSource,
    this.timeControlFilter = GameTimeControlFilter.all,
    this.hasActiveFilter = false,
    this.scrollController,
    this.hasMorePages = false,
    this.isLoadingMore = false,
    this.totalEventsOverride,
    this.onLoadMore,
  });

  final List<PlayerEventData> events;
  final PlayerProfileKey playerKey;
  final PlayerProfileDataSource dataSource;
  final GameTimeControlFilter timeControlFilter;
  final bool hasActiveFilter;
  final ScrollController? scrollController;
  final bool hasMorePages;
  final bool isLoadingMore;
  final int? totalEventsOverride;
  final Future<void> Function()? onLoadMore;

  /// Check if an event matches the time control filter
  bool _eventMatchesTimeControl(PlayerEventData event) {
    if (timeControlFilter == GameTimeControlFilter.all) return true;
    final eventTimeControl = (event.dominantTimeControl ?? '').toLowerCase();
    if (eventTimeControl.isEmpty) return true;

    switch (timeControlFilter) {
      case GameTimeControlFilter.classical:
        return eventTimeControl.contains('classical') ||
            eventTimeControl.contains('standard');
      case GameTimeControlFilter.rapid:
        return eventTimeControl.contains('rapid');
      case GameTimeControlFilter.blitz:
        return eventTimeControl.contains('blitz') ||
            eventTimeControl.contains('bullet');
      case GameTimeControlFilter.all:
        return true;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final twicStatsAsync =
        dataSource == PlayerProfileDataSource.twic
            ? ref.watch(
              twicPlayerStatsProvider(
                TwicPlayerStatsRequest(
                  playerKey: playerKey,
                  scope: TwicStatsScope.filtered,
                ),
              ),
            )
            : const AsyncValue<PlayerAnalytics?>.data(null);
    final twicStats = twicStatsAsync.valueOrNull;

    Widget buildEventList() {
      final filteredEvents =
          hasActiveFilter
              ? events.where(_eventMatchesTimeControl).toList(growable: false)
              : events;

      final computedTotalGames = filteredEvents.fold<int>(
        0,
        (sum, e) => sum + e.gamesPlayed,
      );
      final computedTotalScore = filteredEvents.fold<double>(
        0,
        (sum, e) => sum + (e.score ?? 0),
      );
      final computedAvgScore =
          computedTotalGames > 0
              ? computedTotalScore / computedTotalGames
              : 0.0;

      final totalGames =
          twicStats?.resultStats.totalGames ?? computedTotalGames;
      final avgScore = twicStats?.resultStats.score ?? computedAvgScore;

      final horizontalPadding = ResponsiveHelper.adaptive(
        phone: 16.w,
        tablet: 24.w,
      );
      final headerItemCount = hasActiveFilter ? 2 : 1;
      final showFooter = hasMorePages || isLoadingMore;
      final emptyFiltered = filteredEvents.isEmpty && hasActiveFilter;
      final baseItemCount =
          emptyFiltered
              ? headerItemCount + 1
              : filteredEvents.length + headerItemCount;
      final totalItems = baseItemCount + (showFooter ? 1 : 0);

      return ListView.builder(
        controller: scrollController,
        scrollCacheExtent: kListScrollCacheExtent,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 16.h,
        ),
        itemCount: totalItems,
        itemBuilder: (context, index) {
          if (showFooter && index == totalItems - 1) {
            if (hasMorePages && !isLoadingMore && onLoadMore != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                onLoadMore!.call();
              });
            }
            return _EventsPaginationFooter(
              hasMorePages: hasMorePages,
              isLoadingMore: isLoadingMore,
              loadedEvents: events.length,
            );
          }

          if (hasActiveFilter && index == 0) {
            return _FilterActiveBanner(
              timeControl: timeControlFilter,
              totalEvents: events.length,
              filteredEvents: filteredEvents.length,
            );
          }

          final statsHeaderIndex = hasActiveFilter ? 1 : 0;
          if (index == statsHeaderIndex) {
            return _StatsHeader(
              totalEvents: totalEventsOverride ?? filteredEvents.length,
              totalGames: totalGames,
              avgScore: avgScore,
            );
          }

          if (emptyFiltered) {
            return _buildNoFilterResultsState(context, timeControlFilter);
          }

          final eventIndex = index - headerItemCount;
          final event = filteredEvents[eventIndex];

          return Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: _PlayerEventCard(
              playerEventData: event,
              index: eventIndex,
              dataSource: dataSource,
            ),
          );
        },
      );
    }

    return buildEventList();
  }

  Widget _buildNoFilterResultsState(
    BuildContext context,
    GameTimeControlFilter timeControl,
  ) {
    const filterRedColor = Color(0xFFEF4444);
    return Center(
      child: Padding(
        padding: EdgeInsets.only(top: 40.h),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.filter_alt_off_outlined,
              size: 56.sp,
              color: filterRedColor.withValues(alpha: 0.5),
            ),
            SizedBox(height: 12.h),
            Text(
              'No ${timeControl.displayText} events',
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.85),
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'This player has no ${timeControl.displayText.toLowerCase()} tournaments.\nTap the time control card to clear filter.',
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.55),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

/// Filter active banner showing which time control filter is applied
class _FilterActiveBanner extends StatelessWidget {
  const _FilterActiveBanner({
    required this.timeControl,
    required this.totalEvents,
    required this.filteredEvents,
  });

  final GameTimeControlFilter timeControl;
  final int totalEvents;
  final int filteredEvents;

  static const _filterRedColor = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: _filterRedColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10.br),
        border: Border.all(
          color: _filterRedColor.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8.w,
            height: 8.w,
            decoration: const BoxDecoration(
              color: _filterRedColor,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              'Showing ${timeControl.displayText} events only',
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
          Text(
            '$filteredEvents of $totalEvents',
            style: AppTypography.textXsMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.1, end: 0);
  }
}

/// Statistics header section - similar design to about tab
class _StatsHeader extends StatelessWidget {
  const _StatsHeader({
    required this.totalEvents,
    required this.totalGames,
    required this.avgScore,
  });

  final int totalEvents;
  final int totalGames;
  final double avgScore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tournament Statistics',
          style: AppTypography.textSmBold.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
        SizedBox(height: 12.h),
        Container(
          padding: EdgeInsets.all(16.sp),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(12.br),
          ),
          child: Row(
            children: [
              _StatBox(
                value: totalEvents.toString(),
                label: 'Events',
                color: kPrimaryColor,
              ),
              SizedBox(width: 12.w),
              _StatBox(
                value: totalGames.toString(),
                label: 'Games',
                color: context.colors.textPrimaryMuted,
              ),
              SizedBox(width: 12.w),
              _StatBox(
                value: '${(avgScore * 100).toStringAsFixed(1)}%',
                label: 'Avg Score',
                color: _getScoreColor(context, avgScore),
              ),
            ],
          ),
        ),
        SizedBox(height: 24.h),
        Text(
          'Participated Events',
          style: AppTypography.textSmBold.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
        SizedBox(height: 12.h),
      ],
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.02, end: 0);
  }

  Color _getScoreColor(BuildContext context, double score) {
    if (score >= 0.6) return kGreenColor;
    if (score >= 0.4) return context.colors.textPrimary;
    return Colors.redAccent;
  }
}

/// Stat box widget
class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8.br),
        ),
        child: Column(
          children: [
            Text(value, style: AppTypography.textMdBold.copyWith(color: color)),
            SizedBox(height: 2.h),
            Text(
              label,
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventsPaginationFooter extends StatelessWidget {
  const _EventsPaginationFooter({
    required this.hasMorePages,
    required this.isLoadingMore,
    required this.loadedEvents,
  });

  final bool hasMorePages;
  final bool isLoadingMore;
  final int loadedEvents;

  @override
  Widget build(BuildContext context) {
    if (isLoadingMore) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 16.h),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
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
              'Loading more events...',
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.textPrimaryMuted,
              ),
            ),
          ],
        ),
      );
    }

    if (!hasMorePages) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 14.h),
        child: Center(
          child: Text(
            'Loaded $loadedEvents events',
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.45),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 14.h),
      child: Center(
        child: Text(
          'Loading more events...',
          style: AppTypography.textXsRegular.copyWith(
            color: context.colors.textPrimaryMuted,
          ),
        ),
      ),
    );
  }
}

/// Player event card using standard EventCard with player stats overlay
class _PlayerEventCard extends ConsumerWidget {
  const _PlayerEventCard({
    required this.playerEventData,
    required this.index,
    required this.dataSource,
  });

  final PlayerEventData playerEventData;
  final int index;
  final PlayerProfileDataSource dataSource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = PlayerProfileEventCardRequest.fromEvent(
      dataSource: dataSource,
      event: playerEventData,
    );
    final resolvedCard =
        ref.watch(playerEventCardProvider(request)).valueOrNull;
    final displayCard =
        resolvedCard ?? buildPlayerEventFallbackCard(playerEventData);

    return GestureDetector(
          onTap: () => _navigateToTournament(context, ref, displayCard),
          child: Column(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: EventCard(
                  key: ValueKey(displayCard.id),
                  tourEventCardModel: displayCard,
                  heroTagSuffix: 'player-profile-$index',
                  // Embedded inside a SliverList (unbounded height) — must use
                  // the compact phone layout to avoid Stack-expand crash.
                  forceCompactLayout: true,
                ),
              ),
              // Player stats row
              Container(
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
                          color: context.colors.textPrimary.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        SizedBox(width: 4.w),
                        Text(
                          '${playerEventData.gamesPlayed} ${playerEventData.gamesPlayed == 1 ? 'game' : 'games'}',
                          style: AppTypography.textXsRegular.copyWith(
                            color: context.colors.textPrimary.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (playerEventData.score != null)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8.w,
                          vertical: 3.h,
                        ),
                        decoration: BoxDecoration(
                          color: _getScoreColor(
                            context,
                            playerEventData.score!,
                            playerEventData.gamesPlayed,
                          ).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4.br),
                        ),
                        child: Text(
                          '${playerEventData.score!.toStringAsFixed(1)}/${playerEventData.gamesPlayed}',
                          style: AppTypography.textXsBold.copyWith(
                            color: _getScoreColor(
                              context,
                              playerEventData.score!,
                              playerEventData.gamesPlayed,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(
          duration: 200.ms,
          delay: Duration(milliseconds: (index % 10) * 50),
        )
        .slideY(begin: 0.02, end: 0);
  }

  Future<void> _navigateToTournament(
    BuildContext context,
    WidgetRef ref,
    GroupEventCardModel displayCard,
  ) {
    return openProfileEvent(
      context: context,
      ref: ref,
      dataSource: dataSource,
      tourId: playerEventData.tourId,
      eventName: playerEventData.tourName,
      site: playerEventData.site,
      canonicalBroadcastId:
          displayCard.eventSource == EventSource.lichessBroadcast
              ? displayCard.id
              : null,
    );
  }

  Color _getScoreColor(BuildContext context, double score, int totalGames) {
    if (totalGames == 0) return context.colors.textPrimary;
    final percentage = score / totalGames;
    if (percentage >= 0.6) return kGreenColor;
    if (percentage >= 0.4) return context.colors.textPrimary;
    return Colors.redAccent;
  }
}
