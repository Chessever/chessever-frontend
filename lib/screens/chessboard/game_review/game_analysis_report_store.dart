import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/services/toby/toby_performance.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Durable on-device store for completed whole-game analysis reports.
///
/// Hot path: memory session cache first (controller), then one SQLite read via
/// [AppDatabase] `cache_store`. Keys are `game_report:<sha1(fingerprint)>`.
/// LRU is enforced with `cached_at` timestamps (max [maxEntries] rows).
///
/// Tests inject [GameAnalysisReportStore.memory] so they never open the real DB.
///
/// Toby's estimate of each side's level ([TobyPerformance]) is kept in the
/// same row, beside the report rather than inside it (`tobyPerformance` and
/// `tobyPerformanceBasis`, additive keys: older rows simply lack them). The
/// estimate usually arrives after the report is saved. It is kept with the
/// [TobyPerformanceRequest.basis] it was computed for and served only to a
/// request with the same basis and the current [kTobyPerformanceModel], so a
/// re-analysed report or edited headers are read again.
class GameAnalysisReportStore {
  /// Production store on the shared app SQLite database ([AppDatabase]).
  GameAnalysisReportStore.sqlite([AppDatabase? database])
    : _database = database ?? AppDatabase.instance,
      _memory = null,
      maxEntries = 48;

  /// In-process map for unit tests (no path_provider / sqflite init).
  GameAnalysisReportStore.memory({this.maxEntries = 48})
    : _database = null,
      _memory = <String, _MemoryEntry>{};

  /// Shared production instance (lazy).
  static GameAnalysisReportStore instance = GameAnalysisReportStore.sqlite();

  @visibleForTesting
  static void debugSetInstance(GameAnalysisReportStore store) {
    instance = store;
  }

  @visibleForTesting
  static void debugResetInstance() {
    instance = GameAnalysisReportStore.sqlite();
  }

  final AppDatabase? _database;
  final Map<String, _MemoryEntry>? _memory;
  final int maxEntries;
  Future<void>? _writeChain;

  /// Toby estimates of this session by report fingerprint, capped at
  /// [maxEntries]. A report saved again keeps its estimate through it. A
  /// fingerprint mapped to null is known to have no stored estimate, so the
  /// next save of its report does not read the row back to find out.
  final LinkedHashMap<String, StoredTobyPerformance?> _hotToby =
      LinkedHashMap<String, StoredTobyPerformance?>();

  static const String keyPrefix = 'game_report:';

  /// Intent that a whole-game report was in flight and should be restarted after
  /// process death (distinct from completed report rows).
  static const String pendingKeyPrefix = 'game_report_pending:';

  /// Stable cache key for [fingerprint].
  static String cacheKeyForFingerprint(String fingerprint) {
    final digest = sha1.convert(utf8.encode(fingerprint));
    return '$keyPrefix$digest';
  }

  /// Stable pending-intent key for [fingerprint].
  static String pendingKeyForFingerprint(String fingerprint) {
    final digest = sha1.convert(utf8.encode(fingerprint));
    return '$pendingKeyPrefix$digest';
  }

  /// Mark that generation for [fingerprint] was started and not finished.
  /// Survives process death so a cold open can restart without a fresh claim.
  Future<void> markPending(String fingerprint) {
    final previous = _writeChain ?? Future<void>.value();
    final done = previous.catchError((_) {}).then((_) async {
      final key = pendingKeyForFingerprint(fingerprint);
      final value = DateTime.now().toUtc().toIso8601String();
      final memory = _memory;
      if (memory != null) {
        memory[key] = _MemoryEntry(
          value: value,
          cachedAt: DateTime.now().millisecondsSinceEpoch,
          fingerprint: fingerprint,
        );
        return;
      }
      final db = _database ?? AppDatabase.instance;
      await db.setCache(key: key, value: value);
    });
    _writeChain = done;
    return done;
  }

  /// Clear interrupted-generation intent for [fingerprint].
  Future<void> clearPending(String fingerprint) {
    final previous = _writeChain ?? Future<void>.value();
    final done = previous.catchError((_) {}).then((_) async {
      final key = pendingKeyForFingerprint(fingerprint);
      final memory = _memory;
      if (memory != null) {
        memory.remove(key);
        return;
      }
      final db = _database ?? AppDatabase.instance;
      await db.removeCache(key: key);
    });
    _writeChain = done;
    return done;
  }

  /// Whether a previous run for [fingerprint] was interrupted before completion.
  Future<bool> isPending(String fingerprint) async {
    try {
      final raw = await _readRaw(pendingKeyForFingerprint(fingerprint));
      return raw != null && raw.isNotEmpty;
    } catch (e, st) {
      debugPrint('GameAnalysisReportStore.isPending failed: $e\n$st');
      return false;
    }
  }

  /// Persist [report] and mark it most-recent (updates `cached_at`).
  Future<void> save(GameAnalysisReport report) {
    final previous = _writeChain ?? Future<void>.value();
    final done = previous.catchError((_) {}).then((_) => _saveUnlocked(report));
    _writeChain = done;
    return done;
  }

  Future<void> _saveUnlocked(GameAnalysisReport report) async {
    final key = cacheKeyForFingerprint(report.fingerprint);
    // The same game keeps its Toby estimate, with the basis it was computed
    // for, when its report is saved again. A re-analysis with other values no
    // longer matches that basis, so the estimate is then read again rather
    // than served.
    StoredTobyPerformance? toby;
    if (_hotToby.containsKey(report.fingerprint)) {
      toby = _hotToby[report.fingerprint];
    } else {
      try {
        final existing = await _readJson(key);
        if (existing != null && existing['fingerprint'] == report.fingerprint) {
          toby = gameReportTobyPerformanceFromJson(existing);
        }
        _rememberToby(report.fingerprint, toby);
      } catch (_) {
        toby = null;
      }
    }
    final payload = jsonEncode(gameAnalysisReportToJson(report, toby: toby));
    final memory = _memory;
    if (memory != null) {
      memory[key] = _MemoryEntry(
        value: payload,
        cachedAt: DateTime.now().millisecondsSinceEpoch,
        fingerprint: report.fingerprint,
      );
      _evictMemoryIfNeeded(memory);
      return;
    }
    final db = _database ?? AppDatabase.instance;
    await db.setCache(key: key, value: payload);
    await _evictSqliteIfNeeded(db);
  }

  /// Await pending writes (tests that dispose fixtures should call this).
  Future<void> flush() async {
    final pending = _writeChain;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
  }

  /// Load a previously saved report for [fingerprint], or null on miss/corrupt.
  Future<GameAnalysisReport?> load(String fingerprint) async {
    try {
      final key = cacheKeyForFingerprint(fingerprint);
      final raw = await _readRaw(key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final json = Map<String, dynamic>.from(decoded);
      final report = gameAnalysisReportFromJson(json);
      if (report == null || report.fingerprint != fingerprint) return null;
      // Remembered even when absent, so the touch below (and later saves)
      // never decode the row again to look for it.
      _rememberToby(fingerprint, gameReportTobyPerformanceFromJson(json));
      // LRU touch — best effort; never fail a successful read.
      unawaited(save(report).catchError((_) {}));
      return report;
    } catch (e, st) {
      debugPrint('GameAnalysisReportStore.load failed: $e\n$st');
      return null;
    }
  }

  /// Toby's estimate saved beside the report for [fingerprint] for a request
  /// with [basis], or null. Never throws.
  Future<TobyPerformance?> loadTobyPerformance(
    String fingerprint, {
    required String basis,
  }) async {
    if (_hotToby.containsKey(fingerprint)) {
      final hot = _hotToby[fingerprint];
      return hot != null && hot.basis == basis ? hot.performance : null;
    }
    try {
      final json = await _readJson(cacheKeyForFingerprint(fingerprint));
      if (json == null || json['fingerprint'] != fingerprint) return null;
      final toby = gameReportTobyPerformanceFromJson(json);
      _rememberToby(fingerprint, toby);
      return toby != null && toby.basis == basis ? toby.performance : null;
    } catch (e) {
      debugPrint('GameAnalysisReportStore.loadTobyPerformance failed: $e');
      return null;
    }
  }

  /// Keeps Toby's estimate beside the report for [fingerprint], computed for
  /// a request with [basis]. When the report is not saved yet, the estimate
  /// joins it when it is saved in this session.
  Future<void> saveTobyPerformance(
    String fingerprint,
    TobyPerformance performance, {
    required String basis,
  }) {
    final previous = _hotToby[fingerprint];
    if (previous != null &&
        previous.basis == basis &&
        previous.performance == performance) {
      return Future<void>.value();
    }
    final stored = (basis: basis, performance: performance);
    _rememberToby(fingerprint, stored);
    final chain = _writeChain ?? Future<void>.value();
    final done = chain.catchError((_) {}).then((_) async {
      final key = cacheKeyForFingerprint(fingerprint);
      final json = await _readJson(key);
      if (json == null || json['fingerprint'] != fingerprint) return;
      _writeTobyJson(json, stored);
      final payload = jsonEncode(json);
      final memory = _memory;
      if (memory != null) {
        memory[key] = _MemoryEntry(
          value: payload,
          cachedAt: DateTime.now().millisecondsSinceEpoch,
          fingerprint: fingerprint,
        );
        return;
      }
      final db = _database ?? AppDatabase.instance;
      await db.setCache(key: key, value: payload);
    });
    _writeChain = done;
    return done;
  }

  void _rememberToby(String fingerprint, StoredTobyPerformance? toby) {
    _hotToby.remove(fingerprint);
    _hotToby[fingerprint] = toby;
    while (_hotToby.length > maxEntries) {
      _hotToby.remove(_hotToby.keys.first);
    }
  }

  /// Simulates a cold start: drops the session tier, keeps durable rows.
  @visibleForTesting
  void clearHotCacheForTest() => _hotToby.clear();

  Future<Map<String, dynamic>?> _readJson(String key) async {
    final raw = await _readRaw(key);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  Future<String?> _readRaw(String key) async {
    final memory = _memory;
    if (memory != null) {
      return memory[key]?.value;
    }
    final db = _database ?? AppDatabase.instance;
    final entry = await db.getCache(key: key);
    return entry?.value;
  }

  void _evictMemoryIfNeeded(Map<String, _MemoryEntry> memory) {
    while (memory.length > maxEntries) {
      MapEntry<String, _MemoryEntry>? oldest;
      for (final e in memory.entries) {
        if (oldest == null || e.value.cachedAt < oldest.value.cachedAt) {
          oldest = e;
        }
      }
      if (oldest == null) break;
      memory.remove(oldest.key);
    }
  }

  Future<void> _evictSqliteIfNeeded(AppDatabase db) async {
    final all = await db.getCacheByPrefixes(prefixes: [keyPrefix]);
    if (all.length <= maxEntries) return;
    final ordered = all.entries.toList()
      ..sort((a, b) => a.value.cachedAt.compareTo(b.value.cachedAt));
    final excess = ordered.length - maxEntries;
    for (var i = 0; i < excess; i++) {
      await db.removeCache(key: ordered[i].key);
    }
  }

  /// Test helper: wipe all rows in this store.
  @visibleForTesting
  Future<void> debugClearAll() async {
    _hotToby.clear();
    final memory = _memory;
    if (memory != null) {
      memory.clear();
      return;
    }
    final db = _database ?? AppDatabase.instance;
    await db.clearCacheByPrefix(keyPrefix);
    await db.clearCacheByPrefix(pendingKeyPrefix);
  }
}

class _MemoryEntry {
  const _MemoryEntry({
    required this.value,
    required this.cachedAt,
    required this.fingerprint,
  });

  final String value;
  final int cachedAt;
  final String fingerprint;
}

// ---------------------------------------------------------------------------
// JSON encode / decode (pure; unit-tested without filesystem)
// ---------------------------------------------------------------------------

/// Payload version. Bump whenever a change alters what a report *says* about
/// the same game, so stored reports from the old rules are dropped instead of
/// being replayed forever. v2: book detection reaches real theory depth.
/// v3: a decided game no longer hands out errors. v4: `?!`, `?` and `??` are
/// lichess's own judgment (`lichess_judgment.dart`) — the blunder threshold, the
/// mate handling and the rule that the engine's own move is never an error all
/// changed, so every stored report still carries the old symbols. v5: Best PV
/// moat and Great only-reliable gap relaxed (★ / ! less conservative); same
/// games can gain positive labels they did not under v4. v6: routine tactical
/// continuation and saturated won-position praise are suppressed. v7: negative
/// symbols are suppressed when the mover retains a decisive (77%+, about +3.3)
/// win. v8: the same amnesty applies when the mover remains decisively lost
/// (23% or lower, about -3.3).
/// v9: native confirmation, same-root evidence and critical punishment.
/// v10: enforce three-position quality at winning boundaries and promotion roots.
const int gameAnalysisReportSchemaVersion = 10;

/// Toby's estimate kept beside a report, with the
/// [TobyPerformanceRequest.basis] of the request it was computed for.
typedef StoredTobyPerformance = ({String basis, TobyPerformance performance});

/// [toby] is written beside the report when known.
Map<String, dynamic> gameAnalysisReportToJson(
  GameAnalysisReport report, {
  StoredTobyPerformance? toby,
}) {
  final json = <String, dynamic>{
    'v': gameAnalysisReportSchemaVersion,
    'fingerprint': report.fingerprint,
    'whiteAccuracy': report.whiteAccuracy,
    'blackAccuracy': report.blackAccuracy,
    'whiteEstimatedRating': report.whiteEstimatedRating,
    'blackEstimatedRating': report.blackEstimatedRating,
    'generatedAt': report.generatedAt.toUtc().toIso8601String(),
    'positions': report.positions.map(_positionToJson).toList(growable: false),
    'moves': report.moves.map(_moveToJson).toList(growable: false),
  };
  if (toby != null) _writeTobyJson(json, toby);
  return json;
}

void _writeTobyJson(Map<String, dynamic> json, StoredTobyPerformance toby) {
  json['tobyPerformance'] = toby.performance.toJson();
  json['tobyPerformanceBasis'] = toby.basis;
}

/// Toby's estimate saved beside a report, or null when there is none (a row
/// from before Toby ratings), it has no basis, or it is from a model other
/// than [kTobyPerformanceModel]. Independent of the report's schema version:
/// the estimate depends on the game, not on how the report classified it.
StoredTobyPerformance? gameReportTobyPerformanceFromJson(
  Map<String, dynamic> json,
) {
  final basis = json['tobyPerformanceBasis'];
  final performance = TobyPerformance.fromJson(json['tobyPerformance']);
  if (basis is! String ||
      basis.isEmpty ||
      performance == null ||
      performance.model != kTobyPerformanceModel) {
    return null;
  }
  return (basis: basis, performance: performance);
}

GameAnalysisReport? gameAnalysisReportFromJson(Map<String, dynamic> json) {
  try {
    // A report written under older classification rules is a miss, not a hit:
    // replaying it would keep showing the labels the new rules just corrected.
    if ((json['v'] as num?)?.toInt() != gameAnalysisReportSchemaVersion) {
      return null;
    }
    final fingerprint = json['fingerprint'] as String?;
    if (fingerprint == null || fingerprint.isEmpty) return null;
    final positionsRaw = json['positions'];
    final movesRaw = json['moves'];
    if (positionsRaw is! List || movesRaw is! List) return null;
    final positions = <GameReportPosition>[];
    for (final item in positionsRaw) {
      if (item is! Map) return null;
      final position = _positionFromJson(Map<String, dynamic>.from(item));
      if (position == null) return null;
      positions.add(position);
    }
    final moves = <GameReportMove>[];
    for (final item in movesRaw) {
      if (item is! Map) return null;
      final move = _moveFromJson(Map<String, dynamic>.from(item));
      if (move == null) return null;
      moves.add(move);
    }
    final generatedAtRaw = json['generatedAt'] as String?;
    final generatedAt = generatedAtRaw == null
        ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
        : (DateTime.tryParse(generatedAtRaw) ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    return GameAnalysisReport(
      fingerprint: fingerprint,
      positions: List.unmodifiable(positions),
      moves: List.unmodifiable(moves),
      whiteAccuracy: (json['whiteAccuracy'] as num?)?.toDouble(),
      blackAccuracy: (json['blackAccuracy'] as num?)?.toDouble(),
      whiteEstimatedRating: (json['whiteEstimatedRating'] as num?)?.toInt(),
      blackEstimatedRating: (json['blackEstimatedRating'] as num?)?.toInt(),
      generatedAt: generatedAt.toUtc(),
    );
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _positionToJson(GameReportPosition position) => {
  'fen': position.fen,
  'lines': position.lines.map(_lineToJson).toList(growable: false),
  if (position.search case final search?)
    'search': {
      'engineId': search.engineId,
      'searchId': search.searchId,
      'complete': search.complete,
    },
  if (position.uncertainty != null) 'uncertainty': position.uncertainty,
};

GameReportPosition? _positionFromJson(Map<String, dynamic> json) {
  final fen = json['fen'] as String?;
  final linesRaw = json['lines'];
  if (fen == null || linesRaw is! List || linesRaw.isEmpty) return null;
  final lines = <GameReportLine>[];
  for (final item in linesRaw) {
    if (item is! Map) return null;
    final line = _lineFromJson(Map<String, dynamic>.from(item));
    if (line == null) return null;
    lines.add(line);
  }
  final rawSearch = json['search'];
  return GameReportPosition(
    fen: fen,
    lines: List.unmodifiable(lines),
    search:
        rawSearch is Map &&
            rawSearch['engineId'] is String &&
            rawSearch['searchId'] is String &&
            rawSearch['complete'] is bool
        ? GameReportSearchEvidence(
            engineId: rawSearch['engineId'] as String,
            searchId: rawSearch['searchId'] as String,
            complete: rawSearch['complete'] as bool,
          )
        : null,
    uncertainty: json['uncertainty'] as String?,
  );
}

Map<String, dynamic> _lineToJson(GameReportLine line) => {
  'moves': line.moves,
  'depth': line.depth,
  if (line.centipawns != null) 'cp': line.centipawns,
  if (line.mate != null) 'mate': line.mate,
};

GameReportLine? _lineFromJson(Map<String, dynamic> json) {
  final movesRaw = json['moves'];
  if (movesRaw is! List) return null;
  final moves = movesRaw.map((e) => e.toString()).toList(growable: false);
  final depth = (json['depth'] as num?)?.toInt() ?? 0;
  return GameReportLine(
    moves: moves,
    depth: depth,
    centipawns: (json['cp'] as num?)?.toInt(),
    mate: (json['mate'] as num?)?.toInt(),
  );
}

Map<String, dynamic> _moveToJson(GameReportMove move) => {
  'ply': move.ply,
  'san': move.san,
  'uci': move.uci,
  'isWhite': move.isWhite,
  if (move.classification != null) 'classification': move.classification!.name,
  'evaluation': _lineToJson(move.evaluation),
  if (move.bestAlternative != null) 'bestAlternative': move.bestAlternative,
};

GameReportMove? _moveFromJson(Map<String, dynamic> json) {
  final ply = (json['ply'] as num?)?.toInt();
  final san = json['san'] as String?;
  final uci = json['uci'] as String?;
  final isWhite = json['isWhite'] as bool?;
  final evaluationRaw = json['evaluation'];
  if (ply == null ||
      san == null ||
      uci == null ||
      isWhite == null ||
      evaluationRaw is! Map) {
    return null;
  }
  final evaluation = _lineFromJson(Map<String, dynamic>.from(evaluationRaw));
  if (evaluation == null) return null;
  GameMoveClassification? classification;
  final className = json['classification'] as String?;
  if (className != null) {
    for (final value in GameMoveClassification.values) {
      if (value.name == className) {
        classification = value;
        break;
      }
    }
  }
  return GameReportMove(
    ply: ply,
    san: san,
    uci: uci,
    isWhite: isWhite,
    classification: classification,
    evaluation: evaluation,
    bestAlternative: json['bestAlternative'] as String?,
  );
}
