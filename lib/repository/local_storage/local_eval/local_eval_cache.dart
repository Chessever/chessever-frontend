import 'dart:convert';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final localEvalCacheProvider = AutoDisposeProvider<LocalEvalCache>(
  (_) => LocalEvalCache(),
);

class LocalEvalCache {
  static const _prefix = 'cloud_eval_';
  static const _versionKey = 'cloud_eval_version';
  static const _currentVersion =
      10; // v10: Enforce persistence thresholds + multiPV tagging

  SharedPreferences get _prefs => SharedPreferencesService.instance.prefs;

  Future<void> save(String fen, CloudEval eval, {int? multiPV}) async {
    final storedVersion = _prefs.getInt(_versionKey) ?? 1;
    if (storedVersion < _currentVersion) {
      await _clearWithPrefs(_prefs);
    }
    await _prefs.setInt(_versionKey, _currentVersion);

    final effectiveMultiPv =
        (multiPV ?? eval.requestedMultiPv ?? eval.pvs.length).clamp(0, 5);
    final key = _buildKey(fen, effectiveMultiPv);
    await _prefs.setString(key, jsonEncode(eval.toJson()));

    // Also store legacy key so older readers (or callers without multiPV) still benefit
    if (effectiveMultiPv > 0) {
      await _prefs.setString('$_prefix$fen', jsonEncode(eval.toJson()));
    }
  }

  Future<CloudEval?> fetch(String fen, {int? multiPV}) async {
    final storedVersion = _prefs.getInt(_versionKey) ?? 1;
    if (storedVersion < _currentVersion) {
      await _clearWithPrefs(_prefs);
      await _prefs.setInt(_versionKey, _currentVersion);
      return null;
    }

    final desired = (multiPV ?? 0);
    final keysToTry = <String>[];

    if (desired > 0) {
      for (int pv = desired; pv >= 1; pv--) {
        keysToTry.add(_buildKey(fen, pv));
      }
    }

    // Legacy fallbacks (no PV suffix)
    keysToTry.add('$_prefix$fen');

    for (final key in keysToTry) {
      final raw = _prefs.getString(key);
      if (raw == null) continue;
      try {
        final eval = CloudEval.fromJson(jsonDecode(raw));
        if (eval.pvs.isEmpty) continue;
        if (desired > 0) {
          // Skip entries that don't satisfy the requested PV count
          if (eval.pvs.length < desired) {
            continue;
          }
          if (eval.pvs.length > desired) {
            final trimmed = CloudEval(
              fen: eval.fen,
              knodes: eval.knodes,
              depth: eval.depth,
              pvs: eval.pvs.take(desired).toList(growable: false),
              requestedMultiPv: desired,
            );
            return trimmed;
          }
          if (eval.requestedMultiPv != desired) {
            return CloudEval(
              fen: eval.fen,
              knodes: eval.knodes,
              depth: eval.depth,
              pvs: eval.pvs,
              requestedMultiPv: desired,
            );
          }
        }
        return eval.requestedMultiPv == null
            ? CloudEval(
                fen: eval.fen,
                knodes: eval.knodes,
                depth: eval.depth,
                pvs: eval.pvs,
                requestedMultiPv: eval.pvs.length,
              )
            : eval;
      } catch (_) {
        // corrupted entry → skip it
      }
    }

    return null;
  }

  /// Batch fetch multiple evals at once - much faster than individual fetches
  Future<Map<String, CloudEval>> batchFetch(List<String> fens) async {
    final result = <String, CloudEval>{};
    if (fens.isEmpty) return result;

    final storedVersion = _prefs.getInt(_versionKey) ?? 1;
    if (storedVersion < _currentVersion) {
      await _clearWithPrefs(_prefs);
      await _prefs.setInt(_versionKey, _currentVersion);
      return result;
    }

    for (final fen in fens) {
      final raw = _prefs.getString(_buildKey(fen, 0));
      if (raw != null) {
        try {
          result[fen] = CloudEval.fromJson(jsonDecode(raw));
        } catch (_) {
          // corrupted entry → skip it
        }
      }
    }

    return result;
  }

  Future<void> clear() async {
    await _clearWithPrefs(_prefs);
    await _prefs.setInt(_versionKey, _currentVersion);
  }

  Future<void> _clearWithPrefs(SharedPreferences prefs) async {
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  String _buildKey(String fen, int multiPV) {
    if (multiPV <= 0) return '$_prefix$fen';
    return '$_prefix${fen}_pv$multiPV';
  }
}
