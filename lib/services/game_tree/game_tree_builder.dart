import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chessever2/services/game_tree/game_tree_codec.dart';
import 'package:chessever2/services/game_tree/game_tree_db.dart';
import 'package:crypto/crypto.dart';
import 'package:dartchess/dartchess.dart' hide File;
import 'package:sqlite3/sqlite3.dart';

/// One PGN file an index reads games from. [kind] is `lichess`, `chesscom`
/// or `pgn`; it names the provider when a game's own headers do not.
class GameTreeSourceFile {
  const GameTreeSourceFile({required this.path, required this.kind});
  final String path;
  final String kind;
}

/// Everything one build needs, all sendable to an isolate.
class GameTreeBuildRequest {
  const GameTreeBuildRequest({
    required this.dbPath,
    required this.sources,
    this.aliases = const [],
    this.fideId,
    this.revision,
    this.cancelPath,
  });

  final String dbPath;
  final List<GameTreeSourceFile> sources;

  /// Lower-case usernames of the prepared player. Empty for a collection,
  /// whose games have no "player" side.
  final List<String> aliases;

  /// The prepared player's FIDE id. A game whose `WhiteFideId` or
  /// `BlackFideId` carries it is theirs whatever the name is spelt like.
  final String? fideId;

  /// The caller's own notion of the source's version (a collection's game
  /// count, say), stored so a later look can tell whether it is current.
  final String? revision;

  /// While a file exists here the build stops at its next commit, keeping
  /// everything indexed so far; the next build resumes from there.
  final String? cancelPath;

  String get signature => jsonEncode({
    'v': kGameTreeSchemaVersion,
    'aliases': [...aliases]..sort(),
    if (fideId != null) 'fide': fideId,
    'sources': [
      for (final s in [...sources]..sort((a, b) => a.path.compareTo(b.path)))
        [s.path, s.kind],
    ],
  });
}

class GameTreeBuildResult {
  const GameTreeBuildResult({
    required this.games,
    required this.positions,
    required this.added,
    required this.rebuilt,
    this.canceled = false,
  });

  final int games;
  final int positions;

  /// Games indexed by this run.
  final int added;
  final bool rebuilt;
  final bool canceled;
}

/// Brings the index at [request.dbPath] up to date with its PGN sources and
/// returns its size. Runs on the calling isolate; [buildGameTreeInBackground]
/// is the UI entry point.
///
/// Sources are append-only: a file that only grew has just its new tail
/// read. Any other change (a file replaced, removed or added, a different
/// player, another schema version) rebuilds from scratch. Work is committed
/// every [_batchGames] games together with how far each file was read, so
/// an interrupted build resumes where it stopped.
GameTreeBuildResult runGameTreeBuild(
  GameTreeBuildRequest request, {
  void Function(double fraction)? onProgress,
}) {
  final db = openGameTreeDatabase(request.dbPath);
  try {
    return _GameTreeBuilder(db, request, onProgress).run();
  } finally {
    db.close();
  }
}

/// [runGameTreeBuild] on a background isolate, with progress on this one.
Future<GameTreeBuildResult> buildGameTreeInBackground(
  GameTreeBuildRequest request, {
  void Function(double fraction)? onProgress,
}) async {
  final progress = ReceivePort();
  final sub = progress.listen((message) {
    if (message is double) onProgress?.call(message);
  });
  try {
    return await _buildOnIsolate(request, progress.sendPort);
  } finally {
    await sub.cancel();
    progress.close();
  }
}

// Its own function so the isolate's closure captures only [request] and
// [port], never the caller's progress callback (which may hold a Ref).
Future<GameTreeBuildResult> _buildOnIsolate(
  GameTreeBuildRequest request,
  SendPort port,
) => Isolate.run(
  () => runGameTreeBuild(request, onProgress: port.send),
  debugName: 'game-tree-build',
);

const int _batchGames = 1500;
const int _chunkBytes = 4 << 20;
const int _hashSpan = 4096;

class _MoveTally {
  _MoveTally(this.child);
  final int child;
  int total = 0;
  int w = 0;
  int b = 0;
  int d = 0;
  int last = 0;
  int sample = 0;
}

class _SourceRow {
  _SourceRow(this.id, this.path, this.kind, this.indexedLen);
  final int id;
  final String path;
  final String kind;
  int indexedLen;
}

class _GameTreeBuilder {
  _GameTreeBuilder(this.db, this.request, this.onProgress)
    : aliases = {
        for (final a in request.aliases)
          if (treePlayerKey(a).isNotEmpty) treePlayerKey(a),
      },
      fideId = _fideKey(request.fideId);

  final Database db;
  final GameTreeBuildRequest request;
  final void Function(double)? onProgress;
  /// The player's names as [treePlayerKey]s.
  final Set<String> aliases;
  final String? fideId;

  static String? _fideKey(String? raw) {
    final clean = raw?.trim().toLowerCase();
    return clean == null || clean.isEmpty ? null : clean;
  }

  /// 1 when the prepared player had White, 2 for Black, 0 when neither tag
  /// is theirs. Their FIDE id decides; a side that carries someone else's
  /// id is not matched by name.
  int _sideOf(PgnScan scan, String white, String black) {
    if (aliases.isEmpty && fideId == null) return 0;
    bool named(String name) => aliases.contains(treePlayerKey(name));
    final id = fideId;
    if (id == null) return named(white) ? 1 : named(black) ? 2 : 0;
    final whiteId = _fideKey(scan.tag('WhiteFideId') ?? scan.tag('WhiteFideID'));
    final blackId = _fideKey(scan.tag('BlackFideId') ?? scan.tag('BlackFideID'));
    if (whiteId == id) return 1;
    if (blackId == id) return 2;
    if (whiteId == null && named(white)) return 1;
    if (blackId == null && named(black)) return 2;
    return 0;
  }

  final Map<int, int> _nodeIds = {};
  final Map<int, _MoveTally> _tallies = {};
  late int _nextNode;
  var _fresh = false;
  var _added = 0;
  var _batch = 0;
  var _bytesDone = 0;
  var _bytesTotal = 1;
  var _lastReported = -1.0;

  late final PreparedStatement _insertGame;
  late final PreparedStatement _insertPosition;
  late final PreparedStatement _insertNode;
  late final PreparedStatement _findNode;
  late final PreparedStatement _upsertMove;
  late final PreparedStatement _markSource;

  GameTreeBuildResult run() {
    createGameTreeSchema(db);
    final signature = request.signature;
    var rebuild = readGameTreeMeta(db, 'signature') != signature;
    final sources = rebuild ? <_SourceRow>[] : _loadSources();
    if (!rebuild) {
      for (final source in sources) {
        if (!_sourceIntact(source)) {
          rebuild = true;
          break;
        }
      }
    }
    final rows = rebuild ? _reset() : sources;
    _fresh = rebuild;

    _bytesTotal = 0;
    for (final row in rows) {
      final file = File(row.path);
      final length = file.existsSync() ? file.lengthSync() : 0;
      _bytesTotal += math.max(0, length - row.indexedLen);
    }
    if (_bytesTotal == 0 && !rebuild) {
      _writeRevision();
      return _result(rebuilt: false);
    }
    _bytesTotal = math.max(1, _bytesTotal);

    _prepare();
    try {
      _nextNode =
          int.tryParse(readGameTreeMeta(db, 'next_node') ?? '') ??
          (db.select('SELECT COALESCE(MAX(id), 0) FROM nodes').first.columnAt(0)
                  as int) +
              1;
      _nodeIds[kGameTreeRootHash] = 0;
      db.execute('BEGIN');
      var canceled = false;
      for (final row in rows) {
        if (!_indexSource(row)) {
          canceled = true;
          break;
        }
      }
      _commit();
      writeGameTreeMeta(db, 'signature', signature);
      _writeRevision();
      db.execute('PRAGMA optimize');
      onProgress?.call(1);
      return _result(rebuilt: rebuild, canceled: canceled);
    } catch (_) {
      if (!db.autocommit) db.execute('ROLLBACK');
      rethrow;
    } finally {
      for (final s in [
        _insertGame,
        _insertPosition,
        _insertNode,
        _findNode,
        _upsertMove,
        _markSource,
      ]) {
        s.close();
      }
    }
  }

  GameTreeBuildResult _result({required bool rebuilt, bool canceled = false}) {
    int count(String table) =>
        db.select('SELECT COUNT(*) FROM $table').first.columnAt(0) as int;
    final games = count('games');
    final positions = count('nodes');
    writeGameTreeMeta(db, 'games', '$games');
    writeGameTreeMeta(db, 'positions', '$positions');
    return GameTreeBuildResult(
      games: games,
      positions: positions,
      added: _added,
      rebuilt: rebuilt,
      canceled: canceled,
    );
  }

  void _writeRevision() {
    final revision = request.revision;
    if (revision != null) writeGameTreeMeta(db, 'revision', revision);
    writeGameTreeMeta(
      db,
      'built_at',
      '${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  List<_SourceRow> _loadSources() {
    final stored = {
      for (final row in db.select(
        'SELECT id, path, kind, indexed_len FROM sources',
      ))
        row.columnAt(1) as String: _SourceRow(
          row.columnAt(0) as int,
          row.columnAt(1) as String,
          (row.columnAt(2) as String?) ?? 'pgn',
          row.columnAt(3) as int,
        ),
    };
    return [
      for (final s in request.sources)
        stored[s.path] ?? _SourceRow(-1, s.path, s.kind, 0),
    ];
  }

  /// Whether the bytes already indexed are still the bytes on disk.
  bool _sourceIntact(_SourceRow source) {
    if (source.id < 0) return false;
    final file = File(source.path);
    if (!file.existsSync()) return source.indexedLen == 0;
    final length = file.lengthSync();
    if (length < source.indexedLen) return false;
    if (source.indexedLen == 0) return true;
    final stored = db.select('SELECT head, tail FROM sources WHERE id = ?', [
      source.id,
    ]).first;
    final (head, tail) = _fingerprint(source.path, source.indexedLen);
    return stored.columnAt(0) == head && stored.columnAt(1) == tail;
  }

  /// Hashes of the first and the last [_hashSpan] bytes before [length].
  (String, String) _fingerprint(String path, int length) {
    final file = File(path).openSync();
    try {
      final headLength = math.min(_hashSpan, length);
      final head = file.readSync(headLength);
      final tailStart = math.max(0, length - _hashSpan);
      file.setPositionSync(tailStart);
      final tail = file.readSync(length - tailStart);
      return ('${sha1.convert(head)}', '${sha1.convert(tail)}');
    } finally {
      file.closeSync();
    }
  }

  List<_SourceRow> _reset() {
    db.execute('BEGIN');
    for (final table in kGameTreeTables) {
      db.execute('DROP TABLE IF EXISTS $table');
    }
    createGameTreeSchema(db);
    final rows = <_SourceRow>[];
    for (final s in request.sources) {
      db.execute('INSERT INTO sources(path, kind) VALUES (?, ?)', [
        s.path,
        s.kind,
      ]);
      rows.add(_SourceRow(db.lastInsertRowId, s.path, s.kind, 0));
    }
    db.execute('COMMIT');
    return rows;
  }

  void _prepare() {
    _insertGame = db.prepare(
      'INSERT OR IGNORE INTO games(src, off, len, gkey, white, black, result, '
      'welo, belo, date, speed, clock, tc, eco, opening, event, url, plies, '
      'side, ts, online, site, round, ev, evid, evslug, evdate) '
      'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      persistent: true,
    );
    _insertPosition = db.prepare(
      'INSERT OR IGNORE INTO positions(node, game, ply, mv) VALUES (?,?,?,?)',
      persistent: true,
    );
    _insertNode = db.prepare(
      'INSERT INTO nodes(hash, id) VALUES (?,?)',
      persistent: true,
    );
    _findNode = db.prepare(
      'SELECT id FROM nodes WHERE hash = ?',
      persistent: true,
    );
    _upsertMove = db.prepare(
      'INSERT INTO moves(node, mv, bucket, child, total, w, b, d, last, sample) '
      'VALUES (?,?,?,?,?,?,?,?,?,?) ON CONFLICT(node, mv, bucket) DO UPDATE SET '
      'total = total + excluded.total, w = w + excluded.w, '
      'b = b + excluded.b, d = d + excluded.d, '
      'last = NULLIF(MAX(COALESCE(last, 0), COALESCE(excluded.last, 0)), 0), '
      'sample = COALESCE(sample, excluded.sample)',
      persistent: true,
    );
    _markSource = db.prepare(
      'UPDATE sources SET indexed_len = ?, head = ?, tail = ? WHERE id = ?',
      persistent: true,
    );
  }

  /// Reads [source] from where the last build stopped. False when canceled.
  bool _indexSource(_SourceRow source) {
    if (source.id < 0) {
      db.execute('INSERT INTO sources(path, kind) VALUES (?, ?)', [
        source.path,
        source.kind,
      ]);
      source = _SourceRow(db.lastInsertRowId, source.path, source.kind, 0);
    }
    final file = File(source.path);
    if (!file.existsSync()) return true;
    final raf = file.openSync();
    try {
      final length = raf.lengthSync();
      var position = source.indexedLen;
      raf.setPositionSync(position);
      var carry = Uint8List(0);
      while (position < length) {
        final chunk = raf.readSync(math.min(_chunkBytes, length - position));
        if (chunk.isEmpty) break;
        final bufferStart = position - carry.length;
        final buffer = carry.isEmpty
            ? chunk
            : (BytesBuilder(copy: false)
                    ..add(carry)
                    ..add(chunk))
                  .takeBytes();
        position += chunk.length;
        final atEnd = position >= length;
        final starts = pgnGameStarts(buffer);
        if (starts.isEmpty) {
          if (atEnd) {
            // No [Event] line at all: one game, or nothing worth reading.
            _game(source, buffer, bufferStart);
            _bytesDone += buffer.length;
          } else {
            carry = buffer;
          }
          continue;
        }
        for (var i = 0; i < starts.length; i++) {
          final last = i == starts.length - 1;
          if (last && !atEnd) break;
          final end = last ? buffer.length : starts[i + 1];
          _game(
            source,
            Uint8List.sublistView(buffer, starts[i], end),
            bufferStart + starts[i],
          );
          _bytesDone += end - starts[i];
          if (_batch >= _batchGames) {
            final read = last ? position : bufferStart + starts[i + 1];
            if (!_checkpoint(source, read)) return false;
          }
        }
        carry = atEnd
            ? Uint8List(0)
            : Uint8List.fromList(Uint8List.sublistView(buffer, starts.last));
        _report();
      }
      _mark(source, length);
      return true;
    } finally {
      raf.closeSync();
    }
  }

  /// Commits a batch with how far [source] has been read; false to stop.
  bool _checkpoint(_SourceRow source, int read) {
    _mark(source, read);
    _commit();
    db.execute('BEGIN');
    final cancel = request.cancelPath;
    return cancel == null || !File(cancel).existsSync();
  }

  void _mark(_SourceRow source, int read) {
    final (head, tail) = read == 0 ? ('', '') : _fingerprint(source.path, read);
    _markSource.execute([read, head, tail, source.id]);
    source.indexedLen = read;
  }

  void _commit() {
    _flushTallies();
    writeGameTreeMeta(db, 'next_node', '$_nextNode');
    if (!db.autocommit) db.execute('COMMIT');
    _batch = 0;
  }

  void _report() {
    final fraction = (_bytesDone / _bytesTotal).clamp(0.0, 0.99);
    if (fraction - _lastReported >= 0.01) {
      _lastReported = fraction;
      onProgress?.call(fraction);
    }
  }

  void _game(_SourceRow source, Uint8List bytes, int offset) {
    final text = decodePgnBytes(bytes);
    if (text.isEmpty) return;
    final scan = scanPgnGame(text);
    if (scan.sans.isEmpty) return;
    final variant = scan.tag('Variant')?.toLowerCase();
    if (variant != null && variant != 'standard' && variant != 'chess') return;

    final white = scan.tag('White') ?? 'White';
    final black = scan.tag('Black') ?? 'Black';
    final side = _sideOf(scan, white, black);
    final site = scan.tag('Site');
    final lichess =
        source.kind == 'lichess' || (site?.contains('lichess.org') ?? false);
    final speed =
        classifyTreeSpeed(
          lichess: lichess,
          timeControl: scan.tag('TimeControl'),
          timeClass: scan.tag('TimeClass'),
          event: scan.tag('Event'),
          site: site,
          source: source.kind,
        ) ??
        (source.kind == 'chessever' && !lichess ? TreeSpeed.classical : null);
    final clock = TreeSpeed.explorerClock(speed);
    final date = treeDateOf(
      scan.tag('UTCDate') ?? scan.tag('Date') ?? scan.tag('EndDate'),
    );
    final result = treeResultCode(scan.tag('Result'));
    final link = scan.tag('Link');

    _insertGame.execute([
      source.id,
      offset,
      bytes.length,
      treeGameKey(scan.headers),
      white,
      black,
      result,
      int.tryParse(scan.tag('WhiteElo') ?? ''),
      int.tryParse(scan.tag('BlackElo') ?? ''),
      date,
      speed,
      clock,
      scan.tag('TimeControl'),
      scan.tag('ECO'),
      scan.tag('Opening') ?? _ecoUrlName(scan.tag('ECOUrl')),
      scan.tag('Event'),
      link ?? (site?.startsWith('http') == true ? site : null),
      scan.plies,
      side,
      date == null
          ? null
          : date * 1000000 +
                treeTimeOf(
                  scan.tag('UTCTime') ??
                      scan.tag('EndTime') ??
                      scan.tag('StartTime'),
                ),
      treeGameIsOnline(sourceKind: source.kind, site: site, link: link) ? 1 : 0,
      site,
      _roundOf(scan.tag('Round')),
      // A broadcast game names its event apart from the round's own Event.
      scan.tag('ChessEverGroupBroadcastName') ?? scan.tag('BroadcastName'),
      scan.tag('ChessEverGroupBroadcastId') ?? scan.tag('ChessEverTourId'),
      scan.tag('ChessEverBroadcastSlug') ?? scan.tag('ChessEverTourSlug'),
      treeDateOf(scan.tag('EventDate')),
    ]);
    if (db.updatedRows == 0) return; // already indexed (same provider URL)
    final gameId = db.lastInsertRowId;
    _added++;
    _batch++;

    final fen = scan.tag('FEN');
    if (fen != null && gameTreeFenKey(fen) != gameTreeFenKey(kInitialFEN)) {
      return; // the tree starts from the initial position only
    }
    final bucket = treeBucket(side: side, clock: clock);
    Position position = Chess.initial;
    var node = 0;
    final limit = math.min(scan.sans.length, kGameTreeMaxPly);
    var complete = true;
    for (var ply = 0; ply < limit; ply++) {
      final Move? move;
      try {
        move = position.parseSan(scan.sans[ply]);
      } catch (_) {
        complete = false;
        break;
      }
      if (move == null) {
        complete = false;
        break;
      }
      final mv = encodeTreeMove(standardTreeUci(position, move));
      final next = position.play(move);
      final child = _node(gameTreeHashOfFen(next.fen));
      _insertPosition.execute([node, gameId, ply, mv]);
      final key = node << 19 | mv << 4 | bucket;
      final tally = _tallies[key] ??= _MoveTally(child);
      tally.total++;
      switch (result) {
        case 0:
          tally.w++;
        case 1:
          tally.b++;
        case 2:
          tally.d++;
      }
      if (date != null && date > tally.last) tally.last = date;
      if (tally.sample == 0) tally.sample = gameId;
      node = child;
      position = next;
    }
    if (complete) _insertPosition.execute([node, gameId, limit, 0]);
  }

  int _node(int hash) {
    final known = _nodeIds[hash];
    if (known != null) return known;
    if (!_fresh) {
      final rows = _findNode.select([hash]);
      if (rows.isNotEmpty) {
        return _nodeIds[hash] = rows.first.columnAt(0) as int;
      }
    }
    final id = _nextNode++;
    _insertNode.execute([hash, id]);
    return _nodeIds[hash] = id;
  }

  void _flushTallies() {
    for (final entry in _tallies.entries) {
      final key = entry.key;
      final t = entry.value;
      _upsertMove.execute([
        key >> 19,
        (key >> 4) & 0x7FFF,
        key & 15,
        t.child,
        t.total,
        t.w,
        t.b,
        t.d,
        t.last == 0 ? null : t.last,
        t.sample == 0 ? null : t.sample,
      ]);
    }
    _tallies.clear();
  }
}

/// Servers write a game outside any round as a dash.
String? _roundOf(String? round) => round == '-' ? null : round;

/// Chess.com names the opening only in its ECOUrl slug.
String? _ecoUrlName(String? url) {
  final slug = url?.split('/').lastOrNull;
  if (slug == null || slug.isEmpty) return null;
  final words = slug.split('-');
  final cut = words.indexWhere((w) => RegExp(r'^\d').hasMatch(w));
  final name = (cut <= 0 ? words : words.sublist(0, cut)).join(' ');
  return name.isEmpty ? null : name;
}
