import 'dart:async';

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/screens/favorites/widgets/collection_inks.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/search_no_matches.dart';
import 'package:chessever2/widgets/paywall/past_event_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// --- Provider ---

final countrymenEventsProvider =
    StateNotifierProvider.autoDispose<
      CountrymenEventsNotifier,
      CountrymenEventsState
    >((ref) => CountrymenEventsNotifier(ref));

class CountrymenEventsState {
  final List<GroupBroadcast> events;
  final bool isLoading;
  final bool hasMore;
  final int offset;
  final String searchQuery;
  final String? error;

  const CountrymenEventsState({
    this.events = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.offset = 0,
    this.searchQuery = '',
    this.error,
  });

  bool get isSearching => searchQuery.isNotEmpty;

  CountrymenEventsState copyWith({
    List<GroupBroadcast>? events,
    bool? isLoading,
    bool? hasMore,
    int? offset,
    String? searchQuery,
    String? error,
  }) {
    return CountrymenEventsState(
      events: events ?? this.events,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      offset: offset ?? this.offset,
      searchQuery: searchQuery ?? this.searchQuery,
      error: error,
    );
  }
}

class CountrymenEventsNotifier extends StateNotifier<CountrymenEventsState> {
  final Ref _ref;
  static const int _pageSize = 20;

  CountrymenEventsNotifier(this._ref)
    : super(const CountrymenEventsState(isLoading: true)) {
    _loadInitial();

    // Listen to effective country changes (includes temporary selections)
    _ref.listen(effectiveCountryProvider, (previous, next) {
      next.whenData((country) {
        if (previous?.valueOrNull?.countryCode != country.countryCode) {
          refresh();
        }
      });
    });
  }

  Future<void> _loadInitial() async {
    await _fetchEvents(isInitial: true);
  }

  Future<void> _fetchEvents({required bool isInitial}) async {
    if (!mounted) return;

    final countryAsync = _ref.read(effectiveCountryProvider);
    final country = countryAsync.valueOrNull;

    if (country == null) {
      state = state.copyWith(isLoading: false, hasMore: false);
      return;
    }

    state = state.copyWith(isLoading: true);

    try {
      final repo = _ref.read(groupBroadcastRepositoryProvider);
      final offset = isInitial ? 0 : state.offset;

      // Use the new comprehensive query that fetches GroupBroadcast with images
      // and prioritizes current+upcoming events.
      // Pass both name and code for robust country matching (handles TUR, Turkiye, Turkey, etc.)
      final events = await repo.getGroupBroadcastsByCountry(
        countryName: country.name,
        countryCode: country.countryCode,
        searchQuery: state.isSearching ? state.searchQuery : null,
        limit: _pageSize,
        offset: offset,
      );

      final allEvents = isInitial ? events : [...state.events, ...events];

      if (!mounted) return;

      state = state.copyWith(
        events: allEvents,
        isLoading: false,
        hasMore: events.length >= _pageSize,
        offset: offset + events.length,
      );
    } catch (e) {
      debugPrint('[CountrymenEvents] Error: $e');
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: userFacingError(e, fallback: 'Failed to load events.'),
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    await _fetchEvents(isInitial: false);
  }

  Future<void> search(String query) async {
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      await clearSearch();
      return;
    }

    state = state.copyWith(
      searchQuery: trimmed,
      events: [],
      offset: 0,
      hasMore: true,
    );

    await _fetchEvents(isInitial: true);
  }

  Future<void> clearSearch() async {
    if (!state.isSearching) return;

    state = state.copyWith(
      searchQuery: '',
      events: [],
      offset: 0,
      hasMore: true,
    );

    await _fetchEvents(isInitial: true);
  }

  Future<void> refresh() async {
    state = const CountrymenEventsState(isLoading: true);
    await _loadInitial();
  }
}

// --- Tab Widget ---

class CountrymenEventsTab extends ConsumerStatefulWidget {
  const CountrymenEventsTab({super.key});

  @override
  ConsumerState<CountrymenEventsTab> createState() =>
      _CountrymenEventsTabState();
}

class _CountrymenEventsTabState extends ConsumerState<CountrymenEventsTab>
    with AutomaticKeepAliveClientMixin, ScrollToTopListenerMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  void onScrollToTopRequested() {
    animateScrollControllerToTop(_scrollController);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    _loadMoreNearEnd(_scrollController.position);
  }

  /// The next page, once the reader is within 200pt of the list's end.
  /// Asked on every scroll and whenever the list's size changes under a
  /// still reader ([ScrollMetricsNotification]): a page landing short, the
  /// header folding away and growing the viewport.
  void _loadMoreNearEnd(ScrollMetrics metrics) {
    if (!mounted || !metrics.hasContentDimensions) return;
    if (metrics.maxScrollExtent - metrics.pixels > 200) return;
    // Nothing listed yet (a first load, an error): nothing to page on from.
    if (ref.read(countrymenEventsProvider).events.isEmpty) return;
    ref.read(countrymenEventsProvider.notifier).loadMore();
  }

  bool _onScrollMetrics(ScrollMetricsNotification notification) {
    if (notification.depth == 0 && notification.metrics.axis == Axis.vertical) {
      _loadMoreNearEnd(notification.metrics);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final state = ref.watch(countrymenEventsProvider);

    final content = RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        await ref.read(countrymenEventsProvider.notifier).refresh();
      },
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onScrollMetrics,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            // The search is the page's, from its floating button (Trello
            // #1420): the list starts right under the header.
            SliverToBoxAdapter(child: SizedBox(height: 4.h)),
            // Content
            _buildContentSliver(state),
            // The last card ends clear of the floating search button; the
            // room gives way on the search's own timeline while it is open.
            SearchModeListEnd.sliver(
              base: 24.h,
              buttons: InkFabStack.reach(context),
            ),
          ],
        ),
      ),
    );

    // Cap the width on tablets (contentMaxWidth is unbounded on phones). The
    // wrapper is always present so folding or unfolding an iPhone Duo between
    // phone and tablet widths keeps the same tree, and the list keeps its
    // scroll position instead of remounting at the top.
    //
    // No scroll-to-top button (Trello #1420): tapping the tab again
    // already scrolls up.
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ResponsiveHelper.contentMaxWidth),
        child: SizedBox.expand(child: content),
      ),
    );
  }

  Widget _buildContentSliver(CountrymenEventsState state) {
    if (state.isLoading && state.events.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildLoadingState(),
      );
    }

    if (state.error != null && state.events.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildErrorState(state.error!),
      );
    }

    if (state.events.isEmpty) {
      if (state.isSearching) {
        // The search's words matched no event: said once, where the first
        // card would be, with the way back to every event.
        final search = SearchModeScope.maybeOf(context)?.controller;
        return SearchNoMatches.sliver(
          query: state.searchQuery,
          subject: 'events',
          onClear: search?.text.clear,
        );
      }
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(),
      );
    }

    return _buildEventsSliver(state);
  }

  Widget _buildEventsSliver(CountrymenEventsState state) {
    final events = state.events;
    // The list's end, one slot of one height whatever it holds: the next
    // page loading, room to scroll on into it, or the end. Nothing under
    // the reader's finger jumps as a page starts or lands.
    final showLoadingIndicator = events.isNotEmpty;

    // Get live event IDs for status indicators
    final liveEventIds =
        ref.watch(liveGroupBroadcastIdsProvider).valueOrNull ?? [];

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
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index >= events.length) {
            return SizedBox(
              key: const ValueKey('countrymen_events_list_end_slot'),
              height: 96.h,
              child: Center(
                child: state.isLoading
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 24.w,
                            height: 24.h,
                            child: CircularProgressIndicator(
                              color: context.colors.textPrimary,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            'Loading more events...',
                            style: AppTypography.textXsRegular.copyWith(
                              color: context.collectionSubtleInk,
                            ),
                          ),
                        ],
                      )
                    : state.hasMore
                    ? const SizedBox.shrink()
                    : Text(
                        'No more events',
                        style: AppTypography.textXsRegular.copyWith(
                          color: context.collectionSubtleInk,
                        ),
                      ),
              ),
            );
          }

          final event = events[index];
          // Convert GroupBroadcast to GroupEventCardModel for EventCard widget
          final cardModel = GroupEventCardModel.fromGroupBroadcast(
            event,
            liveEventIds,
          );

          return Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: EventCard(
              tourEventCardModel: cardModel,
              heroTagSuffix: 'countrymen-events-$index',
              onTap: () => _onEventTap(event),
            ),
          );
        }, childCount: events.length + (showLoadingIndicator ? 1 : 0)),
      ),
    );
  }

  Future<void> _onEventTap(GroupBroadcast event) async {
    if (!await ensurePastEventAccess(context, broadcast: event) || !mounted) {
      return;
    }
    ref.read(selectedBroadcastModelProvider.notifier).state = event;
    Navigator.pushNamed(context, '/tournament_detail_screen');
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
            'Loading events...',
            style: AppTypography.textSmRegular.copyWith(
              color: context.collectionMutedInk,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
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
              color: context.collectionAlertInk.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16.br),
            ),
            child: Icon(
              Icons.error_outline_rounded,
              color: context.collectionAlertInk,
              size: 32.ic,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Failed to load events',
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
                color: context.collectionMutedInk,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: 24.h),
          TextButton(
            onPressed: () =>
                ref.read(countrymenEventsProvider.notifier).refresh(),
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
    final countryAsync = ref.watch(effectiveCountryProvider);
    final countryName = countryAsync.valueOrNull?.name ?? 'your country';

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
              Icons.event_outlined,
              color: context.colors.textPrimary.withValues(alpha: 0.7),
              size: 40.ic,
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            'No events found',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40.w),
            child: Text(
              'No chess events found in $countryName',
              style: AppTypography.textSmRegular.copyWith(
                color: context.collectionMutedInk,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.95, 0.95));
  }
}
