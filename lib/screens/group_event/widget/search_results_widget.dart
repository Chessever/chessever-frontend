import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/group_event/smart_opening_event.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/screens/group_event/widget/player_search_cards.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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

    if (searchQuery.trim().isEmpty) {
      return _buildInitialState(context);
    }

    return searchResultsAsync.when(
      data: (results) {
        var tournaments =
            results.tournamentResults.map((r) => r.tournament).toList();

        // Apply client-side filter if active
        if (searchFilter != defaultFilterPopupState) {
          tournaments = _applySearchFilter(tournaments, searchFilter);
        }

        final openingQuery = SmartOpeningQuery.parse(searchQuery);
        if (tournaments.isEmpty &&
            results.playerResults.isEmpty &&
            openingQuery == null) {
          return _buildEmptyState(context, searchQuery);
        }

        return _SearchResultsListView(
          scrollController: scrollController,
          tournaments: tournaments,
          searchQuery: searchQuery,
          openingQuery: openingQuery,
        );
      },
      loading: () => _buildLoadingState(),
      error: (error, stackTrace) {
        debugPrint('[SearchResultsWidget] Error: $error');
        return const GenericErrorWidget();
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, String query) {
    return Center(
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
        )
        .animate()
        .fadeIn(duration: 300.ms)
        .scale(
          begin: const Offset(0.95, 0.95),
          end: const Offset(1.0, 1.0),
          duration: 300.ms,
        );
  }

  Widget _buildInitialState(BuildContext context) {
    return Center(
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
              'Enter a search term to find events',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.sp,
                color: context.colors.textSecondary,
              ),
            ),
          ],
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
    required this.searchQuery,
    this.openingQuery,
  });

  final ScrollController scrollController;
  final List<GroupEventCardModel> tournaments;
  final String searchQuery;
  final SmartOpeningQuery? openingQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Check if we have players to show in the cards
    final hasPlayerCards = ref.watch(topSearchedPlayersProvider).isNotEmpty;
    final isTablet = ResponsiveHelper.isTablet;
    final crossAxisCount = ResponsiveHelper.getGridCrossAxisCount(
      phoneCount: 1,
    );
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.sp,
      tablet: 24.sp,
    );

    return RefreshIndicator(
      onRefresh: () async {
        // Invalidate the search provider to refetch
        ref.invalidate(supabaseCombinedSearchProvider(searchQuery.trim()));
      },
      color: kPrimaryColor,
      backgroundColor: context.colors.surface,
      displacement: 60.h,
      strokeWidth: 3.w,
      child:
          isTablet && crossAxisCount > 1
              ? _buildTabletGridLayout(
                hasPlayerCards,
                horizontalPadding,
                crossAxisCount,
              )
              : _buildPhoneListLayout(hasPlayerCards, horizontalPadding),
    );
  }

  Widget _buildTabletGridLayout(
    bool hasPlayerCards,
    double horizontalPadding,
    int crossAxisCount,
  ) {
    return CustomScrollView(
      key: PageStorageKey<String>('search_results_$searchQuery'),
      controller: scrollController,
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
              child: PlayerSearchCards(searchQuery: searchQuery),
            ),
          ),
        if (openingQuery != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                hasPlayerCards ? 0 : 16.sp,
                horizontalPadding,
                0,
              ),
              child: SmartOpeningEventCard(query: openingQuery!),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: hasPlayerCards || openingQuery != null ? 0 : 16.sp,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16.sp,
              mainAxisSpacing: 16.sp,
              childAspectRatio: ResponsiveHelper.isLandscape ? 2.2 : 1.8,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final tournament = tournaments[index];
              return _SearchEventCard(
                key: ValueKey('search_event_${tournament.id}'),
                tournament: tournament,
                isFirst: index == 0,
                listIndex: index,
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
      // Add rows for player cards and the opening smart database card.
      itemCount:
          tournaments.length +
          (hasPlayerCards ? 1 : 0) +
          (openingQuery != null ? 1 : 0),
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
      cacheExtent: 2000,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      itemBuilder: (context, index) {
        // Show player search cards at the top
        if (hasPlayerCards && index == 0) {
          return PlayerSearchCards(searchQuery: searchQuery);
        }

        final openingIndex = hasPlayerCards ? 1 : 0;
        if (openingQuery != null && index == openingIndex) {
          return SmartOpeningEventCard(query: openingQuery!);
        }

        // Adjust index if player/opening cards are present
        final adjustedIndex =
            index - (hasPlayerCards ? 1 : 0) - (openingQuery != null ? 1 : 0);
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
  });

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
      padding: EdgeInsets.only(top: widget.isFirst ? 0 : 12.sp, bottom: 12.sp),
      child: EventCard(
        tourEventCardModel: widget.tournament,
        heroTagSuffix: 'search-${widget.tournament.id}',
        onTap:
            () => ref
                .read(groupEventScreenProvider.notifier)
                .onSelectTournament(context: context, id: widget.tournament.id),
      ),
    );

    // Use global set to track animations - survives tab switches and rebuilds
    if (!searchAnimatedEventIds.contains(eventId)) {
      searchAnimatedEventIds.add(eventId);
      return card
          .animate()
          .fadeIn(
            duration: 200.ms,
            delay: Duration(milliseconds: (widget.listIndex % 10) * 30),
          )
          .slideY(begin: 0.05, end: 0, duration: 200.ms, curve: Curves.easeOut);
    }

    return card;
  }
}

/// Filters search results by format, status, and ELO range.
List<GroupEventCardModel> _applySearchFilter(
  List<GroupEventCardModel> tournaments,
  FilterPopupState filter,
) {
  final filterSet =
      filter.formatsAndStates
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

    if (requestedFormats.isNotEmpty) {
      final tourFormat = tour.timeControl.trim().toLowerCase();
      if (!requestedFormats.contains(tourFormat)) return false;
    }

    if (filter.hasEloFilter && tour.maxAvgElo > 0) {
      final minElo = filter.minElo ?? kFilterMinElo.round();
      final maxElo = filter.maxElo ?? kFilterMaxElo.round();
      if (tour.maxAvgElo < minElo || tour.maxAvgElo > maxElo) return false;
    }

    return true;
  }).toList();
}
