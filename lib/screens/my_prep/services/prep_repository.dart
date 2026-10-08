import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/gamebase/models/gamebase_player.dart';
import 'package:chessever2/services/game_tree/game_tree_codec.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const _userAgent =
    'ChessEverMobile/1.0 (https://chessever.com; support@chessever.com)';

/// A lookup or download failure worth showing the reader as written.
class PrepException implements Exception {
  const PrepException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// What a sync reports while it waits on the server.
typedef PrepProgress = void Function(String message);

/// Lichess and Chess.com profile lookups, and the server-cached game
/// downloads desktop Prep uses, stored as one PGN file per account.
class PrepRepository {
  PrepRepository(this._gamebase, {http.Client? client})
    : _client = client ?? http.Client();

  final GamebaseRepository _gamebase;
  final http.Client _client;
  void dispose() => _client.close();

  Future<List<GamebasePlayer>> searchPlayers(String query) {
    final clean = query.trim();
    if (clean.length < 2) return Future.value(const []);
    return _gamebase.getPlayers(
      name: RegExp(r'^\d+$').hasMatch(clean) ? null : clean,
      fideId: RegExp(r'^\d+$').hasMatch(clean) ? clean : null,
      pageSize: 20,
    );
  }

  Future<PrepAccount> refreshDetails(PrepAccount account) async {
    if (account.source.online) return lookup(account.source, account.username);
    if (account.source == PrepSource.chessever) {
      final player = await _gamebase.getPlayerById(account.externalId!);
      if (player == null) {
        throw const PrepException('This database player is unavailable.');
      }
      return PrepAccount.fromPlayer(player);
    }
    return account;
  }

  /// How long a cold account may take to prepare before we give up. The
  /// server keeps preparing; a later sync picks the snapshot up.
  static const Duration _prepareTimeout = Duration(minutes: 20);

  // ------------------------------------------------------------ profiles

  Future<PrepAccount> lookup(PrepSource source, String username) =>
      switch (source) {
        PrepSource.lichess => _lookupLichess(username),
        PrepSource.chesscom => _lookupChessCom(username),
        _ => throw const PrepException(
          'Select a player from the database search.',
        ),
      };

  Future<PrepAccount> _lookupLichess(String username) async {
    final clean = _cleanUsername(username);
    final response = await _get(Uri.https('lichess.org', '/api/user/$clean'));
    if (response.statusCode == 404) {
      throw PrepException('No Lichess account is called "$clean".');
    }
    _check(response, 'Lichess');
    final json = jsonDecode(response.body);
    if (json is! Map || json['closed'] == true || json['disabled'] == true) {
      throw PrepException('The Lichess account "$clean" is closed.');
    }
    final ratings = <String, int>{};
    final perfs = json['perfs'];
    if (perfs is Map) {
      for (final entry in perfs.entries) {
        final perf = entry.value;
        final rating = perf is Map ? perf['rating'] : null;
        final games = perf is Map ? perf['games'] : null;
        if (rating is int && (games is! int || games > 0)) {
          ratings[_lichessPerf(entry.key.toString())] = rating;
        }
      }
    }
    final profile = json['profile'];
    final id = json['username']?.toString().trim();
    final realName = profile is Map
        ? [
            profile['firstName'],
            profile['lastName'],
          ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ')
        : '';
    return PrepAccount(
      source: PrepSource.lichess,
      username: id?.isNotEmpty == true ? id! : clean,
      displayName: realName.isNotEmpty ? realName : null,
      title: json['title']?.toString(),
      country: profile is Map ? _flagCode(profile['flag']) : null,
      ratings: ratings,
    );
  }

  Future<PrepAccount> _lookupChessCom(String username) async {
    final clean = _cleanUsername(username).toLowerCase();
    final response = await _get(
      Uri.https('api.chess.com', '/pub/player/$clean'),
    );
    if (response.statusCode == 404) {
      throw PrepException('No Chess.com account is called "$clean".');
    }
    _check(response, 'Chess.com');
    final profile = jsonDecode(response.body);
    if (profile is! Map) {
      throw const PrepException('Chess.com sent no profile.');
    }
    final status = profile['status']?.toString() ?? '';
    if (status.startsWith('closed')) {
      throw PrepException('The Chess.com account "$clean" is closed.');
    }

    final ratings = <String, int>{};
    try {
      final stats = await _get(
        Uri.https('api.chess.com', '/pub/player/$clean/stats'),
      );
      if (stats.statusCode == 200) {
        final json = jsonDecode(stats.body);
        if (json is Map) {
          for (final key in const [
            'chess_bullet',
            'chess_blitz',
            'chess_rapid',
            'chess_daily',
          ]) {
            final bucket = json[key];
            final last = bucket is Map ? bucket['last'] : null;
            final rating = last is Map ? last['rating'] : null;
            if (rating is int) ratings[key.substring(6)] = rating;
          }
        }
      }
    } catch (_) {
      // Ratings are decoration; the account itself was found.
    }

    // The API lowercases `username`; the profile URL keeps its real case.
    final url = profile['url']?.toString() ?? '';
    final cased = Uri.tryParse(url)?.pathSegments.lastOrNull ?? '';
    final name = profile['name']?.toString().trim();
    return PrepAccount(
      source: PrepSource.chesscom,
      username: cased.toLowerCase() == clean ? cased : clean,
      displayName: name?.isNotEmpty == true ? name : null,
      avatarUrl: profile['avatar']?.toString(),
      title: profile['title']?.toString(),
      country: _chessComCountry(profile['country']?.toString()),
      ratings: ratings,
    );
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _client
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': _userAgent,
            },
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const PrepException('The lookup timed out. Check your connection.');
    } on SocketException {
      throw const PrepException(
        'No connection. Try again when you are online.',
      );
    }
  }

  void _check(http.Response response, String provider) {
    if (response.statusCode == 429) {
      throw PrepException('$provider is busy. Try again in a minute.');
    }
    if (response.statusCode >= 400) {
      throw PrepException('$provider answered ${response.statusCode}.');
    }
  }

  // ------------------------------------------------------------ games

  /// Brings [account]'s stored games up to date and returns the account
  /// with its new sync record. A first sync, or a changed selection, takes
  /// the whole selected snapshot; later syncs ask only for newer games.
  Future<PrepAccount> sync(
    PrepAccount account, {
    bool forceRefresh = false,
    bool frequent = false,
    PrepProgress? onProgress,
    CancelToken? cancelToken,
    bool reinstall = false,
  }) async {
    if (account.source == PrepSource.manual) return account;
    if (account.source == PrepSource.chessever) {
      onProgress?.call('Downloading ChessEver games…');
      final export = await _gamebase.getPlayerGamesPgn(
        playerId: account.externalId!,
        fideId: account.fideId,
        cancelToken: cancelToken,
      );
      if (export == null ||
          (export.pgn.trim().isEmpty && export.gameCount > 0)) {
        throw const PrepException(
          'ChessEver game export is unavailable. Try again.',
        );
      }
      if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
      onProgress?.call('Saving games…');
      final file = await gamesFile(account);
      final count = await compute(
        _writeGames,
        _WriteRequest(path: file.path, incoming: export.pgn, merge: false),
      );
      return account.copyWith(
        lastSyncAtMs: DateTime.now().millisecondsSinceEpoch,
        syncedScope: 'chessever:all',
        gameCount: count,
        clearError: true,
      );
    }
    final now = DateTime.now();
    final prefs = account.preferences;
    if (prefs.validationError case final error?) throw PrepException(error);
    final scope = prefs.scopeKey(now);
    final file = await gamesFile(account);
    final sameScope =
        !reinstall && account.syncedScope == scope && await file.exists();
    final since = sameScope ? account.lastSyncAtMs : null;

    onProgress?.call('Checking ${account.source.label}…');
    var refresh = forceRefresh;
    final deadline = now.add(_prepareTimeout);
    GamebasePlayerPgnExport? export;
    while (true) {
      try {
        export = await _gamebase.getExternalPlayerGamesPgn(
          source: account.source.gamebase,
          username: account.username,
          refresh: refresh,
          // An overlapping cursor, so a game finishing during the last sync
          // still arrives; duplicates are dropped on merge.
          sinceMs: since == null
              ? null
              : since - const Duration(hours: 1).inMilliseconds,
          dateFromMs: prefs.fromMs(now),
          untilMs: prefs.untilMs,
          timeControls: {for (final t in prefs.timeControls) t.name},
          cadence: frequent ? 'frequent' : null,
          cancelToken: cancelToken,
        );
        break;
      } on GamebaseExternalPlayerPgnPreparingException catch (preparing) {
        // Only the first request asks for a refresh; polls must not keep
        // restarting the job they are waiting on.
        refresh = false;
        if (DateTime.now().isAfter(deadline)) {
          throw const PrepException(
            'This account is still being prepared. It keeps going on our '
            'server, so try again in a few minutes.',
          );
        }
        final got = preparing.preparedGameCount;
        final expected = preparing.expectedGameCount;
        onProgress?.call(
          got == null
              ? 'Preparing games on ChessEver…'
              : expected == null
              ? 'Preparing games · $got received'
              : 'Preparing games · $got of about $expected',
        );
        await _sleep(preparing.retryAfter, cancelToken);
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) rethrow;
        final code = error.response?.statusCode;
        if (code == 404) {
          throw PrepException(
            '${account.source.label} has no account "${account.username}".',
          );
        }
        if (code == 413) {
          throw const PrepException(
            'That selection is too large. Choose fewer time controls or a '
            'shorter period.',
          );
        }
        if (code == 429) {
          throw PrepException(
            '${account.source.label} is limiting downloads. Try again in a minute.',
          );
        }
        throw PrepException(
          'Could not reach ChessEver (${code ?? 'offline'}). Try again shortly.',
        );
      }
    }
    if (export == null) {
      throw const PrepException('Game downloads are not available right now.');
    }
    if (prefs.isFiltered && export.filterVersion != '1') {
      throw const PrepException(
        'Download options need a server update. Choose All time controls and '
        'All time for now.',
      );
    }

    onProgress?.call('Saving games…');
    if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
    // A delta, or a full snapshot of the same selection, only ever adds
    // games: they are appended so every stored game keeps its place in the
    // file, which is what lets the opening index read just the new tail.
    final count = await compute(
      _writeGames,
      _WriteRequest(path: file.path, incoming: export.pgn, merge: sameScope),
    );
    return account.copyWith(
      lastSyncAtMs: now.millisecondsSinceEpoch,
      syncedScope: scope,
      gameCount: count,
      clearError: true,
    );
  }

  /// The account's stored PGN, or empty when it has never synced.
  Future<String> readGames(PrepAccount account) async {
    final file = await gamesFile(account);
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  Future<void> deleteGames(PrepAccount account) async {
    final file = await gamesFile(account);
    if (await file.exists()) await file.delete();
  }

  Future<File> gamesFile(PrepAccount account) async {
    final dir = await prepDirectory();
    return File('${dir.path}/${gamesFileName(account)}');
  }

  /// The account's PGN file name inside [prepDirectory].
  static String gamesFileName(PrepAccount account) {
    final id = sha1.convert(utf8.encode(account.key)).toString();
    return '${account.source.name}_$id.pgn';
  }

  static Future<Directory> prepDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/prep');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _sleep(Duration delay, CancelToken? token) async {
    final done = Completer<void>();
    final timer = Timer(delay, () {
      if (!done.isCompleted) done.complete();
    });
    unawaited(
      token?.whenCancel.then((_) {
        timer.cancel();
        if (!done.isCompleted) {
          done.completeError(
            DioException.requestCancelled(
              requestOptions: RequestOptions(),
              reason: 'Prep sync canceled',
            ),
          );
        }
      }),
    );
    await done.future;
  }
}

String _cleanUsername(String raw) {
  var clean = raw.trim();
  // Accept a pasted profile link as well as a bare name.
  final link = RegExp(
    r'(?:lichess\.org/@/|chess\.com/(?:member|players?)/)([A-Za-z0-9_-]+)',
  ).firstMatch(clean);
  if (link != null) clean = link.group(1)!;
  clean = clean.replaceFirst(RegExp(r'^@'), '');
  if (!RegExp(r'^[A-Za-z0-9_-]{2,30}$').hasMatch(clean)) {
    throw const PrepException('Usernames use letters, numbers, - and _ only.');
  }
  return clean;
}

/// Lichess perf keys to the names Prep shows.
String _lichessPerf(String key) => switch (key) {
  'ultraBullet' => 'ultrabullet',
  'correspondence' => 'daily',
  _ => key,
};

String? _flagCode(Object? flag) {
  final text = flag?.toString().trim().toUpperCase() ?? '';
  return RegExp(r'^[A-Z]{2}$').hasMatch(text) ? text : null;
}

String? _chessComCountry(String? url) {
  final code = url?.split('/').lastOrNull?.toUpperCase() ?? '';
  return RegExp(r'^[A-Z]{2}$').hasMatch(code) ? code : null;
}

class _WriteRequest {
  const _WriteRequest({
    required this.path,
    required this.incoming,
    required this.merge,
  });
  final String path;
  final String incoming;
  final bool merge;
}

/// Writes (or adds to) one account's PGN file and returns its game count.
/// Adding appends only games whose provider URL the file does not hold yet,
/// leaving every stored byte where it was. Runs off the UI isolate.
int _writeGames(_WriteRequest request) => writePrepGames(
  path: request.path,
  incoming: request.incoming,
  merge: request.merge,
);

int writePrepGames({
  required String path,
  required String incoming,
  required bool merge,
}) {
  final file = File(path);
  final games = splitPrepPgn(incoming);
  if (!merge || !file.existsSync()) {
    final seen = <String>{};
    final unique = <String>[];
    for (final game in games) {
      final key = _snapshotGameKey(game);
      if (seen.add(key)) unique.add(game);
    }
    _atomicWrite(file, unique.join('\n\n'));
    return unique.length;
  }
  final existing = file.readAsStringSync();
  final known = <String>{
    for (final m in _siteTag.allMatches(existing))
      if (_isProviderUrl(m.group(1)!)) m.group(1)!,
  };
  final stored = existing.trim().isEmpty
      ? 0
      : _eventStart.allMatches(existing).length.clamp(1, 1 << 30);
  final fresh = <String>[];
  for (final game in games) {
    final key = prepGameKey(game);
    if (key == null || known.add(key)) fresh.add(game);
  }
  if (fresh.isEmpty) return stored;
  final raf = file.openSync(mode: FileMode.append);
  try {
    raf.writeStringSync('${stored == 0 ? '' : '\n\n'}${fresh.join('\n\n')}');
    raf.flushSync();
  } finally {
    raf.closeSync();
  }
  return stored + fresh.length;
}

bool _isProviderUrl(String url) =>
    url.contains('lichess.org/') || url.contains('chess.com/');

/// Exports Combined one source at a time. Run off the UI isolate.
int writeCombinedPrepGames({
  required String path,
  required List<String> sources,
}) {
  final temporary = File('$path.tmp');
  final output = temporary.openSync(mode: FileMode.write);
  final seen = <String>{};
  try {
    for (final sourcePath in sources) {
      final source = File(sourcePath);
      if (!source.existsSync()) continue;
      for (final pgn in splitPrepPgn(source.readAsStringSync())) {
        if (!seen.add(_snapshotGameKey(pgn))) continue;
        output.writeStringSync('${seen.length == 1 ? '' : '\n\n'}$pgn');
      }
    }
    output.flushSync();
  } finally {
    output.closeSync();
  }
  temporary.renameSync(path);
  return seen.length;
}

String _snapshotGameKey(String game) =>
    prepGameKey(game) ??
    sha1
        .convert(utf8.encode(game.replaceAll(RegExp(r'\s+'), ' ').trim()))
        .toString();

/// An imported player source contains playable games for the stated PGN name.
int writeImportedPrepGames({
  required String path,
  required String pgn,
  required String playerName,
}) {
  final alias = playerName.trim().toLowerCase();
  final matching = splitPrepPgn(pgn).where((game) {
    final scan = scanPgnGame(game);
    return scan.sans.isNotEmpty &&
        [
          scan.tag('White'),
          scan.tag('Black'),
        ].any((name) => name?.trim().toLowerCase() == alias);
  }).toList();
  if (matching.isEmpty) {
    throw PrepException(
      'No playable games match "$playerName". Use the player name from the PGN.',
    );
  }
  return writePrepGames(
    path: path,
    incoming: matching.join('\n\n'),
    merge: false,
  );
}

void _atomicWrite(File file, String text) {
  final temp = File('${file.path}.tmp');
  temp.writeAsStringSync(text, flush: true);
  temp.renameSync(file.path);
}

final RegExp _eventStart = RegExp(r'^\[Event\s', multiLine: true);

/// Splits a PGN blob into games at each `[Event` header.
List<String> splitPrepPgn(String text) {
  final normalized = text.replaceAll('\r\n', '\n').trim();
  if (normalized.isEmpty) return const [];
  final starts = _eventStart
      .allMatches(normalized)
      .map((m) => m.start)
      .toList();
  if (starts.isEmpty) return [normalized];
  return [
    for (var i = 0; i < starts.length; i++)
      normalized
          .substring(starts[i], i + 1 < starts.length ? starts[i + 1] : null)
          .trim(),
  ];
}

final RegExp _siteTag = RegExp(
  r'^\[(?:Site|Link)\s+"([^"]+)"\]',
  multiLine: true,
);

/// A provider game's stable identity: its URL.
String? prepGameKey(String pgn) {
  final match = _siteTag
      .allMatches(pgn)
      .map((m) => m.group(1)!)
      .where(
        (url) => url.contains('lichess.org/') || url.contains('chess.com/'),
      );
  return match.isEmpty ? null : match.last;
}
