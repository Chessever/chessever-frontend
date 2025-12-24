import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/group_event/widget/player_search_cards.dart';
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
        final tournaments = results.tournamentResults;

        if (tournaments.isEmpty && results.playerResults.isEmpty) {
          return _buildEmptyState(context, searchQuery);
        }

        return _SearchResultsListView(
          scrollController: scrollController,
          tournaments: tournaments.map((r) => r.tournament).toList(),
          searchQuery: searchQuery,
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
            Icon(Icons.search_off, size: 64.sp, color: kSubtleIconColor),
            SizedBox(height: 16.sp),
            Text(
              'No events found',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: kWhiteColor70,
              ),
            ),
            SizedBox(height: 8.sp),
            Text(
              'No events match "$query"',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.sp, color: kSecondaryTextColor),
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
            Icon(Icons.search, size: 64.sp, color: kSubtleIconColor),
            SizedBox(height: 16.sp),
            Text(
              'Search Events',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: kWhiteColor70,
              ),
            ),
            SizedBox(height: 8.sp),
            Text(
              'Enter a search term to find events',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.sp, color: kSecondaryTextColor),
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
        ...List.generate(
          5,
          (index) => _SkeletonEventCard(isFirst: index == 0),
        ),
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
          color: kBlack2Color,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: kDarkGreyColor.withValues(alpha: 0.3)),
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
  });

  final ScrollController scrollController;
  final List<GroupEventCardModel> tournaments;
  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Check if we have players to show in the cards
    final hasPlayerCards = ref.watch(topSearchedPlayersProvider).isNotEmpty;

    return RefreshIndicator(
      onRefresh: () async {
        // Invalidate the search provider to refetch
        ref.invalidate(supabaseCombinedSearchProvider(searchQuery.trim()));
      },
      color: kPrimaryColor,
      backgroundColor: kBlack2Color,
      displacement: 60.h,
      strokeWidth: 3.w,
      child: ListView.builder(
        key: PageStorageKey<String>('search_results_$searchQuery'),
        controller: scrollController,
        padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
        // Add 1 to item count if we have player cards to show
        itemCount: tournaments.length + (hasPlayerCards ? 1 : 0),
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
      ),
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
      padding: EdgeInsets.only(
        top: widget.isFirst ? 0 : 12.sp,
        bottom: 12.sp,
      ),
      child: EventCard(
        tourEventCardModel: widget.tournament,
        heroTagSuffix: 'search-${widget.tournament.id}',
        onTap: () => ref
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
