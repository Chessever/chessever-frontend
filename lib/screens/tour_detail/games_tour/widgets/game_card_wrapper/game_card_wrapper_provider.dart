import 'dart:async';

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

/// Immediate open payload + background full-event expand future.
///
/// The board route is pushed with [immediate]; [expanded] completes later with
/// the full event list (and freshest selected-game PGN) so the switcher can be
/// updated without blocking the first open frame.
class BoardNavigationLaunch {
  final List<GamesTourModel> immediateGames;
  final int immediateIndex;
  final Future<({List<GamesTourModel> games, int index})> expanded;

  const BoardNavigationLaunch({
    required this.immediateGames,
    required this.immediateIndex,
    required this.expanded,
  });
}

class _GameCardWrapperProvider {
  _GameCardWrapperProvider(this._ref);

  final Ref _ref;

  /// Sync open payload: the card/list model already in hand. Never awaits
  /// network, cache decode, or isolate sort.
  _ResolvedNavigation _immediateOpenNavigation({
    required List<GamesTourModel> orderedGames,
    required int gameIndex,
  }) {
    if (orderedGames.isEmpty) {
      return _ResolvedNavigation(games: orderedGames, index: gameIndex);
    }
    final safeIndex = gameIndex.clamp(0, orderedGames.length - 1);
    return _ResolvedNavigation(games: orderedGames, index: safeIndex);
  }

  Future<_ResolvedNavigation> _resolveNavigationGames({
    required List<GamesTourModel> orderedGames,
    required int gameIndex,
    // Kept for call-site clarity; expansion keys off the *tapped* game's event
    // so For You, favorites Games, countrymen Games, and the tournament Games
    // tab all hydrate the switcher the same way.
    required ChessboardView viewSource,
  }) async {
    if (orderedGames.isEmpty) {
      return _ResolvedNavigation(games: orderedGames, index: gameIndex);
    }

    final safeIndex = gameIndex.clamp(0, orderedGames.length - 1);
    final tappedGame = orderedGames[safeIndex];

    // The board's game-switcher dropdown (and its round timeline) must list the
    // FULL event of the game being opened — every prior round and board — no
    // matter which screen opened the board (For You, favorites Games,
    // countrymen Games, smart events, single-round pins, …). Source lists often
    // hand only a subset (top-N preview) or a multi-event feed; expand by the
    // *tapped* game's tourId rather than requiring the whole ordered list to be
    // single-tour.
    //
    // Leave the list EXACTLY as passed when expanding is wrong/unneeded:
    //  - virtual gamebase / empty tourId → no broadcast tour to fetch.
    //  - single-tour list that already covers 2+ rounds and is not For You →
    //    already the full multi-round Games-tab list (or equivalent); never
    //    refetch or reorder it.
    // Multi-tour lists (favorites / countrymen) always expand the tapped tour
    // so the dropdown is that event alone, not the mixed feed.
    final tourId = tappedGame.tourId;
    if (tourId.isEmpty || isVirtualGamebaseId(tourId)) {
      return _ResolvedNavigation(games: orderedGames, index: safeIndex);
    }

    final isSingleTourList = orderedGames.every((g) => g.tourId == tourId);
    final sameTourGames =
        isSingleTourList
            ? orderedGames
            : orderedGames.where((g) => g.tourId == tourId).toList();
    final coveredRounds = sameTourGames.map((g) => g.roundId).toSet();
    // For You always carries a re-ranked top-N preview (never the full event),
    // so it always expands. Multi-tour feeds always expand the tapped tour.
    // A single-event multi-round list is left alone (Games tab).
    if (viewSource != ChessboardView.forYou &&
        isSingleTourList &&
        coveredRounds.length >= 2) {
      return _ResolvedNavigation(games: orderedGames, index: safeIndex);
    }

    try {
      final storage = _ref.read(gamesLocalStorage);
      // Cache-first: reuse the persisted full-event list when it exists (fast,
      // isolate decode, no network). BUT the For You feed only fetches the
      // top-N preview per event via a pure RPC (`getForYouTopGamesByEventIds`)
      // that never writes the games cache — so an event reached ONLY through
      // For You (never opened via its event card / Games tab) has NO cached
      // games. Same for a cold favorites/countrymen open of a never-visited
      // tour. Fetch the full event once so the dropdown lists every round,
      // exactly like entering through the Games tab. `fetchAndSaveGames` also
      // persists it, so every re-open of this event stays network-free.
      //
      // IMPORTANT: this work runs *after* the board route is pushed (see
      // [navigateToChessBoard]); it must not sit on the pre-push critical path.
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

  /// Starts the post-open expand/hydrate work and returns the immediate open
  /// payload used for the first board frame. Does **not** await network or
  /// isolate materialization.
  BoardNavigationLaunch beginBoardNavigation({
    required List<GamesTourModel> orderedGames,
    required int gameIndex,
    required ChessboardView viewSource,
  }) {
    final immediate = _immediateOpenNavigation(
      orderedGames: orderedGames,
      gameIndex: gameIndex,
    );
    final expanded = _resolveHydratedNavigationGames(
      orderedGames: orderedGames,
      gameIndex: gameIndex,
      viewSource: viewSource,
    ).then((resolved) => (games: resolved.games, index: resolved.index));
    return BoardNavigationLaunch(
      immediateGames: immediate.games,
      immediateIndex: immediate.index,
      expanded: expanded,
    );
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

  /// Test seam for the non-blocking open contract: returns the immediate push
  /// payload plus the background expand future without awaiting expand.
  @visibleForTesting
  BoardNavigationLaunch debugBeginBoardNavigation({
    required List<GamesTourModel> orderedGames,
    required int gameIndex,
    ChessboardView viewSource = ChessboardView.forYou,
  }) {
    return beginBoardNavigation(
      orderedGames: orderedGames,
      gameIndex: gameIndex,
      viewSource: viewSource,
    );
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

    // Critical path: open with the already-available card/list model. Full-event
    // expand + selected-game PGN freshen run in the background and install into
    // the live board switcher when ready — never gate Navigator.push on them.
    final launch = beginBoardNavigation(
      orderedGames: orderedGames,
      gameIndex: gameIndex,
      viewSource: viewSource,
    );

    if (!context.mounted) {
      return;
    }

    // Disable tournament streaming while inside the chessboard to avoid
    // periodic refreshes and repeated fetch logs.
    _ref.read(shouldStreamProvider.notifier).state = false;

    final returnedIndex = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder:
            (_) => _ExpandingChessBoardScreen(
              initialGames: launch.immediateGames,
              initialIndex: launch.immediateIndex,
              expandedNavigation: launch.expanded,
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

/// Host that opens the board on the immediate list, then swaps in the full
/// event (and freshest selected game) when background expand completes —
/// preserving the opened [gameId] as current.
class _ExpandingChessBoardScreen extends StatefulWidget {
  const _ExpandingChessBoardScreen({
    required this.initialGames,
    required this.initialIndex,
    required this.expandedNavigation,
    required this.hideEventInfo,
    required this.playerProfileDataSource,
    required this.showGamebaseButton,
    required this.disableGamebaseOverlayByDefault,
    required this.showClock,
    this.savedAnalysisData,
  });

  final List<GamesTourModel> initialGames;
  final int initialIndex;
  final Future<({List<GamesTourModel> games, int index})> expandedNavigation;
  final bool hideEventInfo;
  final PlayerProfileDataSource playerProfileDataSource;
  final bool showGamebaseButton;
  final bool disableGamebaseOverlayByDefault;
  final bool showClock;
  final SavedAnalysisData? savedAnalysisData;

  @override
  State<_ExpandingChessBoardScreen> createState() =>
      _ExpandingChessBoardScreenState();
}

class _ExpandingChessBoardScreenState extends State<_ExpandingChessBoardScreen> {
  late List<GamesTourModel> _games;
  late int _index;
  String? _openedGameId;

  @override
  void initState() {
    super.initState();
    _games = widget.initialGames;
    _index =
        widget.initialGames.isEmpty
            ? widget.initialIndex
            : widget.initialIndex.clamp(0, widget.initialGames.length - 1);
    if (_games.isNotEmpty) {
      _openedGameId = _games[_index].gameId;
    }
    unawaited(_applyExpandedNavigation());
  }

  Future<void> _applyExpandedNavigation() async {
    try {
      final resolved = await widget.expandedNavigation;
      if (!mounted || resolved.games.isEmpty) return;

      var nextIndex = resolved.index.clamp(0, resolved.games.length - 1);
      if (_openedGameId != null) {
        final byId = resolved.games.indexWhere((g) => g.gameId == _openedGameId);
        if (byId >= 0) {
          nextIndex = byId;
        }
      }

      if (!_navigationChanged(_games, _index, resolved.games, nextIndex)) {
        return;
      }

      setState(() {
        _games = resolved.games;
        _index = nextIndex;
      });
    } catch (_) {
      // Keep the immediate open list; switcher stays on the entry subset.
    }
  }

  bool _navigationChanged(
    List<GamesTourModel> currentGames,
    int currentIndex,
    List<GamesTourModel> nextGames,
    int nextIndex,
  ) {
    if (currentIndex != nextIndex || currentGames.length != nextGames.length) {
      return true;
    }
    for (var i = 0; i < currentGames.length; i++) {
      final a = currentGames[i];
      final b = nextGames[i];
      if (a.gameId != b.gameId ||
          a.pgn != b.pgn ||
          a.fen != b.fen ||
          a.lastMove != b.lastMove ||
          a.gameStatus != b.gameStatus) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ChessBoardScreenNew(
      games: _games,
      currentIndex: _index,
      hideEventInfo: widget.hideEventInfo,
      playerProfileDataSource: widget.playerProfileDataSource,
      showGamebaseButton: widget.showGamebaseButton,
      disableGamebaseOverlayByDefault: widget.disableGamebaseOverlayByDefault,
      showClock: widget.showClock,
      savedAnalysisData: widget.savedAnalysisData,
    );
  }
}
