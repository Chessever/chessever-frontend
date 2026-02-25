import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
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
      final fullGames = await _ref.read(gamesLocalStorage).getGames(tourId);

      if (fullGames.isEmpty) {
        return _ResolvedNavigation(games: orderedGames, index: safeIndex);
      }

      // Sort games to match tour detail screen ordering:
      // 1. Round number descending (latest round first)
      // 2. Game number descending
      // 3. Board number ascending (board 1 first)
      final sortedGames = _sortGamesForNavigation(fullGames);

      final fullModels = <GamesTourModel>[];
      for (final game in sortedGames) {
        try {
          fullModels.add(GamesTourModel.fromGame(game));
        } catch (_) {
          // Skip invalid game rows to keep navigation resilient.
        }
      }

      if (fullModels.isEmpty) {
        return _ResolvedNavigation(games: orderedGames, index: safeIndex);
      }

      final overrides = {for (final game in orderedGames) game.gameId: game};
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

      final resolvedIndex = mergedModels.indexWhere(
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

  /// Sorts games to match tour detail screen ordering.
  /// Order: round descending → game number descending → board number ascending
  List<Games> _sortGamesForNavigation(List<Games> games) {
    if (games.isEmpty) return games;

    // Pre-parse round and game numbers for performance
    final gameInfo = <String, (int, int)>{};
    for (final game in games) {
      gameInfo[game.id] = (
        _extractRoundNumber(game.roundSlug),
        _extractGameNumber(game.roundSlug),
      );
    }

    final sortedGames = List<Games>.from(games);
    sortedGames.sort((a, b) {
      final (roundA, gameA) = gameInfo[a.id] ?? (0, 0);
      final (roundB, gameB) = gameInfo[b.id] ?? (0, 0);

      // Sort by round number descending (latest round first)
      if (roundA != roundB) return roundB.compareTo(roundA);

      // Within same round, sort by game number descending
      if (gameA != gameB) return gameB.compareTo(gameA);

      // Finally, sort by board number ascending (board 1 first)
      final aBoard = a.boardNr, bBoard = b.boardNr;
      if (aBoard != null && bBoard != null) return aBoard.compareTo(bBoard);
      if (aBoard != null) return -1;
      if (bBoard != null) return 1;
      return 0;
    });

    return sortedGames;
  }

  /// Extracts round number from round slug (e.g., "round-5" -> 5)
  /// Named knockout stages get high numbers so they sort after numbered rounds.
  int _extractRoundNumber(String roundSlug) {
    final slug = roundSlug.toLowerCase();
    if (slug.contains('final') &&
        !slug.contains('quarter') &&
        !slug.contains('semi')) {
      return 10000;
    }
    if (slug.contains('semifinal') || slug.contains('semi-final')) {
      return 9000;
    }
    if (slug.contains('quarterfinal') || slug.contains('quarter-final')) {
      return 8000;
    }
    final match =
        RegExp(r'round-?(\d+)', caseSensitive: false).firstMatch(roundSlug) ??
        RegExp(r'(\d+)').firstMatch(roundSlug);
    return int.tryParse(match?.group(1) ?? '0') ?? 0;
  }

  /// Extracts game number from round slug (e.g., "round-6--game-2" -> 2)
  int _extractGameNumber(String roundSlug) {
    final match = RegExp(
      r'game-?(\d+)',
      caseSensitive: false,
    ).firstMatch(roundSlug);
    return int.tryParse(match?.group(1) ?? '0') ?? 0;
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
