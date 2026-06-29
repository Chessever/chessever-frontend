import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/providers/for_you_games_logic.dart';
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

@visibleForTesting
Future<List<GamesTourModel>> loadFullTourGamesForBoardSelector({
  required List<GamesTourModel> currentGames,
  required int currentIndex,
  required GamesLocalStorage gamesStorage,
}) async {
  if (currentGames.isEmpty) return currentGames;

  final safeIndex = currentIndex.clamp(0, currentGames.length - 1);
  final selectedGame = currentGames[safeIndex];
  final tourId = selectedGame.tourId.trim();
  if (tourId.isEmpty) return currentGames;

  try {
    final rawGames = await gamesStorage.fetchAndSaveGames(tourId);
    final fullGames = sortGamesForGamesTab(
      games: rawGames,
      pinnedIds: const [],
    );
    if (fullGames.length <= currentGames.length) {
      return currentGames;
    }

    final selectedIndex = fullGames.indexWhere(
      (game) => game.gameId == selectedGame.gameId,
    );
    if (selectedIndex < 0) return currentGames;

    // Preserve the just-rendered live card snapshot for the selected board so
    // opening from For You does not briefly rewind the tapped game while the
    // full selector list is hydrated.
    return List<GamesTourModel>.from(fullGames)..[selectedIndex] = selectedGame;
  } catch (error) {
    debugPrint(
      '[GameCardWrapper] Falling back to source games for tour $tourId: $error',
    );
    return currentGames;
  }
}

class _GameCardWrapperProvider {
  _GameCardWrapperProvider(this._ref);

  final Ref _ref;

  Future<_ResolvedNavigation> _resolveNavigationGames({
    required List<GamesTourModel> orderedGames,
    required int gameIndex,
    required ChessboardView viewSource,
  }) async {
    if (orderedGames.isEmpty) {
      return _ResolvedNavigation(games: orderedGames, index: gameIndex);
    }

    final safeIndex = gameIndex.clamp(0, orderedGames.length - 1);
    if (viewSource != ChessboardView.forYou) {
      return _ResolvedNavigation(games: orderedGames, index: safeIndex);
    }

    final resolvedGames = await loadFullTourGamesForBoardSelector(
      currentGames: orderedGames,
      currentIndex: safeIndex,
      gamesStorage: _ref.read(gamesLocalStorage),
    );
    final selectedGameId = orderedGames[safeIndex].gameId;
    final resolvedIndex = resolvedGames.indexWhere(
      (game) => game.gameId == selectedGameId,
    );

    return _ResolvedNavigation(
      games: resolvedGames,
      index: resolvedIndex >= 0 ? resolvedIndex : safeIndex,
    );
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

    if (!context.mounted) {
      _ref.read(shouldStreamProvider.notifier).state = true;
      return;
    }

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
    _ref.invalidate(gameUpdatesStreamProvider);
    _ref.invalidate(liveGameUpdateStreamProvider);
    _ref.invalidate(gameUpdatesBatchStreamProvider);

    // If a different index was returned from the chessboard, notify the parent
    if (returnedIndex != null &&
        returnedIndex != gameIndex &&
        onReturnFromChessboard != null) {
      onReturnFromChessboard(returnedIndex);
    }
  }
}
