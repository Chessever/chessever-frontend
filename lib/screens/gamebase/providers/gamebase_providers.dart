import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chess/chess.dart' hide State;
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'dart:async';

import 'gamebase_explorer_state.dart';

/// Normalize a FEN string for Gamebase lookups.
///
/// Ensure the FEN is well-formed and whitespace-normalized for API lookups.
///
/// Some callers/libraries may emit 4-field FENs (without halfmove/fullmove).
/// The Gamebase API expects a standard 6-field FEN, so we append counters when
/// missing while preserving existing counters for progressed positions.
String normalizeFenForGamebase(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  if (parts.length < 4) return fen.trim();
  if (parts.length == 4) return '${parts.join(' ')} 0 1';
  return parts.take(6).join(' ');
}

/// StateNotifier for managing Gamebase explorer state.
class GamebaseExplorerNotifier extends StateNotifier<GamebaseExplorerState> {
  GamebaseExplorerNotifier(this.ref) : super(const GamebaseExplorerState());
  // NOTE: We intentionally do NOT fetch in the constructor.
  // The view calls setPosition() with the actual board FEN, which triggers
  // the fetch. Fetching here with the default starting FEN causes a race
  // condition where the starting position response can overwrite the real
  // position's data.

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

    // Immediately reflect loading state so the UI doesn't flash "No games found"
    // during the debounce window.
    state = state.copyWith(isLoading: true, error: null);

    if (delay == Duration.zero) {
      Future.microtask(_fetchMoveAggregates);
      return;
    }

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
          state.filters.playerIds.isNotEmpty
              ? state.filters.playerIds.first
              : null;

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
          currentFen: normalizeFenForGamebase(chess.fen),
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
              ? normalizeFenForGamebase(chess.fen)
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

    state = state.copyWith(
      currentMoveIndex: newIndex,
      currentFen: normalizeFenForGamebase(chess.fen),
    );

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
      currentFen: normalizeFenForGamebase(chess.fen),
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
              ? normalizeFenForGamebase(chess.fen)
              : 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    );

    _scheduleFetch();
  }

  /// Reset to initial position
  void reset() {
    _chess = Chess();
    state = const GamebaseExplorerState(
      currentFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      currentMoveIndex: -1,
    );
    _scheduleFetch(Duration.zero);
  }

  /// Set position from FEN (for loading a specific position)
  void setPosition(String fen) {
    try {
      final normalized = normalizeFenForGamebase(fen);

      // Skip if FEN hasn't changed to avoid unnecessary API calls
      if (state.currentFen == normalized) {
        debugPrint('[GamebaseExplorer] setPosition: FEN unchanged, skipping');
        return;
      }

      debugPrint(
        '[GamebaseExplorer] setPosition: ${normalized.split(' ').take(2).join(' ')}...',
      );
      _chess = Chess.fromFEN(normalized);
      state = state.copyWith(
        currentFen: normalized,
        moveHistory: [],
        currentMoveIndex: -1,
      );
      _scheduleFetch();
    } catch (e) {
      debugPrint('[GamebaseExplorer] setPosition error: $e');
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
      state.filters.copyWith(playerIds: [player.id], selectedPlayers: [player]),
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

/// Fetches a lightweight game "preview" by game UUID via global search.
///
/// Gamebase `/api/game/{id}` can fail in production; global search can still
/// return stable metadata (date/players/opening) for a specific UUID.
final gamePreviewByIdProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, gameId) async {
      if (gameId.trim().isEmpty) return null;

      final repository = ref.read(gamebaseRepositoryProvider);
      final response = await repository.globalSearch(
        query: gameId.trim(),
        pageNumber: 1,
        pageSize: 5,
      );

      for (final r in response.results) {
        if (r.resource != 'game') continue;
        final preview = r.preview ?? const <String, dynamic>{};
        final id = preview['id']?.toString() ?? r.id;
        if (id == gameId) {
          return <String, dynamic>{'id': id, ...preview};
        }
      }

      return null;
    });

/// Fetches a full game with PGN by game UUID.
/// Returns null if the game cannot be fetched (e.g., API error).
final gameWithPgnByIdProvider = FutureProvider.autoDispose
    .family<GamebaseGameWithPgn?, String>((ref, gameId) async {
      if (gameId.trim().isEmpty) return null;

      final repository = ref.read(gamebaseRepositoryProvider);
      return repository.getGameWithPgn(gameId.trim());
    });
