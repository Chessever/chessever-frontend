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
  static const int _inFilterChunkSize = 150;
  static final Map<int, ChessPlayer?> _playerByFideIdCache = {};

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
    if (fideId <= 0) return null;
    final cached = _playerByFideIdCache[fideId];
    if (cached != null || _playerByFideIdCache.containsKey(fideId)) {
      return cached;
    }

    final data =
        await supabase
            .from('chess_players')
            .select('fideid, name, title, rating, country')
            .eq('fideid', fideId)
            .maybeSingle();

    if (data == null) {
      _playerByFideIdCache[fideId] = null;
      return null;
    }

    final player = ChessPlayer.fromMap(data);
    _playerByFideIdCache[fideId] = player;
    return player;
  }

  /// Batch load players by FIDE IDs with in-memory caching.
  Future<Map<int, ChessPlayer>> getPlayersByFideIds(
    Iterable<int> fideIds,
  ) async {
    final ids = fideIds.where((id) => id > 0).toSet();
    if (ids.isEmpty) return const <int, ChessPlayer>{};

    final result = <int, ChessPlayer>{};
    final missing = <int>[];

    for (final id in ids) {
      final cached = _playerByFideIdCache[id];
      if (cached != null) {
        result[id] = cached;
      } else if (!_playerByFideIdCache.containsKey(id)) {
        missing.add(id);
      }
    }

    if (missing.isNotEmpty) {
      for (int i = 0; i < missing.length; i += _inFilterChunkSize) {
        final end =
            (i + _inFilterChunkSize < missing.length)
                ? i + _inFilterChunkSize
                : missing.length;
        final chunk = missing.sublist(i, end);
        final rows = await supabase
            .from('chess_players')
            .select('fideid, name, title, rating, country')
            .inFilter('fideid', chunk);

        final fetchedIds = <int>{};
        for (final row in (rows as List)) {
          final player = ChessPlayer.fromMap(Map<String, dynamic>.from(row));
          fetchedIds.add(player.fideid);
          _playerByFideIdCache[player.fideid] = player;
          result[player.fideid] = player;
        }

        for (final requestedId in chunk) {
          if (!fetchedIds.contains(requestedId)) {
            _playerByFideIdCache[requestedId] = null;
          }
        }
      }
    }

    return result;
  }
}
