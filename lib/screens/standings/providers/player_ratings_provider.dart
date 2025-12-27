import 'package:chessever2/repository/lichess/fide/lichess_fide_repository.dart';
import 'package:chessever2/repository/supabase/supabase.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Unified rating provider that handles all fallback sources in sequence:
/// 1. Lichess FIDE API (if fideId available)
/// 2. Supabase chess_players table (if fideId available)
/// 3. PGN-based ratings from games table
/// This avoids nested widget issues with autoDispose providers.
final unifiedRatingProvider = FutureProvider.family.autoDispose<
    int?,
    UnifiedRatingRequest>((ref, request) async {
  // Source 1: Try Lichess FIDE API first (if we have fideId)
  if (request.fideId != null) {
    try {
      final lichessRepo = ref.read(lichessFideRepoProvider);
      final player = await lichessRepo.getPlayerById(request.fideId!);
      if (player != null) {
        final rating = player.getRating(request.timeControlType);
        if (rating != null && rating > 0) {
          return rating;
        }
      }
    } catch (e) {
      print('Lichess API failed for fideId ${request.fideId}: $e');
    }
  }

  // Source 2: Try Supabase chess_players table (if we have fideId)
  if (request.fideId != null) {
    try {
      final supabase = ref.read(supabaseProvider);
      final response = await supabase
          .from('chess_players')
          .select('rating, rapid_rating, blitz_rating')
          .eq('fideid', request.fideId!)
          .maybeSingle();

      if (response != null) {
        int? rating;
        switch (request.timeControlType) {
          case 'standard':
            rating = response['rating'] as int?;
            break;
          case 'rapid':
            rating = response['rapid_rating'] as int?;
            break;
          case 'blitz':
            rating = response['blitz_rating'] as int?;
            break;
          default:
            rating = response['rating'] as int?;
        }
        if (rating != null && rating > 0) {
          return rating;
        }
      }
    } catch (e) {
      print('Supabase chess_players query failed: $e');
    }
  }

  // Source 3: Try PGN-based ratings from games table
  if (request.playerName.isNotEmpty) {
    try {
      final supabase = ref.read(supabaseProvider);
      final response = await supabase
          .from('games')
          .select('pgn, players')
          .or('player_white.ilike.%${request.playerName}%,player_black.ilike.%${request.playerName}%')
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
            if (name.toLowerCase().contains(request.playerName.toLowerCase()) ||
                request.playerName.toLowerCase().contains(name.toLowerCase())) {
              final rating = playerMap['rating'] as int?;
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
            return pgnRating;
          }
        }
      }
    } catch (e) {
      print('PGN-based rating query failed: $e');
    }
  }

  return null;
});

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
    // Check if player is White or Black
    final whiteMatch = RegExp(r'\[White "([^"]+)"\]').firstMatch(pgn);
    final blackMatch = RegExp(r'\[Black "([^"]+)"\]').firstMatch(pgn);

    final isWhite = whiteMatch?.group(1) == playerName;
    final isBlack = blackMatch?.group(1) == playerName;

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
