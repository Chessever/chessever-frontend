import 'package:chessever2/repository/supabase/game/games.dart'
    show SearchPlayer;
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/screens/group_event/widget/player_search_cards.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/event_time_control.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/layout_swap_scroll_keeper.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Global set to track which event IDs have been animated in search tab
final searchAnimatedEventIds = <String>{};

/// Widget for displaying search results as a list of events (no game cards)
/// Shows player search cards at the top, followed by matching tournament/event cards
class SearchResultsWidget extends HookConsumerWidget {
  const SearchResultsWidget({
    super.key,
    required this.scrollController,
    required this.searchQuery,
  });

  final ScrollController scrollController;
  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Track mounted state
    final isMounted = useRef(true);
    useEffect(() {
      isMounted.value = true;
      return () => isMounted.value = false;
    }, []);

    // Last delivered results: shown while the next (debounced) query loads,
    // so typing never tears the list down into a skeleton and back.
    final lastResults = useRef<EnhancedSearchResult?>(null);

    // Watch the combined search provider for tournaments
    final searchResultsAsync = ref.watch(
      supabaseCombinedSearchProvider(searchQuery.trim()),
    );

    // Watch search filter state
    final searchFilter = ref.watch(searchAppliedFilterProvider);

    // Clear animation tracking when query changes
    useEffect(() {
      searchAnimatedEventIds.clear();
      return null;
    }, [searchQuery]);

    if (!isSearchableQuery(searchQuery)) {
      return _buildInitialState(
        context,
        keepTyping: searchQuery.trim().isNotEmpty,
      );
    }

    Widget buildResults(EnhancedSearchResult results) {
      var tournaments = results.tournamentResults
          .map((r) => r.tournament)
          .toList();

      // Apply client-side filter if active
      if (searchFilter != defaultFilterPopupState) {
        tournaments = _applySearchFilter(tournaments, searchFilter);
      }

      if (tournaments.isEmpty && results.playerResults.isEmpty) {
        return _buildEmptyState(context, searchQuery);
      }

      return _SearchResultsListView(
        scrollController: scrollController,
        tournaments: tournaments,
        players: topSearchedPlayers(results),
        searchQuery: searchQuery,
      );
    }

    return searchResultsAsync.when(
      data: (results) {
        lastResults.value = results;
        return buildResults(results);
      },
      loading: () {
        final previous = lastResults.value;
        if (previous == null || previous.isEmpty) {
          return _buildLoadingState();
        }
        return buildResults(previous);
      },
      error: (error, stackTrace) {
        debugPrint('[SearchResultsWidget] Error: $error');
        return const GenericErrorWidget();
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, String query) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(32.sp),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: 64.sp,
                color: context.colors.iconSecondary,
              ),
              SizedBox(height: 16.sp),
              Text(
                'No events found',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimaryMuted,
                ),
              ),
              SizedBox(height: 8.sp),
              Text(
                'No events match "$query"',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInitialState(BuildContext context, {bool keepTyping = false}) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(32.sp),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search,
                size: 64.sp,
                color: context.colors.iconSecondary,
              ),
              SizedBox(height: 16.sp),
              Text(
                'Search Events',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimaryMuted,
                ),
              ),
              SizedBox(height: 8.sp),
              Text(
                keepTyping
                    ? 'Keep typing to search'
                    : 'Enter a search term to find events',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const _SearchResultsSkeletonLoader();
  }
}

/// Skeleton loader that mimics the search results structure (events only)
class _SearchResultsSkeletonLoader extends StatelessWidget {
  const _SearchResultsSkeletonLoader();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        // Show 5 skeleton event cards
        ...List.generate(5, (index) => _SkeletonEventCard(isFirst: index == 0)),
      ],
    );
  }
}

class _SkeletonEventCard extends StatelessWidget {
  const _SkeletonEventCard({required this.isFirst});

  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    return SkeletonWidget(
      child: Container(
        margin: EdgeInsets.only(top: isFirst ? 0 : 12.sp, bottom: 12.sp),
        height: 80.sp,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: context.colors.divider),
        ),
      ),
    );
  }
}

/// List view showing event cards only (no game cards)
class _SearchResultsListView extends ConsumerWidget {
  const _SearchResultsListView({
    required this.scrollController,
    required this.tournaments,
    required this.players,
    required this.searchQuery,
  });

  final ScrollController scrollController;
  final List<GroupEventCardModel> tournaments;
  final List<SearchPlayer> players;
  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPlayerCards = players.isNotEmpty;
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.sp,
      tablet: 24.sp,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ResponsiveHelper.isTablet
            ? ResponsiveHelper.columnsForWidth(
                constraints.maxWidth - horizontalPadding * 2,
                spacing: 16.sp,
              )
            : 1;
        final cardWidth =
            (constraints.maxWidth -
                horizontalPadding * 2 -
                16.sp * (columns - 1)) /
            columns;
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(supabaseCombinedSearchProvider(searchQuery.trim()));
          },
          color: context.colors.accentText,
          backgroundColor: context.colors.surface,
          displacement: 60.h,
          strokeWidth: 3.w,
          child: LayoutSwapScrollKeeper(
            controller: scrollController,
            layout: columns,
            child: columns > 1
                ? _buildTabletGridLayout(
                    hasPlayerCards,
                    horizontalPadding,
                    columns,
                    EventCard.gridMainAxisExtent(context, cardWidth),
                  )
                : _buildPhoneListLayout(hasPlayerCards, horizontalPadding),
          ),
        );
      },
    );
  }

  Widget _buildTabletGridLayout(
    bool hasPlayerCards,
    double horizontalPadding,
    int crossAxisCount,
    double cardHeight,
  ) {
    return CustomScrollView(
      key: PageStorageKey<String>('search_results_$searchQuery'),
      controller: scrollController,
      scrollCacheExtent: kListScrollCacheExtent,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        if (hasPlayerCards)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: 16.sp,
              ),
              child: PlayerSearchCards(players: players),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: hasPlayerCards ? 0 : 16.sp,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16.sp,
              mainAxisSpacing: 16.sp,
              mainAxisExtent: cardHeight,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final tournament = tournaments[index];
              return _SearchEventCard(
                key: ValueKey('search_event_${tournament.id}'),
                tournament: tournament,
                isFirst: index == 0,
                listIndex: index,
                grid: true,
              );
            }, childCount: tournaments.length),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneListLayout(bool hasPlayerCards, double horizontalPadding) {
    return ListView.builder(
      key: PageStorageKey<String>('search_results_$searchQuery'),
      controller: scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 16.sp,
      ),
      // Add 1 to item count if we have player cards to show
      itemCount: tournaments.length + (hasPlayerCards ? 1 : 0),
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
      scrollCacheExtent: kListScrollCacheExtent,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      itemBuilder: (context, index) {
        // Show player search cards at the top
        if (hasPlayerCards && index == 0) {
          return PlayerSearchCards(players: players);
        }

        // Adjust index if player cards are present
        final adjustedIndex = hasPlayerCards ? index - 1 : index;
        if (adjustedIndex < 0 || adjustedIndex >= tournaments.length) {
          return const SizedBox.shrink();
        }

        final tournament = tournaments[adjustedIndex];

        return _SearchEventCard(
          key: ValueKey('search_event_${tournament.id}'),
          tournament: tournament,
          isFirst: adjustedIndex == 0,
          listIndex: adjustedIndex,
        );
      },
    );
  }
}

/// Event card widget with keep-alive and animation support
class _SearchEventCard extends ConsumerStatefulWidget {
  const _SearchEventCard({
    super.key,
    required this.tournament,
    required this.isFirst,
    required this.listIndex,
    this.grid = false,
  });

  final bool grid;
  final GroupEventCardModel tournament;
  final bool isFirst;
  final int listIndex;

  @override
  ConsumerState<_SearchEventCard> createState() => _SearchEventCardState();
}

class _SearchEventCardState extends ConsumerState<_SearchEventCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final eventId = widget.tournament.id;
    final card = Padding(
      padding: widget.grid
          ? EdgeInsets.zero
          : EdgeInsets.only(top: widget.isFirst ? 0 : 12.sp, bottom: 12.sp),
      child: EventCard(
        tourEventCardModel: widget.tournament,
        forceCompactLayout: !widget.grid,
        heroTagSuffix: 'search-${widget.tournament.id}',
        onTap: () => ref
            .read(tournamentNavigationProvider)
            .openTournament(
              context: context,
              id: widget.tournament.id,
              category: GroupEventCategory.search,
            ),
      ),
    );

    // Per-result staggered fadeIn/slideY removed: it ran an animated Opacity
    // (saveLayer) per card with a listIndex stagger, cascading jank across the
    // search results list. Bookkeeping kept; results paint instantly.
    if (!searchAnimatedEventIds.contains(eventId)) {
      searchAnimatedEventIds.add(eventId);
    }
    return card;
  }
}

/// Filters search results by format, status, and ELO range.
List<GroupEventCardModel> _applySearchFilter(
  List<GroupEventCardModel> tournaments,
  FilterPopupState filter,
) {
  final filterSet = filter.formatsAndStates
      .map((f) => f.trim().toLowerCase())
      .where((f) => f.isNotEmpty)
      .toSet();
  final requestedStatuses = <String>{
    'live',
    'completed',
  }.intersection(filterSet);
  final requestedFormats = filterSet.difference(requestedStatuses);

  return tournaments.where((tour) {
    if (requestedStatuses.isNotEmpty) {
      final isLive =
          tour.tourEventCategory == TourEventCategory.live ||
          tour.tourEventCategory == TourEventCategory.ongoing;
      final matchesStatus =
          (requestedStatuses.contains('live') && isLive) ||
          (requestedStatuses.contains('completed') && !isLive);
      if (!matchesStatus) return false;
    }

    if (!broadcastMatchesTimeControlFilter(
      tour.timeControl,
      requestedFormats,
    )) {
      return false;
    }

    if (filter.hasEloFilter && tour.maxAvgElo > 0) {
      final minElo = filter.minElo ?? kFilterMinElo.round();
      final maxElo = filter.maxElo ?? kFilterMaxElo.round();
      if (tour.maxAvgElo < minElo || tour.maxAvgElo > maxElo) return false;
    }

    return true;
  }).toList();
}
