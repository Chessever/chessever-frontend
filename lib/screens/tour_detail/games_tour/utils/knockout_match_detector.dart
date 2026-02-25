import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

/// Utility class to detect and handle knockout tournament formats
/// where players face each other multiple times in matches
class KnockoutMatchDetector {
  /// Detects if this is a 1v1 match format event (e.g., "12-game Match").
  ///
  /// Returns true when the tour format string contains "match"
  /// (case-insensitive) AND there are exactly 2 unique players.
  static bool isMatchFormat(String? formatString, List<GamesTourModel> games) {
    if (formatString == null || formatString.isEmpty || games.isEmpty) {
      return false;
    }

    if (!formatString.toLowerCase().contains('match')) return false;

    // Count unique players
    final players = <String>{};
    for (final game in games) {
      players.add(game.whitePlayer.name);
      players.add(game.blackPlayer.name);
      if (players.length > 2) return false; // early exit
    }

    return players.length == 2;
  }

  /// Detects if games follow a knockout match format
  ///
  /// A knockout match format is identified by:
  /// 1. Multiple games between the same player pairs
  /// 2. Round slugs following patterns like "game-1", "game-2", "tiebreak-*"
  /// 3. Sequential games (game-1, game-2, etc.) for same players
  static bool isKnockoutMatchFormat(List<GamesTourModel> games) {
    if (games.length < 4) return false; // Need at least 2 matches of 2 games

    // Check for game-N pattern in round slugs
    final gamePatternCount =
        games.where((g) {
          final slug = g.roundSlug?.toLowerCase() ?? '';
          return RegExp(r'game-\d+').hasMatch(slug);
        }).length;

    // Check for tiebreak pattern
    final tiebreakPatternCount =
        games.where((g) {
          final slug = g.roundSlug?.toLowerCase() ?? '';
          return slug.contains('tiebreak');
        }).length;

    // If more than 30% of games follow these patterns, likely a knockout format
    final patternRatio =
        (gamePatternCount + tiebreakPatternCount) / games.length;
    if (patternRatio < 0.3) return false;

    // Check for repeated player matchups
    final matchups = <String, int>{};
    for (final game in games) {
      final key = _getMatchupKey(game.whitePlayer.name, game.blackPlayer.name);
      matchups[key] = (matchups[key] ?? 0) + 1;
    }

    // A single unique matchup means a 1v1 match (e.g., World Championship,
    // Gurel vs Van Foreest), NOT a knockout bracket. Knockouts require
    // multiple distinct matchups (e.g., Player A vs B, Player C vs D).
    if (matchups.length <= 1) return false;

    // Count matchups with 2+ games (actual matches)
    final multiGameMatchups =
        matchups.values.where((count) => count >= 2).length;
    final matchupRatio = multiGameMatchups / matchups.length;

    // If more than 50% of matchups have multiple games, it's a knockout format
    return matchupRatio > 0.5;
  }

  /// Groups games by matches (same player pairs) within the SAME round
  /// This ensures matches from different rounds (e.g., Round 1 vs Round 2) are separate
  /// Returns a map of match key -> list of games in that match
  static Map<String, List<GamesTourModel>> groupByMatches(
    List<GamesTourModel> games,
  ) {
    final matches = <String, List<GamesTourModel>>{};

    for (final game in games) {
      final key = _getMatchupKey(game.whitePlayer.name, game.blackPlayer.name);
      matches.putIfAbsent(key, () => []).add(game);
    }

    // Sort games within each match by round slug (game-1, game-2, tiebreak-1, etc.)
    for (final matchGames in matches.values) {
      matchGames.sort((a, b) => _compareRoundSlugs(a.roundSlug, b.roundSlug));
    }

    return matches;
  }

  /// Groups games by MATCHES first (same player pairs across ALL rounds/games)
  /// This is the correct structure for knockout tournaments where:
  /// - Adams vs Alrehaili play Game 1 (round_id: t8DzIZPc)
  /// - Same match Game 2 (round_id: NUcmLDqC)
  /// - Same match Tiebreaks (round_id: xyz)
  /// Returns a map of match key -> all games in that match (across all rounds)
  static Map<String, List<GamesTourModel>> groupByMatchesAcrossAllRounds(
    List<GamesTourModel> allGames,
  ) {
    final matches = <String, List<GamesTourModel>>{};

    for (final game in allGames) {
      final key = _getMatchupKey(game.whitePlayer.name, game.blackPlayer.name);
      matches.putIfAbsent(key, () => []).add(game);
    }

    // Sort games within each match by round slug (game-1, game-2, tiebreak-1, etc.)
    for (final matchGames in matches.values) {
      matchGames.sort((a, b) => _compareRoundSlugs(a.roundSlug, b.roundSlug));
    }

    return matches;
  }

  /// Extracts the tournament round name from tour name
  /// Examples:
  /// - "FIDE World Cup 2025 | Quarterfinals" → "Quarterfinals"
  /// - "Tournament Name | Round 1" → "Round 1"
  /// - "Tournament Name | Semifinals" → "Semifinals"
  /// - "Tournament Name" → "Round 1" (default if no separator found)
  static String extractTournamentRoundName(String tourName) {
    // Look for pipe separator
    if (tourName.contains('|')) {
      final parts = tourName.split('|');
      if (parts.length >= 2) {
        // Return the part after the last pipe, trimmed
        return parts.last.trim();
      }
    }

    // Check if the tour name itself contains round indicators
    final roundMatch = RegExp(
      r'round\s+(\d+)',
      caseSensitive: false,
    ).firstMatch(tourName);
    if (roundMatch != null) {
      return 'Round ${roundMatch.group(1)}';
    }

    // Check for common stage names in the tour name
    final lowerName = tourName.toLowerCase();
    if (lowerName.contains('final') && !lowerName.contains('semifinal')) {
      return 'Finals';
    } else if (lowerName.contains('semifinal')) {
      return 'Semifinals';
    } else if (lowerName.contains('quarterfinal')) {
      return 'Quarterfinals';
    }

    // Default fallback
    return 'Round 1';
  }

  /// Determines the actual tournament round/stage for a match
  /// (e.g., "Round 1", "Quarterfinals", "Semifinals", "Finals")
  /// Currently extracts from roundId, but could be enhanced to detect stage from number of players
  static String getTournamentStage(List<GamesTourModel> matchGames) {
    if (matchGames.isEmpty) return 'Unknown';

    // Try to extract round number from first game's roundId
    final firstGame = matchGames.first;
    final roundId = firstGame.roundId;

    // Check if there's a round number in the roundId
    final match = RegExp(
      r'round[\s-]*(\d+)',
      caseSensitive: false,
    ).firstMatch(roundId);
    if (match != null) {
      return 'Round ${match.group(1)}';
    }

    // Default: return "Round 1" for simplicity
    return 'Round 1';
  }

  /// Creates a match header model for displaying match information
  static MatchHeaderModel createMatchHeader(
    String matchKey,
    List<GamesTourModel> matchGames,
  ) {
    if (matchGames.isEmpty) {
      throw ArgumentError('Match must have at least one game');
    }

    final firstGame = matchGames.first;
    final player1 = firstGame.whitePlayer.name;
    final player2 = firstGame.blackPlayer.name;

    // Calculate match score
    final score = _calculateMatchScore(matchGames);

    // Extract base round name (e.g., "Round 1" from "game-1")
    final roundName = _extractBaseRoundName(matchGames);

    return MatchHeaderModel(
      matchKey: matchKey,
      player1: player1,
      player2: player2,
      player1Score: score.player1Score,
      player2Score: score.player2Score,
      games: matchGames,
      roundName: roundName,
      isComplete: _isMatchComplete(matchGames),
    );
  }

  /// Formats round slug for display
  /// Examples:
  /// - "game-1" -> "Game 1"
  /// - "game-2" -> "Game 2"
  /// - "tiebreak-1-rapid-1" -> "Tiebreak 1 - Rapid 1"
  /// - "tiebreak-2-blitz-1" -> "Tiebreak 2 - Blitz 1"
  static String formatRoundSlug(String? slug) {
    if (slug == null || slug.isEmpty) return '';

    final lower = slug.toLowerCase();

    // Handle standard game format
    if (lower.startsWith('game-')) {
      final num = lower.replaceAll('game-', '');
      return 'Game $num';
    }

    // Handle tiebreak formats
    if (lower.contains('tiebreak')) {
      // Extract tiebreak number and type
      final tiebreakMatch = RegExp(r'tiebreak-(\d+)').firstMatch(lower);
      final rapidMatch = RegExp(r'rapid-(\d+)').firstMatch(lower);
      final blitzMatch = RegExp(r'blitz-(\d+)').firstMatch(lower);
      final armageddonMatch = RegExp(r'armageddon').hasMatch(lower);

      final parts = <String>[];

      if (tiebreakMatch != null) {
        final tbNum = tiebreakMatch.group(1);
        parts.add('Tiebreak $tbNum');
      } else {
        parts.add('Tiebreak');
      }

      if (rapidMatch != null) {
        parts.add('Rapid ${rapidMatch.group(1)}');
      } else if (blitzMatch != null) {
        parts.add('Blitz ${blitzMatch.group(1)}');
      } else if (armageddonMatch) {
        parts.add('Armageddon');
      }

      return parts.join(' - ');
    }

    // Fallback: capitalize first letter of each word
    return slug
        .split(RegExp(r'[-_\s]'))
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase() + s.substring(1))
        .join(' ');
  }

  /// Groups matches by their base round (e.g., all "game-1" matches together)
  static Map<String, List<MatchHeaderModel>> groupMatchesByRound(
    List<MatchHeaderModel> matches,
  ) {
    final grouped = <String, List<MatchHeaderModel>>{};

    for (final match in matches) {
      grouped.putIfAbsent(match.roundName, () => []).add(match);
    }

    return grouped;
  }

  // Private helper methods

  static String _getMatchupKey(String player1, String player2) {
    // Normalize player names and create a consistent key
    final sorted = [player1.trim(), player2.trim()]..sort();
    return '${sorted[0]}|${sorted[1]}';
  }

  static int _compareRoundSlugs(String? a, String? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;

    // Extract numbers and types for sorting
    final aInfo = _parseRoundSlugInfo(a);
    final bInfo = _parseRoundSlugInfo(b);

    // First compare by type priority (game < tiebreak)
    if (aInfo.typePriority != bInfo.typePriority) {
      return aInfo.typePriority.compareTo(bInfo.typePriority);
    }

    // Then compare by main number
    if (aInfo.mainNumber != bInfo.mainNumber) {
      return aInfo.mainNumber.compareTo(bInfo.mainNumber);
    }

    // Then compare by sub number
    return aInfo.subNumber.compareTo(bInfo.subNumber);
  }

  static _RoundSlugInfo _parseRoundSlugInfo(String slug) {
    final lower = slug.toLowerCase();

    // Check if it's a regular game
    if (lower.startsWith('game-')) {
      final num = int.tryParse(lower.replaceAll('game-', '')) ?? 0;
      return _RoundSlugInfo(typePriority: 0, mainNumber: num, subNumber: 0);
    }

    // Check if it's a tiebreak
    if (lower.contains('tiebreak')) {
      final tiebreakMatch = RegExp(r'tiebreak-(\d+)').firstMatch(lower);
      final rapidMatch = RegExp(r'rapid-(\d+)').firstMatch(lower);
      final blitzMatch = RegExp(r'blitz-(\d+)').firstMatch(lower);

      final tiebreakNum = int.tryParse(tiebreakMatch?.group(1) ?? '1') ?? 1;
      final subNum =
          int.tryParse(rapidMatch?.group(1) ?? blitzMatch?.group(1) ?? '1') ??
          1;

      // Priority: 10 for rapid, 20 for blitz, 30 for armageddon
      int typePriority = 10;
      if (blitzMatch != null) typePriority = 20;
      if (lower.contains('armageddon')) typePriority = 30;

      return _RoundSlugInfo(
        typePriority: typePriority + tiebreakNum,
        mainNumber: tiebreakNum,
        subNumber: subNum,
      );
    }

    // Fallback
    return _RoundSlugInfo(typePriority: 999, mainNumber: 0, subNumber: 0);
  }

  static ({double player1Score, double player2Score}) _calculateMatchScore(
    List<GamesTourModel> games,
  ) {
    double player1Score = 0.0;
    double player2Score = 0.0;

    if (games.isEmpty) return (player1Score: 0.0, player2Score: 0.0);

    // Use first game to determine which player is player1 and player2
    final player1Name = games.first.whitePlayer.name;

    for (final game in games) {
      final status = game.effectiveGameStatus;
      final isPlayer1White = game.whitePlayer.name == player1Name;

      switch (status) {
        case GameStatus.whiteWins:
          if (isPlayer1White) {
            player1Score += 1.0;
          } else {
            player2Score += 1.0;
          }
          break;
        case GameStatus.blackWins:
          if (isPlayer1White) {
            player2Score += 1.0;
          } else {
            player1Score += 1.0;
          }
          break;
        case GameStatus.draw:
          player1Score += 0.5;
          player2Score += 0.5;
          break;
        default:
          break;
      }
    }

    return (player1Score: player1Score, player2Score: player2Score);
  }

  static String _extractBaseRoundName(List<GamesTourModel> games) {
    if (games.isEmpty) return 'Round';

    // Try to find the base round from the first game's round slug
    final firstSlug = games.first.roundSlug?.toLowerCase() ?? '';

    // If it's a "game-N" pattern, extract the round number
    if (firstSlug.startsWith('game-')) {
      return 'Round 1'; // All games in same knockout round are "Round 1"
    }

    // For tournaments with actual round numbers in roundId
    final roundId = games.first.roundId;
    final match = RegExp(
      r'round[\s-]*(\d+)',
      caseSensitive: false,
    ).firstMatch(roundId);
    if (match != null) {
      return 'Round ${match.group(1)}';
    }

    return 'Round 1';
  }

  static bool _isMatchComplete(List<GamesTourModel> games) {
    // A match is complete if all games are finished
    return games.every((g) => g.effectiveGameStatus.isFinished);
  }
}

/// Information parsed from a round slug for sorting
class _RoundSlugInfo {
  final int typePriority;
  final int mainNumber;
  final int subNumber;

  _RoundSlugInfo({
    required this.typePriority,
    required this.mainNumber,
    required this.subNumber,
  });
}

/// Model representing a match header with player information and score
class MatchHeaderModel {
  final String matchKey;
  final String player1;
  final String player2;
  final double player1Score;
  final double player2Score;
  final List<GamesTourModel> games;
  final String roundName;
  final bool isComplete;

  const MatchHeaderModel({
    required this.matchKey,
    required this.player1,
    required this.player2,
    required this.player1Score,
    required this.player2Score,
    required this.games,
    required this.roundName,
    required this.isComplete,
  });

  String get matchTitle => '$player1 vs $player2';

  String get scoreDisplay => '$player1Score - $player2Score';

  String get fullTitle => '$roundName: $matchTitle';
}
