import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:chessever2/repository/supabase/evals/evals.dart';
import 'package:chessever2/repository/supabase/position/position_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final evalsRepositoryProvider = AutoDisposeProvider<EvalRepository>(
  (ref) => EvalRepository(ref),
);

class EvalRepository extends BaseRepository {
  EvalRepository(this.ref);

  final ref;

  Future<Evals> upsert(Evals eval) => handleApiCall(() async {
    final pvsCount = eval.pvs.length;
    final existingRecord =
        await supabase
            .from('evals')
            .select()
            .eq('position_id', eval.positionId)
            .eq('knodes', eval.knodes)
            .eq('depth', eval.depth)
            .eq('pvs_count', pvsCount)
            .maybeSingle();
    if (existingRecord != null) {
      print('Eval record already exists, returning existing record');
      return eval;
    }
    final newData =
        await supabase.from('evals').insert(eval.toJson()).select().single();
    return Evals.fromJson(newData);
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

  Future<Evals?> fetchFromSupabase(String fen) async {
    final posRepo = ref.read(positionRepositoryProvider);

    final pos = await posRepo.getByFen(fen);
    if (pos == null) return null;

    final evals = await getByPositionId(pos.id);
    return evals.isEmpty ? null : evals.first;
  }

  CloudEval evalsToCloudEval(String fen, Evals eval) {
    final fenParts = fen.split(' ');
    final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';

    final pvsList = (eval.pvs as List).map((e) => Pv(
      moves: e['moves'] ?? '',
      cp: e['cp'] ?? 0,
    )).toList();

    final cp = pvsList.isNotEmpty ? pvsList.first.cp : 0;

    // With the fixed saving logic, all new evaluations should be in white's perspective
    // But old data might still be wrong, so this serves as a fallback
    print("🔧 SUPABASE: fen=$fen, side=$sideToMove, cp=$cp (assuming white's perspective from fixed saving logic)");

    return CloudEval(
      fen: fen,
      knodes: eval.knodes,
      depth: eval.depth,
      pvs: pvsList,
    );
  }

  Future<void> delete(int id) =>
      handleApiCall(() => supabase.from('evals').delete().eq('id', id));
}
