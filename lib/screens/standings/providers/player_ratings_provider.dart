import 'package:chessever2/repository/lichess/fide/fide_player.dart';
import 'package:chessever2/repository/lichess/fide/lichess_fide_repository.dart';
import 'package:chessever2/repository/supabase/supabase.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const List<String> _chessTitlePrefixes = [
  'GM ',
  'IM ',
  'FM ',
  'CM ',
  'NM ',
  'WGM ',
  'WIM ',
  'WFM ',
  'WCM ',
  'WNM ',
];

String _stripTitlePrefix(String playerName) {
  final trimmed = playerName.trim();
  for (final prefix in _chessTitlePrefixes) {
    if (trimmed.startsWith(prefix)) {
      return trimmed.substring(prefix.length).trim();
    }
  }
  return trimmed;
}

String _normalizeNameForMatch(String name) {
  final normalized = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return normalized;
}

int? _parseRating(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? double.tryParse(value)?.round();
  return null;
}

/// Unified rating provider that handles all fallback sources in sequence:
/// 1. Supabase chess_players table by fideId (23k+ players, most reliable)
/// 2. Supabase chess_players table by name (fallback if no fideId)
/// 3. Lichess FIDE API (if fideId available)
/// 4. PGN-based ratings from games table
/// This avoids nested widget issues with autoDispose providers.
final unifiedRatingProvider = FutureProvider.family.autoDispose<
    int?,
    UnifiedRatingRequest>((ref, request) async {
  final supabase = ref.read(supabaseProvider);
  final normalizedName = _stripTitlePrefix(request.playerName);

  // Debug logging (uncomment to troubleshoot rating lookups)
  // print('🔍 UnifiedRating: Starting lookup for ${request.playerName} (fideId: ${request.fideId}, tc: ${request.timeControlType})');

  // Source 1: Try Supabase chess_players table by fideId (most reliable)
  if (request.fideId != null && request.fideId! > 0) {
    try {
      // print('📊 UnifiedRating: Trying chess_players by fideId ${request.fideId}');
      final response = await supabase
          .from('chess_players')
          .select('rating, rapid_rating, blitz_rating')
          .eq('fideid', request.fideId!)
          .maybeSingle();

      // print('📊 UnifiedRating: chess_players response: $response');
      if (response != null) {
        final rating = _extractRatingByType(response, request.timeControlType);
        // print('📊 UnifiedRating: Extracted ${request.timeControlType} rating: $rating');
        if (rating != null && rating > 0) {
          // print('✅ UnifiedRating: Returning $rating from chess_players');
          return rating;
        }
      }
    } catch (e) {
      // print('❌ UnifiedRating: chess_players fideId query failed: $e');
      // Supabase fideId query failed, continue to next source
    }
  } else {
    // print('⚠️ UnifiedRating: No fideId available, skipping chess_players lookup');
  }

  // Source 2: Try Supabase chess_players table by NAME (fallback when no fideId)
  if (normalizedName.isNotEmpty) {
    try {
      // print('📊 UnifiedRating: Trying chess_players by name "$normalizedName"');
      final response = await supabase
          .from('chess_players')
          .select('rating, rapid_rating, blitz_rating')
          .ilike('name', '%$normalizedName%')
          .limit(1)
          .maybeSingle();

      // print('📊 UnifiedRating: Name search response: $response');
      if (response != null) {
        final rating = _extractRatingByType(response, request.timeControlType);
        if (rating != null && rating > 0) {
          // print('✅ UnifiedRating: Returning $rating from name search');
          return rating;
        }
      }
    } catch (e) {
      // print('❌ UnifiedRating: Name search failed: $e');
      // Supabase name query failed, continue to next source
    }
  }

  // Source 3: Try Lichess FIDE API (if we have fideId and Supabase didn't have it)
  if (request.fideId != null && request.fideId! > 0) {
    try {
      // print('🌐 UnifiedRating: Trying Lichess FIDE API for fideId ${request.fideId}');
      final lichessRepo = ref.read(lichessFideRepoProvider);
      final player = await lichessRepo.getPlayerById(request.fideId!);
      if (player != null) {
        final rating = player.getRating(request.timeControlType);
        // print('🌐 UnifiedRating: Lichess returned ${request.timeControlType}: $rating');
        if (rating != null && rating > 0) {
          // print('✅ UnifiedRating: Returning $rating from Lichess API');
          return rating;
        }
      } else {
        // print('🌐 UnifiedRating: Lichess returned null player');
      }
    } catch (e) {
      // print('❌ UnifiedRating: Lichess API failed: $e');
      // Lichess API failed, continue to next source
    }
  }

  // Source 3b: Try Lichess search by name when no fideId is available
  if (request.fideId == null && normalizedName.isNotEmpty) {
    try {
      final lichessRepo = ref.read(lichessFideRepoProvider);
      final matches = await lichessRepo.searchPlayersByName(normalizedName);
      if (matches.isNotEmpty) {
        final normalizedTarget = _normalizeNameForMatch(normalizedName);
        FidePlayer? bestMatch;
        for (final candidate in matches) {
          final candidateName = _normalizeNameForMatch(candidate.name);
          if (candidateName == normalizedTarget) {
            bestMatch = candidate;
            break;
          }
          if (bestMatch == null &&
              (candidateName.contains(normalizedTarget) ||
                  normalizedTarget.contains(candidateName))) {
            bestMatch = candidate;
          }
        }
        bestMatch ??= matches.first;
        final rating = bestMatch.getRating(request.timeControlType);
        if (rating != null && rating > 0) {
          return rating;
        }
      }
    } catch (e) {
      // Lichess search failed, continue to next source
    }
  }

  // Source 4: Try PGN-based ratings from games table
  if (normalizedName.isNotEmpty) {
    try {
      final response = await supabase
          .from('games')
          .select('pgn, players')
          .or('player_white.ilike.%$normalizedName%,player_black.ilike.%$normalizedName%')
          .order('last_move_time', ascending: false)
          .limit(1);

      if (response.isNotEmpty) {
        final gameData = response.first;
        final players = gameData['players'] as List<dynamic>?;

        // Try to get rating from players array
        if (players != null) {
          for (final player in players) {
            final playerMap = player as Map<String, dynamic>;
            final name = playerMap['name'] as String? ?? '';
            final normalizedPlayer = _normalizeNameForMatch(name);
            final normalizedTarget = _normalizeNameForMatch(normalizedName);
            if (normalizedPlayer.contains(normalizedTarget) ||
                normalizedTarget.contains(normalizedPlayer)) {
              final rating = _parseRating(playerMap['rating']);
              if (rating != null && rating > 0) {
                return rating;
              }
            }
          }
        }

        // Fallback: extract from PGN
        final pgn = gameData['pgn'] as String?;
        if (pgn != null && pgn.isNotEmpty) {
          final pgnRating = _extractRatingFromPGN(pgn, request.playerName);
          if (pgnRating != null && pgnRating > 0) {
            // print('✅ UnifiedRating: Returning $pgnRating from PGN');
            return pgnRating;
          }
        }
      }
    } catch (e) {
      // print('❌ UnifiedRating: PGN query failed: $e');
      // PGN-based rating query failed
    }
  }

  // print('⚠️ UnifiedRating: All sources exhausted, returning null for ${request.playerName} (${request.timeControlType})');
  return null;
});

/// Helper to extract rating by time control type from chess_players response
int? _extractRatingByType(Map<String, dynamic> response, String timeControlType) {
  switch (timeControlType) {
    case 'standard':
      return _parseRating(response['rating']);
    case 'rapid':
      return _parseRating(response['rapid_rating']);
    case 'blitz':
      return _parseRating(response['blitz_rating']);
    default:
      return _parseRating(response['rating']);
  }
}

class UnifiedRatingRequest {
  final int? fideId;
  final String playerName;
  final String timeControlType;

  const UnifiedRatingRequest({
    this.fideId,
    required this.playerName,
    required this.timeControlType,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnifiedRatingRequest &&
          runtimeType == other.runtimeType &&
          fideId == other.fideId &&
          playerName == other.playerName &&
          timeControlType == other.timeControlType;

  @override
  int get hashCode =>
      fideId.hashCode ^ playerName.hashCode ^ timeControlType.hashCode;
}

/// Request for all player ratings at once (avoids 3 separate API calls)
class AllRatingsRequest {
  final int? fideId;
  final String playerName;

  const AllRatingsRequest({
    this.fideId,
    required this.playerName,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AllRatingsRequest &&
          runtimeType == other.runtimeType &&
          fideId == other.fideId &&
          playerName == other.playerName;

  @override
  int get hashCode => fideId.hashCode ^ playerName.hashCode;
}

/// Result containing all three rating types
class AllRatingsResult {
  final int? standard;
  final int? rapid;
  final int? blitz;

  const AllRatingsResult({this.standard, this.rapid, this.blitz});

  int? getRating(String timeControlType) {
    switch (timeControlType.toLowerCase()) {
      case 'standard':
      case 'classical':
        return standard;
      case 'rapid':
        return rapid;
      case 'blitz':
        return blitz;
      default:
        return standard;
    }
  }

  bool get hasAnyRating => standard != null || rapid != null || blitz != null;
}

/// Provider that fetches ALL ratings for a player at once.
/// This is much more efficient than making 3 separate API calls.
/// The result is cached by Riverpod since AllRatingsRequest only includes
/// fideId and playerName (not timeControlType).
final allRatingsProvider = FutureProvider.family.autoDispose<
    AllRatingsResult,
    AllRatingsRequest>((ref, request) async {
  final supabase = ref.read(supabaseProvider);
  final normalizedName = _stripTitlePrefix(request.playerName);

  // Source 1: Try Supabase chess_players table by fideId (most reliable)
  if (request.fideId != null && request.fideId! > 0) {
    try {
      final response = await supabase
          .from('chess_players')
          .select('rating, rapid_rating, blitz_rating')
          .eq('fideid', request.fideId!)
          .maybeSingle();

      if (response != null) {
        final standard = _parseRating(response['rating']);
        final rapid = _parseRating(response['rapid_rating']);
        final blitz = _parseRating(response['blitz_rating']);
        if ((standard != null && standard > 0) ||
            (rapid != null && rapid > 0) ||
            (blitz != null && blitz > 0)) {
          return AllRatingsResult(
            standard: standard != null && standard > 0 ? standard : null,
            rapid: rapid != null && rapid > 0 ? rapid : null,
            blitz: blitz != null && blitz > 0 ? blitz : null,
          );
        }
      }
    } catch (e) {
      // Continue to next source
    }
  }

  // Source 2: Try Supabase chess_players table by NAME
  if (normalizedName.isNotEmpty) {
    try {
      final response = await supabase
          .from('chess_players')
          .select('rating, rapid_rating, blitz_rating')
          .ilike('name', '%$normalizedName%')
          .limit(1)
          .maybeSingle();

      if (response != null) {
        final standard = _parseRating(response['rating']);
        final rapid = _parseRating(response['rapid_rating']);
        final blitz = _parseRating(response['blitz_rating']);
        if ((standard != null && standard > 0) ||
            (rapid != null && rapid > 0) ||
            (blitz != null && blitz > 0)) {
          return AllRatingsResult(
            standard: standard != null && standard > 0 ? standard : null,
            rapid: rapid != null && rapid > 0 ? rapid : null,
            blitz: blitz != null && blitz > 0 ? blitz : null,
          );
        }
      }
    } catch (e) {
      // Continue to next source
    }
  }

  // Source 3: Try Lichess FIDE API (returns all ratings in one call!)
  if (request.fideId != null && request.fideId! > 0) {
    try {
      final lichessRepo = ref.read(lichessFideRepoProvider);
      final player = await lichessRepo.getPlayerById(request.fideId!);
      if (player != null) {
        return AllRatingsResult(
          standard: player.standard != null && player.standard! > 0 ? player.standard : null,
          rapid: player.rapid != null && player.rapid! > 0 ? player.rapid : null,
          blitz: player.blitz != null && player.blitz! > 0 ? player.blitz : null,
        );
      }
    } catch (e) {
      // Continue to next source
    }
  }

  // Source 3b: Try Lichess search by name when no fideId
  if (request.fideId == null && normalizedName.isNotEmpty) {
    try {
      final lichessRepo = ref.read(lichessFideRepoProvider);
      final matches = await lichessRepo.searchPlayersByName(normalizedName);
      if (matches.isNotEmpty) {
        final normalizedTarget = _normalizeNameForMatch(normalizedName);
        FidePlayer? bestMatch;
        for (final candidate in matches) {
          final candidateName = _normalizeNameForMatch(candidate.name);
          if (candidateName == normalizedTarget) {
            bestMatch = candidate;
            break;
          }
          if (bestMatch == null &&
              (candidateName.contains(normalizedTarget) ||
                  normalizedTarget.contains(candidateName))) {
            bestMatch = candidate;
          }
        }
        bestMatch ??= matches.first;
        return AllRatingsResult(
          standard: bestMatch.standard != null && bestMatch.standard! > 0 ? bestMatch.standard : null,
          rapid: bestMatch.rapid != null && bestMatch.rapid! > 0 ? bestMatch.rapid : null,
          blitz: bestMatch.blitz != null && bestMatch.blitz! > 0 ? bestMatch.blitz : null,
        );
      }
    } catch (e) {
      // Continue to next source
    }
  }

  // Return empty result (no ratings found)
  return const AllRatingsResult();
});

/// Provider to get player rating from chess_players table by FIDE ID
/// This table has 23k+ players with all their ratings
final chessPlayerRatingProvider = FutureProvider.family.autoDispose<
    int?,
    ChessPlayerRatingRequest>((ref, request) async {
  if (request.fideId == null) return null;

  final supabase = ref.read(supabaseProvider);

  try {
    final response = await supabase
        .from('chess_players')
        .select('rating, rapid_rating, blitz_rating')
        .eq('fideid', request.fideId!)
        .maybeSingle();

    if (response == null) return null;

    // Map time control type to the correct column
    switch (request.timeControlType) {
      case 'standard':
        return response['rating'] as int?;
      case 'rapid':
        return response['rapid_rating'] as int?;
      case 'blitz':
        return response['blitz_rating'] as int?;
      default:
        return response['rating'] as int?;
    }
  } catch (e) {
    print('Error fetching rating from chess_players for fideId ${request.fideId}: $e');
    return null;
  }
});

class ChessPlayerRatingRequest {
  final int? fideId;
  final String timeControlType;

  const ChessPlayerRatingRequest({
    required this.fideId,
    required this.timeControlType,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChessPlayerRatingRequest &&
          runtimeType == other.runtimeType &&
          fideId == other.fideId &&
          timeControlType == other.timeControlType;

  @override
  int get hashCode => fideId.hashCode ^ timeControlType.hashCode;
}

// Helper method to extract rating from PGN
int? _extractRatingFromPGN(String pgn, String playerName) {
  try {
    final normalizedTarget =
        _normalizeNameForMatch(_stripTitlePrefix(playerName));
    // Check if player is White or Black
    final whiteMatch = RegExp(r'\[White "([^"]+)"\]').firstMatch(pgn);
    final blackMatch = RegExp(r'\[Black "([^"]+)"\]').firstMatch(pgn);

    final whiteName =
        _normalizeNameForMatch(_stripTitlePrefix(whiteMatch?.group(1) ?? ''));
    final blackName =
        _normalizeNameForMatch(_stripTitlePrefix(blackMatch?.group(1) ?? ''));

    final isWhite = whiteName == normalizedTarget;
    final isBlack = blackName == normalizedTarget;

    if (isWhite != true && isBlack != true) return null;

    // Extract appropriate ELO
    final pattern =
        isWhite == true
            ? RegExp(r'\[WhiteElo "(\d+)"\]')
            : RegExp(r'\[BlackElo "(\d+)"\]');

    final match = pattern.firstMatch(pgn);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }

    return null;
  } catch (e) {
    return null;
  }
}

// Provider to get latest rating for a player by time control type
final playerLatestRatingProvider = FutureProvider.family.autoDispose<
  int?,
  PlayerRatingRequest
>((ref, request) async {
  final supabase = ref.read(supabaseProvider);

  try {
    // Use a simpler approach: query by PGN content and get tours info in one query
    final response = await supabase
        .from('games')
        .select('''
          pgn,
          players,
          last_move_time,
          tours!inner(info)
        ''')
        .like('pgn', '%${request.playerName}%')
        .eq('tours.info->>fideTc', request.timeControlType)
        .order('last_move_time', ascending: false)
        .limit(1);

    if (response.isEmpty) return null;

    final gameData = response.first;
    final pgn = gameData['pgn'] as String?;
    final players = gameData['players'] as List<dynamic>;

    // First try to get rating from players array
    for (final player in players) {
      final playerMap = player as Map<String, dynamic>;
      if (playerMap['name'] == request.playerName) {
        final rating = playerMap['rating'] as int?;
        if (rating != null && rating > 0) {
          return rating;
        }
      }
    }

    // Fallback: extract rating from PGN if not in players array
    if (pgn != null && pgn.isNotEmpty) {
      return _extractRatingFromPGN(pgn, request.playerName);
    }

    return null;
  } catch (e) {
    // Log error for debugging and return null
    print(
      'Error fetching rating for ${request.playerName} (${request.timeControlType}): $e',
    );
    return null;
  }
});

class PlayerRatingRequest {
  final String playerName;
  final String timeControlType; // "standard", "blitz", "rapid"

  const PlayerRatingRequest({
    required this.playerName,
    required this.timeControlType,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerRatingRequest &&
          runtimeType == other.runtimeType &&
          playerName == other.playerName &&
          timeControlType == other.timeControlType;

  @override
  int get hashCode => playerName.hashCode ^ timeControlType.hashCode;
}
