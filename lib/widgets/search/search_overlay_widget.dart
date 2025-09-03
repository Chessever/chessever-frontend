import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:chessever2/widgets/search/widgets/search_result_title.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SearchOverlay extends ConsumerWidget {
  final String query;
  final Function(GroupEventCardModel) onTournamentTap;
  final Function(SearchPlayer)? onPlayerTap;

  const SearchOverlay({
    super.key,
    required this.query,
    required this.onTournamentTap,
    this.onPlayerTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(selectedGroupCategoryProvider);
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FutureBuilder<EnhancedSearchResult>(
          future: ref
              .read(groupBroadcastLocalStorage(currentTab))
              .searchWithScoring(query),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildLoadingState();
            }

            if (snapshot.hasError) {
              return _buildErrorState(snapshot.error.toString());
            }

            final searchResult =
                snapshot.data ??
                const EnhancedSearchResult(
                  tournamentResults: [],
                  playerResults: [],
                  allPlayers: [],
                );

            if (kDebugMode) {
              print(
                'Tournament results: ${searchResult.tournamentResults.length}',
              );
              print('Player results: ${searchResult.playerResults.length}');
              searchResult.playerResults.forEach((result) {
                print(
                  'Player: ${result.player?.name}, ID: ${result.player?.id}',
                );
              });
            }

            if (searchResult.tournamentResults.isEmpty &&
                searchResult.playerResults.isEmpty) {
              return _buildEmptyState();
            }

            return _buildSearchResults(searchResult);
          },
        ),
      ),
    );
  }

  Widget _buildSearchResults(EnhancedSearchResult searchResult) {
    final hasTournaments = searchResult.tournamentResults.isNotEmpty;
    final hasPlayers = searchResult.playerResults.isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: 400.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(searchResult, hasTournaments, hasPlayers),
          Flexible(
            child:
                hasTournaments && hasPlayers
                    ? _buildTwoColumnLayout(searchResult)
                    : _buildSingleColumnLayout(searchResult, hasTournaments),
          ),
        ],
      ),
    );
  }

  Widget _buildTwoColumnLayout(EnhancedSearchResult searchResult) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildResultColumn(
            title: 'Events',
            count: searchResult.tournamentResults.length,
            results: searchResult.tournamentResults,
            icon: Icons.emoji_events,
            isPlayerSection: false,
          ),
        ),

        Container(
          width: 1,
          color: Colors.white.withOpacity(0.1),
          margin: EdgeInsets.symmetric(vertical: 8.h),
        ),

        Expanded(
          child: _buildResultColumn(
            title: 'Players',
            count: searchResult.playerResults.length,
            results: searchResult.playerResults,
            icon: Icons.person,
            isPlayerSection: true,
          ),
        ),
      ],
    );
  }

  Widget _buildSingleColumnLayout(
    EnhancedSearchResult searchResult,
    bool hasTournaments,
  ) {
    final results =
        hasTournaments
            ? searchResult.tournamentResults
            : searchResult.playerResults;
    final title = hasTournaments ? 'Events' : 'Players';
    final icon = hasTournaments ? Icons.emoji_events : Icons.person;

    return _buildResultColumn(
      title: title,
      count: results.length,
      results: results,
      icon: icon,
      isFullWidth: true,
      isPlayerSection: !hasTournaments,
    );
  }

  Widget _buildResultColumn({
    required String title,
    required int count,
    required List<SearchResult> results,
    required IconData icon,
    bool isFullWidth = false,
    bool isPlayerSection = false,
  }) {
    final filteredResults =
        isPlayerSection
            ? results.where((result) => result.player != null).toList()
            : results;

    if (filteredResults.isEmpty) {
      return Center(
        child: Text(
          'No $title found',
          style: TextStyle(color: Colors.grey[400], fontSize: 14),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.all(12.sp),
          child: Row(
            children: [
              Icon(icon, size: 16.ic, color: Colors.blue),
              SizedBox(width: 8.w),
              Text(
                '$title (${filteredResults.length})',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: filteredResults.length,
            itemBuilder: (context, index) {
              final result = filteredResults[index];
              return SearchResultTile(
                result: result,
                onTap:
                    isPlayerSection
                        ? () => onPlayerTap?.call(result.player!)
                        : () => onTournamentTap(result.tournament),
                isPlayerResult: isPlayerSection,
                isFullWidth: isFullWidth,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(
    EnhancedSearchResult searchResult,
    bool hasTournaments,
    bool hasPlayers,
  ) {
    final totalResults =
        searchResult.tournamentResults.length +
        searchResult.playerResults.length;

    return Container(
      padding: EdgeInsets.all(16.sp),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 16.ic, color: Colors.blue),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              '$totalResults result${totalResults != 1 ? 's' : ''} for "$query"',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return SizedBox(
      height: 200.h,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              strokeWidth: 2,
            ),
            SizedBox(height: 16.h),
            Text(
              'Searching...',
              style: TextStyle(color: Colors.white70, fontSize: 14.sp),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return SizedBox(
      height: 200.h,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48.ic, color: Colors.red),
            SizedBox(height: 16.h),
            Text(
              'Search failed',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              error,
              style: TextStyle(color: Colors.grey[400], fontSize: 12.sp),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SizedBox(
      height: 200.h,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48.ic, color: Colors.grey[600]),
            SizedBox(height: 16.h),
            Text(
              'No results found',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Try different keywords for "$query"',
              style: TextStyle(color: Colors.grey[400], fontSize: 14.sp),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
