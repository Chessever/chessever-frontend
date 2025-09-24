import 'dart:math' as math;

import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';

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
      final queryTokens = normalizedQuery.split(' ').where((token) => token.isNotEmpty).toList();
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
            final playerData = '${player.name} ${player.rating} ${player.title} ${player.fed}'.toLowerCase();
            // Check if all query tokens are found in player data
            if (_allTokensMatch(queryTokens, playerData)) {
              hasMatch = true;
              matchedText = player.name;
              break;
            }
          }
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

  /// Normalizes search terms by removing extra spaces, converting to lowercase,
  /// and handling special characters
  String _normalizeSearchTerm(String term) {
    return term
        .toLowerCase()
        .trim()
        .replaceAll(
          RegExp(r'\s+'),
          ' ',
        ) // Replace multiple spaces with single space
        .replaceAll(
          RegExp(r'[^\w\s-]'),
          '',
        ) // Keep only alphanumeric, spaces, and hyphens
        .trim();
  }

  /// Enhanced scoring with better space and character handling
  ({double score, String matchType}) _calculateEnhancedGameSearchScore(
    String query,
    String text,
  ) {
    final normalizedText = _normalizeSearchTerm(text);

    // 1. EXACT MATCH (highest priority)
    if (normalizedText == query) {
      return (score: 150.0, matchType: 'exact');
    }

    // 2. EXACT MATCH IGNORING SPACES
    final queryNoSpaces = query.replaceAll(' ', '');
    final textNoSpaces = normalizedText.replaceAll(' ', '');
    if (textNoSpaces == queryNoSpaces && queryNoSpaces.isNotEmpty) {
      return (score: 140.0, matchType: 'exact_no_spaces');
    }

    // 3. STARTS WITH QUERY
    if (normalizedText.startsWith(query)) {
      return (score: 130.0, matchType: 'starts_with');
    }

    // 4. STARTS WITH QUERY (ignoring spaces)
    if (textNoSpaces.startsWith(queryNoSpaces) && queryNoSpaces.isNotEmpty) {
      return (score: 120.0, matchType: 'starts_with_no_spaces');
    }

    // 5. WORD BOUNDARY MATCHES
    final queryWords = query.split(' ').where((w) => w.isNotEmpty).toList();
    final textWords =
        normalizedText.split(' ').where((w) => w.isNotEmpty).toList();

    // All query words found as complete words
    if (queryWords.isNotEmpty && _allWordsFound(queryWords, textWords)) {
      final coverage = queryWords.length / textWords.length;
      return (score: 110.0 + (coverage * 10.0), matchType: 'all_words_match');
    }

    // 6. SEQUENTIAL WORD MATCHES
    final sequentialScore = _calculateSequentialWordMatch(
      queryWords,
      textWords,
    );
    if (sequentialScore > 0) {
      return (score: 100.0 + sequentialScore, matchType: 'sequential_words');
    }

    // 7. CONTAINS FULL QUERY
    if (normalizedText.contains(query)) {
      final position = normalizedText.indexOf(query);
      final positionBonus = position == 0 ? 10.0 : (position < 5 ? 5.0 : 0.0);
      return (score: 90.0 + positionBonus, matchType: 'contains');
    }

    // 8. CONTAINS QUERY (ignoring spaces)
    if (textNoSpaces.contains(queryNoSpaces) && queryNoSpaces.length > 2) {
      return (score: 85.0, matchType: 'contains_no_spaces');
    }

    // 9. PARTIAL WORD MATCHES
    double maxPartialScore = 0.0;
    String bestPartialMatch = 'partial';

    for (final queryWord in queryWords) {
      if (queryWord.length < 2) continue; // Skip very short words

      for (final textWord in textWords) {
        // Word starts with query word
        if (textWord.startsWith(queryWord)) {
          final score = (queryWord.length / textWord.length) * 70.0;
          maxPartialScore = math.max(maxPartialScore, score);
          bestPartialMatch = 'word_starts_with';
        }
        // Word contains query word
        else if (textWord.contains(queryWord)) {
          final score = (queryWord.length / textWord.length) * 60.0;
          maxPartialScore = math.max(maxPartialScore, score);
          bestPartialMatch = 'word_contains';
        }
        // Fuzzy match for typos
        else {
          final similarity = _calculateJaroWinklerSimilarity(
            queryWord,
            textWord,
          );
          if (similarity > 0.8 && queryWord.length > 2) {
            final score = similarity * 50.0;
            maxPartialScore = math.max(maxPartialScore, score);
            bestPartialMatch = 'fuzzy_match';
          }
        }
      }
    }

    // 10. CHARACTER-LEVEL SIMILARITY (last resort)
    if (maxPartialScore < 30.0) {
      final charSimilarity = _calculateJaroWinklerSimilarity(
        query,
        normalizedText,
      );
      if (charSimilarity > 0.7) {
        maxPartialScore = math.max(maxPartialScore, charSimilarity * 40.0);
        bestPartialMatch = 'character_similarity';
      }
    }

    return (score: maxPartialScore, matchType: bestPartialMatch);
  }

  /// Check if all query words are found as complete words in text
  bool _allWordsFound(List<String> queryWords, List<String> textWords) {
    for (final queryWord in queryWords) {
      bool found = false;
      for (final textWord in textWords) {
        if (textWord == queryWord ||
            textWord.startsWith('$queryWord ') ||
            textWord.endsWith(' $queryWord')) {
          found = true;
          break;
        }
      }
      if (!found) return false;
    }
    return true;
  }

  /// Calculate score for sequential word matching
  double _calculateSequentialWordMatch(
    List<String> queryWords,
    List<String> textWords,
  ) {
    if (queryWords.isEmpty) return 0.0;

    int bestSequence = 0;
    int currentSequence = 0;
    int queryIndex = 0;

    for (final textWord in textWords) {
      if (queryIndex < queryWords.length &&
          textWord.startsWith(queryWords[queryIndex])) {
        currentSequence++;
        queryIndex++;
      } else {
        bestSequence = math.max(bestSequence, currentSequence);
        currentSequence = 0;
        queryIndex = 0;
        // Check if current word matches first query word
        if (textWord.startsWith(queryWords[0])) {
          currentSequence = 1;
          queryIndex = 1;
        }
      }
    }
    bestSequence = math.max(bestSequence, currentSequence);

    return (bestSequence / queryWords.length) * 15.0; // Bonus up to 15 points
  }

  /// Improved string similarity using Jaro-Winkler algorithm
  double _calculateJaroWinklerSimilarity(String s1, String s2) {
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    if (s1 == s2) return 1.0;

    final jaroSimilarity = _calculateJaroSimilarity(s1, s2);

    // Jaro-Winkler gives more weight to strings with common prefixes
    int prefixLength = 0;
    final maxPrefix = math.min(math.min(s1.length, s2.length), 4);

    for (int i = 0; i < maxPrefix; i++) {
      if (s1[i] == s2[i]) {
        prefixLength++;
      } else {
        break;
      }
    }

    return jaroSimilarity + (0.1 * prefixLength * (1 - jaroSimilarity));
  }

  /// Calculate Jaro similarity
  double _calculateJaroSimilarity(String s1, String s2) {
    final len1 = s1.length;
    final len2 = s2.length;

    if (len1 == 0 && len2 == 0) return 1.0;
    if (len1 == 0 || len2 == 0) return 0.0;

    final matchWindow = (math.max(len1, len2) / 2 - 1).floor();
    if (matchWindow < 0) return 0.0;

    final s1Matches = List.filled(len1, false);
    final s2Matches = List.filled(len2, false);

    int matches = 0;

    // Find matches
    for (int i = 0; i < len1; i++) {
      final start = math.max(0, i - matchWindow);
      final end = math.min(i + matchWindow + 1, len2);

      for (int j = start; j < end; j++) {
        if (s2Matches[j] || s1[i] != s2[j]) continue;
        s1Matches[i] = true;
        s2Matches[j] = true;
        matches++;
        break;
      }
    }

    if (matches == 0) return 0.0;

    // Count transpositions
    int transpositions = 0;
    int k = 0;

    for (int i = 0; i < len1; i++) {
      if (!s1Matches[i]) continue;
      while (!s2Matches[k]) {
        k++;
      }
      if (s1[i] != s2[k]) transpositions++;
      k++;
    }

    return (matches / len1 +
            matches / len2 +
            (matches - transpositions / 2) / matches) /
        3.0;
  }

  /// Get all searchable content from a game including player data, ratings, titles, etc.
  List<SearchableItem> _getAllSearchableContent(Games game) {
    final items = <SearchableItem>[];

    // Add existing search terms (player names, game names)
    final searchTerms = game.search ?? [];
    for (final term in searchTerms) {
      if (term.trim().isNotEmpty) {
        items.add(SearchableItem(
          text: term,
          displayText: term,
          type: 'name',
        ));
      }
    }

    // Add player-specific data from the players JSON
    if (game.players != null) {
      for (final player in game.players!) {
        // Player ratings
        if (player.rating > 0) {
          final rating = player.rating.toString();
          items.add(SearchableItem(
            text: rating,
            displayText: '${player.name} ($rating)',
            type: 'rating',
          ));

          // Add rating ranges for easier searching
          if (player.rating >= 2700) {
            items.add(SearchableItem(
              text: '2700+',
              displayText: '${player.name} (2700+)',
              type: 'rating_range',
            ));
          } else if (player.rating >= 2500) {
            items.add(SearchableItem(
              text: '2500+',
              displayText: '${player.name} (2500+)',
              type: 'rating_range',
            ));
          } else if (player.rating >= 2300) {
            items.add(SearchableItem(
              text: '2300+',
              displayText: '${player.name} (2300+)',
              type: 'rating_range',
            ));
          }
        }

        // Player titles
        if (player.title.trim().isNotEmpty) {
          items.add(SearchableItem(
            text: player.title,
            displayText: '${player.title} ${player.name}',
            type: 'title',
          ));
        }

        // Player federations/countries
        if (player.fed.trim().isNotEmpty) {
          items.add(SearchableItem(
            text: player.fed,
            displayText: '${player.name} (${player.fed})',
            type: 'country',
          ));
        }
      }
    }

    // Add game status/results
    if (game.status?.trim().isNotEmpty == true) {
      String displayStatus = game.status!;
      // Convert status to more readable format
      if (game.status == '1/2-1/2' || game.status == '½-½') {
        displayStatus = 'draw';
        items.add(SearchableItem(
          text: 'draw',
          displayText: 'Draw result',
          type: 'result',
        ));
      }

      items.add(SearchableItem(
        text: game.status!,
        displayText: 'Result: $displayStatus',
        type: 'result',
      ));
    }

    return items;
  }

  /// Get priority order for match types (lower number = higher priority)
  int _getMatchTypePriority(String matchType) {
    // Extract the base match type (remove prefix like 'name_', 'rating_', etc.)
    final baseType = matchType.contains('_')
        ? matchType.split('_').last
        : matchType;

    // Prioritize certain content types
    if (matchType.startsWith('name_')) {
      return 1; // Player names get highest priority
    } else if (matchType.startsWith('title_')) {
      return 2; // Titles get high priority
    } else if (matchType.startsWith('country_')) {
      return 3; // Countries get medium-high priority
    } else if (matchType.startsWith('rating_')) {
      return 4; // Ratings get medium priority
    } else if (matchType.startsWith('result_')) {
      return 5; // Results get lower priority
    }

    // Then prioritize by match quality
    switch (baseType) {
      case 'exact':
        return 10;
      case 'exact_no_spaces':
        return 11;
      case 'starts_with':
        return 12;
      case 'starts_with_no_spaces':
        return 13;
      case 'all_words_match':
        return 14;
      case 'sequential_words':
        return 15;
      case 'contains':
        return 16;
      case 'contains_no_spaces':
        return 17;
      case 'word_starts_with':
        return 18;
      case 'word_contains':
        return 19;
      case 'fuzzy_match':
        return 20;
      case 'character_similarity':
        return 21;
      default:
        return 99;
    }
  }
}

/// Helper class to represent a searchable item with metadata
class SearchableItem {
  final String text;         // The text to search against
  final String displayText;  // The text to show in results
  final String type;         // The type of content (name, rating, title, etc.)

  SearchableItem({
    required this.text,
    required this.displayText,
    required this.type,
  });
}
