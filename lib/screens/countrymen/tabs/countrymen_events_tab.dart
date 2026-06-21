import 'dart:async';

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/scroll_to_top_button.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// --- Provider ---

final countrymenEventsProvider = StateNotifierProvider.autoDispose<
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
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(countrymenEventsProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      ref.read(countrymenEventsProvider.notifier).search(value);
    });
  }

  void _clearSearch() {
    HapticFeedback.lightImpact();
    _debounceTimer?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(countrymenEventsProvider.notifier).clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final state = ref.watch(countrymenEventsProvider);
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    Widget content = RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        await ref.read(countrymenEventsProvider.notifier).refresh();
      },
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // Search bar (scrolls with content)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                12.h,
                horizontalPadding,
                8.h,
              ),
              child: SearchBarWidget(
                hintText: 'Search',
                margin: 0.sp,
                autoFocus: false,
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                onClose: _clearSearch,
              ),
            ),
          ),
          // Content
          _buildContentSliver(state),
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
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _buildNoSearchResultsState(),
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
    final showLoadingIndicator =
        (state.hasMore || state.isLoading) && events.isNotEmpty;

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
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 24.h),
              child: Center(
                child:
                    state.isLoading
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
                                color: const Color(0xFF71717A),
                              ),
                            ),
                          ],
                        )
                        : state.hasMore
                        ? const SizedBox.shrink()
                        : Text(
                          'No more events',
                          style: AppTypography.textXsRegular.copyWith(
                            color: const Color(0xFF52525B),
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

  void _onEventTap(GroupBroadcast event) {
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
              color: const Color(0xFFA1A1AA),
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
              color: const Color(0xFFEF4444).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16.br),
            ),
            child: Icon(
              Icons.error_outline_rounded,
              color: const Color(0xFFEF4444),
              size: 32.ic,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Failed to load events',
            style: AppTypography.textMdMedium.copyWith(color: context.colors.textPrimary),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.w),
            child: Text(
              error,
              style: AppTypography.textSmRegular.copyWith(
                color: const Color(0xFFA1A1AA),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: 24.h),
          TextButton(
            onPressed:
                () => ref.read(countrymenEventsProvider.notifier).refresh(),
            style: TextButton.styleFrom(
              backgroundColor: context.colors.textPrimary.withValues(alpha: 0.1),
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.br),
              ),
            ),
            child: Text(
              'Retry',
              style: AppTypography.textSmMedium.copyWith(color: context.colors.textPrimary),
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
            style: AppTypography.textMdMedium.copyWith(color: context.colors.textPrimary),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40.w),
            child: Text(
              'No chess events found in $countryName',
              style: AppTypography.textSmRegular.copyWith(
                color: const Color(0xFFA1A1AA),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildNoSearchResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_outlined,
            size: 56.sp,
            color: context.colors.textPrimary.withValues(alpha: 0.4),
          ),
          SizedBox(height: 12.h),
          Text(
            'No results',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.85),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Try a different search term',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}
