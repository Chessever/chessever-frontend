import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Resolves (and lazily creates) the per-user special "Liked Games" folder.
/// Identical mechanically to any user-created folder.
final likedGamesFolderProvider = FutureProvider<LibraryFolder>((ref) async {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.ensureLikedGamesFolder();
});

/// All saved analyses inside the user's "Liked Games" folder, newest-first.
/// Drives the heart fill state on the board and the in-folder list.
final likedGamesProvider =
    AsyncNotifierProvider<LikedGamesNotifier, List<SavedAnalysis>>(
      LikedGamesNotifier.new,
    );

class LikedGamesNotifier extends AsyncNotifier<List<SavedAnalysis>> {
  LibraryRepository get _repo => ref.read(libraryRepositoryProvider);

  /// In-flight per-game-id toggle calls, so rapid re-taps don't race.
  final Set<String> _inFlight = <String>{};

  @override
  Future<List<SavedAnalysis>> build() async {
    ref.onDispose(_inFlight.clear);
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
  Future<bool> toggle(GamesTourModel game) async {
    // Like identity is the original game (for saved-analysis games this is the
    // sourceGameId, not the synthetic `saved_analysis_<id>` gameId), so a game
    // liked here matches the same game opened from anywhere else.
    final likeId = game.likeId;
    if (!_inFlight.add(likeId)) {
      return isLiked(likeId);
    }

    try {
      final folder = await ref.read(likedGamesFolderProvider.future);
      final list = List<SavedAnalysis>.from(state.valueOrNull ?? const []);
      final existing = list.firstWhereOrNull(
        (a) => a.sourceGameId == likeId,
      );

      if (existing != null) {
        // OPTIMISTIC unlike
        list.removeWhere((a) => a.id == existing.id);
        state = AsyncValue.data(list);
        await _repo.deleteSavedAnalysis(existing.id);
        return false;
      }

      final userId = ref.read(currentUserProvider)?.id;
      if (userId == null) throw Exception('User not authenticated');

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

      // OPTIMISTIC insert with a placeholder id; will be reconciled on reload.
      list.insert(0, analysis);
      state = AsyncValue.data(list);

      final created = await _repo.createSavedAnalysis(analysis);
      final reconciled =
          List<SavedAnalysis>.from(state.valueOrNull ?? const [])
            ..removeWhere((a) => a.id.isEmpty && a.sourceGameId == likeId)
            ..insert(0, created);
      state = AsyncValue.data(reconciled);
      return true;
    } catch (e) {
      debugPrint('[LikedGames] toggle failed: $e');
      await _reload();
      return isLiked(likeId);
    } finally {
      _inFlight.remove(likeId);
    }
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
    final list = List<SavedAnalysis>.from(state.valueOrNull ?? const [])
      ..removeWhere((a) => a.id == analysis.id);
    state = AsyncValue.data(list);
    try {
      await _repo.deleteSavedAnalysis(analysis.id);
      return true;
    } catch (e) {
      debugPrint('[LikedGames] removeAnalysis failed: $e');
      await _reload();
      return false;
    }
  }

  Future<void> _reload() async {
    state = await AsyncValue.guard(() async {
      final folder = await ref.read(likedGamesFolderProvider.future);
      return _repo.getSavedAnalyses(folderId: folder.id);
    });
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
