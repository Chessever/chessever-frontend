import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chess/chess.dart' hide State;
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'dart:async';
import 'dart:collection';

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

/// Convert a 6-field FEN into number of played plies.
int _pliesFromFen(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  if (parts.length < 6) return 0;
  final turn = parts[1];
  final fullMove = int.tryParse(parts[5]) ?? 1;
  final base = (fullMove - 1) * 2;
  return base + (turn == 'b' ? 1 : 0);
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
  static final RegExp _uciRegex = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');
  static const Duration _memoryCacheTtl = Duration(minutes: 10);
  static const int _memoryCacheMaxEntries = 300;
  final LinkedHashMap<String, _PositionAggregateCacheEntry> _positionCache =
      LinkedHashMap<String, _PositionAggregateCacheEntry>();

  Chess get chess {
    _chess ??= Chess();
    return _chess!;
  }

  void _scheduleFetch([Duration delay = const Duration(milliseconds: 200)]) {
    _debounceTimer?.cancel();

    if (delay == Duration.zero) {
      Future.microtask(_fetchMoveAggregates);
      return;
    }

    _debounceTimer = Timer(delay, _fetchMoveAggregates);
  }

  bool _canPrefetchWithActiveFilters() {
    // Safe prefetch mode: player-scoped explorer with no extra filters.
    // This keeps load bounded while making per-move navigation feel instant.
    final f = state.filters;
    return f.playerIds.length == 1 &&
        f.timeControls.isEmpty &&
        f.minRating == null &&
        f.maxRating == null;
  }

  /// Fetch move aggregates for current position
  Future<void> _fetchMoveAggregates() async {
    final fetchId = ++_fetchToken;
    final requestedFen = state.currentFen;

    // Only send the explored line up to the current position.
    // moveHistory may contain "future" moves when the user navigates back.
    final exploredMoves =
        state.currentMoveIndex >= 0
            ? state.moveHistory.sublist(0, state.currentMoveIndex + 1)
            : const <String>[];

    final cacheKey = _buildCacheKey(
      fen: requestedFen,
      exploredMoves: exploredMoves,
      filters: state.filters,
    );
    final cached = _getFreshCacheEntry(cacheKey);
    if (cached != null) {
      state = state.copyWith(
        moveAggregates: cached,
        isLoading: false,
        error: null,
      );
      return;
    }

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
        moves: exploredMoves,
        timeControl: timeControlFilter,
        minRating: state.filters.minRating,
        maxRating: state.filters.maxRating,
        playerId: playerIdFilter,
      );

      // Ignore if a newer request started or FEN changed while awaiting.
      if (fetchId != _fetchToken || requestedFen != state.currentFen) return;

      final aggregates = response.data.moves
          .where((m) => _isLegalUciForFen(m.uci, state.currentFen))
          .toList(growable: false);

      // Sort by total games descending
      aggregates.sort((a, b) => b.total.compareTo(a.total));

      _putCacheEntry(cacheKey, aggregates);
      state = state.copyWith(moveAggregates: aggregates, isLoading: false);

      // Opportunistically prefetch a few likely next positions to make the
      // explorer feel instantaneous even when backend caches are cold.
      // Skip prefetch when filters are active because those paths can be slow.
      if (!state.hasActiveFilters || _canPrefetchWithActiveFilters()) {
        _prefetchNextPositions(
          repository: repository,
          baseFen: state.currentFen,
          exploredMoves: exploredMoves,
          aggregates: aggregates,
        );
      }
    } catch (e) {
      if (fetchId != _fetchToken) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void _prefetchNextPositions({
    required GamebaseRepository repository,
    required String baseFen,
    required List<String> exploredMoves,
    required List<MoveAggregate> aggregates,
  }) {
    // Keep this conservative: it's a perf win, but we don't want to DDOS our own API.
    final maxPrefetch = _canPrefetchWithActiveFilters() ? 2 : 3;
    final filters = state.filters;
    final timeControlFilter =
        filters.timeControls.isNotEmpty ? filters.timeControls.first : null;
    final playerIdFilter =
        filters.playerIds.isNotEmpty ? filters.playerIds.first : null;

    for (final a in aggregates.take(maxPrefetch)) {
      try {
        final chess = Chess.fromFEN(baseFen);
        final from = a.uci.substring(0, 2);
        final to = a.uci.substring(2, 4);
        final promotion = a.uci.length > 4 ? a.uci[4] : null;
        final moved = chess.move({
          'from': from,
          'to': to,
          if (promotion != null) 'promotion': promotion,
        });
        if (!moved) continue;

        final nextFen = normalizeFenForGamebase(chess.fen);
        final nextMoves = <String>[...exploredMoves, a.uci];

        // Fire-and-forget; cache fill only.
        unawaited(() async {
          try {
            final response = await repository.getMoveAggregates(
              fen: nextFen,
              moves: nextMoves,
              timeControl: timeControlFilter,
              minRating: filters.minRating,
              maxRating: filters.maxRating,
              playerId: playerIdFilter,
            );
            final prefetched = response.data.moves
                .where((m) => _isLegalUciForFen(m.uci, nextFen))
                .toList(growable: false)
              ..sort((a, b) => b.total.compareTo(a.total));
            _putCacheEntry(
              _buildCacheKey(
                fen: nextFen,
                exploredMoves: nextMoves,
                filters: filters,
              ),
              prefetched,
            );
          } catch (_) {
            // Ignore prefetch failures.
          }
        }());
      } catch (_) {
        // Ignore prefetch failures.
      }
    }
  }

  bool _isLegalUciForFen(String uci, String fen) {
    if (!_uciRegex.hasMatch(uci)) return false;
    try {
      final testBoard = Chess.fromFEN(fen);
      final from = uci.substring(0, 2);
      final to = uci.substring(2, 4);
      final promotion = uci.length > 4 ? uci[4] : null;
      return testBoard.move({
        'from': from,
        'to': to,
        if (promotion != null) 'promotion': promotion,
      });
    } catch (_) {
      return false;
    }
  }

  /// Make a move on the board (UCI format)
  void makeMove(String uci) {
    final normalizedUci = uci.trim().toLowerCase();
    if (!_uciRegex.hasMatch(normalizedUci)) return;

    // Rapid taps can race with async aggregate refreshes; ignore stale moves
    // that are no longer legal in the current explorer position.
    if (!_isLegalUciForFen(normalizedUci, state.currentFen)) {
      debugPrint(
        '[GamebaseExplorer] Ignoring stale/illegal move: $normalizedUci',
      );
      return;
    }

    try {
      // Parse UCI move
      final from = normalizedUci.substring(0, 2);
      final to = normalizedUci.substring(2, 4);
      final promotion = normalizedUci.length > 4 ? normalizedUci[4] : null;

      // Reset chess to current position if needed
      _rebuildChessPosition();

      // Make the move
      final moved = chess.move({
        'from': from,
        'to': to,
        if (promotion != null) 'promotion': promotion,
      });

      if (moved) {
        // If we're not at the end of history, truncate
        final newHistory = state.moveHistory.sublist(
          0,
          state.currentMoveIndex + 1,
        )..add(normalizedUci);

        state = state.copyWith(
          currentFen: normalizeFenForGamebase(chess.fen),
          moveHistory: newHistory,
          currentMoveIndex: newHistory.length - 1,
        );

        _scheduleFetch(Duration.zero);
      }
    } catch (e) {
      debugPrint('[GamebaseExplorer] makeMove error for $normalizedUci: $e');
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

    _scheduleFetch(Duration.zero);
  }

  /// Go to next move.
  ///
  /// If there is a stored next move in the explored line, replay it.
  /// Otherwise, automatically play the most-played move from the current
  /// position's aggregates (so the forward button is always usable).
  void goForward() {
    if (!state.canGoForward) return;

    if (state.currentMoveIndex < state.maxNavigableMoveIndex) {
      // Replay the next stored move in history.
      final newIndex = state.currentMoveIndex + 1;
      _rebuildChessPosition();

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

      _scheduleFetch(Duration.zero);
    } else if (!state.isLoading && state.moveAggregates.isNotEmpty) {
      // At the frontier — play the most-played move from current position.
      makeMove(state.moveAggregates.first.uci);
    }
  }

  /// Go to first position
  void goToStart() {
    _chess = Chess();
    state = state.copyWith(
      currentMoveIndex: -1,
      currentFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    );
    _scheduleFetch(Duration.zero);
  }

  /// Go to last position.
  ///
  /// If not already at the frontier of the explored line, jump there.
  /// If already at the frontier, play the most-played aggregate move (same
  /// behaviour as [goForward]).
  void goToEnd() {
    final targetIndex = state.maxNavigableMoveIndex;
    if (targetIndex > state.currentMoveIndex) {
      goToMove(targetIndex);
    } else if (!state.isLoading && state.moveAggregates.isNotEmpty) {
      makeMove(state.moveAggregates.first.uci);
    }
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

    _scheduleFetch(Duration.zero);
  }

  /// Initialize the explorer pre-filtered to a specific player.
  ///
  /// Sets the player filter and starting position atomically, then fires a
  /// single fetch. Avoids the double-fetch that would occur if [goToStart]
  /// and [addPlayerFilter] were called separately.
  void initializeWithPlayer(GamebasePlayer player) {
    _chess = Chess();
    state = GamebaseExplorerState(
      currentFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      currentMoveIndex: -1,
      filters: GamebaseFilters(
        playerIds: [player.id],
        selectedPlayers: [player],
      ),
    );
    _scheduleFetch(Duration.zero);
  }

  /// Reset to initial position.
  ///
  /// When [fetch] is false, this is used for exit/teardown paths where we
  /// want local state cleared without firing a new network request.
  void reset({bool fetch = true}) {
    _debounceTimer?.cancel();
    // Invalidate any in-flight response from a previous position.
    _fetchToken++;
    _chess = Chess();
    state = const GamebaseExplorerState(
      currentFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      currentMoveIndex: -1,
    );
    if (fetch) {
      _scheduleFetch(Duration.zero);
    }
  }

  /// Set position from FEN (for loading a specific position)
  void setPosition(String fen) {
    setPositionWithMoves(fen, const <String>[]);
  }

  /// Set position from board FEN and full explored move line (UCI).
  ///
  /// This keeps the explorer aligned with the board and enables backend deep
  /// line aggregation beyond the indexed opening window.
  void setPositionWithMoves(String fen, List<String> moves) {
    try {
      final normalized = normalizeFenForGamebase(fen);
      final sanitizedMoves = moves
          .map((m) => m.trim().toLowerCase())
          .where((m) => RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$').hasMatch(m))
          .toList(growable: false);
      final expectedPlyCount = _pliesFromFen(normalized);
      final clampedMoves =
          sanitizedMoves.length > expectedPlyCount
              ? sanitizedMoves.sublist(0, expectedPlyCount)
              : sanitizedMoves;
      final newIndex = clampedMoves.isEmpty ? -1 : clampedMoves.length - 1;

      // Skip if nothing changed to avoid unnecessary API calls.
      if (state.currentFen == normalized &&
          state.currentMoveIndex == newIndex &&
          listEquals(state.moveHistory, clampedMoves)) {
        debugPrint(
          '[GamebaseExplorer] setPositionWithMoves: position unchanged, skipping',
        );
        return;
      }

      debugPrint(
        '[GamebaseExplorer] setPosition: ${normalized.split(' ').take(2).join(' ')}...',
      );
      _chess = Chess.fromFEN(normalized);
      state = state.copyWith(
        currentFen: normalized,
        moveHistory: clampedMoves,
        currentMoveIndex: newIndex,
      );
      _scheduleFetch(Duration.zero);
    } catch (e) {
      debugPrint('[GamebaseExplorer] setPosition error: $e');
      state = state.copyWith(error: 'Invalid FEN: $fen');
    }
  }

  /// Update filters and refetch data
  void updateFilters(GamebaseFilters filters) {
    state = state.copyWith(filters: filters);
    _scheduleFetch(Duration.zero);
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

  String _buildCacheKey({
    required String fen,
    required List<String> exploredMoves,
    required GamebaseFilters filters,
  }) {
    final timeControl =
        filters.timeControls.isNotEmpty
            ? filters.timeControls.first.name
            : 'any';
    final playerId =
        filters.playerIds.isNotEmpty ? filters.playerIds.first : 'any';
    final minRating = filters.minRating?.toString() ?? 'any';
    final maxRating = filters.maxRating?.toString() ?? 'any';

    return [
      fen,
      exploredMoves.join(','),
      timeControl,
      playerId,
      minRating,
      maxRating,
    ].join('|');
  }

  List<MoveAggregate>? _getFreshCacheEntry(String key) {
    final entry = _positionCache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.cachedAt) > _memoryCacheTtl) {
      _positionCache.remove(key);
      return null;
    }
    return entry.moves;
  }

  void _putCacheEntry(String key, List<MoveAggregate> moves) {
    if (moves.isEmpty) return;
    _positionCache.remove(key);
    _positionCache[key] = _PositionAggregateCacheEntry(
      moves: List<MoveAggregate>.unmodifiable(moves),
      cachedAt: DateTime.now(),
    );
    while (_positionCache.length > _memoryCacheMaxEntries) {
      _positionCache.remove(_positionCache.keys.first);
    }
  }
}

class _PositionAggregateCacheEntry {
  const _PositionAggregateCacheEntry({
    required this.moves,
    required this.cachedAt,
  });

  final List<MoveAggregate> moves;
  final DateTime cachedAt;
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

class GamebasePositionGamesQuery {
  final String fen;
  final List<String> moves;
  final String? uci;
  final TimeControl? timeControl;
  final String? playerId;
  final int? minRating;
  final int? maxRating;
  final int pageNumber; // 0-indexed
  final int pageSize;

  const GamebasePositionGamesQuery({
    required this.fen,
    this.moves = const <String>[],
    this.uci,
    this.timeControl,
    this.playerId,
    this.minRating,
    this.maxRating,
    this.pageNumber = 0,
    this.pageSize = 20,
  });

  @override
  bool operator ==(Object other) {
    return other is GamebasePositionGamesQuery &&
        other.fen == fen &&
        listEquals(other.moves, moves) &&
        other.uci == uci &&
        other.timeControl == timeControl &&
        other.playerId == playerId &&
        other.minRating == minRating &&
        other.maxRating == maxRating &&
        other.pageNumber == pageNumber &&
        other.pageSize == pageSize;
  }

  @override
  int get hashCode => Object.hash(
    fen,
    Object.hashAll(moves),
    uci,
    timeControl,
    playerId,
    minRating,
    maxRating,
    pageNumber,
    pageSize,
  );
}

final positionGamesProvider = FutureProvider.autoDispose
    .family<GamebaseSearchQueryResponse, GamebasePositionGamesQuery>((
      ref,
      query,
    ) async {
      final repository = ref.read(gamebaseRepositoryProvider);
      return repository.getPositionGames(
        fen: query.fen,
        moves: query.moves,
        uci: query.uci,
        timeControl: query.timeControl,
        playerId: query.playerId,
        minRating: query.minRating,
        maxRating: query.maxRating,
        pageNumber: query.pageNumber,
        pageSize: query.pageSize,
      );
    });
