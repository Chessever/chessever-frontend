import '../base_repository.dart';

class PlayersRepository extends BaseRepository {
  Future<List<Map<String, dynamic>>> fetchPlayersPage({
    int offset = 0,
    int pageSize = 50,
    String search = '',
    String? countryCode,
  }) async {
    return handleApiCall(() async {
      final query = supabase
          .from('chess_players')
          .select('fide_id, name, title, rating, fed')
          .order('rating', ascending: false)
          .range(offset, offset + pageSize - 1);

      if (search.trim().isNotEmpty) {
        final term = '%${search.trim()}%';
        query.or('name.ilike.$term,title.ilike.$term');
      }

      if (countryCode != null && countryCode.isNotEmpty) {
        query.eq('fed', countryCode.toUpperCase());
      }

      final data = await query;

      return (data as List<dynamic>)
          .map((row) => row as Map<String, dynamic>)
          .toList();
    });
  }
}
