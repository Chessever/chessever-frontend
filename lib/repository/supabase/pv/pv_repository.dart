import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:chessever2/repository/supabase/pv/supabase_pv.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final pvRepositoryProvider = AutoDisposeProvider<PvRepository>(
  (ref) => PvRepository(),
);

class PvRepository extends BaseRepository {
 
  Future<List<SupabasePv>> getByEvalId(int evalId) => handleApiCall(() async {
    final response = await supabase.from('pvs').select().eq('eval_id', evalId);
    return (response as List).map((json) => SupabasePv.fromJson(json)).toList();
  });

  Future<SupabasePv> create({
    required int evalId,
    required int idx,
    int? cp,
    int? mate,
    required String line,
  }) => handleApiCall(() async {
    final response =
        await supabase
            .from('pvs')
            .insert({
              'eval_id': evalId,
              'idx': idx,
              'cp': cp,
              'mate': mate,
              'line': line,
            })
            .select()
            .single();
    return SupabasePv.fromJson(response);
  });

  Future<void> delete(int id) => handleApiCall(() async {
    await supabase.from('pvs').delete().eq('id', id);
  });
}
