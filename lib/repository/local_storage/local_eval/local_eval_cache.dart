import 'dart:convert';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final localEvalCacheProvider = AutoDisposeProvider<LocalEvalCache>(
  (_) => LocalEvalCache(),
);

class LocalEvalCache {
  static const _prefix = 'cloud_eval_';
  static const _versionKey = 'cloud_eval_version';
  static const _currentVersion =
      8; // v8: Force clear for eval bar perspective fix

  Future<void> save(String fen, CloudEval eval, {int? multiPV}) async {
    final prefs = await SharedPreferences.getInstance();
    final storedVersion = prefs.getInt(_versionKey) ?? 1;
    if (storedVersion < _currentVersion) {
      await _clearWithPrefs(prefs);
    }
    await prefs.setInt(_versionKey, _currentVersion);

    final effectiveMultiPv = (multiPV ?? eval.pvs.length).clamp(0, 5);
    final key = _buildKey(fen, effectiveMultiPv);
    await prefs.setString(key, jsonEncode(eval.toJson()));

    // Also store legacy key so older readers (or callers without multiPV) still benefit
    if (effectiveMultiPv > 0) {
      await prefs.setString('$_prefix$fen', jsonEncode(eval.toJson()));
    }
  }

  Future<CloudEval?> fetch(String fen, {int? multiPV}) async {
    final prefs = await SharedPreferences.getInstance();
    final storedVersion = prefs.getInt(_versionKey) ?? 1;
    if (storedVersion < _currentVersion) {
      await _clearWithPrefs(prefs);
      await prefs.setInt(_versionKey, _currentVersion);
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
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        final eval = CloudEval.fromJson(jsonDecode(raw));
        if (eval.pvs.isEmpty) continue;
        // Ensure we only accept entries that don't exceed requested PV count
        if (desired > 0 && eval.pvs.length > desired) {
          // Truncate in-memory copy so callers never see more lines than requested
          final trimmed = CloudEval(
            fen: eval.fen,
            knodes: eval.knodes,
            depth: eval.depth,
            pvs: eval.pvs.take(desired).toList(growable: false),
          );
          return trimmed;
        }
        return eval;
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

    final prefs = await SharedPreferences.getInstance();
    final storedVersion = prefs.getInt(_versionKey) ?? 1;
    if (storedVersion < _currentVersion) {
      await _clearWithPrefs(prefs);
      await prefs.setInt(_versionKey, _currentVersion);
      return result;
    }

    for (final fen in fens) {
      final raw = prefs.getString(_buildKey(fen, 0));
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
    final prefs = await SharedPreferences.getInstance();
    await _clearWithPrefs(prefs);
    await prefs.setInt(_versionKey, _currentVersion);
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
