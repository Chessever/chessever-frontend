import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/widgets/search/gameSearch/game_result_search.dart';

class EnhancedGameSearchResult {
  final List<GameSearchResult> results;
  final DateTime timestamp;

  EnhancedGameSearchResult({required this.results, required this.timestamp});
}

class GameSearchResult {
  final Games game;
  final double score;
  final String matchedText;
  final String matchType;

  const GameSearchResult({
    required this.game,
    required this.score,
    required this.matchedText,
    required this.matchType,
  });
}

// Enhanced search extension for games
extension GamesLocalStorageEnhancedSearch on GamesLocalStorage {
  Future<EnhancedGameSearchResult> searchGamesWithScoring({
    required String tourId,
    required String query,
    int maxResults = 50,
  }) async {
    try {
      final games = await getGames(tourId);

      if (query.isEmpty) {
        return EnhancedGameSearchResult(results: [], timestamp: DateTime.now());
      }

      final normalizedQuery = query.toLowerCase().trim();
      final queryTokens =
          normalizedQuery
              .split(' ')
              .where((token) => token.isNotEmpty)
              .toList();
      final results = <GameSearchResult>[];

      for (final game in games) {
        bool hasMatch = false;
        String matchedText = '';

        // Check search terms (player names, etc.)
        final searchTerms = game.search ?? [];
        for (final searchTerm in searchTerms) {
          final lowerSearchTerm = searchTerm.toLowerCase();
          // Check if all query tokens are found in this search term
          if (_allTokensMatch(queryTokens, lowerSearchTerm)) {
            hasMatch = true;
            matchedText = searchTerm;
            break;
          }
        }

        // Check player data if available
        if (!hasMatch && game.players != null) {
          for (final player in game.players!) {
            final playerData =
                '${player.name} ${player.rating} ${player.title} ${player.fed}'
                    .toLowerCase();
            // Check if all query tokens are found in player data
            if (_allTokensMatch(queryTokens, playerData)) {
              hasMatch = true;
              matchedText = player.name;
              break;
            }
          }
        }

        // Check ECO code and opening name
        if (!hasMatch) {
          final eco = game.eco?.toLowerCase() ?? '';
          final openingName = game.openingName?.toLowerCase() ?? '';
          if (eco.isNotEmpty && _allTokensMatch(queryTokens, eco)) {
            hasMatch = true;
            matchedText = game.eco!;
          } else if (openingName.isNotEmpty &&
              _allTokensMatch(queryTokens, openingName)) {
            hasMatch = true;
            matchedText = game.openingName!;
          }
        }

        // Check exact PGN result tokens. Keep this intentionally literal:
        // no draw/white-won/black-won aliases, only standard PGN results.
        if (!hasMatch && gameResultMatchesSearchQuery(game, normalizedQuery)) {
          hasMatch = true;
          matchedText = gameResultSearchText(game);
        }

        if (hasMatch) {
          results.add(
            GameSearchResult(
              game: game,
              score: 1.0,
              matchedText: matchedText,
              matchType: 'match',
            ),
          );
        }
      }

      // Limit the number of results
      final limitedResults = results.take(maxResults).toList();

      return EnhancedGameSearchResult(
        results: limitedResults,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      return EnhancedGameSearchResult(results: [], timestamp: DateTime.now());
    }
  }

  /// Check if all query tokens are found in the text
  bool _allTokensMatch(List<String> tokens, String text) {
    for (final token in tokens) {
      if (!text.contains(token)) {
        return false;
      }
    }
    return true;
  }
}
