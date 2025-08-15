import '../base_repository.dart';

class PlayersRepository extends BaseRepository {
  Future<List<Map<String, dynamic>>> fetchPlayersPage({
    int offset = 0,
    int pageSize = 50,
  }) async {
    return handleApiCall(() async {
      final data = await supabase
          .from('games')
          .select('id, players')
          .order('id', ascending: true)
          .range(offset, offset + pageSize - 1);

      return (data as List<dynamic>)
          .map((row) => row as Map<String, dynamic>)
          .toList();
    });
  }
}
