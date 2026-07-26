import 'dart:async';
import 'dart:convert';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Durable on-device store for completed whole-game analysis reports.
///
/// Hot path: memory session cache first (controller), then one SQLite read via
/// [AppDatabase] `cache_store`. Keys are `game_report:<sha1(fingerprint)>`.
/// LRU is enforced with `cached_at` timestamps (max [maxEntries] rows).
///
/// Tests inject [GameAnalysisReportStore.memory] so they never open the real DB.
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

  static const String keyPrefix = 'game_report:';

  /// Stable cache key for [fingerprint].
  static String cacheKeyForFingerprint(String fingerprint) {
    final digest = sha1.convert(utf8.encode(fingerprint));
    return '$keyPrefix$digest';
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
    final payload = jsonEncode(gameAnalysisReportToJson(report));
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
      final report = gameAnalysisReportFromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (report == null || report.fingerprint != fingerprint) return null;
      // LRU touch — best effort; never fail a successful read.
      unawaited(save(report).catchError((_) {}));
      return report;
    } catch (e, st) {
      debugPrint('GameAnalysisReportStore.load failed: $e\n$st');
      return null;
    }
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
    final ordered =
        all.entries.toList()
          ..sort((a, b) => a.value.cachedAt.compareTo(b.value.cachedAt));
    final excess = ordered.length - maxEntries;
    for (var i = 0; i < excess; i++) {
      await db.removeCache(key: ordered[i].key);
    }
  }

  /// Test helper: wipe all rows in this store.
  @visibleForTesting
  Future<void> debugClearAll() async {
    final memory = _memory;
    if (memory != null) {
      memory.clear();
      return;
    }
    final db = _database ?? AppDatabase.instance;
    await db.clearCacheByPrefix(keyPrefix);
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
/// v3: a decided game no longer hands out errors (see
/// `reportOutcomeAlreadySettled`) — every stored report still carries the "?"
/// this fixed.
const int gameAnalysisReportSchemaVersion = 3;

Map<String, dynamic> gameAnalysisReportToJson(GameAnalysisReport report) {
  return <String, dynamic>{
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
    final generatedAt =
        generatedAtRaw == null
            ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
            : (DateTime.tryParse(generatedAtRaw) ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    return GameAnalysisReport(
      fingerprint: fingerprint,
      positions: List.unmodifiable(positions),
      moves: List.unmodifiable(moves),
      whiteAccuracy: (json['whiteAccuracy'] as num?)?.toDouble() ?? 0,
      blackAccuracy: (json['blackAccuracy'] as num?)?.toDouble() ?? 0,
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
  return GameReportPosition(fen: fen, lines: List.unmodifiable(lines));
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
