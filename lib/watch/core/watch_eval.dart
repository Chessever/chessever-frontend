import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

/// An engine's view of a position, from White's side: centipawns, or a
/// mate in [mate] moves (negative: for Black).
class WatchEval {
  const WatchEval({this.cp, this.mate, this.depth = 0});
  final int? cp;
  final int? mate;
  final int depth;

  /// White's share of the bar, 0 to 1, on Lichess's curve: +1 pawn reads
  /// about 0.6, +4 about 0.9, a mate all the way.
  double get whiteShare {
    final m = mate;
    if (m != null) return m > 0 ? 1 : 0;
    final c = (cp ?? 0).clamp(-10000, 10000);
    return 0.5 + 0.5 * (2 / (1 + math.exp(-0.00368208 * c)) - 1);
  }

  /// "+1.3", "−0.4", "#3", "#−2".
  String get label {
    final m = mate;
    if (m != null) return m > 0 ? '#$m' : '#−${-m}';
    final pawns = (cp ?? 0) / 100;
    final text = pawns.abs().toStringAsFixed(1);
    return pawns < 0 ? '−$text' : '+$text';
  }
}

/// Evaluations for the positions on the wrist, from Lichess's cloud of
/// engine lines: no engine runs on the watch. Relay positions are nearly
/// always there; one that is not stays unknown, and the bar says so.
///
/// Every position is asked for once and remembered; a request in flight is
/// shared. A rate limit (429) pauses requests for a minute.
class WatchEvalSource {
  WatchEvalSource({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? DateTime.now;

  /// The app's one source; tests replace it.
  static WatchEvalSource shared = WatchEvalSource();

  static const endpoint = 'https://lichess.org/api/cloud-eval';
  final http.Client _client;
  final DateTime Function() _now;
  final _known = <String, WatchEval?>{};
  final _pending = <String, Future<WatchEval?>>{};
  DateTime? _pausedUntil;

  /// Only the position matters to the engine, not the clocks or counters.
  static String key(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    return parts.take(4).join(' ');
  }

  /// What is already known for [fen], without asking.
  WatchEval? cached(String fen) => _known[key(fen)];

  Future<WatchEval?> eval(String fen) {
    final k = key(fen);
    if (_known.containsKey(k)) return Future.value(_known[k]);
    final paused = _pausedUntil;
    if (paused != null && _now().isBefore(paused)) return Future.value(null);
    return _pending[k] ??= _fetch(k).whenComplete(() {
      // Returning remove's value would return this very future from its own
      // completion callback, leaving every awaiting board stuck indefinitely.
      _pending.remove(k);
    });
  }

  Future<WatchEval?> _fetch(String k) async {
    try {
      final response = await _client
          .get(
            Uri.parse(
              endpoint,
            ).replace(queryParameters: {'fen': k, 'multiPv': '1'}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 429) {
        _pausedUntil = _now().add(const Duration(minutes: 1));
        return null;
      }
      if (response.statusCode == 404) return _known[k] = null;
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map) return null;
      final pvs = body['pvs'];
      final best = pvs is List && pvs.isNotEmpty ? pvs.first : null;
      if (best is! Map) return _known[k] = null;
      final cp = best['cp'];
      final mate = best['mate'];
      final depth = body['depth'];
      return _known[k] = WatchEval(
        cp: cp is num ? cp.toInt() : null,
        mate: mate is num ? mate.toInt() : null,
        depth: depth is num ? depth.toInt() : 0,
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}
