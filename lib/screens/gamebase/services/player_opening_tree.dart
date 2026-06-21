import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:flutter/foundation.dart';

enum PlayerOpeningTreeStatus { idle, building, complete, canceled, error }

@immutable
class PlayerOpeningTreeProgress {
  const PlayerOpeningTreeProgress({
    this.status = PlayerOpeningTreeStatus.idle,
    this.indexedPositions = 0,
    this.error,
  });

  final PlayerOpeningTreeStatus status;
  final int indexedPositions;
  final String? error;

  bool get isRunning => status == PlayerOpeningTreeStatus.building;

  PlayerOpeningTreeProgress copyWith({
    PlayerOpeningTreeStatus? status,
    int? indexedPositions,
    String? error,
  }) {
    return PlayerOpeningTreeProgress(
      status: status ?? this.status,
      indexedPositions: indexedPositions ?? this.indexedPositions,
      error: error,
    );
  }
}

@immutable
class PlayerOpeningTreeState {
  const PlayerOpeningTreeState({
    this.playerId,
    this.treeId,
    this.progress = const PlayerOpeningTreeProgress(),
    this.index = const PlayerOpeningTreeIndex.empty(),
  });

  final String? playerId;
  final String? treeId;
  final PlayerOpeningTreeProgress progress;
  final PlayerOpeningTreeIndex index;

  bool get hasUsableIndex => index.positionCount > 0;
  bool get isReady => progress.status == PlayerOpeningTreeStatus.complete;

  PlayerOpeningTreeState copyWith({
    String? playerId,
    String? treeId,
    PlayerOpeningTreeProgress? progress,
    PlayerOpeningTreeIndex? index,
  }) {
    return PlayerOpeningTreeState(
      playerId: playerId ?? this.playerId,
      treeId: treeId ?? this.treeId,
      progress: progress ?? this.progress,
      index: index ?? this.index,
    );
  }
}

@immutable
class PlayerOpeningTreeIndex {
  const PlayerOpeningTreeIndex({
    required this.treeId,
    required this.playerId,
    required this.maxPly,
    required this.rootNodeId,
    required this.generatedAt,
    required this.nodesById,
    required this.nodesByFenKey,
  });

  const PlayerOpeningTreeIndex.empty()
    : treeId = null,
      playerId = null,
      maxPly = 0,
      rootNodeId = 0,
      generatedAt = null,
      nodesById = const <int, PlayerOpeningTreeNode>{},
      nodesByFenKey = const <String, PlayerOpeningTreeNode>{};

  final String? treeId;
  final String? playerId;
  final int maxPly;
  final int rootNodeId;
  final DateTime? generatedAt;
  final Map<int, PlayerOpeningTreeNode> nodesById;
  final Map<String, PlayerOpeningTreeNode> nodesByFenKey;

  int get positionCount => nodesByFenKey.length;

  factory PlayerOpeningTreeIndex.fromSnapshot(
    PlayerOpeningTreeSnapshot snapshot,
  ) {
    return PlayerOpeningTreeIndex(
      treeId: snapshot.treeId,
      playerId: snapshot.playerId,
      maxPly: snapshot.maxPly,
      rootNodeId: snapshot.rootNodeId,
      generatedAt: snapshot.generatedAt,
      nodesById: Map<int, PlayerOpeningTreeNode>.unmodifiable({
        for (final node in snapshot.nodes) node.id: node,
      }),
      nodesByFenKey: Map<String, PlayerOpeningTreeNode>.unmodifiable({
        for (final node in snapshot.nodes) node.fenKey: node,
      }),
    );
  }

  List<MoveAggregate> movesForFen(
    String fen, {
    PlayerOpeningTreeFilterCriteria filters =
        const PlayerOpeningTreeFilterCriteria(),
  }) {
    final node = nodesByFenKey[_fenKey(fen)];
    if (node == null) return const <MoveAggregate>[];
    final moves = node.moves
      .map((move) => move.toMoveAggregate(filters: filters))
      .where((move) => move.total > 0)
      .toList(growable: false)..sort((a, b) => b.total.compareTo(a.total));
    return List<MoveAggregate>.unmodifiable(moves);
  }
}

@immutable
class PlayerOpeningTreeSnapshot {
  const PlayerOpeningTreeSnapshot({
    required this.treeId,
    required this.playerId,
    required this.maxPly,
    required this.rootNodeId,
    required this.generatedAt,
    required this.fenKeys,
    required this.nodes,
  });

  final String treeId;
  final String playerId;
  final int maxPly;
  final int rootNodeId;
  final DateTime? generatedAt;
  final List<String> fenKeys;
  final List<PlayerOpeningTreeNode> nodes;

  factory PlayerOpeningTreeSnapshot.fromJson(Map<String, dynamic> json) {
    final fenKeys = List<String>.unmodifiable(
      (json['fk'] as List? ?? const []).map((key) => key.toString().trim()),
    );
    return PlayerOpeningTreeSnapshot(
      treeId: (json['tid'] ?? json['treeId'])?.toString() ?? '',
      playerId: (json['pid'] ?? json['playerId'])?.toString() ?? '',
      maxPly: _readInt(json['mp'] ?? json['maxPly']),
      rootNodeId: _readInt(json['r'] ?? json['rootNodeId']),
      generatedAt: DateTime.tryParse(
        (json['g'] ?? json['generatedAt'])?.toString() ?? '',
      ),
      fenKeys: fenKeys,
      nodes: List<PlayerOpeningTreeNode>.unmodifiable(
        ((json['n'] ?? json['nodes']) as List? ?? const [])
            .whereType<Map>()
            .map(
              (node) => PlayerOpeningTreeNode.fromJson(
                Map<String, dynamic>.from(node),
                fenKeys: fenKeys,
              ),
            ),
      ),
    );
  }
}

@immutable
class PlayerOpeningTreeNode {
  const PlayerOpeningTreeNode({
    required this.id,
    required this.fenKey,
    required this.ply,
    required this.moves,
  });

  final int id;
  final String fenKey;
  final int ply;
  final List<PlayerOpeningTreeMove> moves;

  factory PlayerOpeningTreeNode.fromJson(
    Map<String, dynamic> json, {
    List<String> fenKeys = const <String>[],
  }) {
    final fenIndex = _readInt(json['f']);
    final compactFen =
        fenIndex >= 0 && fenIndex < fenKeys.length ? fenKeys[fenIndex] : '';
    return PlayerOpeningTreeNode(
      id: _readInt(json['id']),
      fenKey:
          compactFen.isNotEmpty
              ? compactFen
              : json['fenKey']?.toString().trim() ?? '',
      ply: _readInt(json['p'] ?? json['ply']),
      moves: List<PlayerOpeningTreeMove>.unmodifiable(
        ((json['m'] ?? json['moves']) as List? ?? const [])
            .whereType<Map>()
            .map(
              (move) => PlayerOpeningTreeMove.fromJson(
                Map<String, dynamic>.from(move),
              ),
            ),
      ),
    );
  }
}

@immutable
class PlayerOpeningTreeMove {
  const PlayerOpeningTreeMove({
    required this.uci,
    required this.childNodeId,
    required this.white,
    required this.black,
    required this.draws,
    required this.total,
    this.lastPlayed,
    this.sampleGameId,
    this.filterBuckets = const <PlayerOpeningTreeFilterBucket>[],
  });

  final String uci;
  final int childNodeId;
  final int white;
  final int black;
  final int draws;
  final int total;
  final DateTime? lastPlayed;
  final String? sampleGameId;
  final List<PlayerOpeningTreeFilterBucket> filterBuckets;

  factory PlayerOpeningTreeMove.fromJson(Map<String, dynamic> json) {
    final buckets = <PlayerOpeningTreeFilterBucket>[];
    final rawBuckets = json['filterBuckets'];
    if (rawBuckets is Map) {
      for (final entry in rawBuckets.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        buckets.add(
          PlayerOpeningTreeFilterBucket.fromLegacyJson(
            entry.key.toString(),
            Map<String, dynamic>.from(value),
          ),
        );
      }
    }
    final compactBuckets = json['fb'];
    if (compactBuckets is List) {
      for (final bucket in compactBuckets) {
        if (bucket is! List) continue;
        final parsed = PlayerOpeningTreeFilterBucket.fromCompactTuple(bucket);
        if (parsed != null) buckets.add(parsed);
      }
    }

    return PlayerOpeningTreeMove(
      uci: (json['u'] ?? json['uci'])?.toString().trim().toLowerCase() ?? '',
      childNodeId: _readInt(json['c'] ?? json['childNodeId']),
      white: _readInt(json['w'] ?? json['white']),
      black: _readInt(json['b'] ?? json['black']),
      draws: _readInt(json['d'] ?? json['draws']),
      total: _readInt(json['t'] ?? json['total']),
      lastPlayed: DateTime.tryParse(
        (json['lp'] ?? json['lastPlayed'])?.toString() ?? '',
      ),
      sampleGameId: (json['sg'] ?? json['sampleGameId'])?.toString().trim(),
      filterBuckets: List<PlayerOpeningTreeFilterBucket>.unmodifiable(buckets),
    );
  }

  MoveAggregate toMoveAggregate({
    PlayerOpeningTreeFilterCriteria filters =
        const PlayerOpeningTreeFilterCriteria(),
  }) {
    final stats = filters.hasMoveBucketFilters ? _filteredStats(filters) : null;
    final resolved =
        stats ??
        PlayerOpeningTreeStats(
          white: white,
          black: black,
          draws: draws,
          total: total,
        );
    return MoveAggregate(
      uci: uci,
      white: resolved.white,
      black: resolved.black,
      draws: resolved.draws,
      total: resolved.total,
      gameId: sampleGameId,
      lastPlayed: lastPlayed,
    );
  }

  PlayerOpeningTreeStats _filteredStats(PlayerOpeningTreeFilterCriteria f) {
    var white = 0;
    var black = 0;
    var draws = 0;
    var total = 0;
    for (final bucket in filterBuckets) {
      if (!_bucketMatches(bucket, f)) continue;
      white += bucket.stats.white;
      black += bucket.stats.black;
      draws += bucket.stats.draws;
      total += bucket.stats.total;
    }
    return PlayerOpeningTreeStats(
      white: white,
      black: black,
      draws: draws,
      total: total,
    );
  }
}

@immutable
class PlayerOpeningTreeFilterBucket {
  const PlayerOpeningTreeFilterBucket({
    required this.color,
    required this.timeControl,
    required this.isOnline,
    required this.stats,
  });

  final String? color;
  final String? timeControl;
  final bool? isOnline;
  final PlayerOpeningTreeStats stats;

  factory PlayerOpeningTreeFilterBucket.fromLegacyJson(
    String key,
    Map<String, dynamic> json,
  ) {
    final bucket = _parseBucketKey(key);
    return PlayerOpeningTreeFilterBucket(
      color: _normalizeBucketColor(bucket['color']),
      timeControl: _normalizeBucketTimeControl(bucket['timeControl']),
      isOnline: _parseBucketBool(bucket['isOnline']),
      stats: PlayerOpeningTreeStats.fromJson(json),
    );
  }

  static PlayerOpeningTreeFilterBucket? fromCompactTuple(List<dynamic> tuple) {
    if (tuple.length < 7) return null;
    return PlayerOpeningTreeFilterBucket(
      color: _normalizeBucketColor(tuple[0]),
      timeControl: _normalizeBucketTimeControl(tuple[1]),
      isOnline: _parseBucketBool(tuple[2]),
      stats: PlayerOpeningTreeStats(
        total: _readInt(tuple[3]),
        white: _readInt(tuple[4]),
        black: _readInt(tuple[5]),
        draws: _readInt(tuple[6]),
      ),
    );
  }
}

@immutable
class PlayerOpeningTreeStats {
  const PlayerOpeningTreeStats({
    required this.white,
    required this.black,
    required this.draws,
    required this.total,
  });

  final int white;
  final int black;
  final int draws;
  final int total;

  factory PlayerOpeningTreeStats.fromJson(Map<String, dynamic> json) {
    return PlayerOpeningTreeStats(
      white: _readInt(json['white']),
      black: _readInt(json['black']),
      draws: _readInt(json['draws']),
      total: _readInt(json['total']),
    );
  }
}

@immutable
class PlayerOpeningTreeFilterCriteria {
  const PlayerOpeningTreeFilterCriteria({
    this.playerId,
    this.timeControl,
    this.color,
    this.isOnline,
  });

  final String? playerId;
  final TimeControl? timeControl;
  final String? color;
  final bool? isOnline;

  bool get hasMoveBucketFilters =>
      timeControl != null || color != null || isOnline != null;
}

String _fenKey(String fen) =>
    fen.trim().split(RegExp(r'\s+')).take(4).join(' ');

Map<String, String> _parseBucketKey(String key) {
  final bucket = <String, String>{};
  for (final part in key.split('|')) {
    final index = part.indexOf('=');
    if (index <= 0 || index == part.length - 1) continue;
    bucket[part.substring(0, index)] = part.substring(index + 1);
  }
  return bucket;
}

bool _bucketMatches(
  PlayerOpeningTreeFilterBucket bucket,
  PlayerOpeningTreeFilterCriteria f,
) {
  final color = f.color?.trim().toLowerCase();
  if (color != null && color.isNotEmpty && bucket.color != color) {
    return false;
  }

  final timeControl =
      f.timeControl == null
          ? null
          : _normalizeBucketTimeControl(f.timeControl!.name);
  if (timeControl != null && bucket.timeControl != timeControl) {
    return false;
  }

  if (f.isOnline != null && bucket.isOnline != f.isOnline) {
    return false;
  }

  return true;
}

String? _normalizeBucketColor(Object? value) {
  final raw = value?.toString().trim().toLowerCase();
  return switch (raw) {
    'w' || 'white' => 'white',
    'b' || 'black' => 'black',
    _ => raw == null || raw.isEmpty ? null : raw,
  };
}

String? _normalizeBucketTimeControl(Object? value) {
  final raw = value?.toString().trim().toLowerCase();
  return switch (raw) {
    'c' || 'classical' => 'classical',
    'r' || 'rapid' => 'rapid',
    'b' || 'blitz' => 'blitz',
    _ => raw == null || raw.isEmpty ? null : raw,
  };
}

bool? _parseBucketBool(Object? value) {
  final raw = value?.toString().trim().toLowerCase();
  return switch (raw) {
    '1' || 'true' => true,
    '0' || 'false' => false,
    _ => null,
  };
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
