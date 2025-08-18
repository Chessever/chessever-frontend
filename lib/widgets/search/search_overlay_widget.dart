import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:chessever2/screens/tournaments/group_event_screen.dart';
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
              .read(groupBroadcastLocalStorage(GroupEventCategory.current))
              .searchWithScoring(query),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildLoadingState();
            }

            final searchResult = snapshot.data ??
                const EnhancedSearchResult(
                  tournamentResults: [],
                  playerResults: [],
                  allPlayers: [],
                );

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

    return Container(
      height: 400,
      child: Column(
        children: [
          _buildHeader(searchResult),
          Expanded(
            child: hasTournaments && hasPlayers
                ? _buildTwoColumnLayout(searchResult)
                : _buildSingleColumnLayout(searchResult),
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
          ),
        ),

        Container(
          width: 1,
          color: Colors.white.withOpacity(0.1),
        ),

        Expanded(
          child: _buildResultColumn(
            title: 'Players',
            count: searchResult.playerResults.length,
            results: _groupPlayerResults(searchResult.playerResults), // Added grouping
            icon: Icons.person,
            isPlayerSection: true,
          ),
        ),
      ],
    );
  }

  Widget _buildSingleColumnLayout(EnhancedSearchResult searchResult) {
    final hasTournaments = searchResult.tournamentResults.isNotEmpty;
    final results = hasTournaments
        ? searchResult.tournamentResults
        : _groupPlayerResults(searchResult.playerResults);
    final title = hasTournaments ? 'Events' : 'Players';
    final icon = hasTournaments ? Icons.emoji_events : Icons.person;

    return _buildResultColumn(
      title: title,
      count: hasTournaments ? results.length : searchResult.playerResults.length,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: Colors.blue,
              ),
              const SizedBox(width: 8),
              Text(
                '$title ($count)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: results.length,
            itemBuilder: (context, index) {
              return AnimatedContainer(
                duration: Duration(milliseconds: 100 + (index * 50)),
                child: SearchResultTile(
                  result: results[index],
                  onTap: isPlayerSection && results[index].player != null
                      ? () => onPlayerTap?.call(results[index].player!)
                      : () => onTournamentTap(results[index].tournament),
                  isPlayerResult: isPlayerSection,
                  isFullWidth: isFullWidth,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(EnhancedSearchResult searchResult) {
    final totalResults =
        searchResult.tournamentResults.length +
            searchResult.playerResults.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search,
            size: 16,
            color: Colors.blue,
          ),
          const SizedBox(width: 8),
          Text(
            '$totalResults result${totalResults != 1 ? 's' : ''} for "$query"',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      height: 300,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              strokeWidth: 2,
            ),
            SizedBox(height: 16),
            Text(
              'Searching...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try different keywords for "$query"',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  List<SearchResult> _groupPlayerResults(List<SearchResult> results) {
    final sortedResults = List<SearchResult>.from(results);
    sortedResults.sort((a, b) {
      final aDuplicateType = _getDuplicateTypeFromResult(a);
      final bDuplicateType = _getDuplicateTypeFromResult(b);

      final aTypeOrder = aDuplicateType == 'same_tournament' ? 0 :
      aDuplicateType == 'cross_tournament' ? 1 : 2;
      final bTypeOrder = bDuplicateType == 'same_tournament' ? 0 :
      bDuplicateType == 'cross_tournament' ? 1 : 2;

      if (aTypeOrder != bTypeOrder) return aTypeOrder.compareTo(bTypeOrder);

      final tournamentCompare = a.tournament.title.compareTo(b.tournament.title);
      if (tournamentCompare != 0) return tournamentCompare;

      return b.score.compareTo(a.score);
    });

    return sortedResults;
  }

  String _getDuplicateTypeFromResult(SearchResult result) {
    final playerId = result.player?.id ?? '';

    if (playerId.contains('_same_tournament')) {
      return 'same_tournament';
    } else if (playerId.contains('_cross_tournament')) {
      return 'cross_tournament';
    }

    return 'none';
  }
}

