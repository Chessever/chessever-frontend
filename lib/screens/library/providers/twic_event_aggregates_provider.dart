import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models_extra.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart';
import 'package:chessever2/screens/library/providers/gamebase_filter_provider.dart';
import 'package:chessever2/screens/library/widgets/library_gamebase_filter_dialog.dart';
import 'package:chessever2/utils/time_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final twicSelectedEventProvider = StateProvider.autoDispose<String?>((ref) => null);

class TwicEventAggregate {
  const TwicEventAggregate({
    required this.id,
    required this.event,
    required this.gameCount,
    this.site,
    this.startDate,
    this.endDate,
    this.dominantTimeControl,
    this.avgElo,
    this.maxElo,
  });

  final String id;
  final String event;
  final int gameCount;
  final String? site;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? dominantTimeControl;
  final int? avgElo;
  final int? maxElo;

  factory TwicEventAggregate.fromApi(GamebaseEventSearchItem item) {
    return TwicEventAggregate(
      id: item.id,
      event: item.event,
      gameCount: item.gameCount,
      site: item.site,
      startDate: item.startDate,
      endDate: item.endDate,
      dominantTimeControl: item.dominantTimeControl,
      avgElo: item.avgElo,
      maxElo: item.maxElo,
    );
  }
}

String _formatTimeControl(String? raw) {
  final normalized = raw?.trim().toUpperCase();
  switch (normalized) {
    case 'CLASSICAL':
      return 'Standard';
    case 'RAPID':
      return 'Rapid';
    case 'BLITZ':
      return 'Blitz';
    default:
      return 'Standard';
  }
}

// ---------------------------------------------------------------------------
// Paginated event aggregates
// ---------------------------------------------------------------------------

class TwicEventAggregatesPaginationState {
  final List<TwicEventAggregate> events;
  final int currentPage;
  final bool isLoading;
  final bool hasMore;
  final String? error;

  const TwicEventAggregatesPaginationState({
    this.events = const [],
    this.currentPage = 0,
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  TwicEventAggregatesPaginationState copyWith({
    List<TwicEventAggregate>? events,
    int? currentPage,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) {
    return TwicEventAggregatesPaginationState(
      events: events ?? this.events,
      currentPage: currentPage ?? this.currentPage,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

class TwicEventAggregatesNotifier
    extends StateNotifier<TwicEventAggregatesPaginationState> {
  final Ref _ref;
  final String _query;
  final GamebaseFilter _filter;

  static const int _pageSize = 20;

  TwicEventAggregatesNotifier(this._ref, this._query, this._filter)
      : super(const TwicEventAggregatesPaginationState()) {
    _loadInitialPage();
  }

  Future<void> _loadInitialPage() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await _fetchPage(1);
      state = TwicEventAggregatesPaginationState(
        events: result.events,
        currentPage: 1,
        isLoading: false,
        hasMore: result.hasMore,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        hasMore: false,
      );
    }
  }

  Future<void> loadNextPage() async {
    if (state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoading: true);

    try {
      final nextPage = state.currentPage + 1;
      final result = await _fetchPage(nextPage);

      state = state.copyWith(
        events: [...state.events, ...result.events],
        currentPage: nextPage,
        isLoading: false,
        hasMore: result.hasMore,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<_EventPageResult> _fetchPage(int pageNumber) async {
    final repo = _ref.read(gamebaseRepositoryProvider);

    final response = await repo.searchEvents(
      query: _query.isEmpty ? '*' : _query,
      pageNumber: pageNumber,
      pageSize: _pageSize,
      result: _filter.resultApiValue,
      color: _filter.colorApiValue,
      timeControl: _filter.timeControlApiValue,
      yearFrom: _filter.minYear != 1800 ? _filter.minYear : null,
      yearTo: _filter.maxYear != DateTime.now().year ? _filter.maxYear : null,
      ratingFrom: _filter.minRating > 0 ? _filter.minRating : null,
      ratingTo: _filter.maxRating < 3500 ? _filter.maxRating : null,
    );

    final events = response.events
        .where((e) => e.event.trim().isNotEmpty)
        .map(TwicEventAggregate.fromApi)
        .toList(growable: false);

    return _EventPageResult(
      events: events,
      hasMore: response.metadata.hasMore,
    );
  }
}

class _EventPageResult {
  final List<TwicEventAggregate> events;
  final bool hasMore;

  const _EventPageResult({required this.events, required this.hasMore});
}

/// Paginated event aggregates provider.
/// Recreated when search query or filters change.
final twicEventAggregatesPaginatedProvider = StateNotifierProvider.autoDispose<
    TwicEventAggregatesNotifier, TwicEventAggregatesPaginationState>((ref) {
  final query = ref.watch(librarySearchQueryProvider).trim();
  final filter = ref.watch(gamebaseFilterProvider);
  return TwicEventAggregatesNotifier(ref, query, filter);
});

/// Whether the user has provided any search input or active filters.
/// Used to gate event card visibility — no events shown on default state.
final hasUserInputProvider = Provider.autoDispose<bool>((ref) {
  final query = ref.watch(librarySearchQueryProvider).trim();
  final hasFilters = ref.watch(hasActiveGamebaseFiltersProvider);
  return query.isNotEmpty || hasFilters;
});

final twicEventCardModelsProvider =
    Provider.autoDispose<List<GroupEventCardModel>>((ref) {
      final eventState = ref.watch(twicEventAggregatesPaginatedProvider);
      final events = eventState.events;

      return events.map((event) {
        return GroupEventCardModel(
          id: event.id,
          title: event.event,
          dates: TimeUtils.formatDateRange(event.startDate, event.endDate),
          maxAvgElo: event.avgElo ?? event.maxElo ?? 0,
          timeUntilStart: TimeUtils.timeUntilStart(event.startDate),
          tourEventCategory: GroupEventCardModel.getCategory(
            groupId: event.id,
            groupName: event.event,
            startDate: event.startDate,
            endDate: event.endDate,
            liveGroupIds: const [],
          ),
          timeControl: _formatTimeControl(event.dominantTimeControl),
          endDate: event.endDate,
          startDate: event.startDate,
          location: event.site,
          searchTerms: [event.event],
          eventSource: EventSource.communityEvent,
        );
      }).toList(growable: false);
    });
