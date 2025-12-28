import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gameCardWrapperProvider = AutoDisposeProvider<_GameCardWrapperProvider>((
  ref,
) {
  return _GameCardWrapperProvider(ref);
});

class _ResolvedNavigation {
  final List<GamesTourModel> games;
  final int index;

  const _ResolvedNavigation({required this.games, required this.index});
}

class _GameCardWrapperProvider {
  _GameCardWrapperProvider(this._ref);

  final Ref _ref;

  Future<_ResolvedNavigation> _resolveNavigationGames({
    required List<GamesTourModel> orderedGames,
    required int gameIndex,
    required ChessboardView viewSource,
  }) async {
    if (viewSource != ChessboardView.forYou) {
      return _ResolvedNavigation(games: orderedGames, index: gameIndex);
    }

    if (orderedGames.isEmpty) {
      return _ResolvedNavigation(games: orderedGames, index: gameIndex);
    }

    final safeIndex = gameIndex.clamp(0, orderedGames.length - 1);
    final currentGame = orderedGames[safeIndex];
    final tourId = currentGame.tourId;

    if (tourId.isEmpty) {
      return _ResolvedNavigation(games: orderedGames, index: safeIndex);
    }

    try {
      final fullGames = await _ref
          .read(gamesLocalStorage)
          .fetchAndSaveGames(tourId);

      if (fullGames.isEmpty) {
        return _ResolvedNavigation(games: orderedGames, index: safeIndex);
      }

      final fullModels = <GamesTourModel>[];
      for (final game in fullGames) {
        try {
          fullModels.add(GamesTourModel.fromGame(game));
        } catch (_) {
          // Skip invalid game rows to keep navigation resilient.
        }
      }

      if (fullModels.isEmpty) {
        return _ResolvedNavigation(games: orderedGames, index: safeIndex);
      }

      final overrides = {
        for (final game in orderedGames) game.gameId: game,
      };
      final mergedModels =
          fullModels.map((game) {
            final override = overrides[game.gameId];
            if (override == null) return game;
            return game.copyWith(
              pgn: override.pgn ?? game.pgn,
              fen: override.fen ?? game.fen,
              lastMove: override.lastMove ?? game.lastMove,
              lastMoveTime: override.lastMoveTime ?? game.lastMoveTime,
              whiteClockSeconds:
                  override.whiteClockSeconds ?? game.whiteClockSeconds,
              blackClockSeconds:
                  override.blackClockSeconds ?? game.blackClockSeconds,
              gameStatus: override.gameStatus,
            );
          }).toList();

      final resolvedIndex = fullModels.indexWhere(
        (game) => game.gameId == currentGame.gameId,
      );
      final finalIndex =
          resolvedIndex >= 0
              ? resolvedIndex
              : safeIndex.clamp(0, mergedModels.length - 1);

      return _ResolvedNavigation(games: mergedModels, index: finalIndex);
    } catch (e) {
      debugPrint('Failed to expand for-you games list: $e');
      return _ResolvedNavigation(games: orderedGames, index: safeIndex);
    }
  }

  void navigateToChessBoard({
    required BuildContext context,
    required List<GamesTourModel> orderedGames,
    required int gameIndex,
    required void Function(int)? onReturnFromChessboard,
    ChessboardView viewSource = ChessboardView.tour,
  }) async {
    _ref.read(chessboardViewFromProviderNew.notifier).state = viewSource;

    // Disable tournament streaming while inside the chessboard to avoid
    // periodic refreshes and repeated fetch logs.
    _ref.read(shouldStreamProvider.notifier).state = false;

    final resolvedNavigation = await _resolveNavigationGames(
      orderedGames: orderedGames,
      gameIndex: gameIndex,
      viewSource: viewSource,
    );

    final returnedIndex = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder:
            (_) => ChessBoardScreenNew(
              games: resolvedNavigation.games,
              currentIndex: resolvedNavigation.index,
            ),
      ),
    );

    // Re-enable streaming when coming back to the tournament screen
    _ref.read(shouldStreamProvider.notifier).state = true;

    // If a different index was returned from the chessboard, notify the parent
    if (returnedIndex != null &&
        returnedIndex != gameIndex &&
        onReturnFromChessboard != null) {
      onReturnFromChessboard(returnedIndex);
    }
  }
}
