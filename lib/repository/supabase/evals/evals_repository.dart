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
    final existingRecord = await supabase
        .from('evals')
        .select()
        .eq('position_id', eval.positionId)
        .eq('depth', eval.depth)
        .maybeSingle();

    if (existingRecord != null) {
      final id = existingRecord['id'] as int?;
      if (id != null) {
        final updatePayload = {
          'knodes': eval.knodes,
          'depth': eval.depth,
          'pvs': eval.pvs,
        };
        final updated = await supabase
            .from('evals')
            .update(updatePayload)
            .eq('id', id)
            .select()
            .single();
        print('Eval record updated for position ${eval.positionId} (id=$id)');
        return Evals.fromJson(updated);
      }
      print('Eval record exists without id for position ${eval.positionId}, reusing existing data');
      return Evals.fromJson(Map<String, dynamic>.from(existingRecord));
    }

    final payload = eval.toJson();
    final newData =
        await supabase.from('evals').insert(payload).select().single();
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
    if (evals.isEmpty) return null;

    final first = evals.first;
    final pvsList = first.pvs;
    final hasWhitePerspective = pvsList is List &&
        pvsList.isNotEmpty &&
        pvsList.every(
          (entry) => entry is Map<String, dynamic> && (entry['whitePerspective'] ?? false) == true,
        );

    if (!hasWhitePerspective) {
      print('🔧 SUPABASE: Cached eval for $fen missing whitePerspective flag, forcing refresh from Lichess');
      return null;
    }

    return first;
  }

  CloudEval evalsToCloudEval(String fen, Evals eval) {
    final fenParts = fen.split(' ');
    final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';

    final pvsList = (eval.pvs as List)
        .map(
          (entry) => Pv.fromJson(
            Map<String, dynamic>.from(entry as Map),
          ),
        )
        .toList();

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
