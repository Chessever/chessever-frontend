import 'dart:math' as math;

import 'package:chessever2/widgets/search/search_result_model.dart';

class SearchScoreMatch {
  const SearchScoreMatch({required this.score, required this.matchedText});

  final double score;
  final String matchedText;
}

class SearchScorer {
  static const SearchScoreMatch noMatch = SearchScoreMatch(
    score: 0,
    matchedText: '',
  );

  static SearchScoreMatch bestTournamentMatch({
    required String query,
    required String name,
    Iterable<String> aliases = const [],
  }) {
    var bestScore = calculateScore(query, name, SearchResultType.tournament);
    var bestMatch = name;

    for (final alias in aliases) {
      if (!_isTournamentIdentityAlias(name, alias)) continue;

      final score = calculateScore(query, alias, SearchResultType.tournament);
      if (score > bestScore) {
        bestScore = score;
        bestMatch = alias;
      }
    }

    if (bestScore <= 0) return noMatch;
    return SearchScoreMatch(score: bestScore, matchedText: bestMatch);
  }

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

    if (type == SearchResultType.tournament) {
      if (!_hasTournamentQueryIdentityMatch(queryLower, textLower)) {
        return 0.0;
      }

      // Boost score for tournament name matches vs player matches.
      score *= 1.1;
    }

    return score.clamp(0.0, 100.0);
  }

  static bool _hasTournamentQueryIdentityMatch(String query, String text) {
    final queryTokens =
        _normalizedTokens(
          query,
        ).where((token) => !_isYearToken(token)).toList();
    final textTokens = _normalizedTokens(text);
    if (queryTokens.isEmpty || textTokens.isEmpty) return false;

    if (queryTokens.length == 1) {
      return _tokenMatchesText(queryTokens.first, textTokens);
    }

    return queryTokens.every(
      (queryToken) => _tokenMatchesText(queryToken, textTokens),
    );
  }

  static bool _isTournamentIdentityAlias(String name, String alias) {
    final nameTokens = _normalizedTokens(name);
    final aliasTokens = _normalizedTokens(alias);
    if (nameTokens.isEmpty || aliasTokens.isEmpty) return false;

    final normalizedName = nameTokens.join(' ');
    final normalizedAlias = aliasTokens.join(' ');
    if (normalizedAlias == normalizedName) return true;
    if (normalizedAlias.startsWith('$normalizedName ')) return true;

    final requiredNameTokens =
        nameTokens.where((token) => !_isYearToken(token)).toSet();
    if (requiredNameTokens.isEmpty) return false;

    final aliasTokenSet = aliasTokens.toSet();
    return requiredNameTokens.every(aliasTokenSet.contains);
  }

  static bool _tokensMatch(String queryToken, String textToken) {
    return textToken == queryToken || textToken.startsWith(queryToken);
  }

  static bool _tokenMatchesText(String queryToken, List<String> textTokens) {
    if (textTokens.any((textToken) => _tokensMatch(queryToken, textToken))) {
      return true;
    }

    // Brand/domain names may be entered without punctuation ("chesscom")
    // while event titles store them split by punctuation ("Chess.com").
    final compactText = textTokens.join();
    return compactText.contains(queryToken);
  }

  static bool _isYearToken(String token) {
    final year = int.tryParse(token);
    return token.length == 4 && year != null && year >= 1800 && year <= 2200;
  }

  static List<String> _normalizedTokens(String value) {
    final normalized =
        value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    if (normalized.isEmpty) return const [];
    return normalized.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
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

    if (longer.isEmpty) return 1.0;

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
