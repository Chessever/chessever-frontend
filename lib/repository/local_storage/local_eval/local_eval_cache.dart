import 'dart:async';
import 'dart:convert';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final localEvalCacheProvider = AutoDisposeProvider<LocalEvalCache>(
  (ref) => LocalEvalCache(ref),
);

class LocalEvalCache {
  LocalEvalCache(this.ref);

  final Ref ref;

  static const _cacheKeyPrefix = 'cloud_eval_';
  static const _versionKey = 'cloud_eval_version';
  static const _currentVersion = 13; // v13: Depth-aware cache keys
  /// Prevents concurrent version check/clear operations
  static Completer<void>? _versionCheckCompleter;
  static bool _versionVerified = false;

  /// Ensures version is checked and cache cleared if needed (only once per session)
  Future<void> _ensureVersionChecked() async {
    // Fast path: already verified this session
    if (_versionVerified) return;

    // If another operation is already checking version, wait for it
    if (_versionCheckCompleter != null) {
      await _versionCheckCompleter!.future;
      return;
    }

    // We're the first - create completer and do the check
    _versionCheckCompleter = Completer<void>();
    try {
      final db = ref.read(appDatabaseProvider);
      final storedVersion = await db.getInt(_versionKey) ?? 1;
      if (storedVersion < _currentVersion) {
        // Clear old cache and set new version in a single transaction
        await db.clearCacheByPrefix(_cacheKeyPrefix);
        await db.setInt(_versionKey, _currentVersion);
      }
      _versionVerified = true;
      _versionCheckCompleter!.complete();
    } catch (e) {
      _versionCheckCompleter!.completeError(e);
      rethrow;
    } finally {
      _versionCheckCompleter = null;
    }
  }

  Future<void> save(String fen, CloudEval eval, {int? multiPV}) async {
    try {
      if (fen.isEmpty || eval.depth <= 0 || eval.pvs.isEmpty) return;

      // Single synchronized version check
      await _ensureVersionChecked();

      final db = ref.read(appDatabaseProvider);

      final effectiveMultiPv =
          (multiPV ?? eval.requestedMultiPv ?? eval.pvs.length).clamp(0, 5);
      final cacheKey = _buildKey(fen, effectiveMultiPv, eval.depth);
      await db.setCacheBatch({cacheKey: jsonEncode(eval.toJson())});
    } catch (e) {
      // Cache failure is not critical
    }
  }

  Future<CloudEval?> fetch(String fen, {int? multiPV, int minDepth = 0}) async {
    try {
      // Single synchronized version check
      await _ensureVersionChecked();

      final db = ref.read(appDatabaseProvider);

      final desired = multiPV ?? 0;
      final entries = await db.getCacheByPrefixes(
        prefixes: [_buildPrefix(fen)],
      );

      CloudEval? bestEval;
      for (final entry in entries.values) {
        try {
          final eval = CloudEval.fromJson(jsonDecode(entry.value));
          if (eval.pvs.isEmpty) continue;
          if (eval.depth < minDepth) continue;

          final effectiveMultiPv = _effectiveMultiPv(eval);
          if (desired > 0 && effectiveMultiPv < desired) {
            continue;
          }

          if (bestEval == null || _isCandidateBetter(eval, bestEval)) {
            bestEval = eval;
          }
        } catch (_) {
          // corrupted entry - skip it
        }
      }

      if (bestEval == null) return null;

      if (desired > 0) {
        if (bestEval.pvs.length > desired) {
          return CloudEval(
            fen: bestEval.fen,
            knodes: bestEval.knodes,
            depth: bestEval.depth,
            pvs: bestEval.pvs.take(desired).toList(growable: false),
            requestedMultiPv: desired,
          );
        }
        if (bestEval.requestedMultiPv != desired) {
          return CloudEval(
            fen: bestEval.fen,
            knodes: bestEval.knodes,
            depth: bestEval.depth,
            pvs: bestEval.pvs,
            requestedMultiPv: desired,
          );
        }
      }

      return bestEval.requestedMultiPv == null
          ? CloudEval(
            fen: bestEval.fen,
            knodes: bestEval.knodes,
            depth: bestEval.depth,
            pvs: bestEval.pvs,
            requestedMultiPv: bestEval.pvs.length,
          )
          : bestEval;
    } catch (e) {
      return null;
    }
  }

  /// Batch fetch multiple evals at once — single SQL query instead of N reads
  Future<Map<String, CloudEval>> batchFetch(List<String> fens) async {
    final result = <String, CloudEval>{};
    if (fens.isEmpty) return result;

    try {
      // Single synchronized version check
      await _ensureVersionChecked();

      final db = ref.read(appDatabaseProvider);
      final requested = fens.toSet();
      final entries = await db.getCacheByPrefixes(
        prefixes: fens.map(_buildPrefix).toList(),
      );

      for (final entry in entries.values) {
        try {
          final eval = CloudEval.fromJson(jsonDecode(entry.value));
          if (!requested.contains(eval.fen) || eval.pvs.isEmpty) {
            continue;
          }

          final existing = result[eval.fen];
          if (existing == null || _isCandidateBetter(eval, existing)) {
            result[eval.fen] = eval;
          }
        } catch (_) {
          // corrupted entry - skip it
        }
      }
    } catch (e) {
      // Cache failure is not critical
    }

    return result;
  }

  Future<void> clear() async {
    await _clearAll();
    _versionVerified = false; // Reset so next access re-checks version
    try {
      final db = ref.read(appDatabaseProvider);
      await db.setInt(_versionKey, _currentVersion);
    } catch (e) {
      // Cache failure is not critical
    }
  }

  Future<void> _clearAll() async {
    try {
      final db = ref.read(appDatabaseProvider);
      await db.clearCacheByPrefix(_cacheKeyPrefix);
    } catch (e) {
      // Cache failure is not critical
    }
  }

  String _buildKey(String fen, int multiPV, int depth) {
    return '$_cacheKeyPrefix${fen}_pv${multiPV}_d$depth';
  }

  String _buildPrefix(String fen) {
    return '$_cacheKeyPrefix${fen}_pv';
  }

  int _effectiveMultiPv(CloudEval eval) {
    return eval.requestedMultiPv ?? eval.pvs.length;
  }

  bool _isCandidateBetter(CloudEval candidate, CloudEval existing) {
    if (candidate.depth != existing.depth) {
      return candidate.depth > existing.depth;
    }
    return _effectiveMultiPv(candidate) >= _effectiveMultiPv(existing);
  }
}
