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
    final existingRecord =
        await supabase
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
          if (eval.multiPv != null) 'multi_pv': eval.multiPv,
        };
        final updated =
            await supabase
                .from('evals')
                .update(updatePayload)
                .eq('id', id)
                .select()
                .single();
        print('Eval record updated for position ${eval.positionId} (id=$id)');
        return Evals.fromJson(updated);
      }
      print(
        'Eval record exists without id for position ${eval.positionId}, reusing existing data',
      );
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

  Future<Evals?> fetchFromSupabase(String fen, {int? desiredMultiPv}) async {
    final posRepo = ref.read(positionRepositoryProvider);

    final pos = await posRepo.getByFen(fen);
    if (pos == null) return null;

    final evals = await getByPositionId(pos.id);
    if (evals.isEmpty) return null;

    Evals? selectBestMatch(Iterable<Evals> candidates) {
      if (candidates.isEmpty) return null;
      final sorted =
          candidates.toList()..sort((a, b) {
            final multiA = (a.multiPv ?? a.pvs.length);
            final multiB = (b.multiPv ?? b.pvs.length);
            if (multiB != multiA)
              return multiB.compareTo(multiA); // prefer higher PV count
            if (b.depth != a.depth)
              return b.depth.compareTo(a.depth); // then deeper depth
            return 0;
          });
      return sorted.first;
    }

    if (desiredMultiPv != null && desiredMultiPv > 0) {
      final matchingOrBetter = evals.where(
        (e) =>
            (e.multiPv ?? e.pvs.length) >= desiredMultiPv && e.pvs.isNotEmpty,
      );
      final exactOrBetter = selectBestMatch(matchingOrBetter);
      if (exactOrBetter != null) {
        final existingMulti = exactOrBetter.multiPv ?? exactOrBetter.pvs.length;
        if (existingMulti == desiredMultiPv) {
          return exactOrBetter;
        }
        final trimmedPvs =
            exactOrBetter.pvs.take(desiredMultiPv).toList(growable: false);
        return exactOrBetter.copyWith(
          pvs: trimmedPvs,
          multiPv: desiredMultiPv,
        );
      }
      return null;
    }

    return selectBestMatch(evals.where((e) => e.pvs.isNotEmpty));
  }

  /// Batch fetch evals for multiple FENs - much faster than individual fetches
  Future<Map<String, Evals>> batchFetchFromSupabase(List<String> fens) async {
    if (fens.isEmpty) return {};

    final result = <String, Evals>{};

    try {
      // Fetch all positions at once using IN clause
      final positions = await supabase
          .from('positions')
          .select()
          .inFilter('fen', fens);

      if (positions.isEmpty) return {};

      final positionIds = <int>[];
      final fenToPositionId = <String, int>{};

      for (final pos in positions) {
        final id = pos['id'] as int?;
        final fen = pos['fen'] as String?;
        if (id != null && fen != null) {
          positionIds.add(id);
          fenToPositionId[fen] = id;
        }
      }

      if (positionIds.isEmpty) return {};

      // Fetch all evals at once using IN clause
      final evalsData = await supabase
          .from('evals')
          .select()
          .inFilter('position_id', positionIds);

      // Group evals by position_id and take first (highest depth)
      final evalsByPositionId = <int, Evals>{};
      for (final evalJson in evalsData) {
        final eval = Evals.fromJson(evalJson);
        final posId = eval.positionId;

        if (!evalsByPositionId.containsKey(posId)) {
          evalsByPositionId[posId] = eval;
          continue;
        }

        final existing = evalsByPositionId[posId]!;
        final existingMulti = existing.multiPv ?? existing.pvs.length;
        final candidateMulti = eval.multiPv ?? eval.pvs.length;

        final shouldReplace =
            candidateMulti > existingMulti ||
            (candidateMulti == existingMulti && eval.depth > existing.depth);
        if (shouldReplace) {
          evalsByPositionId[posId] = eval;
        }
      }

      // Map back to FENs
      for (final entry in fenToPositionId.entries) {
        final fen = entry.key;
        final posId = entry.value;
        if (evalsByPositionId.containsKey(posId)) {
          result[fen] = evalsByPositionId[posId]!;
        }
      }
    } catch (e) {
      print('❌ Batch fetch from Supabase failed: $e');
    }

    return result;
  }

  CloudEval evalsToCloudEval(String fen, Evals eval) {
    bool legacyPerspective = false;

    final pvsList = <Pv>[];
    for (final entry in eval.pvs) {
      final map = Map<String, dynamic>.from(entry as Map);
      final hasPerspectiveKey = map.containsKey('whitePerspective');

      final rawMoves =
          (map['moves'] as String?) ?? (map['line'] as String?) ?? '';
      final moves = rawMoves == 'no moves' ? '' : rawMoves;

      int cp = 0;
      bool isMate = false;
      int? mate;

      final dynamic mateValue = map['mate'];
      if (mateValue != null) {
        final parsedMate = int.tryParse(mateValue.toString());
        if (parsedMate != null) {
          mate = parsedMate;
          isMate = true;
          cp = parsedMate.sign * 100000;
        }
      }

      if (!isMate) {
        final dynamic cpValue = map['cp'];
        if (cpValue is int) {
          cp = cpValue;
        } else if (cpValue != null) {
          cp = int.tryParse(cpValue.toString()) ?? 0;
        }
      }

      bool whitePerspective = (map['whitePerspective'] as bool?) ?? false;

      if (!whitePerspective && !hasPerspectiveKey) {
        // CRITICAL: Legacy data (no whitePerspective key) from Lichess API
        // was ALREADY in white's perspective - no conversion needed!
        // Lichess API always returns evaluations in white's perspective.
        // Only Stockfish returns side-to-move perspective (handled in stockfish_singleton.dart)
        legacyPerspective = true;
        whitePerspective = true;
        // NO CONVERSION - legacy Lichess data already in white's perspective!
      } else if (!whitePerspective) {
        // Stored from black's perspective explicitly - normalize
        whitePerspective = true;
        cp = -cp;
        if (mate != null) mate = -mate;
      }

      pvsList.add(
        Pv(
          moves: moves,
          cp: cp,
          isMate: isMate,
          mate: mate,
          whitePerspective: whitePerspective,
        ),
      );
    }

    if (legacyPerspective) {
      print(
        '🔧 SUPABASE: Normalized legacy evaluation for $fen to white perspective',
      );
    }

    return CloudEval(
      fen: fen,
      knodes: eval.knodes,
      depth: eval.depth,
      pvs: pvsList,
      requestedMultiPv: eval.multiPv ?? pvsList.length,
    );
  }

  Future<void> delete(int id) =>
      handleApiCall(() => supabase.from('evals').delete().eq('id', id));

  /// DANGEROUS: Clears ALL evaluations from Supabase
  /// Use only when fixing perspective bugs or data corruption
  Future<void> clearAll() async {
    await handleApiCall(() async {
      print('⚠️ CLEARING ALL EVALS FROM SUPABASE...');
      // Delete all records from evals table
      await supabase.from('evals').delete().neq('id', 0);
      print('✅ All evals cleared from Supabase');
    });
  }
}
