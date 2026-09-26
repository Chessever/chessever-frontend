import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'gamebase_providers.dart';

/// A page fetched from the server this long ago is current: it is shown as the
/// answer with no second request. Anything older (and anything read back from
/// disk) is shown at once and checked against the server behind it.
///
/// Two minutes is the window the explorer has always served a page from
/// memory without asking again.
const Duration kExplorerGamesFreshFor = Duration(minutes: 2);

/// A settled `positionGamesProvider` page stays alive this long after it
/// arrives, even with nothing watching it, so stepping back through a line
/// is answered from memory with no request and no loading frame. Then it is
/// released, as the explorer always did.
const Duration kExplorerGamesRetainFor = Duration(minutes: 2);

/// Pages that expire within this much of each other are released by one
/// timer tick, so a burst of pages never arms a timer each.
const Duration kExplorerGamesReleaseBatch = Duration(seconds: 1);

/// Safety cap on pages kept alive by [kExplorerGamesRetainFor]. Steady
/// reading settles about eight pages per position (the inline strip, '∑' and
/// six rows), so two minutes of it stays well under this; the oldest are
/// released first if a burst ever gets here. A decoded page is about 50 KB.
const int kExplorerGamesRetainedPagesCap = 256;

/// First pages kept in memory for an instant paint, fetched or read from disk.
/// A decoded 20-row page is about 50 KB of heap, so this is about 3 MB. The
/// position on screen is read back from disk as it settles, so a sheet opened
/// there still paints from memory.
const int kExplorerGamesMemoryPages = 64;

/// First pages saved on disk across app restarts, and their byte budget.
const int kExplorerGamesDiskPages = 400;
const int kExplorerGamesDiskBytes = 8 * 1024 * 1024;

/// A single page larger than this is never saved.
const int kExplorerGamesDiskMaxPageBytes = 256 * 1024;

/// A saved page older than this is deleted instead of shown.
const Duration kExplorerGamesDiskMaxAge = Duration(days: 7);

/// Bump whenever what a saved page means changes, so old files are ignored.
const String kExplorerGamesCacheSchema = 'gbpg:v1';

/// Where the rows a games list painted came from.
enum ExplorerGamesSource {
  /// Fetched from the server during this session.
  memory,

  /// Saved on disk by an earlier session (or earlier in this one).
  disk,

  /// Nothing was held: the list waited for the server.
  network,
}

/// A first page held for an instant paint, with the moment it was asked for.
@immutable
class ExplorerGamesSnapshot {
  const ExplorerGamesSnapshot({
    required this.response,
    required this.fetchedAt,
    required this.source,
  });

  final GamebaseSearchQueryResponse response;

  /// When the request for [response] was sent. The server answered after
  /// this, so the rows are no older than this moment.
  final DateTime fetchedAt;

  /// [ExplorerGamesSource.memory] or [ExplorerGamesSource.disk].
  final ExplorerGamesSource source;
}

/// Cache key for a request: the schema version plus the SHA-1 of the whole
/// wire request (method, base URL, path, and every body or query field).
String explorerGamesCacheKey(GamebaseWireRequest request) => sha1
    .convert(utf8.encode('$kExplorerGamesCacheSchema|${request.identity}'))
    .toString();

/// Saved pages are tagged with a hash of the signed-in account, never the id
/// itself. A guest is the empty id.
String explorerGamesOwnerHash(String userId) => sha1
    .convert(utf8.encode('explorer-games-owner|${userId.trim()}'))
    .toString();

// ─────────────────────────────────────────────────────────────────────────────
// Disk
// ─────────────────────────────────────────────────────────────────────────────

/// Where first pages survive an app restart.
abstract class ExplorerGamesDiskStore {
  /// Pages saved under [keys] for [owner] and younger than the store's max
  /// age. Keys with nothing usable saved are absent from the result.
  ///
  /// Asking for a different [owner] than the one the saved pages belong to
  /// deletes all of them first.
  Future<Map<String, ExplorerGamesSnapshot>> readMany(
    List<String> keys, {
    required String owner,
  });

  /// Saves [response] under [key] for [owner]. Same owner rule as [readMany].
  Future<void> write(
    String key,
    GamebaseSearchQueryResponse response,
    DateTime fetchedAt, {
    required String owner,
  });

  /// Deletes every saved page.
  Future<void> clear();
}

/// Saves nothing. The default under `flutter test`, where no test should
/// depend on files left behind by another.
class NoopExplorerGamesDiskStore implements ExplorerGamesDiskStore {
  const NoopExplorerGamesDiskStore();

  @override
  Future<Map<String, ExplorerGamesSnapshot>> readMany(
    List<String> keys, {
    required String owner,
  }) async => const <String, ExplorerGamesSnapshot>{};

  @override
  Future<void> write(
    String key,
    GamebaseSearchQueryResponse response,
    DateTime fetchedAt, {
    required String owner,
  }) async {}

  @override
  Future<void> clear() async {}
}

/// One small JSON file per saved page in the app's cache folder, which the
/// OS may also purge on its own.
///
/// * Writes go to a `.tmp` file that is renamed into place, so a crash never
///   leaves half a page behind.
/// * [_index] lists every saved file, least recently used first. Every file
///   this store adds goes through [_track] and every file it removes goes
///   through [_forget], which also drops it from the index, so the index
///   never counts a file that is gone and eviction never removes a live page
///   early.
/// * The index is built by scanning the folder, which stats every saved file.
///   The first read after an app start does not wait for that: it reads the
///   pages it was asked for straight by name and answers, and the scan runs
///   right after it. Writes, which evict, always have the index first.
/// * An `owner` marker file records whose pages these are. Any call for a
///   different owner deletes them all before it does anything else.
/// * All calls run one at a time, in order.
class FileExplorerGamesDiskStore implements ExplorerGamesDiskStore {
  FileExplorerGamesDiskStore({
    required Future<Directory> Function() directory,
    this.maxPages = kExplorerGamesDiskPages,
    this.maxBytes = kExplorerGamesDiskBytes,
    this.maxPageBytes = kExplorerGamesDiskMaxPageBytes,
    this.maxAge = kExplorerGamesDiskMaxAge,
    DateTime Function()? now,
  }) : _resolveDirectory = directory,
       _now = now ?? DateTime.now;

  final Future<Directory> Function() _resolveDirectory;
  final DateTime Function() _now;
  final int maxPages;
  final int maxBytes;
  final int maxPageBytes;
  final Duration maxAge;

  static const String _ownerFileName = 'owner';
  static const String _pageSuffix = '.json';
  static const String _tmpSuffix = '.tmp';
  static final RegExp _keyPattern = RegExp(r'^[0-9a-f]{40}$');

  Directory? _dir;
  String? _owner;
  final LinkedHashMap<String, int> _index = LinkedHashMap<String, int>();
  int _bytes = 0;

  /// Whether [_index] describes the folder yet.
  bool _indexed = false;

  /// Pages read before the index was built, in read order: they become the
  /// most recently used once it is.
  final List<String> _readBeforeIndex = <String>[];
  Future<void> _tail = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await op());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  File _file(Directory dir, String name) =>
      File('${dir.path}${Platform.pathSeparator}$name');

  /// The folder and whose pages it holds: one small read, no scan.
  Future<Directory> _open() async {
    final existing = _dir;
    if (existing != null) return existing;
    final dir = await _resolveDirectory();
    await dir.create(recursive: true);
    final ownerFile = _file(dir, _ownerFileName);
    _owner = await ownerFile.exists()
        ? (await ownerFile.readAsString()).trim()
        : null;
    _dir = dir;
    return dir;
  }

  /// Builds [_index] from the folder, once: drops leftovers and expired
  /// pages, then evicts down to the caps.
  Future<void> _ensureIndex(Directory dir) async {
    if (_indexed) return;
    final found = <(String, int, DateTime)>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.endsWith(_tmpSuffix)) {
        await _deleteQuietly(entity);
        continue;
      }
      if (!name.endsWith(_pageSuffix)) continue;
      final stat = await entity.stat();
      if (_now().difference(stat.modified) > maxAge) {
        await _deleteQuietly(entity);
        continue;
      }
      found.add((name, stat.size, stat.modified));
    }
    found.sort((a, b) => a.$3.compareTo(b.$3));
    _index.clear();
    _bytes = 0;
    for (final (name, size, _) in found) {
      _track(name, size);
    }
    _indexed = true;
    for (final name in _readBeforeIndex) {
      _touch(name);
    }
    _readBeforeIndex.clear();
    await _evict(dir);
  }

  Future<void> _ensureOwner(Directory dir, String owner) async {
    if (_owner == owner) return;
    await _wipe(dir);
    final marker = _file(dir, '$_ownerFileName$_tmpSuffix');
    await marker.writeAsString(owner, flush: true);
    await marker.rename(_file(dir, _ownerFileName).path);
    _owner = owner;
  }

  Future<void> _wipe(Directory dir) async {
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.endsWith(_pageSuffix) || name.endsWith(_tmpSuffix)) {
        await _deleteQuietly(entity);
      }
    }
    _index.clear();
    _bytes = 0;
    // An empty folder is fully described by an empty index.
    _indexed = true;
    _readBeforeIndex.clear();
  }

  void _track(String name, int size) {
    final previous = _index.remove(name);
    if (previous != null) _bytes -= previous;
    _index[name] = size;
    _bytes += size;
  }

  void _touch(String name) {
    final size = _index.remove(name);
    if (size != null) _index[name] = size;
  }

  Future<void> _forget(Directory dir, String name) async {
    final size = _index.remove(name);
    if (size != null) _bytes -= size;
    await _deleteQuietly(_file(dir, name));
  }

  Future<void> _evict(Directory dir) async {
    while (_index.isNotEmpty &&
        (_index.length > maxPages || _bytes > maxBytes)) {
      await _forget(dir, _index.keys.first);
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone.
    }
  }

  @override
  Future<Map<String, ExplorerGamesSnapshot>> readMany(
    List<String> keys, {
    required String owner,
  }) {
    return _serial(() async {
      final dir = await _open();
      await _ensureOwner(dir, owner);
      final found = <String, ExplorerGamesSnapshot>{};
      for (final key in keys) {
        if (!_keyPattern.hasMatch(key)) continue;
        final name = '$key$_pageSuffix';
        if (_indexed && !_index.containsKey(name)) continue;
        final String raw;
        try {
          raw = await _file(dir, name).readAsString();
        } on FileSystemException {
          // Not saved (read by name before the index exists), or purged by
          // the OS behind the index.
          if (_indexed) await _forget(dir, name);
          continue;
        }
        ExplorerGamesSnapshot? snapshot;
        try {
          snapshot = _decode(raw, key: key, owner: owner);
        } catch (_) {
          snapshot = null;
        }
        if (snapshot == null ||
            _now().difference(snapshot.fetchedAt) > maxAge) {
          await _forget(dir, name);
          continue;
        }
        if (_indexed) {
          _touch(name);
        } else {
          _readBeforeIndex.add(name);
        }
        found[key] = snapshot;
      }
      if (!_indexed) {
        // Answer first; the folder scan runs next, before any later call.
        unawaited(_serial(() => _ensureIndex(dir)));
      }
      return found;
    });
  }

  @override
  Future<void> write(
    String key,
    GamebaseSearchQueryResponse response,
    DateTime fetchedAt, {
    required String owner,
  }) {
    return _serial(() async {
      if (!_keyPattern.hasMatch(key)) return;
      final dir = await _open();
      await _ensureOwner(dir, owner);
      await _ensureIndex(dir);
      final bytes = utf8.encode(
        jsonEncode(<String, Object?>{
          'schema': kExplorerGamesCacheSchema,
          'key': key,
          'owner': owner,
          'fetchedAt': fetchedAt.millisecondsSinceEpoch,
          'response': response.toJson(),
        }),
      );
      final name = '$key$_pageSuffix';
      if (bytes.length > maxPageBytes) {
        // Never keep an older copy of a page that can no longer be saved.
        if (_index.containsKey(name)) await _forget(dir, name);
        return;
      }
      final tmp = _file(dir, '$name$_tmpSuffix');
      await tmp.writeAsBytes(bytes);
      await tmp.rename(_file(dir, name).path);
      _track(name, bytes.length);
      await _evict(dir);
    });
  }

  @override
  Future<void> clear() {
    return _serial(() async {
      final dir = await _open();
      await _wipe(dir);
      await _deleteQuietly(_file(dir, _ownerFileName));
      _owner = null;
    });
  }

  ExplorerGamesSnapshot? _decode(
    String raw, {
    required String key,
    required String owner,
  }) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    if (decoded['schema'] != kExplorerGamesCacheSchema) return null;
    if (decoded['key'] != key || decoded['owner'] != owner) return null;
    final fetchedAtMs = decoded['fetchedAt'];
    final response = decoded['response'];
    if (fetchedAtMs is! int || response is! Map) return null;
    return ExplorerGamesSnapshot(
      response: GamebaseSearchQueryResponse.fromJson(
        Map<String, dynamic>.from(response),
      ),
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAtMs),
      source: ExplorerGamesSource.disk,
    );
  }

  /// The saved page files, least recently used first, as the index sees them.
  @visibleForTesting
  Future<List<String>> debugIndexedFiles() => _serial(() async {
    await _ensureIndex(await _open());
    return _index.keys.toList(growable: false);
  });

  /// Total bytes the index believes are saved.
  @visibleForTesting
  Future<int> debugIndexedBytes() => _serial(() async {
    await _ensureIndex(await _open());
    return _bytes;
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Cache
// ─────────────────────────────────────────────────────────────────────────────

/// Memory, disk and in-flight bookkeeping behind every explorer games list.
///
/// * [fetch] is the only way a games page is requested from the server. One
///   request per wire request is ever in flight: a warm-up, the inline strip
///   and a sheet asking for the same page share it.
/// * First pages (`pageNumber == 0`) are remembered in memory and saved to
///   disk as they arrive, keyed by the exact wire request, so they can paint
///   a sheet instantly later, in this session or the next.
/// * Nothing read back from memory or disk is ever treated as current: the
///   caller shows it and asks the server again (see [isFresh]).
/// * When the signed-in account changes, memory and disk are emptied.
class ExplorerGamesCache {
  ExplorerGamesCache({
    required GamebaseRepository Function() repository,
    ExplorerGamesDiskStore disk = const NoopExplorerGamesDiskStore(),
    String Function()? currentUserId,
    DateTime Function()? now,
    this.memoryPages = kExplorerGamesMemoryPages,
    this.releaseOnTimer = false,
  }) : _repositoryOf = repository,
       _store = disk,
       _currentUserId = currentUserId ?? _supabaseUserId,
       _now = now ?? DateTime.now;

  final GamebaseRepository Function() _repositoryOf;
  final ExplorerGamesDiskStore _store;
  final String Function() _currentUserId;
  final DateTime Function() _now;
  final int memoryPages;

  /// Release retained pages on a timer the moment they expire, whether or
  /// not the explorer is still in use. On in the app ([explorerGamesCacheProvider]).
  /// Without it they are released on the next cache call, which is all a
  /// test that owns its container past the widget tree can allow: a pending
  /// timer there fails the test.
  final bool releaseOnTimer;
  Timer? _releaseTimer;

  final LinkedHashMap<GamebasePositionGamesQuery, String> _keys =
      LinkedHashMap<GamebasePositionGamesQuery, String>();
  final LinkedHashMap<String, ExplorerGamesSnapshot> _memory =
      LinkedHashMap<String, ExplorerGamesSnapshot>();
  final Map<String, Future<GamebaseSearchQueryResponse>> _inFlight = {};
  final Map<String, Future<void>> _diskReads = {};
  final Expando<DateTime> _fetchedAt = Expando<DateTime>('explorerGames');
  final ListQueue<(KeepAliveLink, DateTime)> _retained =
      ListQueue<(KeepAliveLink, DateTime)>();

  /// Disk work runs in this order, one call at a time.
  Future<void> _diskTail = Future<void>.value();

  /// Bumped whenever everything is forgotten, so late disk reads and writes
  /// started for the previous account are dropped.
  int _generation = 0;
  String? _ownerHash;
  bool _disposed = false;

  String? _lastUserId;
  String? _lastUserHash;

  String _currentOwnerHash() {
    final userId = _currentUserId();
    if (userId == _lastUserId && _lastUserHash != null) return _lastUserHash!;
    _lastUserId = userId;
    return _lastUserHash = explorerGamesOwnerHash(userId);
  }

  static String _supabaseUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id ?? '';
    } catch (_) {
      return '';
    }
  }

  // ── Keys ──────────────────────────────────────────────────────────────────

  /// The cache key for [query]: the exact request the repository sends for
  /// it. Two queries that differ only in fields the wire request drops (a
  /// move line that does not replay, moves on the FEN endpoint) share a key.
  String keyFor(GamebasePositionGamesQuery query) {
    final memo = _keys.remove(query);
    if (memo != null) {
      _keys[query] = memo;
      return memo;
    }
    final key = explorerGamesCacheKey(_wireRequest(query));
    _keys[query] = key;
    while (_keys.length > 512) {
      _keys.remove(_keys.keys.first);
    }
    return key;
  }

  GamebaseWireRequest _wireRequest(GamebasePositionGamesQuery query) {
    final repository = _repositoryOf();
    try {
      if (query.useFenEndpoint) {
        return repository.fenPositionGamesRequest(
          fen: query.fen,
          uci: query.uci,
          timeControl: query.timeControl,
          playerId: query.playerId,
          color: query.color,
          result: query.result,
          isOnline: query.isOnline,
          minRating: query.minRating,
          maxRating: query.maxRating,
          yearFrom: query.yearFrom,
          yearTo: query.yearTo,
          sortBy: query.sortBy,
          sortDirection: query.sortDirection,
          notationPlies: query.notationPlies,
          pageNumber: query.pageNumber,
          pageSize: query.pageSize,
        );
      }
      return repository.positionGamesRequest(
        fen: query.fen,
        moves: query.moves,
        uci: query.uci,
        timeControl: query.timeControl,
        playerId: query.playerId,
        color: query.color,
        result: query.result,
        isOnline: query.isOnline,
        minRating: query.minRating,
        maxRating: query.maxRating,
        yearFrom: query.yearFrom,
        yearTo: query.yearTo,
        sortBy: query.sortBy,
        sortDirection: query.sortDirection,
        notationPlies: query.notationPlies,
        pageNumber: query.pageNumber,
        pageSize: query.pageSize,
      );
    } catch (_) {
      // A repository stand-in that cannot describe its requests still gets a
      // key that is unique per query.
      return GamebaseWireRequest(
        method: 'QUERY',
        url: query.useFenEndpoint ? 'fen' : 'games',
        payload: <String, dynamic>{
          'fen': query.fen,
          'moves': query.moves,
          'uci': query.uci,
          'timeControl': query.timeControl?.name,
          'playerId': query.playerId,
          'color': query.color,
          'result': query.result,
          'isOnline': query.isOnline,
          'minRating': query.minRating,
          'maxRating': query.maxRating,
          'yearFrom': query.yearFrom,
          'yearTo': query.yearTo,
          'sortBy': query.sortBy.name,
          'sortDirection': query.sortDirection.name,
          'notationPlies': query.notationPlies,
          'pageNumber': query.pageNumber,
          'pageSize': query.pageSize,
        },
      );
    }
  }

  // ── Network ───────────────────────────────────────────────────────────────

  /// Asks the server for [query], sharing any identical request in flight.
  Future<GamebaseSearchQueryResponse> fetch(GamebasePositionGamesQuery query) {
    _syncOwner();
    _sweepRetained();
    final key = keyFor(query);
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final generation = _generation;
    final completer = Completer<GamebaseSearchQueryResponse>();
    final future = completer.future;
    _inFlight[key] = future;
    unawaited(() async {
      // Stamped as the request goes out, never as the answer lands: the
      // server answers some time after this, so the rows are no older than
      // this moment, and two pages compare by when they were asked for. A
      // slow page that lands after a newer one was asked for is still the
      // older of the two.
      final fetchedAt = _now();
      try {
        final response = await _send(query);
        _fetchedAt[response] = fetchedAt;
        if (query.pageNumber == 0 && generation == _generation && !_disposed) {
          _remember(
            key,
            ExplorerGamesSnapshot(
              response: response,
              fetchedAt: fetchedAt,
              source: ExplorerGamesSource.memory,
            ),
          );
          _persist(key, response, fetchedAt);
        }
        completer.complete(response);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        if (identical(_inFlight[key], future)) _inFlight.remove(key);
      }
    }());
    return future;
  }

  Future<GamebaseSearchQueryResponse> _send(GamebasePositionGamesQuery query) {
    final repository = _repositoryOf();
    if (query.useFenEndpoint) {
      return repository.getFenPositionGames(
        fen: query.fen,
        uci: query.uci,
        timeControl: query.timeControl,
        playerId: query.playerId,
        color: query.color,
        result: query.result,
        isOnline: query.isOnline,
        minRating: query.minRating,
        maxRating: query.maxRating,
        yearFrom: query.yearFrom,
        yearTo: query.yearTo,
        sortBy: query.sortBy,
        sortDirection: query.sortDirection,
        notationPlies: query.notationPlies,
        pageNumber: query.pageNumber,
        pageSize: query.pageSize,
      );
    }
    return repository.getPositionGames(
      fen: query.fen,
      moves: query.moves,
      uci: query.uci,
      timeControl: query.timeControl,
      playerId: query.playerId,
      color: query.color,
      result: query.result,
      isOnline: query.isOnline,
      minRating: query.minRating,
      maxRating: query.maxRating,
      yearFrom: query.yearFrom,
      yearTo: query.yearTo,
      sortBy: query.sortBy,
      sortDirection: query.sortDirection,
      notationPlies: query.notationPlies,
      pageNumber: query.pageNumber,
      pageSize: query.pageSize,
    );
  }

  /// When [fetch] sent the request [response] answers, if it came through
  /// [fetch]. The server produced it after this, so it is no older than this.
  DateTime? fetchedAtOf(GamebaseSearchQueryResponse response) =>
      _fetchedAt[response];

  /// Whether [response] came from the server recently enough to be shown as
  /// the answer without asking again. A page of unknown age never is.
  bool isFresh(GamebaseSearchQueryResponse response) {
    final fetchedAt = _fetchedAt[response];
    return fetchedAt != null &&
        _now().difference(fetchedAt) <= kExplorerGamesFreshFor;
  }

  /// Whether [fetch] has a request for [query] on the wire right now.
  bool isFetching(GamebasePositionGamesQuery query) =>
      _inFlight.containsKey(keyFor(query));

  // ── Memory ────────────────────────────────────────────────────────────────

  /// The first page held for [query], if any, without waiting.
  ExplorerGamesSnapshot? peek(GamebasePositionGamesQuery query) {
    _syncOwner();
    _sweepRetained();
    if (query.pageNumber != 0) return null;
    final key = keyFor(query);
    final hit = _memory.remove(key);
    if (hit == null) return null;
    // Too old to show at all: forgotten, as the disk would.
    if (_now().difference(hit.fetchedAt) > kExplorerGamesDiskMaxAge) {
      return null;
    }
    _memory[key] = hit;
    return hit;
  }

  void _remember(String key, ExplorerGamesSnapshot snapshot) {
    final existing = _memory.remove(key);
    _memory[key] =
        existing != null && existing.fetchedAt.isAfter(snapshot.fetchedAt)
        ? existing
        : snapshot;
    while (_memory.length > memoryPages) {
      _memory.remove(_memory.keys.first);
    }
  }

  // ── Disk ──────────────────────────────────────────────────────────────────

  Future<void> _enqueueDisk(Future<void> Function() op) {
    final done = Completer<void>();
    _diskTail = _diskTail.then((_) async {
      try {
        await op();
      } catch (error) {
        // The disk is only an accelerator; a failure costs a network request.
        if (kDebugMode) debugPrint('[ExplorerGamesCache] disk: $error');
      } finally {
        done.complete();
      }
    });
    return done.future;
  }

  void _persist(
    String key,
    GamebaseSearchQueryResponse response,
    DateTime fetchedAt,
  ) {
    final generation = _generation;
    final owner = _ownerHash;
    if (owner == null) return;
    unawaited(
      _enqueueDisk(() async {
        if (generation != _generation || _disposed) return;
        await _store.write(key, response, fetchedAt, owner: owner);
      }),
    );
  }

  /// Loads whatever the disk holds for these first pages into memory, in one
  /// read, so a later [peek] answers synchronously.
  Future<void> preload(Iterable<GamebasePositionGamesQuery> queries) {
    _syncOwner();
    final owner = _ownerHash;
    if (owner == null || _disposed) return Future<void>.value();
    final keys = <String>[];
    final waits = <Future<void>>[];
    for (final query in queries) {
      if (query.pageNumber != 0) continue;
      final key = keyFor(query);
      if (_memory.containsKey(key) || keys.contains(key)) continue;
      final pending = _diskReads[key];
      if (pending != null) {
        waits.add(pending);
        continue;
      }
      keys.add(key);
    }
    if (keys.isNotEmpty) {
      final generation = _generation;
      late final Future<void> read;
      read = _enqueueDisk(() async {
        try {
          if (generation != _generation || _disposed) return;
          final found = await _store.readMany(keys, owner: owner);
          if (generation != _generation || _disposed) return;
          for (final entry in found.entries) {
            _remember(entry.key, entry.value);
          }
        } finally {
          for (final key in keys) {
            if (identical(_diskReads[key], read)) _diskReads.remove(key);
          }
        }
      });
      for (final key in keys) {
        _diskReads[key] = read;
      }
      waits.add(read);
    }
    return waits.isEmpty ? Future<void>.value() : Future.wait(waits);
  }

  /// The held first page for [query], reading the disk if memory has none.
  Future<ExplorerGamesSnapshot?> read(GamebasePositionGamesQuery query) async {
    final held = peek(query);
    if (held != null || query.pageNumber != 0) return held;
    await preload(<GamebasePositionGamesQuery>[query]);
    return peek(query);
  }

  // ── Retention ─────────────────────────────────────────────────────────────

  /// Keeps a settled `positionGamesProvider` page alive for
  /// [kExplorerGamesRetainFor], then releases it.
  ///
  /// Pages are queued in the order they settle, so the head always expires
  /// first. With [releaseOnTimer] one timer is armed for the head (never one
  /// per page) and re-armed after each release; it is cancelled with the
  /// cache. Every cache call also releases whatever has expired.
  ///
  /// Releasing only ends the keep-alive: a page something still watches
  /// stays. Whoever re-attaches to a held page older than
  /// [kExplorerGamesFreshFor] treats it as a copy to check, never as current
  /// (see [refreshExplorerGamesIfStale]).
  void retain(KeepAliveLink link) {
    if (_disposed) {
      link.close();
      return;
    }
    _retained.add((link, _now().add(kExplorerGamesRetainFor)));
    while (_retained.length > kExplorerGamesRetainedPagesCap) {
      _retained.removeFirst().$1.close();
    }
    _sweepRetained();
  }

  void _sweepRetained() {
    final now = _now();
    while (_retained.isNotEmpty && !_retained.first.$2.isAfter(now)) {
      _retained.removeFirst().$1.close();
    }
    _armReleaseTimer();
  }

  void _armReleaseTimer() {
    if (!releaseOnTimer || _disposed) return;
    if (_retained.isEmpty) {
      _releaseTimer?.cancel();
      _releaseTimer = null;
      return;
    }
    if (_releaseTimer?.isActive ?? false) return;
    final due = _retained.first.$2.difference(_now());
    _releaseTimer = Timer(
      (due.isNegative ? Duration.zero : due) + kExplorerGamesReleaseBatch,
      () {
        _releaseTimer = null;
        if (!_disposed) _sweepRetained();
      },
    );
  }

  void _releaseRetained() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    while (_retained.isNotEmpty) {
      _retained.removeFirst().$1.close();
    }
  }

  /// Whether a release timer is armed.
  @visibleForTesting
  bool get debugReleaseTimerArmed => _releaseTimer?.isActive ?? false;

  /// Pages currently kept alive by [retain].
  @visibleForTesting
  int get debugRetainedCount => _retained.length;

  // ── Account ───────────────────────────────────────────────────────────────

  /// Re-reads the signed-in account; if it changed, forgets every page.
  void handleAccountChange() => _syncOwner();

  void _syncOwner() {
    if (_disposed) return;
    final hash = _currentOwnerHash();
    final previous = _ownerHash;
    _ownerHash = hash;
    if (previous == null || previous == hash) return;
    _forgetAll();
  }

  void _forgetAll() {
    _generation++;
    _memory.clear();
    _diskReads.clear();
    _releaseRetained();
    unawaited(_enqueueDisk(_store.clear));
  }

  /// Forgets every page in memory and on disk.
  Future<void> clear() {
    _forgetAll();
    return _enqueueDisk(() async {});
  }

  /// Completes once every disk call queued so far has finished.
  @visibleForTesting
  Future<void> debugDiskIdle() => _enqueueDisk(() async {});

  void dispose() {
    _disposed = true;
    _generation++;
    _releaseRetained();
    _memory.clear();
    _keys.clear();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Instrumentation
// ─────────────────────────────────────────────────────────────────────────────

/// Records where a games sheet's first rows came from and how long after the
/// open they painted: a debug log line and a Sentry breadcrumb.
void recordExplorerGamesPaint({
  required String surface,
  required ExplorerGamesSource source,
  required Duration elapsed,
}) {
  if (kDebugMode) {
    debugPrint(
      '[ExplorerGames] $surface painted from ${source.name} '
      'in ${elapsed.inMilliseconds} ms',
    );
  }
  try {
    Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'explorer.games',
        message: '$surface painted from ${source.name}',
        type: 'debug',
        data: <String, dynamic>{
          'source': source.name,
          'ms': elapsed.inMilliseconds,
        },
      ),
    );
  } catch (_) {
    // Diagnostics must never affect the sheet.
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

bool _underFlutterTest() {
  try {
    return Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

/// Where first pages are saved between sessions: the app's cache folder,
/// which the OS may purge. Nothing is saved under `flutter test`.
final explorerGamesDiskStoreProvider = Provider<ExplorerGamesDiskStore>((ref) {
  if (_underFlutterTest()) return const NoopExplorerGamesDiskStore();
  return FileExplorerGamesDiskStore(
    directory: () async {
      final base = await getApplicationCacheDirectory();
      return Directory('${base.path}${Platform.pathSeparator}explorer_games');
    },
  );
});

/// Asks the server again for [query] when the answer held for it came back
/// more than [kExplorerGamesFreshFor] ago. Call it as a list (re)attaches to
/// a page, outside a build: the list then shows the held rows as a copy being
/// checked, and the fresh answer replaces them.
///
/// Only a settled answer is refreshed: one in flight is about to be current,
/// and a failed one is released and fetched again on its own. Returns whether
/// it asked.
bool refreshExplorerGamesIfStale(
  WidgetRef ref,
  GamebasePositionGamesQuery query,
) {
  final provider = positionGamesProvider(query);
  if (!ref.exists(provider)) return false;
  final held = ref.read(provider);
  if (held.isLoading || held.hasError || !held.hasValue) return false;
  if (ref.read(explorerGamesCacheProvider).isFresh(held.requireValue)) {
    return false;
  }
  ref.invalidate(provider);
  return true;
}

/// App-lifetime cache behind every explorer games list.
final explorerGamesCacheProvider = Provider<ExplorerGamesCache>((ref) {
  final cache = ExplorerGamesCache(
    repository: () => ref.read(gamebaseRepositoryProvider),
    disk: ref.read(explorerGamesDiskStoreProvider),
    releaseOnTimer: !_underFlutterTest(),
  );
  StreamSubscription<AuthState>? authSubscription;
  try {
    // Signing out or into another account empties memory and disk at once,
    // not only on the next explorer call.
    authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (_) => cache.handleAccountChange(),
      onError: (_) {},
    );
  } catch (_) {
    // Supabase is not initialised (tests); every call still checks the
    // account itself.
  }
  ref.onDispose(() {
    authSubscription?.cancel();
    cache.dispose();
  });
  return cache;
});
