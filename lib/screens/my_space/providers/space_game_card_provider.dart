import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/library/utils/gamebase_game_to_games_tour_model.dart';
import 'package:chessever2/screens/my_space/models/space_game_card.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/live_game_position_resolver.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Which game a game shortcut points at, as a family key: its id, whether it
/// lives in Gamebase, and the saved copy it opens, if any.
typedef SpaceGameRef = ({String targetId, bool gamebase, String? analysisId});

SpaceGameRef spaceGameRefOf(SpaceShortcut s) => (
  targetId: s.targetId,
  gamebase: s.params['source'] == 'gamebase',
  analysisId: spaceGameAnalysisId(s),
);

/// How long a looked-up game outlives the last tile showing it, so scrolling
/// a rail back and forth or reopening My Space never looks it up again.
const Duration kSpaceGameKeepWarm = Duration(minutes: 2);

const Duration _kLookupTimeout = Duration(seconds: 12);

/// Gamebase and Supabase game ids are uuids; Lichess short ids are not. Gates
/// the Gamebase retry after a Supabase miss, like a shared game link does.
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Broadcast rows a batch reads per request; keeps the `in` filter's URL
/// well under PostgREST's limit however many games a user pins.
const int _kBatchChunk = 100;

/// The `games` columns a tile needs, [GameRepository]'s preview projection:
/// no `pgn`. The final position rides in `fen` and `last_move`, and the
/// clocks in `last_clock_*`, so a pin never downloads (or replays) a whole
/// game to draw one board.
@visibleForTesting
const String kSpaceGameColumns = '''
          id,
          round_id,
          round_slug,
          tour_id,
          tour_slug,
          name,
          fen,
          players,
          last_move,
          think_time,
          status,
          lichess_id,
          player_white,
          player_black,
          date_start,
          time_start,
          board_nr,
          last_move_time,
          game_day,
          last_clock_white,
          last_clock_black,
          eco,
          opening_name,
          tours!games_tour_id_fkey(
            avg_elo,
            tc:info->>tc,
            group_broadcasts!tours_group_broadcast_id_fkey(time_control)
          )
        ''';

/// Which column an id is read by, as [GameRepository.getGameByAnyId] routes
/// it: a uuid, a namespaced id or a ChessEver Direct id is a `games.id`;
/// anything else is a Lichess short id. Keep the three patterns in step.
final _canonicalGameId = [
  _uuid,
  RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*:[^\s/?#]+$'),
  RegExp(r'^[A-Za-z0-9]{8}-[A-Za-z0-9]+$'),
];

/// Reads broadcast games by id (or Lichess id) without their PGN.
typedef SpaceGameRowsReader = Future<List<Games>> Function(List<String> ids);

/// The one read behind every batch: one request per column an id is looked
/// up by (almost always just `games.id`), [_kBatchChunk] ids at a time.
final spaceGameRowsReaderProvider = Provider.autoDispose<SpaceGameRowsReader>((
  ref,
) {
  final repo = ref.watch(gameRepositoryProvider);
  return (ids) => repo.handleApiCall(() async {
    final byId = <String>[];
    final byLichess = <String>[];
    for (final id in ids) {
      (_canonicalGameId.any((p) => p.hasMatch(id)) ? byId : byLichess).add(id);
    }
    Future<List<Games>> read(String column, List<String> values) async {
      final out = <Games>[];
      for (var i = 0; i < values.length; i += _kBatchChunk) {
        final rows = await repo.supabase
            .from('games')
            .select(kSpaceGameColumns)
            .inFilter(
              column,
              values.sublist(i, math.min(i + _kBatchChunk, values.length)),
            );
        for (final row in rows as List) {
          out.add(Games.fromJson(Map<String, dynamic>.from(row as Map)));
        }
      }
      return out;
    }

    final parts = await Future.wait([
      read('id', byId),
      read('lichess_id', byLichess),
    ]);
    return [...parts[0], ...parts[1]];
  });
});

/// The broadcast games one read covers, as a family key: sorted and
/// deduplicated, so the same set is the same batch.
@immutable
class SpaceGameBatch {
  SpaceGameBatch(Iterable<String> ids)
    : ids = List.unmodifiable(ids.toSet().toList()..sort());

  final List<String> ids;

  @override
  bool operator ==(Object other) =>
      other is SpaceGameBatch &&
      const ListEquality<String>().equals(ids, other.ids);

  @override
  int get hashCode => Object.hashAll(ids);

  @override
  String toString() => 'SpaceGameBatch(${ids.length})';
}

/// Which live batch covers each broadcast game id, so a tile mounting after
/// its rail (scrolled in, or a rail further down) reads the batch that
/// already holds its game instead of starting another. Entries leave with
/// their batch, or when its read fails, so the next tile tries again.
final _spaceGameBatchIndexProvider = Provider<Map<String, SpaceGameBatch>>(
  (ref) => <String, SpaceGameBatch>{},
);

/// One read for a set of pinned broadcast games, keyed by id and by Lichess
/// id. Each tile's [spaceGameCardProvider] reads its game from here; the
/// first tile to look one up gathers every pin still waiting on a lookup
/// into the batch, so a whole My Space costs one request.
final spaceGameBatchProvider = FutureProvider.autoDispose
    .family<Map<String, Games>, SpaceGameBatch>((ref, batch) async {
      final read = ref.watch(spaceGameRowsReaderProvider);
      final index = ref.read(_spaceGameBatchIndexProvider);
      for (final id in batch.ids) {
        index[id] = batch;
      }
      void release() => index.removeWhere((_, b) => b == batch);
      ref.onDispose(release);
      try {
        final rows = await read(batch.ids);
        return {
          for (final row in rows) ...{
            row.id: row,
            if (row.lichessId?.trim() case final lichess?
                when lichess.isNotEmpty)
              lichess: row,
          },
        };
      } catch (_) {
        release();
        rethrow;
      }
    });

/// The id a game pin is read by in a batch, or null when it is not read from
/// the broadcast table (a Gamebase game, a saved copy, an analysis only).
String? _batchId(SpaceGameRef key) {
  if (key.gamebase || key.analysisId != null) return null;
  final id = key.targetId.trim();
  if (id.isEmpty || id.startsWith('analysis:')) return null;
  return id;
}

/// The batch [key]'s game is read in: the live batch that already covers it,
/// or a new one with every pin My Space still has to look up and no batch
/// covers yet. The pins are read, not watched: a pin taking its snapshot
/// must not send its neighbours to a new batch.
Future<Map<String, Games>>? _watchBatch(Ref ref, SpaceGameRef key) {
  final id = _batchId(key);
  if (id == null) return null;
  final index = ref.read(_spaceGameBatchIndexProvider);
  var batch = index[id];
  if (batch == null) {
    final ids = <String>{id};
    final pins = ref.exists(spaceShortcutsProvider)
        ? ref.read(spaceShortcutsProvider).valueOrNull
        : null;
    for (final s in pins ?? const <SpaceShortcut>[]) {
      if (s.kind != SpaceShortcutKind.game || !spaceGameCardNeedsFetch(s)) {
        continue;
      }
      final other = _batchId(spaceGameRefOf(s));
      if (other != null && !index.containsKey(other)) ids.add(other);
    }
    batch = SpaceGameBatch(ids);
  }
  return ref.watch(spaceGameBatchProvider(batch).future);
}

/// Keeps an autoDispose read for [kSpaceGameKeepWarm] after its last listener
/// leaves. Returns a closer for a miss: a game that did not resolve is never
/// kept, so the next tile to show it tries again.
void Function() _keepWarm(Ref<Object?> ref) {
  final link = ref.keepAlive();
  Timer? release;
  ref.onCancel(() {
    release?.cancel();
    release = Timer(kSpaceGameKeepWarm, link.close);
  });
  ref.onResume(() {
    release?.cancel();
    release = null;
  });
  ref.onDispose(() => release?.cancel());
  return link.close;
}

/// The game behind a game shortcut, as the app's game card models it,
/// looked up the way opening the shortcut resolves it: a saved copy from My
/// Likes (or the library), a Gamebase game, or a broadcast game (with the
/// Gamebase fallback for a uuid Supabase does not know). A broadcast game
/// comes from its [spaceGameBatchProvider] read, without its PGN. Null when
/// it cannot be found or the lookup fails; it never throws to a tile.
final spaceGameCardProvider = FutureProvider.autoDispose
    .family<GamesTourModel?, SpaceGameRef>((ref, key) async {
      final close = _keepWarm(ref);
      final batch = _watchBatch(ref, key);
      GamesTourModel? found;
      try {
        found = await _resolve(ref, key, batch).timeout(_kLookupTimeout);
      } catch (e) {
        debugPrint('[MySpace] game ${key.targetId} not resolved: $e');
      }
      if (found == null) {
        close();
        return null;
      }
      final game = spaceGameAtFinalPosition(found);
      _storeCard(ref, key, game);
      return game;
    });

/// Stores a looked-up [game] on its pin as the card snapshot when the pin has
/// none, or stored the game while it was still being played and it has since
/// finished. The tile then draws it from the pin, flags and ratings included,
/// on every later open instead of looking it up again. Only while My Space
/// holds its pins.
void _storeCard(Ref ref, SpaceGameRef key, GamesTourModel game) {
  if (!ref.exists(spaceShortcutsProvider)) return;
  final pin = ref
      .read(spaceShortcutsProvider)
      .valueOrNull
      ?.firstWhereOrNull(
        (s) => s.kind == SpaceShortcutKind.game && spaceGameRefOf(s) == key,
      );
  if (pin == null) return;
  final worth =
      !spaceGameHasCard(pin) ||
      (spaceGameCardNeedsFetch(pin) && game.gameStatus.isFinished);
  if (!worth) return;
  unawaited(
    ref
        .read(spaceShortcutsProvider.notifier)
        .mergeParams(pin.key, spaceGameCardParams(game)),
  );
}

Future<GamesTourModel?> _resolve(
  Ref ref,
  SpaceGameRef key,
  Future<Map<String, Games>>? batch,
) async {
  final analysisId = key.analysisId;
  if (analysisId != null) {
    final held = ref
        .read(likedGamesProvider)
        .valueOrNull
        ?.firstWhereOrNull((a) => a.id == analysisId);
    if (held != null) return spaceGameFromAnalysis(held);
    try {
      final saved = await ref
          .read(libraryRepositoryProvider)
          .getSavedAnalysis(analysisId);
      if (saved != null) return spaceGameFromAnalysis(saved);
    } catch (e) {
      debugPrint('[MySpace] saved game $analysisId not read: $e');
    }
  }

  final id = key.targetId.trim();
  if (id.isEmpty || id.startsWith('analysis:')) return null;
  if (key.gamebase) return _gamebase(ref, id);
  Games? row;
  try {
    row = batch != null
        ? (await batch)[id]
        // A saved copy that is gone falls back to the game it was saved
        // from, on its own: that is rare, and its pin is in no batch.
        : (await ref.read(spaceGameRowsReaderProvider)([id])).firstOrNull;
  } catch (_) {
    if (!_uuid.hasMatch(id)) rethrow;
  }
  if (row != null) return GamesTourModel.fromGame(row);
  return _uuid.hasMatch(id) ? _gamebase(ref, id) : null;
}

Future<GamesTourModel?> _gamebase(Ref ref, String id) async {
  final game = await ref.read(gamebaseRepositoryProvider).getGameById(id);
  return game == null ? null : mapGamebaseGameToGamesTourModel(game);
}

/// [game] at its last position, as the grid card resolves it: the freshest of
/// its FEN and its PGN's end, and the last move from the PGN when the row
/// carries none (Gamebase games arrive with moves only).
GamesTourModel spaceGameAtFinalPosition(GamesTourModel game) {
  final fen = resolveFreshestGameFen(
    fen: game.fen,
    pgn: game.pgn,
    lastMove: game.lastMove,
  );
  final hasLastMove = game.lastMove?.trim().isNotEmpty ?? false;
  final lastMove = hasLastMove
      ? game.lastMove
      : resolveFinalPositionFromPgn(game.pgn)?.lastMoveUci;
  if (fen == game.fen && lastMove == game.lastMove) return game;
  return game.copyWith(fen: fen, lastMove: lastMove);
}

/// How much of a game a My Space tile knows about its players.
enum SpaceGamePlayers {
  /// The card's players: from the pin's snapshot, or the looked-up game.
  ready,

  /// A pin with no snapshot whose game is still being looked up; only the
  /// pinned names are known.
  loading,

  /// A pin with no snapshot whose game could not be found; the pinned names
  /// are all there is.
  missing,
}

/// The game a My Space tile draws for [s], and how much it knows of the
/// players ([SpaceGamePlayers]): its stored card snapshot, or, when it has
/// none or the game was live when it was stored, the looked-up game once it
/// arrives (the snapshot, or the names alone, until then).
({GamesTourModel game, SpaceGamePlayers players}) watchSpaceGameFace(
  WidgetRef ref,
  SpaceShortcut s,
) {
  final seed = spaceGameCardSeed(s);
  if (!spaceGameCardNeedsFetch(s)) {
    return (game: seed, players: SpaceGamePlayers.ready);
  }
  final lookup = ref.watch(spaceGameCardProvider(spaceGameRefOf(s)));
  final found = lookup.valueOrNull;
  if (found == null) {
    return (
      game: seed,
      players: spaceGameHasCard(s)
          ? SpaceGamePlayers.ready
          : lookup.isLoading
          ? SpaceGamePlayers.loading
          : SpaceGamePlayers.missing,
    );
  }
  // Keep the pinned position when the lookup came back without one.
  final hasFen = found.fen?.trim().isNotEmpty ?? false;
  return (
    game: hasFen || seed.fen == null ? found : found.copyWith(fen: seed.fen),
    players: SpaceGamePlayers.ready,
  );
}
