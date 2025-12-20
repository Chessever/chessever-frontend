import 'dart:async';

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// --- Provider ---

final countrymenEventsProvider = StateNotifierProvider.autoDispose<
    CountrymenEventsNotifier, CountrymenEventsState>(
  (ref) => CountrymenEventsNotifier(ref),
);

class CountrymenEventsState {
  final List<Tour> events;
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
    List<Tour>? events,
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

    // Listen to country changes
    _ref.listen(countryDropdownProvider, (previous, next) {
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

    final countryAsync = _ref.read(countryDropdownProvider);
    final country = countryAsync.valueOrNull;

    if (country == null) {
      state = state.copyWith(isLoading: false, hasMore: false);
      return;
    }

    state = state.copyWith(isLoading: true);

    try {
      final repo = _ref.read(tourRepositoryProvider);
      final offset = isInitial ? 0 : state.offset;

      final events = state.isSearching
          ? await repo.searchTours(
              query: state.searchQuery,
              countryName: country.name,
              limit: _pageSize,
              offset: offset,
            )
          : await repo.getToursByCountryLocation(
              countryName: country.name,
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
      state = state.copyWith(isLoading: false, error: e.toString());
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
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
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

    return Column(
      children: [
        SizedBox(height: 12.h),
        // Search bar
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: SearchBarWidget(
            hintText: 'Search events',
            margin: 0.sp,
            autoFocus: false,
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: _onSearchChanged,
            onClose: _clearSearch,
          ),
        ),
        SizedBox(height: 8.h),
        // Events list
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              HapticFeedbackService.medium();
              await ref.read(countrymenEventsProvider.notifier).refresh();
            },
            color: kWhiteColor,
            backgroundColor: kBlack2Color,
            child: _buildContent(state),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(CountrymenEventsState state) {
    if (state.isLoading && state.events.isEmpty) {
      return _buildLoadingState();
    }

    if (state.error != null && state.events.isEmpty) {
      return _buildErrorState(state.error!);
    }

    if (state.events.isEmpty) {
      if (state.isSearching) {
        return _buildNoSearchResultsState();
      }
      return _buildEmptyState();
    }

    return _buildEventsList(state);
  }

  Widget _buildEventsList(CountrymenEventsState state) {
    final events = state.events;
    final showLoadingIndicator =
        (state.hasMore || state.isLoading) && events.isNotEmpty;

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      itemCount: events.length + (showLoadingIndicator ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= events.length) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 24.h),
            child: Center(
              child: state.isLoading
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24.w,
                          height: 24.h,
                          child: const CircularProgressIndicator(
                            color: kWhiteColor,
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
        return Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: _EventCard(event: event),
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48.w,
            height: 48.h,
            child: const CircularProgressIndicator(
              color: kWhiteColor,
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
            style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
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
            onPressed: () =>
                ref.read(countrymenEventsProvider.notifier).refresh(),
            style: TextButton.styleFrom(
              backgroundColor: kWhiteColor.withValues(alpha: 0.1),
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.br),
              ),
            ),
            child: Text(
              'Retry',
              style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildEmptyState() {
    final countryAsync = ref.watch(countryDropdownProvider);
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
                  kWhiteColor.withValues(alpha: 0.15),
                  kWhiteColor.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(20.br),
            ),
            child: Icon(
              Icons.event_outlined,
              color: kWhiteColor.withValues(alpha: 0.7),
              size: 40.ic,
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            'No events found',
            style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
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
            color: kWhiteColor.withValues(alpha: 0.4),
          ),
          SizedBox(height: 12.h),
          Text(
            'No results',
            style: AppTypography.textMdMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.85),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Try a different search term',
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

class _EventCard extends StatelessWidget {
  final Tour event;

  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Navigate to event detail
        // TODO: Implement navigation to event detail
      },
      child: Container(
        padding: EdgeInsets.all(16.sp),
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color: const Color(0xFF27272A),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event name
            Text(
              event.name,
              style: AppTypography.textMdMedium.copyWith(
                color: kWhiteColor,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 8.h),
            // Date and location row
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 14.ic,
                  color: const Color(0xFFA1A1AA),
                ),
                SizedBox(width: 6.w),
                Text(
                  event.dateRangeFormatted,
                  style: AppTypography.textXsRegular.copyWith(
                    color: const Color(0xFFA1A1AA),
                  ),
                ),
                if (event.info.location != null) ...[
                  SizedBox(width: 12.w),
                  Icon(
                    Icons.location_on_outlined,
                    size: 14.ic,
                    color: const Color(0xFFA1A1AA),
                  ),
                  SizedBox(width: 4.w),
                  Expanded(
                    child: Text(
                      event.info.location!,
                      style: AppTypography.textXsRegular.copyWith(
                        color: const Color(0xFFA1A1AA),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
            if (event.avgElo != null || event.totalPlayers > 0) ...[
              SizedBox(height: 8.h),
              Row(
                children: [
                  if (event.avgElo != null) ...[
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8.w,
                        vertical: 4.h,
                      ),
                      decoration: BoxDecoration(
                        color: kPrimaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4.br),
                      ),
                      child: Text(
                        'Avg ${event.avgElo}',
                        style: AppTypography.textXsMedium.copyWith(
                          color: kPrimaryColor,
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                  ],
                  if (event.totalPlayers > 0)
                    Text(
                      '${event.totalPlayers} players',
                      style: AppTypography.textXsRegular.copyWith(
                        color: const Color(0xFF71717A),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
