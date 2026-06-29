import 'package:chessever2/providers/for_you_games_logic.dart';
import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Isolate entry point that turns a single event's raw [Games] into the
/// fully-ordered Games-tab list ([GamesTourModel]s, round DESC → game DESC →
/// board ASC). Delegates to the shared [sortGamesForGamesTab] so the For You
/// board dropdown matches the Games tab exactly. Kept top-level (and pin-less —
/// the For You nav has no pin context) so it can run via [compute]; the PGN
/// parsing inside [GamesTourModel.fromGame] is heavy and must stay off the main
/// thread to keep game-card taps snappy.
List<GamesTourModel> sortForYouEventGames(List<Games> games) =>
    sortGamesForGamesTab(games: games, pinnedIds: const <String>[]);

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
    if (viewSource != ChessboardView.forYou || orderedGames.isEmpty) {
      return _ResolvedNavigation(games: orderedGames, index: gameIndex);
    }

    final safeIndex = gameIndex.clamp(0, orderedGames.length - 1);
    final tappedGame = orderedGames[safeIndex];
    final tourId = tappedGame.tourId;

    // A For You card only carries the top-N preview games for its event, so the
    // board's game-switcher dropdown would otherwise show an incomplete,
    // re-ranked subset. Resolve the full event game list — the same set and
    // order the event's Games tab shows — so the dropdown matches navigating in
    // through the event card → Games tab. Virtual gamebase events have no
    // broadcast tour to expand, so they keep the passed list as-is.
    if (tourId.isEmpty || isVirtualGamebaseId(tourId)) {
      return _ResolvedNavigation(games: orderedGames, index: safeIndex);
    }

    try {
      // Cache-only read: the For You feed already fetched and persisted this
      // event's games, so we reuse that cache instead of hitting the network —
      // a blocking fetch here would make the tap feel laggy. Both the cache
      // decode and the sort/convert run in background isolates, so the main
      // thread stays free. If nothing is cached we fall back to the preview
      // subset rather than blocking on the network.
      final rawGames = await _ref.read(gamesLocalStorage).getCachedGames(tourId);
      if (rawGames.isEmpty) {
        return _ResolvedNavigation(games: orderedGames, index: safeIndex);
      }

      final fullGames = await compute(sortForYouEventGames, rawGames);
      final resolvedIndex = fullGames.indexWhere(
        (g) => g.gameId == tappedGame.gameId,
      );

      // If the tapped game isn't in the cached set (e.g. a brand-new live game
      // not yet persisted), keep the subset so the board still opens on it.
      if (resolvedIndex < 0) {
        return _ResolvedNavigation(games: orderedGames, index: safeIndex);
      }

      // Preserve the tapped game's live version (fresh fen/clock from the feed)
      // while the rest of the event fills out the dropdown.
      fullGames[resolvedIndex] = tappedGame;
      return _ResolvedNavigation(games: fullGames, index: resolvedIndex);
    } catch (_) {
      return _ResolvedNavigation(games: orderedGames, index: safeIndex);
    }
  }

  /// Test seam for the For You navigation resolution above. Returns the
  /// `(games, index)` that would be handed to `ChessBoardScreenNew` so tests can
  /// assert the board (and therefore its game-switcher dropdown) receives the
  /// full event list rather than the For You preview subset.
  @visibleForTesting
  Future<(List<GamesTourModel>, int)> debugResolveForYouNavigation({
    required List<GamesTourModel> orderedGames,
    required int gameIndex,
  }) async {
    final resolved = await _resolveNavigationGames(
      orderedGames: orderedGames,
      gameIndex: gameIndex,
      viewSource: ChessboardView.forYou,
    );
    return (resolved.games, resolved.index);
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
