import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:chessever2/widgets/search/search_scorer.dart';

class EnhancedSearchResult {
  final List<SearchResult> tournamentResults;
  final List<SearchResult> playerResults;

  const EnhancedSearchResult({
    required this.tournamentResults,
    required this.playerResults,
  });
}

extension GroupBroadcastLocalStorageSearch on GroupBroadcastLocalStorage {
  Future<EnhancedSearchResult> searchWithScoring(
    String query, [
    List<String>? liveBroadcastId,
  ]) async {
    try {
      final broadcasts = await getGroupBroadcasts();
      if (query.isEmpty) {
        return const EnhancedSearchResult(
          tournamentResults: [],
          playerResults: [],
        );
      }

      final queryLower = query.toLowerCase().trim();
      final tournamentResults = <SearchResult>[];
      final playerResults = <SearchResult>[];

      for (final gb in broadcasts) {
        final tourEventModel = TourEventCardModel.fromGroupBroadcast(
          gb,
          liveBroadcastId ?? [],
        );

        // Search in tournament name
        final tournamentScore = SearchScorer.calculateScore(
          queryLower,
          gb.name,
          SearchResultType.tournament,
        );

        if (tournamentScore > 10.0) {
          // Minimum threshold
          tournamentResults.add(
            SearchResult(
              tournament: tourEventModel,
              score: tournamentScore,
              matchedText: gb.name,
              type: SearchResultType.tournament,
            ),
          );
        }

        // Search in players (search field)
        double bestPlayerScore = 0.0;
        String bestPlayerMatch = '';

        for (final searchTerm in gb.search) {
          // Skip tournament names in search array (they usually come first)
          if (searchTerm.toLowerCase().contains('chess') &&
                  searchTerm.toLowerCase().contains('festival') ||
              searchTerm.toLowerCase().contains('tournament') ||
              searchTerm.toLowerCase().contains('championship')) {
            continue;
          }

          final playerScore = SearchScorer.calculateScore(
            queryLower,
            searchTerm,
            SearchResultType.player,
          );

          if (playerScore > bestPlayerScore) {
            bestPlayerScore = playerScore;
            bestPlayerMatch = searchTerm;
          }
        }

        if (bestPlayerScore > 10.0) {
          // Minimum threshold
          playerResults.add(
            SearchResult(
              tournament: tourEventModel,
              score: bestPlayerScore,
              matchedText: bestPlayerMatch,
              type: SearchResultType.player,
            ),
          );
        }
      }

      // Sort by score (highest first)
      tournamentResults.sort((a, b) => b.score.compareTo(a.score));
      playerResults.sort((a, b) => b.score.compareTo(a.score));

      return EnhancedSearchResult(
        tournamentResults: tournamentResults,
        playerResults: playerResults,
      );
    } catch (e) {
      return const EnhancedSearchResult(
        tournamentResults: [],
        playerResults: [],
      );
    }
  }
}
