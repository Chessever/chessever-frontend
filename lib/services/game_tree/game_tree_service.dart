import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/services/game_tree/game_tree_builder.dart';
import 'package:chessever2/services/game_tree/game_tree_db.dart';
import 'package:chessever2/services/game_tree/game_tree_registry.dart';
import 'package:chessever2/services/game_tree/game_tree_store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

enum GameTreePhase { idle, fetching, indexing, ready, failed }

/// What one scope's tree build is doing, for buttons and progress lines.
@immutable
class GameTreeStatus {
  const GameTreeStatus({
    this.phase = GameTreePhase.idle,
    this.fraction,
    this.message,
    this.error,
  });

  final GameTreePhase phase;

  /// 0..1 when known.
  final double? fraction;
  final String? message;
  final String? error;

  bool get busy =>
      phase == GameTreePhase.fetching || phase == GameTreePhase.indexing;

  int? get percent =>
      fraction == null ? null : (fraction!.clamp(0, 1) * 100).round();
}

/// Build status by scope id. A scope that never built is absent.
final gameTreeStatusProvider =
    StateNotifierProvider<GameTreeStatusNotifier, Map<String, GameTreeStatus>>(
      (ref) => GameTreeStatusNotifier(),
    );

class GameTreeStatusNotifier
    extends StateNotifier<Map<String, GameTreeStatus>> {
  GameTreeStatusNotifier() : super(const {});

  void set(String scopeId, GameTreeStatus status) {
    if (!mounted) return;
    state = {...state, scopeId: status};
  }

  void clear(String scopeId) {
    if (!mounted || !state.containsKey(scopeId)) return;
    state = {...state}..remove(scopeId);
  }
}

/// Raised when the reader stops a build.
class GameTreeCanceled implements Exception {
  const GameTreeCanceled();
}

/// Where trees live and how they are built, one at a time per scope.
///
/// Indexes go in the app's cache directory: they are rebuilt from their
/// PGN sources whenever missing, so the system may reclaim them and they
/// are never backed up.
abstract final class GameTreeService {
  static final Map<String, Future<void>> _locks = {};
  static final Set<String> _cancelRequested = {};

  static Future<Directory> directory() async {
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}/game_trees');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String> databasePath(String scopeId) async =>
      '${(await directory()).path}/$scopeId.sqlite';

  /// A stable scope id for something that is not a My Prep profile, such
  /// as `library:<folder id>` or `collection:<slug>`.
  static String scopeFor(String identity) =>
      'tree-${sha1.convert(utf8.encode(identity)).toString().substring(0, 24)}';

  /// The registered store for [scopeId], opening its index from disk when
  /// one was built before.
  static Future<GameTreeStore?> existing(
    String scopeId, {
    required bool playerScope,
  }) async {
    final open = GameTreeRegistry.storeFor(scopeId);
    if (open != null) return open;
    final store = GameTreeStore.open(
      scopeId,
      await databasePath(scopeId),
      playerScope: playerScope,
    );
    if (store != null) GameTreeRegistry.register(store);
    return store;
  }

  /// Brings [scopeId]'s index up to date with [sources] and returns it,
  /// registered for the explorer. Concurrent calls for one scope queue.
  static Future<GameTreeStore> ensure({
    required String scopeId,
    required List<GameTreeSourceFile> sources,
    List<String> aliases = const [],
    String? revision,
    required bool playerScope,
    void Function(double fraction)? onProgress,
    Map<String, String> sourceLabels = const {},
  }) {
    return _serialized(scopeId, () async {
      final path = await databasePath(scopeId);
      final cancel = '$path.cancel';
      final cancelFile = File(cancel);
      if (await cancelFile.exists()) await cancelFile.delete();
      _cancelRequested.remove(scopeId);
      final result = await buildGameTreeInBackground(
        GameTreeBuildRequest(
          dbPath: path,
          sources: sources,
          aliases: aliases,
          revision: revision,
          cancelPath: cancel,
        ),
        onProgress: onProgress,
      );
      if (await cancelFile.exists()) await cancelFile.delete();
      var store = GameTreeRegistry.storeFor(scopeId);
      if (store == null) {
        store = GameTreeStore.open(scopeId, path, playerScope: playerScope);
        if (store == null) {
          throw StateError('The opening index could not be opened.');
        }
      } else {
        store.refresh();
      }
      GameTreeRegistry.register(store, sourceLabels: sourceLabels);
      if (result.canceled) throw const GameTreeCanceled();
      return store;
    });
  }

  /// Asks a running build of [scopeId] to stop at its next commit.
  static Future<void> cancel(String scopeId) async {
    _cancelRequested.add(scopeId);
    final path = await databasePath(scopeId);
    await File('$path.cancel').writeAsString('1');
  }

  static bool cancelRequested(String scopeId) =>
      _cancelRequested.contains(scopeId);

  /// Removes [scopeId]'s index and any PGN fetched for it.
  static Future<void> delete(String scopeId) => _serialized(scopeId, () async {
    GameTreeRegistry.unregister(scopeId);
    final path = await databasePath(scopeId);
    for (final file in [
      ...gameTreeDatabaseFiles(path),
      File('$path.cancel'),
      File(await pgnPath(scopeId)),
    ]) {
      try {
        if (await file.exists()) await file.delete();
      } catch (error) {
        debugPrint('[GameTree] could not delete ${file.path}: $error');
      }
    }
  });

  /// Where a remote collection's games are kept for its index.
  static Future<String> pgnPath(String scopeId) async =>
      '${(await directory()).path}/$scopeId.pgn';

  static Future<T> _serialized<T>(String scopeId, Future<T> Function() run) {
    final previous = _locks[scopeId] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) => run());
    final settled = next.then<void>((_) {}, onError: (_) {});
    _locks[scopeId] = settled;
    unawaited(
      settled.whenComplete(() {
        if (identical(_locks[scopeId], settled)) _locks.remove(scopeId);
      }),
    );
    return next;
  }
}

/// Writes a collection's games to one PGN file, a game per `[Event` block,
/// so the index can address each by its bytes. Returns how many it wrote.
class GameTreePgnWriter {
  GameTreePgnWriter._(this._sink, this._temp, this._target);

  static Future<GameTreePgnWriter> open(String path) async {
    final temp = File('$path.part');
    await temp.parent.create(recursive: true);
    return GameTreePgnWriter._(temp.openWrite(), temp, File(path));
  }

  final IOSink _sink;
  final File _temp;
  final File _target;
  var _count = 0;

  int get count => _count;

  void add(String pgn) {
    var text = pgn.replaceAll('\r\n', '\n').trim();
    if (text.isEmpty) return;
    // Every game opens with an Event tag, the boundary the index splits on.
    if (!text.startsWith('[Event ')) {
      text = text.startsWith('[')
          ? '[Event "?"]\n$text'
          : '[Event "?"]\n\n$text';
    }
    if (_count > 0) _sink.write('\n\n');
    _sink.write(text);
    _sink.write('\n');
    _count++;
  }

  /// Replaces the target file with what was written.
  Future<void> commit() async {
    await _sink.flush();
    await _sink.close();
    await _temp.rename(_target.path);
  }

  Future<void> discard() async {
    try {
      await _sink.close();
    } catch (_) {}
    if (await _temp.exists()) await _temp.delete();
  }
}

/// Opens the board explorer on [scopeId]'s tree, titled [title].
Future<void> openGameTreeExplorer(
  BuildContext context, {
  required String scopeId,
  required String title,
  String? country,
  String? playerTitle,
  GamebasePlayerColor? color,
  TimeControl? timeControl,
  String? initialFen,
  List<String>? initialMoves,
}) {
  final id = GameTreeRegistry.playerIdFor(scopeId);
  final player = GamebasePlayer(
    id: id,
    fideId: '',
    name: title,
    gender: PlayerGender.male,
    fed: country ?? '',
    title: playerTitle,
  );
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => GamebaseExplorerScreen.scoped(
        initialPlayer: player,
        initialFilters: GamebaseFilters(
          playerIds: [id],
          selectedPlayers: [player],
          timeControls: timeControl == null ? const [] : [timeControl],
          playerColor: color,
        ),
        initialFen: initialFen,
        initialMoves: initialMoves,
      ),
    ),
  );
}
