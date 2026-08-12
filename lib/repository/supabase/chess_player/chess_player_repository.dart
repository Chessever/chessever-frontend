import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:chessever2/utils/country_utils.dart';

// --- Model ---

class ChessPlayer {
  final int fideid;
  final String name;
  final String? title;
  final int? rating;
  final int? rapidRating;
  final int? blitzRating;
  final String? country;
  final String? sex;
  final int? birthYear;
  final String? flag;

  const ChessPlayer({
    required this.fideid,
    required this.name,
    this.title,
    this.rating,
    this.rapidRating,
    this.blitzRating,
    this.country,
    this.sex,
    this.birthYear,
    this.flag,
  });

  factory ChessPlayer.fromMap(Map<String, dynamic> map) {
    return ChessPlayer(
      fideid: map['fideid'] as int,
      name: map['name'] as String? ?? '',
      title: map['title'] as String?,
      rating: (map['rating'] as num?)?.toInt(),
      rapidRating: (map['rapid_rating'] as num?)?.toInt(),
      blitzRating: (map['blitz_rating'] as num?)?.toInt(),
      country: map['country'] as String?,
      sex: map['sex'] as String?,
      birthYear: (map['birthday'] as num?)?.toInt(),
      flag: map['flag'] as String?,
    );
  }

  int? ratingFor(RankingTimeControl timeControl) => switch (timeControl) {
    RankingTimeControl.classical => rating,
    RankingTimeControl.rapid => rapidRating,
    RankingTimeControl.blitz => blitzRating,
  };

  bool get isInactive => isFideInactiveFlag(flag);
}

// --- Provider ---

final chessPlayerRepositoryProvider = Provider<ChessPlayerRepository>((ref) {
  return ChessPlayerRepository();
});

// --- Repository ---

class ChessPlayerRepository extends BaseRepository {
  static const int _inFilterChunkSize = 150;
  static final Map<int, ChessPlayer?> _playerByFideIdCache = {};

  /// Get top players (by rating).
  ///
  /// Same ranking rules as Favorites → Players: rating > 0, rating < 3300,
  /// ordered rating descending, offset/limit range pagination.
  /// Optional [titles] filters to FIDE title codes (e.g. GM, IM, FM).
  Future<List<ChessPlayer>> getTopPlayers({
    int limit = 30,
    int offset = 0,
    Iterable<String>? titles,
  }) async {
    var builder = supabase
        .from('chess_players')
        .select('fideid, name, title, rating, country')
        .gt('rating', 0)
        .lt('rating', 3300);

    final titleList =
        titles
            ?.map((t) => t.trim().toUpperCase())
            .where((t) => t.isNotEmpty)
            .toList();
    if (titleList != null && titleList.isNotEmpty) {
      builder = builder.inFilter('title', titleList);
    }

    final data = await builder
        .order('rating', ascending: false)
        .range(offset, offset + limit - 1);

    return (data as List).map((row) => ChessPlayer.fromMap(row)).toList();
  }

  /// Fetch a stable page from the canonical FIDE monthly ranking fields.
  ///
  /// [countryCode] is a FIDE federation code (`USA`, `TUR`, …), not ISO-2. Pass
  /// it to scope the whole ranking — filters, search and pagination included —
  /// to one federation; leave it null for the world list.
  Future<List<ChessPlayer>> getRankedPlayers({
    required RankingFilters filters,
    String? countryCode,
    String searchQuery = '',
    int limit = 30,
    int offset = 0,
    DateTime? now,
  }) async {
    final ratingColumn = filters.timeControl.ratingColumn;
    var query = supabase
        .from('chess_players')
        .select(
          'fideid, name, title, rating, rapid_rating, blitz_rating, '
          'country, sex, birthday, flag',
        )
        .not(ratingColumn, 'is', null)
        .gt(ratingColumn, 0)
        .lt(ratingColumn, 3300);

    final federation = countryCode?.trim().toUpperCase();
    if (federation != null && federation.isNotEmpty) {
      query = query.eq('country', federation);
    }

    if (filters.activity == RankingActivity.active) {
      query = query.or('flag.is.null,flag.not.ilike.*i*');
    }
    if (filters.category.requiresFemale) {
      query = query.eq('sex', 'F');
    }
    if (filters.category.requiresJunior) {
      query = query.gte('birthday', (now ?? DateTime.now()).year - 20);
    }

    final normalizedSearch = searchQuery.trim();
    if (normalizedSearch.isNotEmpty) {
      query = query.ilike('name', '%$normalizedSearch%');
    }

    final data = await query
        .order(ratingColumn, ascending: false)
        .order('fideid', ascending: true)
        .range(offset, offset + limit - 1);

    return (data as List).map((row) => ChessPlayer.fromMap(row)).toList();
  }

  /// Search all players by name
  Future<List<ChessPlayer>> searchAllPlayers({
    required String query,
    int limit = 30,
    int offset = 0,
    Iterable<String>? titles,
  }) async {
    if (query.trim().isEmpty) {
      return getTopPlayers(limit: limit, offset: offset, titles: titles);
    }

    final term = '%${query.trim()}%';
    final fedCode = CountryUtils.resolveFideCode(query);

    final orFilters = StringBuffer('name.ilike.$term,title.ilike.$term');
    if (fedCode != null) {
      orFilters.write(',country.eq.$fedCode');
    }

    var builder = supabase
        .from('chess_players')
        .select('fideid, name, title, rating, country')
        .or(orFilters.toString())
        .gt('rating', 0)
        .lt('rating', 3300);

    final titleList =
        titles
            ?.map((t) => t.trim().toUpperCase())
            .where((t) => t.isNotEmpty)
            .toList();
    if (titleList != null && titleList.isNotEmpty) {
      builder = builder.inFilter('title', titleList);
    }

    final data = await builder
        .order('rating', ascending: false)
        .range(offset, offset + limit - 1);

    return (data as List).map((row) => ChessPlayer.fromMap(row)).toList();
  }

  /// Search players by name words in any order.
  ///
  /// Handles FIDE-style names such as "Carlsen, Magnus" when the user types
  /// natural-order text such as "Magnus" or "Magnus Carlsen".
  Future<List<ChessPlayer>> searchPlayersByNameWords({
    required String query,
    int limit = 30,
    int offset = 0,
  }) async {
    final words =
        query
            .trim()
            .replaceAll(',', ' ')
            .split(RegExp(r'\s+'))
            .where((word) => word.length >= 2)
            .toList();

    if (words.isEmpty) return [];

    var builder = supabase
        .from('chess_players')
        .select('fideid, name, title, rating, country');

    for (final word in words) {
      builder = builder.ilike('name', '%$word%');
    }

    final data = await builder
        .or('rating.lt.3300,rating.is.null')
        .order('rating', ascending: false, nullsFirst: false)
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
