import 'dart:math' as math;

import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';

class EnhancedGameSearchResult {
  final List<GameSearchResult> results;

  const EnhancedGameSearchResult({
    required this.results,
  });
}

class GameSearchResult {
  final Games game;
  final double score;
  final String matchedText;

  const GameSearchResult({
    required this.game,
    required this.score,
    required this.matchedText,
  });
}

// Enhanced search extension for games
extension GamesLocalStorageEnhancedSearch on GamesLocalStorage {
  Future<EnhancedGameSearchResult> searchGamesWithScoring({
    required String tourId,
    required String query,
  }) async {
    try {
      final games = await getGames(tourId);

      if (query.isEmpty) {
        return const EnhancedGameSearchResult(results: []);
      }

      final queryLower = query.toLowerCase().trim();
      final results = <GameSearchResult>[];

      for (final game in games) {
        // Search in the search field (which contains player names and game info)
        final searchTerms = game.search ?? [];

        double bestScore = 0.0;
        String bestMatch = '';

        for (final searchTerm in searchTerms) {
          final score = _calculateGameSearchScore(queryLower, searchTerm);

          if (score > bestScore) {
            bestScore = score;
            bestMatch = searchTerm;
          }
        }

        if (bestScore > 10.0) {
          // Minimum threshold
          results.add(
            GameSearchResult(
              game: game,
              score: bestScore,
              matchedText: bestMatch,
            ),
          );
        }
      }

      // Sort by score (highest first)
      results.sort((a, b) => b.score.compareTo(a.score));

      return EnhancedGameSearchResult(results: results);
    } catch (e) {
      return const EnhancedGameSearchResult(results: []);
    }
  }

  double _calculateGameSearchScore(String query, String text) {
    final textLower = text.toLowerCase();

    // Exact match gets highest score
    if (textLower == query) {
      return 120.0;
    }

    // Starts with query
    if (textLower.startsWith(query)) {
      return 100.0;
    }

    // Contains query
    if (textLower.contains(query)) {
      return 80.0;
    }

    // Fuzzy matching for typos (simple word distance)
    final words = textLower.split(' ');
    double maxWordScore = 0.0;

    for (final word in words) {
      if (word.startsWith(query)) {
        maxWordScore = math.max(maxWordScore, 70.0);
      } else if (word.contains(query)) {
        maxWordScore = math.max(maxWordScore, 50.0);
      } else {
        // Simple character similarity
        final similarity = _calculateStringSimilarity(query, word);
        if (similarity > 0.7) {
          maxWordScore = math.max(maxWordScore, similarity * 40.0);
        }
      }
    }

    return maxWordScore;
  }

  double _calculateStringSimilarity(String s1, String s2) {
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final longer = s1.length > s2.length ? s1 : s2;
    final shorter = s1.length > s2.length ? s2 : s1;

    if (longer.length == 0) return 1.0;

    final editDistance = _calculateLevenshteinDistance(longer, shorter);
    return (longer.length - editDistance) / longer.length;
  }

  int _calculateLevenshteinDistance(String s1, String s2) {
    final costs = List.generate(s2.length + 1, (i) => i);

    for (int i = 1; i <= s1.length; i++) {
      costs[0] = i;
      int nw = i - 1;

      for (int j = 1; j <= s2.length; j++) {
        final cj = math.min(
          1 + math.min(costs[j], costs[j - 1]),
          s1[i - 1] == s2[j - 1] ? nw : nw + 1,
        );
        nw = costs[j];
        costs[j] = cj.toInt();
      }
    }

    return costs[s2.length];
  }
}
