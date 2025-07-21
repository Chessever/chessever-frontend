import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:chessever2/repository/supabase/evals/evals.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final evalsRepositoryProvider = AutoDisposeProvider<EvalRepository>(
  (ref) => EvalRepository(),
);

class EvalRepository extends BaseRepository {
  Future<Evals> create(Evals eval) => handleApiCall(() async {
    final data =
        await supabase.from('evals').insert(eval.toJson()).select().single();
    return Evals.fromJson(data);
  });

  Future<Evals?> getById(int id) => handleApiCall(() async {
    final data =
        await supabase.from('evals').select().eq('id', id).maybeSingle();
    return data != null ? Evals.fromJson(data) : null;
  });

  Future<List<Evals>> getByPositionId(int positionId) =>
      handleApiCall(() async {
        final data = await supabase
            .from('evals')
            .select()
            .eq('position_id', positionId);
        return data.map<Evals>((json) => Evals.fromJson(json)).toList();
      });

  Future<void> delete(int id) =>
      handleApiCall(() => supabase.from('evals').delete().eq('id', id));
}
