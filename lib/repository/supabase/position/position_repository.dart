import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:chessever2/repository/supabase/position/position.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final positionRepositoryProvider = AutoDisposeProvider<PositionRepository>(
  (ref) => PositionRepository(),
);

class PositionRepository extends BaseRepository {
  Future<List<Position>> getAll() => handleApiCall(() async {
    final response = await supabase.from('positions').select();
    return (response as List).map((json) => Position.fromJson(json)).toList();
  });

  Future<Position?> getById(int id) => handleApiCall(() async {
    final response =
        await supabase.from('positions').select().eq('id', id).maybeSingle();
    return response != null ? Position.fromJson(response) : null;
  });

  Future<Position> create(String fen) => handleApiCall(() async {
    final response = await supabase
    .from('positions')
    .upsert({'fen': fen}, onConflict: 'fen')
    .select()
    .single();
    return Position.fromJson(response);
  });

  Future<Position?> getByFen(String fen) => handleApiCall(() async {
    final res =
    await supabase.from('positions').select().eq('fen', fen).maybeSingle();
    return res == null ? null : Position.fromJson(res);
  });

  Future<void> delete(int id) => handleApiCall(() async {
    await supabase.from('positions').delete().eq('id', id);
  });
}
