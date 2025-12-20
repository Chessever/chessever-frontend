import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/repository/supabase/base_repository.dart';

// --- Model ---

class ChessPlayer {
  final int fideid;
  final String name;
  final String? title;
  final int? rating;
  final String? country;

  const ChessPlayer({
    required this.fideid,
    required this.name,
    this.title,
    this.rating,
    this.country,
  });

  factory ChessPlayer.fromMap(Map<String, dynamic> map) {
    return ChessPlayer(
      fideid: map['fideid'] as int,
      name: map['name'] as String? ?? '',
      title: map['title'] as String?,
      rating: map['rating'] as int?,
      country: map['country'] as String?,
    );
  }
}

// --- Provider ---

final chessPlayerRepositoryProvider = Provider<ChessPlayerRepository>((ref) {
  return ChessPlayerRepository();
});

// --- Repository ---

class ChessPlayerRepository extends BaseRepository {

  /// Get top players (by rating)
  Future<List<ChessPlayer>> getTopPlayers({
    int limit = 30,
    int offset = 0,
  }) async {
    final data = await supabase
        .from('chess_players')
        .select('fideid, name, title, rating, country')
        .gt('rating', 0)
        .lt('rating', 3300)
        .order('rating', ascending: false)
        .range(offset, offset + limit - 1);

    return (data as List).map((row) => ChessPlayer.fromMap(row)).toList();
  }

  /// Search all players by name
  Future<List<ChessPlayer>> searchAllPlayers({
    required String query,
    int limit = 30,
    int offset = 0,
  }) async {
    if (query.trim().isEmpty) {
      return getTopPlayers(limit: limit, offset: offset);
    }

    final term = '%${query.trim()}%';
    final data = await supabase
        .from('chess_players')
        .select('fideid, name, title, rating, country')
        .or('name.ilike.$term,title.ilike.$term')
        .gt('rating', 0)
        .lt('rating', 3300)
        .order('rating', ascending: false)
        .range(offset, offset + limit - 1);

    return (data as List).map((row) => ChessPlayer.fromMap(row)).toList();
  }

  /// Get players by country (FIDE federation code)
  Future<List<ChessPlayer>> getPlayersByCountry({
    required String countryCode,
    String? searchQuery,
    int limit = 30,
    int offset = 0,
  }) async {
    var builder = supabase
        .from('chess_players')
        .select('fideid, name, title, rating, country')
        .eq('country', countryCode)
        .gt('rating', 0)
        .lt('rating', 3300);

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      builder = builder.or('name.ilike.$term,title.ilike.$term');
    }

    final data = await builder
        .order('rating', ascending: false)
        .range(offset, offset + limit - 1);

    return (data as List).map((row) => ChessPlayer.fromMap(row)).toList();
  }

  /// Get a single player by FIDE ID
  Future<ChessPlayer?> getPlayerByFideId(int fideId) async {
    final data = await supabase
        .from('chess_players')
        .select('fideid, name, title, rating, country')
        .eq('fideid', fideId)
        .maybeSingle();

    if (data == null) return null;
    return ChessPlayer.fromMap(data);
  }
}
