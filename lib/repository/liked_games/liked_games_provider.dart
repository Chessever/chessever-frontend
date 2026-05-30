import 'dart:async';

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
import 'package:supabase_flutter/supabase_flutter.dart';

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
  SupabaseClient get _supabase => Supabase.instance.client;

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
    final folder = await ref.read(likedGamesFolderProvider.future);
    final list = List<SavedAnalysis>.from(state.valueOrNull ?? const []);
    final existing = list.firstWhereOrNull(
      (a) => a.sourceGameId == game.gameId,
    );

    if (existing != null) {
      // OPTIMISTIC unlike
      list.removeWhere((a) => a.id == existing.id);
      state = AsyncValue.data(list);
      try {
        await _repo.deleteSavedAnalysis(existing.id);
      } catch (e) {
        debugPrint('[LikedGames] unlike failed: $e');
        await _reload();
      }
      return false;
    }

    // Guard against rapid double-fire on the same gameId.
    if (!_inFlight.add(game.gameId)) return true;
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final chessGame = await _resolveChessGame(game);
      final now = DateTime.now();
      final analysis = SavedAnalysis(
        id: '',
        userId: userId,
        folderId: folder.id,
        title: '${game.whitePlayer.name} vs ${game.blackPlayer.name}',
        sourceGameId: game.gameId,
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
      final reconciled = List<SavedAnalysis>.from(state.valueOrNull ?? const [])
        ..removeWhere((a) => a.id.isEmpty && a.sourceGameId == game.gameId)
        ..insert(0, created);
      state = AsyncValue.data(reconciled);
      return true;
    } catch (e) {
      debugPrint('[LikedGames] like failed: $e');
      await _reload();
      return false;
    } finally {
      _inFlight.remove(game.gameId);
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
    if (game.eco != null && game.eco!.isNotEmpty) {
      meta['ECO'] = game.eco!;
    }
    if (game.openingName != null && game.openingName!.isNotEmpty) {
      meta['Opening'] = game.openingName!;
    }
    if (game.tourSlug != null && game.tourSlug!.isNotEmpty) {
      meta.putIfAbsent('Event', () => game.tourSlug!);
    }

    return chessGame.copyWith(metadata: meta);
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
