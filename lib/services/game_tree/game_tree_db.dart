import 'dart:io';

import 'package:chessever2/services/game_tree/game_tree_codec.dart';
import 'package:sqlite3/sqlite3.dart';

/// The on-disk layout of one opening index.
///
/// Games are not copied in: each row points at its bytes in a PGN source
/// file (`src`, `off`, `len`), so the index holds only what the tree and
/// the games list read. The tree is numbered nodes (one per position,
/// found by a 64-bit position hash) and moves out of them, counted per
/// (side, clock) bucket. `positions` lists, for every node, the games that
/// passed through it, the ply, and the move they played there.
const List<String> kGameTreeSchema = [
  'CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT) WITHOUT ROWID',
  'CREATE TABLE IF NOT EXISTS sources('
      'id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE, kind TEXT, '
      'indexed_len INTEGER NOT NULL DEFAULT 0, head TEXT, tail TEXT)',
  'CREATE TABLE IF NOT EXISTS games('
      'id INTEGER PRIMARY KEY, src INTEGER NOT NULL, off INTEGER NOT NULL, '
      'len INTEGER NOT NULL, gkey TEXT, white TEXT, black TEXT, '
      'result INTEGER NOT NULL, welo INTEGER, belo INTEGER, date INTEGER, '
      'speed INTEGER, clock INTEGER NOT NULL DEFAULT 0, tc TEXT, eco TEXT, '
      'opening TEXT, event TEXT, url TEXT, plies INTEGER NOT NULL, '
      'side INTEGER NOT NULL DEFAULT 0, ts INTEGER)',
  'CREATE UNIQUE INDEX IF NOT EXISTS games_gkey ON games(gkey)',
  // Newest first: ts is yyyymmddHHMMSS, so games of one day keep their order.
  'CREATE INDEX IF NOT EXISTS games_ts ON games(ts DESC, id DESC)',
  // Positions are only ever found by hash, so the hash is the key and the
  // small sequential id (what moves and positions store) a plain column.
  'CREATE TABLE IF NOT EXISTS nodes('
      'hash INTEGER PRIMARY KEY, id INTEGER NOT NULL) WITHOUT ROWID',
  'CREATE TABLE IF NOT EXISTS moves('
      'node INTEGER NOT NULL, mv INTEGER NOT NULL, bucket INTEGER NOT NULL, '
      'child INTEGER NOT NULL, total INTEGER NOT NULL, w INTEGER NOT NULL, '
      'b INTEGER NOT NULL, d INTEGER NOT NULL, last INTEGER, sample INTEGER, '
      'PRIMARY KEY(node, mv, bucket)) WITHOUT ROWID',
  'CREATE TABLE IF NOT EXISTS positions('
      'node INTEGER NOT NULL, game INTEGER NOT NULL, ply INTEGER NOT NULL, '
      'mv INTEGER NOT NULL, PRIMARY KEY(node, game, ply)) WITHOUT ROWID',
];

const List<String> kGameTreeTables = [
  'positions',
  'moves',
  'nodes',
  'games',
  'sources',
  'meta',
];

/// Opens (creating when absent) the index at [path] with the settings both
/// the builder and readers rely on: WAL, so the UI reads while a build
/// writes; NORMAL sync, which WAL keeps crash-safe.
Database openGameTreeDatabase(String path, {bool readOnly = false}) {
  if (!readOnly) Directory(File(path).parent.path).createSync(recursive: true);
  final db = sqlite3.open(
    path,
    mode: readOnly ? OpenMode.readOnly : OpenMode.readWriteCreate,
  );
  db.execute('PRAGMA busy_timeout = 15000');
  if (!readOnly) {
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA synchronous = NORMAL');
  }
  db.execute('PRAGMA temp_store = MEMORY');
  return db;
}

void createGameTreeSchema(Database db) {
  for (final statement in kGameTreeSchema) {
    db.execute(statement);
  }
  db.execute(
    'INSERT OR IGNORE INTO nodes(hash, id) VALUES (?, 0)',
    [kGameTreeRootHash],
  );
}

String? readGameTreeMeta(Database db, String key) {
  try {
    final rows = db.select('SELECT v FROM meta WHERE k = ?', [key]);
    return rows.isEmpty ? null : rows.first.columnAt(0) as String?;
  } on SqliteException {
    return null; // not created yet
  }
}

void writeGameTreeMeta(Database db, String key, String value) {
  db.execute(
    'INSERT INTO meta(k, v) VALUES (?, ?) '
    'ON CONFLICT(k) DO UPDATE SET v = excluded.v',
    [key, value],
  );
}

/// Every file an index at [path] owns.
List<File> gameTreeDatabaseFiles(String path) => [
  File(path),
  File('$path-wal'),
  File('$path-shm'),
];
