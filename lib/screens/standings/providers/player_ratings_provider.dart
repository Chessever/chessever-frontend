import 'package:chessever2/repository/supabase/supabase.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
