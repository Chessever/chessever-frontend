import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chess/chess.dart' hide State;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'dart:async';

import 'gamebase_explorer_state.dart';

/// StateNotifier for managing Gamebase explorer state.
class GamebaseExplorerNotifier extends StateNotifier<GamebaseExplorerState> {
  GamebaseExplorerNotifier(this.ref) : super(const GamebaseExplorerState()) {
    // Load initial position data
    _fetchMoveAggregates();
  }

  final Ref ref;

  /// Internal chess instance for position tracking
  Chess? _chess;

  /// Debounce timer for network fetches
  Timer? _debounceTimer;

  /// Monotonic token to ignore stale responses
  int _fetchToken = 0;

  Chess get chess {
    _chess ??= Chess();
    return _chess!;
  }

  void _scheduleFetch([Duration delay = const Duration(milliseconds: 200)]) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, _fetchMoveAggregates);
  }

  /// Fetch move aggregates for current position
  Future<void> _fetchMoveAggregates() async {
    final fetchId = ++_fetchToken;
    final requestedFen = state.currentFen;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final repository = ref.read(gamebaseRepositoryProvider);

      // Current API supports a single time control / player filter.
      final timeControlFilter =
          state.filters.timeControls.isNotEmpty
              ? state.filters.timeControls.first
              : null;
      final playerIdFilter =
          state.filters.playerIds.isNotEmpty ? state.filters.playerIds.first : null;

      final response = await repository.getMoveAggregates(
        fen: state.currentFen,
        timeControl: timeControlFilter,
        minRating: state.filters.minRating,
        maxRating: state.filters.maxRating,
        playerId: playerIdFilter,
      );

      // Ignore if a newer request started or FEN changed while awaiting.
      if (fetchId != _fetchToken || requestedFen != state.currentFen) return;

      final aggregates = List<MoveAggregate>.from(response.data.moves);

      // Sort by total games descending
      aggregates.sort((a, b) => b.total.compareTo(a.total));

      state = state.copyWith(moveAggregates: aggregates, isLoading: false);
    } catch (e) {
      if (fetchId != _fetchToken) return;
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        moveAggregates: [],
      );
    }
  }

  /// Make a move on the board (UCI format)
  void makeMove(String uci) {
    try {
      // Parse UCI move
      final from = uci.substring(0, 2);
      final to = uci.substring(2, 4);
      final promotion = uci.length > 4 ? uci[4] : null;

      // Reset chess to current position if needed
      _rebuildChessPosition();

      // Make the move
      final dynamic move = chess.move({
        'from': from,
        'to': to,
        if (promotion != null) 'promotion': promotion,
      });

      if (move != null) {
        // If we're not at the end of history, truncate
        final newHistory = state.moveHistory.sublist(
          0,
          state.currentMoveIndex + 1,
        )..add(uci);

        state = state.copyWith(
          currentFen: chess.fen,
          moveHistory: newHistory,
          currentMoveIndex: newHistory.length - 1,
        );

        _scheduleFetch();
      }
    } catch (e) {
      state = state.copyWith(error: 'Invalid move: $uci');
    }
  }

  /// Rebuild chess position from move history
  void _rebuildChessPosition() {
    _chess = Chess();
    for (
      var i = 0;
      i <= state.currentMoveIndex && i < state.moveHistory.length;
      i++
    ) {
      final uci = state.moveHistory[i];
      final from = uci.substring(0, 2);
      final to = uci.substring(2, 4);
      final promotion = uci.length > 4 ? uci[4] : null;
      chess.move({
        'from': from,
        'to': to,
        if (promotion != null) 'promotion': promotion,
      });
    }
  }

  /// Go to previous move
  void goBack() {
    if (!state.canGoBack) return;

    final newIndex = state.currentMoveIndex - 1;
    _chess = Chess();

    // Replay moves up to new index
    for (var i = 0; i <= newIndex && i < state.moveHistory.length; i++) {
      final uci = state.moveHistory[i];
      final from = uci.substring(0, 2);
      final to = uci.substring(2, 4);
      final promotion = uci.length > 4 ? uci[4] : null;
      chess.move({
        'from': from,
        'to': to,
        if (promotion != null) 'promotion': promotion,
      });
    }

    state = state.copyWith(
      currentMoveIndex: newIndex,
      currentFen:
          newIndex >= 0
              ? chess.fen
              : 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    );

    _scheduleFetch();
  }

  /// Go to next move
  void goForward() {
    if (!state.canGoForward) return;

    final newIndex = state.currentMoveIndex + 1;
    _rebuildChessPosition();

    // Make one more move
    final uci = state.moveHistory[newIndex];
    final from = uci.substring(0, 2);
    final to = uci.substring(2, 4);
    final promotion = uci.length > 4 ? uci[4] : null;
    chess.move({
      'from': from,
      'to': to,
      if (promotion != null) 'promotion': promotion,
    });

    state = state.copyWith(currentMoveIndex: newIndex, currentFen: chess.fen);

    _scheduleFetch();
  }

  /// Go to first position
  void goToStart() {
    _chess = Chess();
    state = state.copyWith(
      currentMoveIndex: -1,
      currentFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    );
    _scheduleFetch();
  }

  /// Go to last position
  void goToEnd() {
    if (state.moveHistory.isEmpty) return;

    _chess = Chess();
    for (final uci in state.moveHistory) {
      final from = uci.substring(0, 2);
      final to = uci.substring(2, 4);
      final promotion = uci.length > 4 ? uci[4] : null;
      chess.move({
        'from': from,
        'to': to,
        if (promotion != null) 'promotion': promotion,
      });
    }

    state = state.copyWith(
      currentMoveIndex: state.moveHistory.length - 1,
      currentFen: chess.fen,
    );

    _scheduleFetch();
  }

  /// Go to specific move index
  void goToMove(int index) {
    if (index < -1 || index >= state.moveHistory.length) return;

    _chess = Chess();
    for (var i = 0; i <= index && i < state.moveHistory.length; i++) {
      final uci = state.moveHistory[i];
      final from = uci.substring(0, 2);
      final to = uci.substring(2, 4);
      final promotion = uci.length > 4 ? uci[4] : null;
      chess.move({
        'from': from,
        'to': to,
        if (promotion != null) 'promotion': promotion,
      });
    }

    state = state.copyWith(
      currentMoveIndex: index,
      currentFen:
          index >= 0
              ? chess.fen
              : 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    );

    _scheduleFetch();
  }

  /// Reset to initial position
  void reset() {
    _chess = Chess();
    state = const GamebaseExplorerState();
    _scheduleFetch();
  }

  /// Set position from FEN (for loading a specific position)
  void setPosition(String fen) {
    try {
      _chess = Chess.fromFEN(fen);
      state = state.copyWith(
        currentFen: fen,
        moveHistory: [],
        currentMoveIndex: -1,
      );
      _scheduleFetch();
    } catch (e) {
      state = state.copyWith(error: 'Invalid FEN: $fen');
    }
  }

  /// Update filters and refetch data
  void updateFilters(GamebaseFilters filters) {
    state = state.copyWith(filters: filters);
    _scheduleFetch();
  }

  /// Toggle a time control filter
  void toggleTimeControl(TimeControl timeControl) {
    final current = state.filters.timeControls;
    if (current.contains(timeControl)) {
      updateFilters(state.filters.copyWith(timeControls: const []));
    } else {
      updateFilters(state.filters.copyWith(timeControls: [timeControl]));
    }
  }

  /// Set rating range filter
  void setRatingRange(int? minRating, int? maxRating) {
    updateFilters(
      state.filters.copyWith(minRating: minRating, maxRating: maxRating),
    );
  }

  /// Add a player filter
  void addPlayerFilter(GamebasePlayer player) {
    updateFilters(
      state.filters.copyWith(
        playerIds: [player.id],
        selectedPlayers: [player],
      ),
    );
  }

  /// Remove a player filter
  void removePlayerFilter(String playerId) {
    final currentIds = List<String>.from(state.filters.playerIds);
    final currentPlayers = List<GamebasePlayer>.from(
      state.filters.selectedPlayers,
    );

    currentIds.remove(playerId);
    currentPlayers.removeWhere((p) => p.id == playerId);
    updateFilters(
      state.filters.copyWith(
        playerIds: currentIds,
        selectedPlayers: currentPlayers,
      ),
    );
  }

  /// Clear all filters
  void clearFilters() {
    updateFilters(const GamebaseFilters());
  }

  /// Select a game to view
  void selectGame(GamebaseGame game) {
    state = state.copyWith(selectedGame: game);
  }

  /// Clear selected game
  void clearSelectedGame() {
    state = state.copyWith(selectedGame: null);
  }

  /// Refresh current position data
  Future<void> refresh() async {
    await _fetchMoveAggregates();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

/// Main provider for Gamebase explorer state.
final gamebaseExplorerProvider = StateNotifierProvider.autoDispose<
  GamebaseExplorerNotifier,
  GamebaseExplorerState
>((ref) => GamebaseExplorerNotifier(ref));

/// Provider for searching players.
final playerSearchProvider = FutureProvider.autoDispose
    .family<List<GamebasePlayer>, String>((ref, query) async {
      if (query.isEmpty || query.length < 2) return [];

      final repository = ref.read(gamebaseRepositoryProvider);
      return repository.getPlayers(name: query, pageSize: 20);
    });

/// Provider for fetching a single player by ID.
final playerByIdProvider = FutureProvider.autoDispose
    .family<GamebasePlayer?, String>((ref, playerId) async {
      final repository = ref.read(gamebaseRepositoryProvider);
      return repository.getPlayerById(playerId);
    });

/// Provider for fetching a single game by ID.
final gameByIdProvider = FutureProvider.autoDispose
    .family<GamebaseGame?, String>((ref, gameId) async {
      final repository = ref.read(gamebaseRepositoryProvider);
      return repository.getGameById(gameId);
    });
