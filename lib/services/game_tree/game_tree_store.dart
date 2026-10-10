import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/services/player_opening_tree.dart';
import 'package:chessever2/services/game_tree/game_tree_codec.dart';
import 'package:chessever2/services/game_tree/game_tree_db.dart';
import 'package:dartchess/dartchess.dart' hide File;
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// One indexed game, as the games list and the explorer read it.
@immutable
class GameTreeGame {
  const GameTreeGame({
    required this.id,
    required this.source,
    required this.white,
    required this.black,
    required this.result,
    required this.plies,
    required this.side,
    this.whiteElo,
    this.blackElo,
    this.date,
    this.speed,
    this.timeControl,
    this.eco,
    this.opening,
    this.event,
    this.url,
    this.sourcePath = '',
    this.online = false,
    this.site,
    this.round,
    this.eventName,
    this.eventId,
    this.eventSlug,
    this.eventDate,
  });

  /// Played on a server rather than over the board.
  final bool online;

  /// The PGN file the game is read from.
  final String sourcePath;

  /// The game's row id, stable until the index is rebuilt.
  final int id;

  /// The source file's kind: `lichess`, `chesscom` or `pgn`.
  final String source;
  final String white;
  final String black;

  /// 0 white won, 1 black won, 2 drawn, 3 unknown.
  final int result;
  final int plies;

  /// The prepared player's side: 1 white, 2 black, 0 neither.
  final int side;
  final int? whiteElo;
  final int? blackElo;

  /// yyyymmdd.
  final int? date;

  /// A [TreeSpeed] index.
  final int? speed;
  final String? timeControl;
  final String? eco;
  final String? opening;
  final String? event;
  final String? url;

  /// The `Site` tag as written: a venue, or a server's game link.
  final String? site;
  final String? round;

  /// A ChessEver broadcast's own event name, id (its group, else its tour)
  /// and slug; null for a game that is not from a broadcast.
  final String? eventName;
  final String? eventId;
  final String? eventSlug;

  /// The event's first day, yyyymmdd.
  final int? eventDate;

  static const String _columns =
      'g.id, s.kind, g.white, g.black, g.result, g.plies, g.side, g.welo, '
      'g.belo, g.date, g.speed, g.tc, g.eco, g.opening, g.event, g.url, s.path, '
      'g.online, g.site, g.round, g.ev, g.evid, g.evslug, g.evdate';

  /// How many columns [_columns] selects; a query's own columns follow.
  static const int _width = 24;

  static GameTreeGame _fromRow(List<Object?> r) => GameTreeGame(
    id: r[0] as int,
    source: (r[1] as String?) ?? 'pgn',
    white: (r[2] as String?) ?? 'White',
    black: (r[3] as String?) ?? 'Black',
    result: r[4] as int,
    plies: r[5] as int,
    side: r[6] as int,
    whiteElo: r[7] as int?,
    blackElo: r[8] as int?,
    date: r[9] as int?,
    speed: r[10] as int?,
    timeControl: r[11] as String?,
    eco: r[12] as String?,
    opening: r[13] as String?,
    event: r[14] as String?,
    url: r[15] as String?,
    sourcePath: (r[16] as String?) ?? '',
    online: r[17] == 1,
    site: r[18] as String?,
    round: r[19] as String?,
    eventName: r[20] as String?,
    eventId: r[21] as String?,
    eventSlug: r[22] as String?,
    eventDate: r[23] as int?,
  );
}

/// What the explorer asks of a position's games.
@immutable
class GameTreePositionQuery {
  const GameTreePositionQuery({
    required this.fen,
    this.uci,
    this.side,
    this.clock,
    this.sort = 'date',
    this.descending = true,
    this.page = 0,
    this.pageSize = 20,
  });

  final String fen;
  final String? uci;

  /// 1 the player had White, 2 Black.
  final int? side;

  /// 1 blitz, 2 rapid, 3 classical.
  final int? clock;

  /// `date`, `whiteElo`, `blackElo` or `avgElo`.
  final String sort;
  final bool descending;
  final int page;
  final int pageSize;
}

@immutable
class GameTreePositionPage {
  const GameTreePositionPage({required this.total, required this.games});
  final int total;

  /// Each with the position it ended in and its last move.
  final List<(GameTreeGame, String?, String?)> games;
}

/// A built opening index, read on the UI isolate. Tree steps are single
/// indexed lookups, fast enough to answer synchronously; anything that
/// scans many games runs on a background isolate with its own connection.
class GameTreeStore {
  GameTreeStore._(this.scopeId, this.dbPath, this._db, {required this.playerScope}) {
    _load();
  }

  /// Opens the index at [dbPath], or null when it is missing or unreadable.
  static GameTreeStore? open(
    String scopeId,
    String dbPath, {
    required bool playerScope,
  }) {
    if (!File(dbPath).existsSync()) return null;
    Database? db;
    try {
      db = openGameTreeDatabase(dbPath);
      return GameTreeStore._(scopeId, dbPath, db, playerScope: playerScope);
    } catch (error) {
      // An index from an older layout lacks columns this one reads. Let go
      // of it; the build that follows writes it again from its sources.
      db?.close();
      debugPrint('[GameTree] could not open $dbPath: $error');
      return null;
    }
  }

  final String scopeId;
  final String dbPath;

  /// A player's tree buckets games by the player's side; a collection's
  /// games have no player, so a side filter does not narrow it.
  final bool playerScope;
  final Database _db;
  late PreparedStatement _moves;
  late PreparedStatement _game;
  final Map<int, (String, String)> _sources = {};
  final Map<int, RandomAccessFile> _files = {};
  late SqliteOpeningTreeIndex _tree;
  var _closed = false;
  int _games = 0;
  String? _revision;

  SqliteOpeningTreeIndex get tree => _tree;
  int get gameCount => _games;
  String? get revision => _revision;
  bool get isClosed => _closed;

  /// Older parsers may have indexed truncated PGNs. Rebuild them before
  /// opening, even when their source files and revision are unchanged.
  bool get isCurrentVersion {
    final signature = readGameTreeMeta(_db, 'signature');
    if (signature == null) return false;
    try {
      final decoded = jsonDecode(signature);
      return decoded is Map && decoded['v'] == kGameTreeSchemaVersion;
    } on FormatException {
      return false;
    }
  }

  /// Re-reads what a build changed: counts, sources, the tree's size.
  void refresh() {
    if (_closed) return;
    for (final file in _files.values) {
      try {
        file.closeSync();
      } catch (_) {}
    }
    _files.clear();
    _moves.close();
    _game.close();
    _load();
  }

  void _load() {
    _moves = _db.prepare(
      'SELECT m.mv, m.bucket, m.total, m.w, m.b, m.d, m.last, m.sample '
      'FROM nodes n JOIN moves m ON m.node = n.id WHERE n.hash = ?',
      persistent: true,
    );
    _game = _db.prepare(
      'SELECT ${GameTreeGame._columns}, g.src, g.off, g.len FROM games g '
      'JOIN sources s ON s.id = g.src WHERE g.id = ?',
      persistent: true,
    );
    _sources
      ..clear()
      ..addAll({
        for (final row in _db.select('SELECT id, path, kind FROM sources'))
          row.columnAt(0) as int: (
            row.columnAt(1) as String,
            (row.columnAt(2) as String?) ?? 'pgn',
          ),
      });
    _games = int.tryParse(readGameTreeMeta(_db, 'games') ?? '') ?? 0;
    _revision = readGameTreeMeta(_db, 'revision');
    _tree = SqliteOpeningTreeIndex._(
      this,
      positions: int.tryParse(readGameTreeMeta(_db, 'positions') ?? '') ?? 0,
    );
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final file in _files.values) {
      try {
        file.closeSync();
      } catch (_) {}
    }
    _files.clear();
    _moves.close();
    _game.close();
    _db.close();
  }

  String gameId(int rowId) => 'prep:$scopeId:$rowId';

  /// One game and its PGN, or null when it is not in this index.
  (GameTreeGame, String)? game(int rowId) {
    if (_closed) return null;
    final rows = _game.select([rowId]);
    if (rows.isEmpty) return null;
    final r = rows.rows.first;
    final game = GameTreeGame._fromRow(r);
    const at = GameTreeGame._width;
    final pgn = _read(r[at] as int, r[at + 1] as int, r[at + 2] as int);
    return pgn == null ? null : (game, pgn);
  }

  /// The PGN text of [rowId], read straight from its source file.
  String? pgn(int rowId) => game(rowId)?.$2;

  /// Rows of games read from [sourcePath] whose play time (yyyymmddHHMMSS,
  /// 0 when undated) is after [ts], oldest first.
  List<(int, int)> rowsAfter(String sourcePath, int ts) {
    if (_closed) return const [];
    return [
      for (final r in _db.select(
        'SELECT g.id, COALESCE(g.ts, 0) AS t FROM games g '
        'JOIN sources s ON s.id = g.src WHERE s.path = ? '
        'AND COALESCE(g.ts, 0) > ? ORDER BY t, g.id',
        [sourcePath, ts],
      ).rows)
        (r[0] as int, r[1] as int),
    ];
  }

  String? _read(int src, int offset, int length) {
    final path = _sources[src]?.$1;
    if (path == null) return null;
    try {
      final file = _files[src] ??= File(path).openSync();
      file.setPositionSync(offset);
      return decodePgnBytes(file.readSync(length));
    } catch (error) {
      debugPrint('[GameTree] could not read a game from $path: $error');
      return null;
    }
  }

  /// Every game, newest first. Off the UI isolate: a large account has
  /// tens of thousands.
  Future<List<GameTreeGame>> loadGames() => _loadGamesOnIsolate(dbPath);

  /// The games that reached [query]'s position, one page at a time.
  Future<GameTreePositionPage> positionGames(GameTreePositionQuery query) =>
      _positionGamesOnIsolate(
        dbPath,
        {for (final e in _sources.entries) e.key: e.value.$1},
        query,
        ignoreSide: !playerScope,
      );
}

// Isolate entry points live in top-level functions, so each closure sent
// to an isolate captures only plain data and never this store.
Future<List<GameTreeGame>> _loadGamesOnIsolate(String path) => Isolate.run(
  () => _loadGames(path),
  debugName: 'game-tree-games',
);

Future<GameTreePositionPage> _positionGamesOnIsolate(
  String path,
  Map<int, String> sources,
  GameTreePositionQuery query, {
  required bool ignoreSide,
}) => Isolate.run(
  () => _positionGames(path, sources, query, ignoreSide: ignoreSide),
  debugName: 'game-tree-position',
);

List<GameTreeGame> _loadGames(String path) {
  final db = openGameTreeDatabase(path, readOnly: true);
  try {
    return [
      for (final r in db.select(
        'SELECT ${GameTreeGame._columns} FROM games g '
        'JOIN sources s ON s.id = g.src ORDER BY g.ts DESC, g.id DESC',
      ).rows)
        GameTreeGame._fromRow(r),
    ];
  } finally {
    db.close();
  }
}

GameTreePositionPage _positionGames(
  String path,
  Map<int, String> sources,
  GameTreePositionQuery query, {
  required bool ignoreSide,
}) {
  final db = openGameTreeDatabase(path, readOnly: true);
  final files = <int, RandomAccessFile>{};
  try {
    final where = <String>[];
    final args = <Object?>[gameTreeHashOfFen(query.fen)];
    final uci = query.uci?.trim().toLowerCase();
    final mv = uci == null || uci.isEmpty ? null : encodeTreeMove(uci);
    final side = ignoreSide ? null : query.side;
    if (side != null) where.add('g.side = $side');
    final clock = query.clock;
    if (clock != null) where.add('g.clock = $clock');
    final hits =
        'WITH hits AS (SELECT DISTINCT p.game AS game FROM positions p '
        'WHERE p.node = (SELECT id FROM nodes WHERE hash = ?)'
        '${mv == null ? '' : ' AND p.mv = $mv'}) ';
    final filter = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')} ';
    final total =
        db
                .select(
                  '${hits}SELECT COUNT(*) FROM hits JOIN games g '
                  'ON g.id = hits.game $filter',
                  args,
                )
                .first
                .columnAt(0)
            as int;
    final dir = query.descending ? 'DESC' : 'ASC';
    final order = switch (query.sort) {
      'whiteElo' => 'g.welo',
      'blackElo' => 'g.belo',
      'avgElo' => '(COALESCE(g.welo, 0) + COALESCE(g.belo, 0))',
      _ => 'g.ts',
    };
    final rows = db.select(
      '${hits}SELECT ${GameTreeGame._columns}, g.src, g.off, g.len '
      'FROM hits JOIN games g ON g.id = hits.game '
      'JOIN sources s ON s.id = g.src $filter'
      'ORDER BY $order $dir, g.id $dir LIMIT ? OFFSET ?',
      [...args, query.pageSize, query.page * query.pageSize],
    );
    final games = <(GameTreeGame, String?, String?)>[];
    for (final r in rows.rows) {
      final game = GameTreeGame._fromRow(r);
      String? fen;
      String? last;
      const at = GameTreeGame._width;
      final src = r[at] as int;
      final filePath = sources[src];
      if (filePath != null) {
        try {
          final file = files[src] ??= File(filePath).openSync();
          file.setPositionSync(r[at + 1] as int);
          (fen, last) = gameTreeEnding(
            decodePgnBytes(file.readSync(r[at + 2] as int)),
          );
        } catch (_) {}
      }
      games.add((game, fen, last));
    }
    return GameTreePositionPage(total: total, games: games);
  } finally {
    for (final file in files.values) {
      file.closeSync();
    }
    db.close();
  }
}

/// A game's final position and last move.
(String?, String?) gameTreeEnding(String pgn) {
  final scan = scanPgnGame(pgn, sanLimit: 1 << 20);
  Position position;
  try {
    final fen = scan.tag('FEN');
    position = fen == null ? Chess.initial : Chess.fromSetup(Setup.parseFen(fen));
  } catch (_) {
    return (null, null);
  }
  String? last;
  for (final san in scan.sans) {
    final Move? move;
    try {
      move = position.parseSan(san);
    } catch (_) {
      break;
    }
    if (move == null) break;
    last = move.uci;
    position = position.play(move);
  }
  return (position.fen, last);
}

/// The explorer's view of a [GameTreeStore]: each position's moves are read
/// from SQLite when the board reaches it, so the tree never sits in memory.
// The index is immutable; only the store behind it learns of new builds,
// and a refresh makes a new index.
// ignore: must_be_immutable
class SqliteOpeningTreeIndex extends PlayerOpeningTreeIndex {
  SqliteOpeningTreeIndex._(this._store, {required int positions})
    : _positionCount = positions,
      super(
        treeId: 'prep:${_store.scopeId}',
        playerId: 'prep:${_store.scopeId}',
        maxPly: kGameTreeMaxPly,
        rootNodeId: 0,
        generatedAt: DateTime.now(),
        nodesById: const {},
        nodesByFenKey: const {},
      );

  final GameTreeStore _store;
  final int _positionCount;

  @override
  int get positionCount => _positionCount;

  @override
  List<MoveAggregate> movesForFen(
    String fen, {
    PlayerOpeningTreeFilterCriteria filters =
        const PlayerOpeningTreeFilterCriteria(),
  }) {
    if (_store._closed) return const [];
    final ResultSet rows;
    try {
      rows = _store._moves.select([gameTreeHashOfFen(fen)]);
    } catch (error) {
      debugPrint('[GameTree] move lookup failed: $error');
      return const [];
    }
    if (rows.isEmpty) return const [];
    final color = _store.playerScope ? filters.color?.trim().toLowerCase() : null;
    final clock = filters.timeControl?.name.toLowerCase();
    // A collection's games are not tagged online or over the board.
    final online = _store.playerScope ? filters.isOnline : null;
    final filtered =
        (color != null && color.isNotEmpty) ||
        clock != null ||
        (filters.isOnline != null && _store.playerScope);
    final byMove = <int, _Agg>{};
    for (final r in rows.rows) {
      final mv = r[0] as int;
      final bucket = r[1] as int;
      final agg = byMove[mv] ??= _Agg();
      final total = r[2] as int;
      agg.allTotal += total;
      if (agg.sample == null && r[7] != null) agg.sample = r[7] as int;
      final last = r[6] as int?;
      if (last != null && last > agg.last) agg.last = last;
      if (filtered) {
        if (color != null && color.isNotEmpty && treeBucketColor(bucket) != color) {
          continue;
        }
        if (clock != null && treeBucketClock(bucket) != clock) continue;
        if (online == false) continue; // every Prep game is an online game
      }
      agg.total += total;
      agg.w += r[3] as int;
      agg.b += r[4] as int;
      agg.d += r[5] as int;
    }
    final moves = <MoveAggregate>[
      for (final entry in byMove.entries)
        if (entry.value.total > 0)
          MoveAggregate(
            uci: decodeTreeMove(entry.key),
            white: entry.value.w,
            black: entry.value.b,
            draws: entry.value.d,
            total: entry.value.total,
            gameId: entry.value.allTotal == 1 && entry.value.sample != null
                ? _store.gameId(entry.value.sample!)
                : null,
            lastPlayed: treeDateTime(entry.value.last),
          ),
    ]..sort((a, b) => b.total.compareTo(a.total));
    return List.unmodifiable(moves);
  }
}

class _Agg {
  int total = 0;
  int allTotal = 0;
  int w = 0;
  int b = 0;
  int d = 0;
  int last = 0;
  int? sample;
}
