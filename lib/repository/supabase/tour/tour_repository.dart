import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tourRepositoryProvider = AutoDisposeProvider<TourRepository>((ref) {
  return TourRepository();
});

class TourRepository extends BaseRepository {
  // Fetch tour by ID
  Future<List<Tour>> getTourByGroupId(String groupId) async {
    return handleApiCall(() async {
      var query = supabase
          .from('tours')
          .select()
          .eq('group_broadcast_id', groupId)
          .order('avg_elo', ascending: false);

      final response = await query;
      return (response as List).map((json) => Tour.fromJson(json)).toList();
    });
  }
}
