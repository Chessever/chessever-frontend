import 'package:chessever2/utils/country_utils.dart';

import '../base_repository.dart';

class PlayersRepository extends BaseRepository {
  /// Fetches a paginated list of players from chess_players table.
  ///
  /// - [search]: Filter by name or title (ilike)
  /// - [countryCode]: Filter by country (exact match)
  /// - Orders by rating descending
  Future<List<Map<String, dynamic>>> fetchPlayersPage({
    int offset = 0,
    int pageSize = 20,
    String search = '',
    String? countryCode,
  }) async {
    return handleApiCall(() async {
      var builder = supabase
          .from('chess_players')
          .select('fideid, name, title, rating, country');

      // Apply search filter
      if (search.trim().isNotEmpty) {
        final term = '%${search.trim()}%';
        builder = builder.or('name.ilike.$term,title.ilike.$term');
      }

      // Apply country filter (only when not searching)
      // Convert ISO 2-letter to FIDE 3-letter code
      if (countryCode != null &&
          countryCode.isNotEmpty &&
          search.trim().isEmpty) {
        final fideCode = CountryUtils.toFideCode(countryCode);
        builder = builder.eq('country', fideCode);
      }

      // Filter: rating < 3300 (exclude bots/invalid)
      builder = builder.or('rating.lt.3300,rating.is.null');

      final data = await builder
          .order('rating', ascending: false, nullsFirst: false)
          .range(offset, offset + pageSize - 1);

      return (data as List<dynamic>).map((row) {
        final map = row as Map<String, dynamic>;
        // Normalize column names for the app
        return {
          'fideId': map['fideid']?.toString(),
          'name': map['name'],
          'title': map['title'],
          'rating': map['rating'] ?? 0,
          'fed': map['country'], // Map 'country' to 'fed' for app compatibility
        };
      }).toList();
    });
  }

  /// Fetches players optimized for onboarding:
  /// 1. Top players from user's country (first batch)
  /// 2. Global top players (mixed in)
  ///
  /// Returns a combined, deduplicated list.
  Future<List<Map<String, dynamic>>> fetchOnboardingPlayers({
    required String countryCode,
    int countryLimit = 8,
    int globalLimit = 7,
  }) async {
    return handleApiCall(() async {
      // Convert ISO 2-letter to FIDE 3-letter code
      final fideCode = CountryUtils.toFideCode(countryCode);

      // Fetch top players from user's country
      final countryData = await supabase
          .from('chess_players')
          .select('fideid, name, title, rating, country')
          .eq('country', fideCode)
          .gt('rating', 0)
          .lt('rating', 3300)
          .order('rating', ascending: false)
          .limit(countryLimit);

      // Fetch global top players (excluding user's country for variety)
      final globalData = await supabase
          .from('chess_players')
          .select('fideid, name, title, rating, country')
          .neq('country', fideCode)
          .gt('rating', 2600) // Only top-tier global players
          .lt('rating', 3300)
          .order('rating', ascending: false)
          .limit(globalLimit);

      final Set<String> seenIds = {};
      final List<Map<String, dynamic>> result = [];

      // Helper to normalize and add player
      void addPlayer(Map<String, dynamic> map) {
        final id = map['fideid']?.toString() ?? '';
        if (id.isEmpty || seenIds.contains(id)) return;
        seenIds.add(id);
        result.add({
          'fideId': id,
          'name': map['name'],
          'title': map['title'],
          'rating': map['rating'] ?? 0,
          'fed': map['country'],
        });
      }

      // Add country players first (priority)
      for (final row in (countryData as List)) {
        addPlayer(row as Map<String, dynamic>);
      }

      // Then add global players
      for (final row in (globalData as List)) {
        addPlayer(row as Map<String, dynamic>);
      }

      return result;
    });
  }

  /// Search players by name with pagination
  Future<List<Map<String, dynamic>>> searchPlayers({
    required String query,
    int offset = 0,
    int pageSize = 20,
  }) async {
    return handleApiCall(() async {
      if (query.trim().isEmpty) return [];

      final term = '%${query.trim()}%';

      final data = await supabase
          .from('chess_players')
          .select('fideid, name, title, rating, country')
          .or('name.ilike.$term,title.ilike.$term')
          .or('rating.lt.3300,rating.is.null')
          .order('rating', ascending: false, nullsFirst: false)
          .range(offset, offset + pageSize - 1);

      return (data as List<dynamic>).map((row) {
        final map = row as Map<String, dynamic>;
        return {
          'fideId': map['fideid']?.toString(),
          'name': map['name'],
          'title': map['title'],
          'rating': map['rating'] ?? 0,
          'fed': map['country'],
        };
      }).toList();
    });
  }
}
