import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/models/like_tag.dart';
import 'package:chessever2/screens/chessboard/utils/like_learning_prompt_tracker.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Resolves (and lazily creates) the per-user special "Liked Games" folder.
/// Identical mechanically to any user-created folder.
///
/// Keyed on the signed-in account. The provider is keep-alive, so without the
/// id a guest who signs in, or a sign out and in as someone else, would keep
/// reading and writing the previous account's folder.
final likedGamesFolderProvider = FutureProvider<LibraryFolder>((ref) async {
  // The key only. Whether there is a session to look the folder up for is the
  // repository's call: it asks the SDK, which still holds the session when
  // the app-level auth state has no user.
  ref.watch(_likedGamesAccountIdProvider);
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.ensureLikedGamesFolder();
});

/// The account the liked folder is resolved for: the signed-in user's id, held
/// through the moments the app-level auth state has no user.
///
/// No user there is not a sign-out. A token refresh that failed offline, a
/// sign-in sheet that is open, and a guest who backed out of one all leave the
/// session alive with the user missing, for up to a token lifetime. Following
/// the id to null would look the folder up again, blank every heart while it
/// answered (for good when offline) and reload the list over likes still being
/// saved. So the folder moves on only when another account's id arrives.
///
/// Only the id is selected: a token refresh or a profile edit hands out a new
/// user object for the same account, and changes nothing here.
final _likedGamesAccountIdProvider =
    NotifierProvider<_LikedGamesAccountId, String?>(_LikedGamesAccountId.new);

class _LikedGamesAccountId extends Notifier<String?> {
  @override
  String? build() {
    final id = ref.watch(currentUserProvider.select((user) => user?.id));
    // On a rebuild this still reads the id held before it.
    return id ?? stateOrNull;
  }

  @override
  bool updateShouldNotify(String? previous, String? next) => previous != next;
}

/// All saved analyses inside the user's "Liked Games" folder, newest-first.
/// Drives the heart fill state on the board and the in-folder list.
final likedGamesProvider =
    AsyncNotifierProvider<LikedGamesNotifier, List<SavedAnalysis>>(
      LikedGamesNotifier.new,
    );

/// Counts the like writes that have settled on the server: a like saved, an
/// unlike or a tag change landed, or a failed write rolled back and reloaded.
/// It never moves on an optimistic state change, so a list that refetches on
/// it reads what the server already holds. A plain counter, so watching it
/// does not create [LikedGamesNotifier].
final likedGamesWriteRevisionProvider = StateProvider<int>((ref) => 0);

/// Immediate per-game tag selection while the canonical liked row is being
/// created or updated. `null` means "use the saved row"; an empty list means
/// "explicitly cleared".
final likedGamePendingTagsProvider =
    StateProvider.family<List<String>?, String>((ref, likeId) => null);

/// Dynamic selected tags for a liked game. The pending value wins while a write
/// is in flight, so reopening UI surfaces shows the user's last tap immediately
/// instead of waiting on Supabase or a provider reload.
final likedGameTagsProvider = Provider.family<List<String>, String>((
  ref,
  likeId,
) {
  final pending = ref.watch(likedGamePendingTagsProvider(likeId));
  if (pending != null) return pending;

  final list = ref.watch(likedGamesProvider).valueOrNull;
  final analysis = list?.firstWhereOrNull((a) => a.sourceGameId == likeId);
  return analysis?.tags ?? const <String>[];
});

class LikedGamesNotifier extends AsyncNotifier<List<SavedAnalysis>> {
  LibraryRepository get _repo => ref.read(libraryRepositoryProvider);

  /// In-flight per-game-id toggle calls, so rapid re-taps don't race.
  final Set<String> _inFlight = <String>{};

  /// Per-likeId future for the currently-running toggle. A tag chosen in the
  /// post-like tag chip can fire before the optimistic liked row exists in
  /// `state` (the like's PGN resolve + insert is still running), so the tag
  /// write awaits this before looking for the row — otherwise it finds nothing
  /// and is silently dropped.
  final Map<String, Future<void>> _toggleOps = <String, Future<void>>{};

  /// Per-game tag writes are queued so rapid chip taps persist in order and the
  /// last visible selection is also the final server value.
  final Map<String, Future<bool>> _tagWriteChains = <String, Future<bool>>{};

  /// How often one reload reads the list while writes keep settling under it.
  static const int _maxReloadReads = 3;

  @override
  Future<List<SavedAnalysis>> build() async {
    // The in-flight bookkeeping above is not cleared here. This build runs
    // again when the account changes or a failed folder lookup is retried, and
    // the writes still out must keep their de-dupe and their tag queue. Each
    // entry removes itself when its write settles.

    // Games re-filed outside the like path (see [_onAnalysisMoved]).
    final moves = LibraryRepository.analysisMoves.listen(_onAnalysisMoved);
    ref.onDispose(moves.cancel);

    final folder = await ref.watch(likedGamesFolderProvider.future);
    final all = await _repo.getSavedAnalyses(folderId: folder.id);
    return all;
  }

  bool isLiked(String sourceGameId) {
    final list = state.valueOrNull;
    if (list == null) return false;
    return list.any((a) => a.sourceGameId == sourceGameId);
  }

  /// Optimistically likes/unlikes [game], using the same SavedAnalysis path
  /// as the "Add to library" flow. Returns the new state (`true` = now liked).
  /// Source-agnostic — works for broadcast, gamebase and twic games alike.
  ///
  /// Throws, with nothing written, when the liked list or its folder cannot
  /// be read, or when the folder is another account's. A write that fails
  /// after that is rolled back and answered with the state it left.
  ///
  /// A call made before the list was loaded waits for it and never unlikes:
  /// a game that turns out to be liked already is answered with `true`.
  Future<bool> toggle(GamesTourModel game) async {
    // Like identity is the original game (for saved-analysis games this is the
    // sourceGameId, not the synthetic `saved_analysis_<id>` gameId), so a game
    // liked here matches the same game opened from anywhere else.
    final likeId = game.likeId;
    if (!_inFlight.add(likeId)) {
      return isLiked(likeId);
    }

    // Publish this toggle's lifetime synchronously (before the first await) so a
    // tag write started while the like is mid-flight can wait for the liked row
    // to be created instead of racing ahead of the optimistic insert.
    final op = Completer<void>();
    _toggleOps[likeId] = op.future;

    try {
      // What this tap could see, read before the first await. Every heart
      // draws a list that is not loaded as "not liked", so a tap made then
      // asked for a like: waiting for the list and then toggling would delete
      // the like, its tags and its date, of a game the user just tried to
      // like. The exception is a list still held from before (the previous
      // account's, while the next one loads) that said "liked": that tap asked
      // for an unlike, and must not end up adding a like.
      final loaded = _listLoaded;
      final mayLike = loaded || !isLiked(likeId);
      // A like is never decided against a list that is not loaded: that reads
      // every game as "not liked", so it inserts a second row for a game
      // already liked and collapses the session list to that one game. A
      // failure here is thrown to the caller, nothing optimistic has happened
      // yet. With the list already there this adds no await.
      if (!loaded) await _loadList();
      final folder = await ref.read(likedGamesFolderProvider.future);
      // With no app-level user (see [_likedGamesAccountIdProvider]) the like
      // is written for the folder's own account. With no session at all the
      // repository refuses the write itself.
      final userId = ref.read(currentUserProvider)?.id ?? folder.userId;
      if (folder.userId != userId) {
        // The folder was resolved for another account (a sign-in mid-session).
        // Writing now would file this like in that account's folder.
        ref.invalidate(likedGamesFolderProvider);
        throw Exception('Liked folder belongs to another account');
      }
      return await _toggleLoaded(
        game,
        likeId: likeId,
        folder: folder,
        userId: userId,
        mayUnlike: loaded,
        mayLike: mayLike,
      );
    } finally {
      _inFlight.remove(likeId);
      if (identical(_toggleOps[likeId], op.future)) {
        _toggleOps.remove(likeId);
      }
      op.complete();
    }
  }

  /// The like or unlike itself, once the list is loaded and [folder] is known
  /// to be [userId]'s. Optimistic: a failed write is taken back, the list is
  /// reloaded, and the answer is the state that leaves.
  ///
  /// [mayUnlike] and [mayLike] hold a tap made on a list that was not loaded
  /// to what it could have meant: it never deletes a like, and it adds one
  /// only when the list it held did not already show the game as liked.
  Future<bool> _toggleLoaded(
    GamesTourModel game, {
    required String likeId,
    required LibraryFolder folder,
    required String userId,
    required bool mayUnlike,
    required bool mayLike,
  }) async {
    SavedAnalysis? unliked;
    var unlikedAt = 0;
    try {
      final list = List<SavedAnalysis>.from(state.requireValue);
      final existing = list.firstWhereOrNull((a) => a.sourceGameId == likeId);

      if (existing != null) {
        // Its row has no id yet: another toggle is still saving this like, and
        // there is nothing on the server to delete. Or the tap asked for a
        // like on a list that could not show this one: it is liked, as asked.
        if (existing.id.isEmpty || !mayUnlike) return true;
        // OPTIMISTIC unlike
        unliked = existing;
        unlikedAt = list.indexOf(existing);
        list.removeWhere((a) => a.id == existing.id);
        state = AsyncValue.data(list);
        // Scoped to the liked folder: a row since moved into a database is no
        // longer a like, and an unlike must not delete it there.
        await _repo.deleteSavedAnalysis(existing.id, folderId: folder.id);
        // A list read that was out during the delete may have put the row back.
        _dropRow(existing.id);
        _serverChanged();
        return false;
      }

      // The tap saw a like in a list that has since been replaced, and asked
      // to remove it. There is none to remove, and none is added.
      if (!mayLike) return false;

      final chessGame = await _resolveChessGame(game);
      final now = DateTime.now();
      final analysis = SavedAnalysis(
        id: '',
        userId: userId,
        folderId: folder.id,
        title: '${game.whitePlayer.name} vs ${game.blackPlayer.name}',
        sourceGameId: likeId,
        sourceTournamentId: game.tourId,
        chessGame: chessGame,
        analysisState: const {},
        variationComments: const {},
        lastViewedPosition: -1,
        tags: const [],
        notes: null,
        isFavorite: false,
        createdAt: now,
        updatedAt: now,
      );

      // The PGN resolve can be a network round trip, and another like may have
      // landed during it. Insert into the list as it is now, not into the copy
      // taken before the wait, or that other like is dropped from the list.
      final current = state.requireValue;
      if (current.any((a) => a.sourceGameId == likeId)) return true;

      // OPTIMISTIC insert with a placeholder id; will be reconciled on reload.
      state = AsyncValue.data([analysis, ...current]);

      final created = await _repo.createSavedAnalysis(analysis);
      final localTags =
          (state.valueOrNull ?? const <SavedAnalysis>[])
              .firstWhereOrNull((a) => a.id.isEmpty && a.sourceGameId == likeId)
              ?.tags;
      final displayCreated =
          localTags != null && localTags.isNotEmpty
              ? created.copyWith(tags: localTags)
              : created;
      final reconciled =
          List<SavedAnalysis>.from(state.valueOrNull ?? const [])
            ..removeWhere(
              (a) =>
                  (a.id.isEmpty && a.sourceGameId == likeId) ||
                  a.id == created.id,
            )
            ..insert(0, displayCreated);
      state = AsyncValue.data(reconciled);
      _serverChanged();
      try {
        await ref
            .read(likeLearningPromptTrackerProvider)
            .recordLike(userId: userId);
      } catch (error) {
        // Liking is the primary action. A local reminder-cadence write must
        // never roll back or report failure for a successfully saved like.
        debugPrint('[LikedGames] like reminder cadence reset failed: $error');
      }
      return true;
    } catch (e) {
      debugPrint('[LikedGames] toggle failed: $e');
      // Take the optimistic change back before reloading: a reload that fails
      // too keeps the list it has, and that list must not show a like that was
      // never saved or hide one that was never deleted.
      _undoOptimistic(unsavedLikeId: likeId, undeleted: unliked, at: unlikedAt);
      await _reload();
      _serverChanged();
      return isLiked(likeId);
    }
  }

  /// Whether the list is loaded and settled. A load in flight, or one that
  /// failed, can still expose the last list it had (the previous account's
  /// right after a sign-in), which is not a list to decide a like against.
  bool get _listLoaded => state.hasValue && !state.isLoading && !state.hasError;

  /// Tells the lists that follow the server that a like write has settled
  /// there. See [likedGamesWriteRevisionProvider].
  void _serverChanged() =>
      ref.read(likedGamesWriteRevisionProvider.notifier).state++;

  /// Waits for a list that is not loaded: for the load in flight, then for one
  /// reload when that load (or an earlier one) failed. Throws what kept it
  /// from loading, so "not loaded" is never read as "no likes".
  Future<void> _loadList() async {
    if (state.isLoading) {
      try {
        await future;
      } catch (_) {
        // Falls through to the one reload below.
      }
    }
    if (!_listLoaded) await _reload();
    if (_listLoaded) return;
    final error = state.error;
    if (error != null) {
      Error.throwWithStackTrace(error, state.stackTrace ?? StackTrace.current);
    }
    throw StateError('Liked games are not loaded');
  }

  /// Takes the row [analysisId] out of a loaded list. Returns whether it was
  /// there.
  bool _dropRow(String analysisId) {
    if (!_listLoaded) return false;
    final current = state.requireValue;
    if (!current.any((a) => a.id == analysisId)) return false;
    state = AsyncValue.data([
      for (final analysis in current)
        if (analysis.id != analysisId) analysis,
    ]);
    return true;
  }

  /// A saved game was re-filed outside the like path: "Move to database" from
  /// a card menu, or the Undo of that move. The sheet that made the move is
  /// closed by the time its Undo runs, so this does not rely on any screen
  /// reporting back.
  void _onAnalysisMoved(SavedAnalysisMove move) {
    final folder = ref.read(likedGamesFolderProvider).valueOrNull;
    if (folder == null) return;
    if (move.folderId == folder.id) {
      // Back in the liked folder: a like again, and this list has no row to
      // show for it. Left out, its heart would read empty and a tap would save
      // the game a second time.
      _serverChanged();
      unawaited(_reload());
      return;
    }
    // Out of the liked folder: no longer a like.
    if (_dropRow(move.analysisId)) _serverChanged();
  }

  /// Undoes an optimistic change in the list as it is now: drops the id-less
  /// placeholder of the like [unsavedLikeId] when it was not saved, and puts
  /// [undeleted] back at [at] when its delete did not go through.
  void _undoOptimistic({
    String? unsavedLikeId,
    SavedAnalysis? undeleted,
    int at = 0,
  }) {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = List<SavedAnalysis>.from(current);
    if (unsavedLikeId != null) {
      next.removeWhere((a) => a.id.isEmpty && a.sourceGameId == unsavedLikeId);
    }
    var changed = next.length != current.length;
    if (undeleted != null && !next.any((a) => a.id == undeleted.id)) {
      next.insert(at > next.length ? next.length : at, undeleted);
      changed = true;
    }
    if (changed) state = AsyncValue.data(next);
  }

  /// Mirrors the resolution used by `add_to_folder_sheet.dart` so a liked
  /// game saves with full PGN + display metadata, identical to the manual
  /// "Add to library" flow.
  Future<ChessGame> _resolveChessGame(GamesTourModel game) async {
    String? pgn = game.pgn;
    final hasMoves = pgn != null && pgnHasMoves(pgn);

    if (!hasMoves) {
      try {
        final supabasePgn = await ref
            .read(gameRepositoryProvider)
            .getGamePgn(game.gameId);
        if (supabasePgn != null && pgnHasMoves(supabasePgn)) {
          pgn = supabasePgn;
        }
      } catch (_) {}

      if (pgn == null || !pgnHasMoves(pgn)) {
        final fullGame = await ref
            .read(gamebaseRepositoryProvider)
            .getGameWithPgn(game.gameId);
        if (fullGame != null) {
          if (fullGame.pgn != null && pgnHasMoves(fullGame.pgn!)) {
            pgn = fullGame.pgn;
          } else if (fullGame.data != null) {
            final builtPgn = buildPgnFromGamebaseData(fullGame.data);
            if (builtPgn != null && pgnHasMoves(builtPgn)) {
              pgn = builtPgn;
            }
          }
        }
      }
    }

    if (pgn == null || pgn.trim().isEmpty) {
      throw Exception('Game PGN not found');
    }

    final chessGame = ChessGame.fromPgn(game.gameId, pgn);
    final meta = Map<String, dynamic>.from(chessGame.metadata);

    meta['White'] = game.whitePlayer.name;
    meta['Black'] = game.blackPlayer.name;

    final whiteFed =
        game.whitePlayer.countryCode.isNotEmpty
            ? game.whitePlayer.countryCode
            : game.whitePlayer.federation;
    final blackFed =
        game.blackPlayer.countryCode.isNotEmpty
            ? game.blackPlayer.countryCode
            : game.blackPlayer.federation;
    if (whiteFed.isNotEmpty) meta['WhiteFed'] = whiteFed;
    if (blackFed.isNotEmpty) meta['BlackFed'] = blackFed;
    if (game.whitePlayer.title.isNotEmpty) {
      meta['WhiteTitle'] = game.whitePlayer.title;
    }
    if (game.blackPlayer.title.isNotEmpty) {
      meta['BlackTitle'] = game.blackPlayer.title;
    }
    if (game.whitePlayer.rating > 0) {
      meta['WhiteElo'] = game.whitePlayer.rating.toString();
    }
    if (game.blackPlayer.rating > 0) {
      meta['BlackElo'] = game.blackPlayer.rating.toString();
    }
    // Persist FIDE ids so the games-tab color filter can identify each side —
    // broadcast/gamebase PGNs often omit these headers, so write them from the
    // live game rather than relying on ChessGame.fromPgn to carry them.
    if (game.whitePlayer.fideId != null) {
      meta['WhiteFideId'] = game.whitePlayer.fideId.toString();
    }
    if (game.blackPlayer.fideId != null) {
      meta['BlackFideId'] = game.blackPlayer.fideId.toString();
    }
    if (game.eco != null && game.eco!.isNotEmpty) {
      meta['ECO'] = game.eco!;
    }
    if (game.openingName != null && game.openingName!.isNotEmpty) {
      meta['Opening'] = game.openingName!;
    }
    if (game.tourSlug != null && game.tourSlug!.isNotEmpty) {
      meta.putIfAbsent('Event', () => game.tourSlug!);
    }

    // Persist the filter-relevant fields the raw PGN headers don't carry, so
    // "My Likes" can reproduce the Favorites → Games tab filters. The broadcast
    // time-control category ('standard'/'rapid'/'blitz') is distinct from the
    // PGN `TimeControl` increment string, which the time-control filter can't
    // interpret. Stored as strings to stay PGN-export safe.
    if (game.timeControl != null && game.timeControl!.isNotEmpty) {
      meta['TcCategory'] = game.timeControl!;
    }
    meta['IsOnline'] = game.isOnline ? 'true' : 'false';

    return chessGame.copyWith(metadata: meta);
  }

  /// Removes a specific liked game by its saved-analysis id (used by the
  /// My Likes list's swipe-to-unlike, which acts on a SavedAnalysis rather
  /// than a GamesTourModel). Optimistic; reloads and returns `false` on failure
  /// so the caller can surface the error.
  Future<bool> removeAnalysis(SavedAnalysis analysis) async {
    // Same rule as [toggle]: the list is only edited once it is loaded, or one
    // removal would replace it with an empty one. With the list already there
    // this adds no await.
    if (!_listLoaded) {
      try {
        await _loadList();
      } catch (e) {
        debugPrint('[LikedGames] removeAnalysis failed: $e');
        return false;
      }
    }
    final list = List<SavedAnalysis>.from(state.requireValue);
    final at = list.indexWhere((a) => a.id == analysis.id);
    final removed = at == -1 ? null : list[at];
    list.removeWhere((a) => a.id == analysis.id);
    state = AsyncValue.data(list);
    try {
      // Scoped to the liked folder, like the unlike in [toggle]: a card left on
      // screen after its game was moved to a database must not delete it there.
      final folder = await ref.read(likedGamesFolderProvider.future);
      await _repo.deleteSavedAnalysis(analysis.id, folderId: folder.id);
      _dropRow(analysis.id);
      _serverChanged();
      return true;
    } catch (e) {
      debugPrint('[LikedGames] removeAnalysis failed: $e');
      _undoOptimistic(undeleted: removed, at: at == -1 ? 0 : at);
      await _reload();
      _serverChanged();
      return false;
    }
  }

  /// Sets the classification [tags] on the liked game identified by [likeId]
  /// (its `sourceGameId`). Additive — only touches the existing `tags` column,
  /// nothing else about the saved analysis changes.
  ///
  /// Called moments after a like, so the persisted row may not exist yet (the
  /// optimistic insert still carries a placeholder id while the create POST is
  /// in flight). We briefly wait for a row with a real id before writing, so
  /// the tag lands on the server record and survives the toggle's reconcile.
  /// No-op if the game isn't (or stops being) liked.
  Future<bool> setTagsForLikeId(String likeId, List<String> tags) {
    final normalized = _normalizeTags(tags);
    ref.read(likedGamePendingTagsProvider(likeId).notifier).state = normalized;
    _applyOptimisticTags(likeId, normalized);

    final previous = _tagWriteChains[likeId] ?? Future<bool>.value(true);
    final write = previous
        .catchError((Object _, StackTrace __) => false)
        .then((_) => _persistTagsForLikeId(likeId, normalized));

    _tagWriteChains[likeId] = write;
    unawaited(
      write.whenComplete(() {
        if (identical(_tagWriteChains[likeId], write)) {
          _tagWriteChains.remove(likeId);
        }
      }),
    );
    return write;
  }

  Future<bool> _persistTagsForLikeId(String likeId, List<String> tags) async {
    final target = await _waitForPersistedLike(likeId);
    if (target == null) {
      ref.read(likedGamePendingTagsProvider(likeId).notifier).state = null;
      return false;
    }

    try {
      final updated = await _repo.updateSavedAnalysisTags(
        analysisId: target.id,
        tags: tags,
      );
      _replaceAnalysis(updated);
      _serverChanged();
      ref.read(likedGamePendingTagsProvider(likeId).notifier).state = null;
      return true;
    } catch (e) {
      debugPrint('[LikedGames] setTagsForLikeId failed: $e');
      await _reload();
      ref.read(likedGamePendingTagsProvider(likeId).notifier).state = null;
      return false;
    }
  }

  Future<SavedAnalysis?> _waitForPersistedLike(String likeId) async {
    // A like for this game may still be in flight — its row gets inserted only
    // after a (possibly networked) PGN resolve. Wait for that toggle to settle
    // so the persisted row, with a real id, exists before we try to tag it.
    // Without this the early `!anyMatch` bail below fires and the tag is lost.
    final inFlightToggle = _toggleOps[likeId];
    if (inFlightToggle != null) {
      try {
        await inFlightToggle;
      } catch (_) {}
    }

    for (var attempt = 0; attempt < 12; attempt++) {
      final current = state.valueOrNull;
      if (current == null) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }

      final target = current.firstWhereOrNull(
        (a) => a.sourceGameId == likeId && a.id.isNotEmpty,
      );
      if (target != null) return target;
      // If the game isn't liked at all (no matching id-less placeholder
      // either), there's nothing to tag — bail out early.
      final anyMatch = current.any((a) => a.sourceGameId == likeId);
      if (!anyMatch) return null;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    return (state.valueOrNull ?? const <SavedAnalysis>[]).firstWhereOrNull(
      (a) => a.sourceGameId == likeId && a.id.isNotEmpty,
    );
  }

  List<String> _normalizeTags(Iterable<String> tags) {
    return normalizeLikeTagLabels(tags);
  }

  bool _applyOptimisticTags(String likeId, List<String> tags) {
    final list = state.valueOrNull;
    if (list == null) return false;

    var changed = false;
    final now = DateTime.now();
    final updated = <SavedAnalysis>[
      for (final analysis in list)
        if (analysis.sourceGameId == likeId)
          () {
            changed = true;
            return analysis.copyWith(tags: tags, updatedAt: now);
          }()
        else
          analysis,
    ];
    if (changed) {
      state = AsyncValue.data(updated);
    }
    return changed;
  }

  void _replaceAnalysis(SavedAnalysis updated) {
    final list = state.valueOrNull;
    if (list == null) return;
    state = AsyncValue.data([
      for (final analysis in list)
        analysis.id == updated.id ? updated : analysis,
    ]);
  }

  Future<void> _reload() async {
    // The folder provider is keep-alive, so a lookup that failed once (offline
    // at cold start, say) would be re-read as the same error for the whole app
    // run. Drop it so this reload asks again.
    var folderLookup = ref.read(likedGamesFolderProvider);
    if (folderLookup.hasError && !folderLookup.isLoading) {
      ref.invalidate(likedGamesFolderProvider);
      folderLookup = ref.read(likedGamesFolderProvider);
    }
    if (folderLookup.isLoading) {
      // This notifier rebuilds with its folder and fetches the list once the
      // folder is known: that build is the reload.
      try {
        await future;
      } catch (e) {
        debugPrint('[LikedGames] reload failed: $e');
      }
      return;
    }

    AsyncValue<List<SavedAnalysis>> next;
    var reads = 0;
    int revision;
    do {
      revision = ref.read(likedGamesWriteRevisionProvider);
      next = await AsyncValue.guard(() async {
        final folder = await ref.read(likedGamesFolderProvider.future);
        return _repo.getSavedAnalyses(folderId: folder.id);
      });
      // A write that settled while this read was out is not in it: assigning
      // it would drop a like just saved, and the next tap would save the game
      // twice. Read again, a bounded number of times.
    } while (++reads < _maxReloadReads &&
        !next.hasError &&
        revision != ref.read(likedGamesWriteRevisionProvider));
    // A refetch that fails keeps the list already held: replacing it with an
    // error would blank every heart and the My Space tally over one bad
    // request.
    if (next.hasError && state.hasValue) {
      debugPrint('[LikedGames] reload failed, list kept: ${next.error}');
      return;
    }
    state = next;
  }

  Future<void> refresh() => _reload();
}

/// Reactive check for whether a specific game is liked (by sourceGameId).
final isGameLikedProvider = Provider.family<bool, String>((ref, gameId) {
  final async = ref.watch(likedGamesProvider);
  return async.maybeWhen(
    data: (list) => list.any((a) => a.sourceGameId == gameId),
    orElse: () => false,
  );
});

extension _FirstWhereOrNull<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
