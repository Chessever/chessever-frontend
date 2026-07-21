import 'package:chessever2/providers/for_you_games_logic.dart';
import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
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
    // Kept for call-site clarity; expansion is now decided from the game list's
    // shape (single-event vs cross-event) rather than the view, so EVERY route
    // that funnels through here hydrates the switcher identically.
    required ChessboardView viewSource,
  }) async {
    if (orderedGames.isEmpty) {
      return _ResolvedNavigation(games: orderedGames, index: gameIndex);
    }

    final safeIndex = gameIndex.clamp(0, orderedGames.length - 1);
    final tappedGame = orderedGames[safeIndex];

    // The board's game-switcher dropdown (and its round timeline) must list the
    // FULL event — every round — no matter which screen opened the board. Most
    // entry points (For You, smart events, brackets, single-round pins, …) hand
    // us only a subset of one event's games, so the switcher would otherwise
    // show just the tapped game's round. This resolver is the single chokepoint
    // every game-card tap funnels through, so expand any single-event subset to
    // the whole event right here.
    //
    // Guards — leave the list EXACTLY as passed when expanding is wrong/unneeded:
    //  - games span multiple tours → an intentionally cross-event list (player
    //    profile, favorites, countrymen); there is no single event to expand.
    //  - virtual gamebase / empty tourId → no broadcast tour to fetch.
    //  - the list already covers 2+ rounds → it is already the full multi-round
    //    event list (e.g. the Games tab), so never refetch or reorder it.
    final tourIds = orderedGames.map((g) => g.tourId).toSet();
    if (tourIds.length != 1) {
      return _ResolvedNavigation(games: orderedGames, index: safeIndex);
    }
    final tourId = tourIds.first;
    if (tourId.isEmpty || isVirtualGamebaseId(tourId)) {
      return _ResolvedNavigation(games: orderedGames, index: safeIndex);
    }
    // For You always carries a re-ranked top-N preview (never the full event),
    // so it always expands. Every other single-event source only expands when
    // it covers a SINGLE round — a strong signal it is a partial subset — so a
    // deliberately multi-round list (Games tab, a filtered view already showing
    // several rounds) is left untouched, never refetched or reordered.
    final coveredRounds = orderedGames.map((g) => g.roundId).toSet();
    if (viewSource != ChessboardView.forYou && coveredRounds.length >= 2) {
      return _ResolvedNavigation(games: orderedGames, index: safeIndex);
    }

    try {
      final storage = _ref.read(gamesLocalStorage);
      // Cache-first: reuse the persisted full-event list when it exists (fast,
      // isolate decode, no network). BUT the For You feed only fetches the
      // top-N preview per event via a pure RPC (`getForYouTopGamesByEventIds`)
      // that never writes the games cache — so an event reached ONLY through
      // For You (never opened via its event card / Games tab) has NO cached
      // games. In that cold case the old code fell back to the 4-game preview
      // subset, and the board's game-switcher showed only the tapped game's
      // round. Fetch the full event once so the dropdown lists every round,
      // exactly like entering through the Games tab. `fetchAndSaveGames` also
      // persists it, so every re-open of this event stays network-free.
      var rawGames = await storage.getCachedGames(tourId);
      if (rawGames.isEmpty) {
        rawGames = await storage.fetchAndSaveGames(tourId);
      }
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

  Future<_ResolvedNavigation> _resolveHydratedNavigationGames({
    required List<GamesTourModel> orderedGames,
    required int gameIndex,
    required ChessboardView viewSource,
  }) async {
    final resolved = await _resolveNavigationGames(
      orderedGames: orderedGames,
      gameIndex: gameIndex,
      viewSource: viewSource,
    );
    return _hydrateSelectedGameForNavigation(resolved);
  }

  Future<_ResolvedNavigation> _hydrateSelectedGameForNavigation(
    _ResolvedNavigation resolved,
  ) async {
    if (resolved.games.isEmpty) {
      return resolved;
    }

    final safeIndex = resolved.index.clamp(0, resolved.games.length - 1);
    final current = resolved.games[safeIndex];
    if (current.source != GameSource.supabase || current.gameId.isEmpty) {
      return _ResolvedNavigation(games: resolved.games, index: safeIndex);
    }

    try {
      final latestRaw = await _ref
          .read(gameRepositoryProvider)
          .getGameWithPGN(current.gameId);
      final latest = GamesTourModel.fromGame(latestRaw);
      final hydrated = selectFreshestNavigationGame(
        current: current,
        incoming: latest,
      );
      if (identical(hydrated, current)) {
        return _ResolvedNavigation(games: resolved.games, index: safeIndex);
      }

      final hydratedGames = List<GamesTourModel>.from(resolved.games);
      hydratedGames[safeIndex] = hydrated;
      return _ResolvedNavigation(games: hydratedGames, index: safeIndex);
    } catch (_) {
      return _ResolvedNavigation(games: resolved.games, index: safeIndex);
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

  @visibleForTesting
  Future<(List<GamesTourModel>, int)> debugResolveNavigation({
    required List<GamesTourModel> orderedGames,
    required int gameIndex,
    ChessboardView viewSource = ChessboardView.tour,
  }) async {
    final resolved = await _resolveHydratedNavigationGames(
      orderedGames: orderedGames,
      gameIndex: gameIndex,
      viewSource: viewSource,
    );
    return (resolved.games, resolved.index);
  }

  void navigateToChessBoard({
    required BuildContext context,
    required List<GamesTourModel> orderedGames,
    required int gameIndex,
    required void Function(int)? onReturnFromChessboard,
    ChessboardView viewSource = ChessboardView.tour,
    bool hideEventInfo = false,
    PlayerProfileDataSource playerProfileDataSource =
        PlayerProfileDataSource.supabase,
    bool showGamebaseButton = false,
    bool disableGamebaseOverlayByDefault = false,
    bool showClock = true,
    SavedAnalysisData? savedAnalysisData,
  }) async {
    _ref.read(chessboardViewFromProviderNew.notifier).state = viewSource;

    final resolvedNavigation = await _resolveHydratedNavigationGames(
      orderedGames: orderedGames,
      gameIndex: gameIndex,
      viewSource: viewSource,
    );

    if (!context.mounted) {
      return;
    }

    // Disable tournament streaming while inside the chessboard to avoid
    // periodic refreshes and repeated fetch logs. Hydration happens first so a
    // tap does not freeze a stale card model before the board opens.
    _ref.read(shouldStreamProvider.notifier).state = false;

    final returnedIndex = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder:
            (_) => ChessBoardScreenNew(
              games: resolvedNavigation.games,
              currentIndex: resolvedNavigation.index,
              hideEventInfo: hideEventInfo,
              playerProfileDataSource: playerProfileDataSource,
              showGamebaseButton: showGamebaseButton,
              disableGamebaseOverlayByDefault: disableGamebaseOverlayByDefault,
              showClock: showClock,
              savedAnalysisData: savedAnalysisData,
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
