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

/// Search and live/finished filters turn an otherwise expandable tournament
/// preview into a deliberate user-visible collection. Keep that filtered
/// membership and order; an unfiltered event list may still hydrate a
/// one-round preview to the complete event.
BoardNavigationListPolicy boardNavigationListPolicyForGamesData(
  GamesScreenModel gamesData,
) {
  return gamesData.isSearchMode ||
          gamesData.gameDisplayMode != GameDisplayMode.all
      ? BoardNavigationListPolicy.preserve
      : BoardNavigationListPolicy.sourceDefault;
}

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
  final _BoardNavigationSnapshot _latest;

  const BoardNavigationLaunch._({
    required this.immediateGames,
    required this.immediateIndex,
    required this.expanded,
    required _BoardNavigationSnapshot latest,
  }) : _latest = latest;

  /// The list currently installed in the deferred board host. Navigation back
  /// uses this snapshot to translate the board's index into the caller's list
  /// by game ID, because an expanded event and its preview use different index
  /// spaces.
  List<GamesTourModel> get currentGames => _latest.games;
}

class _BoardNavigationSnapshot {
  _BoardNavigationSnapshot({required this.games});

  List<GamesTourModel> games;
}

/// Maps a board result back into the exact list that opened it. A game exposed
/// only by full-event expansion has no row in the caller, so returning to the
/// previous screen keeps its existing scroll position instead of jumping to an
/// unrelated row that happens to share the expanded index.
@visibleForTesting
int? callerIndexForBoardReturn({
  required List<GamesTourModel> callerGames,
  required List<GamesTourModel> boardGames,
  required int boardIndex,
}) {
  if (boardIndex < 0 || boardIndex >= boardGames.length) return null;
  final gameId = boardGames[boardIndex].gameId;
  final callerIndex = callerGames.indexWhere((game) => game.gameId == gameId);
  return callerIndex < 0 ? null : callerIndex;
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
    // Decides whether this list may be expanded at all. Collection surfaces
    // are authoritative; everything else keys expansion off the *tapped*
    // game's event so For You and the tournament Games tab hydrate the
    // switcher the same way.
    required ChessboardView viewSource,
    required BoardNavigationListPolicy listPolicy,
  }) async {
    if (orderedGames.isEmpty) {
      return _ResolvedNavigation(games: orderedGames, index: gameIndex);
    }

    final safeIndex = gameIndex.clamp(0, orderedGames.length - 1);
    final tappedGame = orderedGames[safeIndex];

    // Collection sources and explicit preserve callers hand over a list the
    // user built or filtered on purpose. Swapping it for the tapped game's full
    // event throws that filter away, so keep exactly what they passed.
    // The selected game is still freshened downstream by
    // [_hydrateSelectedGameForNavigation]; only the *membership and order* are
    // frozen here.
    if (listPolicy == BoardNavigationListPolicy.preserve ||
        viewSource.preservesNavigationCollection) {
      return _ResolvedNavigation(games: orderedGames, index: safeIndex);
    }

    // For every remaining route the board's game-switcher dropdown (and its
    // round timeline) must list the FULL event of the game being opened —
    // every prior round and board. Those lists hand over only a subset (a
    // top-N preview, a single-round pin), so expand by the *tapped* game's
    // tourId rather than requiring the whole ordered list to be single-tour.
    //
    // Leave the list EXACTLY as passed when expanding is wrong/unneeded:
    //  - archive/local game, virtual gamebase, or empty tourId → no broadcast
    //    tour to fetch.
    //  - single-tour list that already covers 2+ rounds and is not For You →
    //    already the full multi-round Games-tab list (or equivalent); never
    //    refetch or reorder it.
    final tourId = tappedGame.tourId;
    if (tappedGame.source != GameSource.supabase ||
        tourId.isEmpty ||
        isVirtualGamebaseId(tourId)) {
      return _ResolvedNavigation(games: orderedGames, index: safeIndex);
    }

    final isSingleTourList = orderedGames.every((g) => g.tourId == tourId);
    final sameTourGames =
        isSingleTourList
            ? orderedGames
            : orderedGames.where((g) => g.tourId == tourId).toList();
    final coveredRounds = sameTourGames.map((g) => g.roundId).toSet();
    // For You always carries a re-ranked top-N preview (never the full event),
    // so it always expands. A single-event multi-round list is left alone
    // (Games tab).
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
      // games. An expandable tournament preview can be cold for the same
      // reason. Fetch the full event once so the dropdown lists every round,
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
      final fullGameIds = fullGames.map((game) => game.gameId).toSet();
      final omitsImmediateSibling = sameTourGames.any(
        (game) => !fullGameIds.contains(game.gameId),
      );
      // A non-empty cache can still lag a live preview. Never let that stale
      // candidate delete a game the caller already displayed: if the user has
      // swiped to the missing sibling while expansion is running, replacing
      // the list would make the PageView remap fail and jump to another game.
      if (omitsImmediateSibling) {
        return _ResolvedNavigation(games: orderedGames, index: safeIndex);
      }

      // Expansion must add event membership without rewinding any live row the
      // caller already owns. Merge every immediate sibling, not only the
      // tapped game: the user can swipe while this background work is running.
      final immediateById = {
        for (final game in sameTourGames) game.gameId: game,
      };
      for (var i = 0; i < fullGames.length; i++) {
        final immediate = immediateById[fullGames[i].gameId];
        if (immediate != null) {
          fullGames[i] = selectFreshestNavigationGame(
            current: fullGames[i],
            incoming: immediate,
          );
        }
      }
      final resolvedIndex = fullGames.indexWhere(
        (g) => g.gameId == tappedGame.gameId,
      );

      // If the tapped game isn't in the cached set (e.g. a brand-new live game
      // not yet persisted), keep the subset so the board still opens on it.
      if (resolvedIndex < 0) {
        return _ResolvedNavigation(games: orderedGames, index: safeIndex);
      }

      return _ResolvedNavigation(games: fullGames, index: resolvedIndex);
    } catch (_) {
      return _ResolvedNavigation(games: orderedGames, index: safeIndex);
    }
  }

  Future<_ResolvedNavigation> _resolveHydratedNavigationGames({
    required List<GamesTourModel> orderedGames,
    required int gameIndex,
    required ChessboardView viewSource,
    required BoardNavigationListPolicy listPolicy,
  }) async {
    final resolved = await _resolveNavigationGames(
      orderedGames: orderedGames,
      gameIndex: gameIndex,
      viewSource: viewSource,
      listPolicy: listPolicy,
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
    BoardNavigationListPolicy listPolicy =
        BoardNavigationListPolicy.sourceDefault,
  }) {
    final immediate = _immediateOpenNavigation(
      orderedGames: orderedGames,
      gameIndex: gameIndex,
    );
    final latest = _BoardNavigationSnapshot(games: immediate.games);
    final expanded = _resolveHydratedNavigationGames(
      orderedGames: orderedGames,
      gameIndex: gameIndex,
      viewSource: viewSource,
      listPolicy: listPolicy,
    ).then((resolved) => (games: resolved.games, index: resolved.index));
    return BoardNavigationLaunch._(
      immediateGames: immediate.games,
      immediateIndex: immediate.index,
      expanded: expanded,
      latest: latest,
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
      listPolicy: BoardNavigationListPolicy.sourceDefault,
    );
    return (resolved.games, resolved.index);
  }

  @visibleForTesting
  Future<(List<GamesTourModel>, int)> debugResolveNavigation({
    required List<GamesTourModel> orderedGames,
    required int gameIndex,
    ChessboardView viewSource = ChessboardView.tour,
    BoardNavigationListPolicy listPolicy =
        BoardNavigationListPolicy.sourceDefault,
  }) async {
    final resolved = await _resolveHydratedNavigationGames(
      orderedGames: orderedGames,
      gameIndex: gameIndex,
      viewSource: viewSource,
      listPolicy: listPolicy,
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
    BoardNavigationListPolicy listPolicy =
        BoardNavigationListPolicy.sourceDefault,
  }) {
    return beginBoardNavigation(
      orderedGames: orderedGames,
      gameIndex: gameIndex,
      viewSource: viewSource,
      listPolicy: listPolicy,
    );
  }

  void navigateToChessBoard({
    required BuildContext context,
    required List<GamesTourModel> orderedGames,
    required int gameIndex,
    required void Function(int)? onReturnFromChessboard,
    ChessboardView viewSource = ChessboardView.tour,
    BoardNavigationListPolicy listPolicy =
        BoardNavigationListPolicy.sourceDefault,
    bool hideEventInfo = false,
    PlayerProfileDataSource playerProfileDataSource =
        PlayerProfileDataSource.supabase,
    bool showGamebaseButton = false,
    bool disableGamebaseOverlayByDefault = false,
    bool showClock = true,
    SavedAnalysisData? savedAnalysisData,
  }) async {
    final previousViewSource = _ref.read(chessboardViewFromProviderNew);
    final previousBoardGames = _ref.read(chessBoardAllGamesProvider);
    final previousVisibleIndex = _ref.read(currentlyVisiblePageIndexProvider);
    final previousShouldStream = _ref.read(shouldStreamProvider);
    _ref.read(chessboardViewFromProviderNew.notifier).state = viewSource;

    // Critical path: open with the already-available card/list model. Full-event
    // expand + selected-game PGN freshen run in the background and install into
    // the live board switcher when ready — never gate Navigator.push on them.
    final launch = beginBoardNavigation(
      orderedGames: orderedGames,
      gameIndex: gameIndex,
      viewSource: viewSource,
      listPolicy: listPolicy,
    );

    if (!context.mounted) {
      _restoreBoardNavigationContext(
        viewSource: previousViewSource,
        games: previousBoardGames,
        visibleIndex: previousVisibleIndex,
        shouldStream: previousShouldStream,
      );
      return;
    }

    // Disable tournament streaming while inside the chessboard to avoid
    // periodic refreshes and repeated fetch logs.
    _ref.read(shouldStreamProvider.notifier).state = false;

    int? returnedIndex;
    var boardGamesAtPop = launch.currentGames;
    final callerRoute = ModalRoute.of(context);
    var callerWasRevealed = false;
    final boardRoute = MaterialPageRoute<int>(
      builder:
          (_) => _ExpandingChessBoardScreen(
            initialGames: launch.immediateGames,
            initialIndex: launch.immediateIndex,
            expandedNavigation: launch.expanded,
            navigationSnapshot: launch._latest,
            viewSource: viewSource,
            hideEventInfo: hideEventInfo,
            playerProfileDataSource: playerProfileDataSource,
            showGamebaseButton: showGamebaseButton,
            disableGamebaseOverlayByDefault: disableGamebaseOverlayByDefault,
            showClock: showClock,
            savedAnalysisData: savedAnalysisData,
          ),
    );
    try {
      returnedIndex = await Navigator.push<int>(context, boardRoute);
      boardGamesAtPop = List<GamesTourModel>.of(launch.currentGames);
      // `Navigator.push` completes when the pop starts. Wait for the route's
      // exit animation and disposal so outgoing dropdown/board callbacks cannot
      // overwrite the caller context after it is restored below.
      await boardRoute.completed;
    } finally {
      // Board navigation is stack-scoped. A nested board (for example one
      // opened from a score card) must not leak its list, page, source, or
      // streaming state into the route revealed underneath it.
      callerWasRevealed = callerRoute?.isCurrent ?? context.mounted;
      if (callerWasRevealed) {
        _restoreBoardNavigationContext(
          viewSource: previousViewSource,
          games: previousBoardGames,
          visibleIndex: previousVisibleIndex,
          shouldStream: previousShouldStream,
        );
        if (previousShouldStream) {
          _ref.invalidate(gameUpdatesStreamProvider);
          _ref.invalidate(liveGameUpdateStreamProvider);
          _ref.invalidate(gameUpdatesBatchStreamProvider);
        }
      }
    }

    // Translate through gameId before telling the previous screen to scroll.
    // Expanded and caller lists can have different membership and ordering.
    if (callerWasRevealed &&
        context.mounted &&
        returnedIndex != null &&
        onReturnFromChessboard != null) {
      final callerIndex = callerIndexForBoardReturn(
        callerGames: orderedGames,
        boardGames: boardGamesAtPop,
        boardIndex: returnedIndex,
      );
      if (callerIndex != null && callerIndex != gameIndex) {
        onReturnFromChessboard(callerIndex);
      }
    }
  }

  void _restoreBoardNavigationContext({
    required ChessboardView viewSource,
    required List<GamesTourModel> games,
    required int visibleIndex,
    required bool shouldStream,
  }) {
    _ref.read(chessboardViewFromProviderNew.notifier).state = viewSource;
    _ref.read(chessBoardAllGamesProvider.notifier).state = games;
    _ref.read(currentlyVisiblePageIndexProvider.notifier).state = visibleIndex;
    _ref.read(shouldStreamProvider.notifier).state = shouldStream;
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
    required this.navigationSnapshot,
    required this.viewSource,
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
  final _BoardNavigationSnapshot navigationSnapshot;
  final ChessboardView viewSource;
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

/// Pumps the production deferred-navigation host in widget tests without
/// routing through a tap-only UI surface. The child remains the real
/// [ChessBoardScreenNew], including its games PageView and switcher dropdown.
@visibleForTesting
class BoardNavigationSnapshotProbe {
  _BoardNavigationSnapshot? _snapshot;

  List<GamesTourModel> get games =>
      List<GamesTourModel>.unmodifiable(_snapshot?.games ?? const []);
}

@visibleForTesting
Widget expandingChessBoardScreenForTesting({
  required List<GamesTourModel> initialGames,
  required int initialIndex,
  required Future<({List<GamesTourModel> games, int index})> expandedNavigation,
  required ChessboardView viewSource,
  BoardNavigationSnapshotProbe? snapshotProbe,
}) {
  final snapshot = _BoardNavigationSnapshot(games: initialGames);
  snapshotProbe?._snapshot = snapshot;
  return _ExpandingChessBoardScreen(
    initialGames: initialGames,
    initialIndex: initialIndex,
    expandedNavigation: expandedNavigation,
    navigationSnapshot: snapshot,
    viewSource: viewSource,
    hideEventInfo: false,
    playerProfileDataSource: PlayerProfileDataSource.supabase,
    showGamebaseButton: false,
    disableGamebaseOverlayByDefault: true,
    showClock: true,
  );
}

class _ExpandingChessBoardScreenState
    extends State<_ExpandingChessBoardScreen> {
  late List<GamesTourModel> _games;
  late int _index;
  String? _visibleGameId;

  @override
  void initState() {
    super.initState();
    _games = widget.initialGames;
    _index =
        widget.initialGames.isEmpty
            ? widget.initialIndex
            : widget.initialIndex.clamp(0, widget.initialGames.length - 1);
    if (_games.isNotEmpty) {
      _visibleGameId = _games[_index].gameId;
    }
    unawaited(_applyExpandedNavigation());
  }

  Future<void> _applyExpandedNavigation() async {
    try {
      final resolved = await widget.expandedNavigation;
      if (!mounted || resolved.games.isEmpty) return;

      var nextIndex = resolved.index.clamp(0, resolved.games.length - 1);
      if (_visibleGameId != null) {
        final byId = resolved.games.indexWhere(
          (g) => g.gameId == _visibleGameId,
        );
        // The user may swipe to another event while the originally tapped
        // event is still expanding. Never install a candidate that deletes
        // the game they have already made active.
        if (byId < 0) {
          return;
        }
        nextIndex = byId;
      }

      if (!_navigationChanged(_games, _index, resolved.games, nextIndex)) {
        return;
      }

      final acceptedGames = resolved.games;
      setState(() {
        _games = acceptedGames;
        _index = nextIndex;
      });
      // Keep the return-index mapper in the same index space as the child
      // PageView. `setState` updates [_games] immediately, but the child still
      // owns the previous list until the next frame. Publishing the expanded
      // snapshot before that rebuild creates a one-frame race where Back can
      // return an old-list index and map it through the new list. Commit only
      // after the child has rebuilt/remapped, and ignore a stale callback if a
      // newer candidate ever supersedes this one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(_games, acceptedGames)) return;
        widget.navigationSnapshot.games = acceptedGames;
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
      viewSource: widget.viewSource,
      hideEventInfo: widget.hideEventInfo,
      playerProfileDataSource: widget.playerProfileDataSource,
      showGamebaseButton: widget.showGamebaseButton,
      disableGamebaseOverlayByDefault: widget.disableGamebaseOverlayByDefault,
      showClock: widget.showClock,
      savedAnalysisData: widget.savedAnalysisData,
      onVisibleGameChanged: (gameId) => _visibleGameId = gameId,
    );
  }
}
