import 'dart:math' as math;

import 'package:chessever2/widgets/search/search_result_model.dart';

class SearchScorer {
  static double calculateScore(
    String query,
    String text,
    SearchResultType type,
  ) {
    if (query.isEmpty || text.isEmpty) return 0.0;

    final queryLower = query.toLowerCase().trim();
    final textLower = text.toLowerCase();

    double score = 0.0;

    // Exact match gets highest score
    if (textLower == queryLower) {
      score = 100.0;
    }
    // Starts with query gets high score
    else if (textLower.startsWith(queryLower)) {
      score = 80.0 + (queryLower.length / textLower.length) * 10;
    }
    // Contains at word boundary
    else if (textLower.contains(' $queryLower') ||
        textLower.contains('$queryLower ')) {
      score = 60.0 + (queryLower.length / textLower.length) * 10;
    }
    // Contains query
    else if (textLower.contains(queryLower)) {
      score = 40.0 + (queryLower.length / textLower.length) * 10;
    }
    // Fuzzy matching - calculate similarity
    else {
      score = _calculateFuzzyScore(queryLower, textLower);
    }

    // Boost score for tournament name matches vs player matches
    if (type == SearchResultType.tournament) {
      score *= 1.1; // Slight boost for tournament name matches
    }

    return score.clamp(0.0, 100.0);
  }

  static double _calculateFuzzyScore(String query, String text) {
    final queryWords = query.split(' ').where((w) => w.isNotEmpty).toList();
    double totalScore = 0.0;

    for (final word in queryWords) {
      double bestWordScore = 0.0;

      // Check each word in text for partial matches
      for (final textWord in text.split(' ')) {
        if (textWord.isEmpty) continue;

        // Calculate Levenshtein-based similarity
        final similarity = _stringSimilarity(word, textWord);
        if (similarity > 0.6) {
          // Only consider good matches
          bestWordScore = math.max(bestWordScore, similarity * 30);
        }
      }

      totalScore += bestWordScore;
    }

    return totalScore / queryWords.length;
  }

  static double _stringSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final longer = s1.length > s2.length ? s1 : s2;
    final shorter = s1.length > s2.length ? s2 : s1;

    if (longer.length == 0) return 1.0;

    final editDistance = _levenshteinDistance(longer, shorter);
    return (longer.length - editDistance) / longer.length;
  }

  static int _levenshteinDistance(String s1, String s2) {
    final costs = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i <= s2.length; i++) {
      costs[i] = i;
    }

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
