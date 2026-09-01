import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/memorial_tree_scope.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/services/player_opening_tree.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
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
  if (parts.length == 5) return '${parts.join(' ')} 1';
  return parts.take(6).join(' ');
}

String _positionKeyForComparison(String fen) =>
    normalizeFenForGamebase(fen).split(RegExp(r'\s+')).take(4).join(' ');

/// Backend fast (materialized-view / FEN-indexed) coverage ends at positions
/// after 20 played plies — `OPENING_EXPLORER_MAX_INDEXED_PLY` / `MV_MAX_PLY`
/// server-side. The next position after this needs the replay-backed path,
/// which is materially more expensive, so broad prefetch must stop before
/// crossing that boundary.
///
/// This was 60 (30 full moves), which is where exact indexed *storage* ends,
/// not where the fast lookup does. The effect was that every navigation
/// between ply 21 and 60 fanned out 3-4 extra replay-path queries, starving
/// the request the user was actually waiting on right at the depth the
/// explorer starts to matter.
const int _kExactIndexedExplorerMaxPly = 20;

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
  static const String _kInitialFen =
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  GamebaseExplorerNotifier(this.ref)
    : super(
        GamebaseExplorerState(
          currentFen: _kInitialFen,
          game: ChessGame(
            gameId: 'explorer_initial',
            startingFen: _kInitialFen,
            metadata: {
              'Event': 'Opening Explorer',
              'Site': 'ChessEver',
              'Date': DateTime.now().toIso8601String().split('T')[0],
              'White': 'White',
              'Black': 'Black',
              'Result': '*',
            },
            mainline: const [],
          ),
          movePointer: const [],
        ),
      );

  final Ref ref;

  /// Internal position tracking using dartchess (consistent with ChessGame)
  Position get currentPosition =>
      Position.setupPosition(Rule.chess, Setup.parseFen(state.currentFen));

  /// Debounce timer for network fetches
  Timer? _debounceTimer;

  /// Monotonic token to ignore stale responses
  int _fetchToken = 0;
  static final RegExp _uciRegex = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');
  static const Duration _memoryCacheTtl = Duration(minutes: 10);
  static const int _memoryCacheMaxEntries = 300;
  final LinkedHashMap<String, _PositionAggregateCacheEntry> _positionCache =
      LinkedHashMap<String, _PositionAggregateCacheEntry>();
  final Map<String, Future<List<MoveAggregate>>> _inFlightAggregateRequests =
      {};
  String? _enabledLocalPlayerTreeId;

  /// Move line that must be sent with the next aggregates request.
  ///
  /// Independent of the in-memory game tree. When `setPositionWithMoves`
  /// fails to rebuild a tree (or rewrites `startingFen` to the deep FEN after
  /// a path mismatch), `state.exploredMoves` becomes empty and fetch used to
  /// ship `moves: []` — which the server answers empty past ply 20. The board
  /// panel's line is the source of truth for the query; keep it here.
  List<String> _queryMoves = const <String>[];
  bool _queryFromInitial = true;

  /// Ply offset carried when the workspace starts from an arbitrary FEN.
  ///
  /// [GamebaseExplorerState.currentMoveNumber] is relative to its local game
  /// tree. Board Editor intentionally starts a new tree, so without this
  /// offset a deep edited position would look like move 1 and bypass the
  /// Explorer depth gate. Keep access depth in the notifier rather than
  /// encoding fake move counters into the edited FEN.
  int _accessMoveNumberOffset = 0;

  int get effectiveMoveNumber =>
      state.currentMoveNumber + _accessMoveNumberOffset;

  void _syncQueryMovesFromTree() {
    if (state.game != null && _isInitialFen(state.game!.startingFen)) {
      _queryFromInitial = true;
      _queryMoves = List<String>.unmodifiable(state.exploredMoves);
    }
  }

  /// Play SFX for a SAN move string if sound is enabled.
  void _playSfx(String san) {
    final boardSettings = ref.read(boardSettingsProviderNew).valueOrNull;
    if (boardSettings?.soundEnabled != true) return;
    AudioPlayerService.instance.playSfxForSan(san);
  }

  /// Get the SAN for a UCI move at the current position.
  String? _getSanForUci(String uci) {
    try {
      final playedMove = NormalMove.fromUci(uci);
      if (!currentPosition.isLegal(playedMove)) return null;
      final (_, san) = currentPosition.makeSan(playedMove);
      return san;
    } catch (_) {
      return null;
    }
  }

  void _scheduleFetch([Duration delay = const Duration(milliseconds: 200)]) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, _fetchMoveAggregates);
  }

  bool _isPlayerScopedOnlyFilter(GamebaseFilters f) {
    // Safe aggressive prefetch mode: player-scoped explorer with no extra
    // filters (color is fine — same player, same index). Keeps load bounded
    // while making per-move navigation feel instant.
    return f.playerIds.length == 1 &&
        f.timeControls.isEmpty &&
        f.minRating == null &&
        f.maxRating == null &&
        f.yearFrom == null &&
        f.yearTo == null &&
        f.isOnline == null;
  }

  bool _hasActiveFilters(GamebaseFilters f) {
    return f.playerIds.isNotEmpty ||
        f.timeControls.isNotEmpty ||
        f.minRating != null ||
        f.maxRating != null ||
        f.yearFrom != null ||
        f.yearTo != null ||
        f.playerColor != null ||
        f.gameResult != null ||
        f.isOnline != null;
  }

  Future<List<MoveAggregate>> _getOrStartAggregatesRequest({
    required String cacheKey,
    required GamebaseRepository repository,
    required String fen,
    required List<String> exploredMoves,
    required GamebaseFilters filters,
  }) {
    final existing = _inFlightAggregateRequests[cacheKey];
    if (existing != null) return existing;

    final timeControlFilter = filters.timeControls.isNotEmpty
        ? filters.timeControls.first
        : null;
    final playerIdFilter = filters.playerIds.isNotEmpty
        ? filters.playerIds.first
        : null;

    final colorFilter = filters.playerColor?.name;
    final resultFilter = filters.gameResult?.apiValue;

    final future = () async {
      final response = await repository.getMoveAggregates(
        fen: fen,
        moves: exploredMoves,
        timeControl: timeControlFilter,
        minRating: filters.minRating,
        maxRating: filters.maxRating,
        playerId: playerIdFilter,
        color: colorFilter,
        result: resultFilter,
        yearFrom: filters.yearFrom,
        yearTo: filters.yearTo,
        isOnline: filters.isOnline,
      );

      final aggregates = response.data.moves
          .where((m) => _isLegalUciForFen(m.uci, fen))
          .toList(growable: false);
      aggregates.sort((a, b) => b.total.compareTo(a.total));
      return aggregates;
    }();

    _inFlightAggregateRequests[cacheKey] = future;
    unawaited(
      future
          .whenComplete(() {
            if (identical(_inFlightAggregateRequests[cacheKey], future)) {
              _inFlightAggregateRequests.remove(cacheKey);
            }
          })
          .catchError((_) {
            // The request owner (or the prefetch call site) reports the
            // failure. This bookkeeping future must not rethrow into the
            // zone as an unhandled async error.
            return const <MoveAggregate>[];
          }),
    );

    return future;
  }

  bool _isInitialFen(String fen) {
    final normalized = normalizeFenForGamebase(fen);
    final initialNormalized = normalizeFenForGamebase(_kInitialFen);
    // Ignore halfmove/fullmove for comparison
    final parts1 = normalized.split(' ');
    final parts2 = initialNormalized.split(' ');
    if (parts1.length < 4 || parts2.length < 4) return false;
    for (var i = 0; i < 4; i++) {
      if (parts1[i] != parts2[i]) return false;
    }
    return true;
  }

  /// Fetch move aggregates for current position
  Future<void> _fetchMoveAggregates() async {
    final fetchId = ++_fetchToken;
    final requestedFen = state.currentFen;
    final filtersSnapshot = state.filters;

    final localPlayerId = _localTreePlayerId(filtersSnapshot);
    if (localPlayerId != null && isLocalPlayerTreeEnabledFor(localPlayerId)) {
      final localState = ref.read(playerOpeningTreeProvider(localPlayerId));
      ref.read(playerOpeningTreeProvider(localPlayerId).notifier).start();
      final localMoves = localState.index.movesForFen(
        requestedFen,
        filters: _localTreeCriteria(filtersSnapshot, localPlayerId),
      );
      state = state.copyWith(
        moveAggregates: localMoves,
        isLoading: localState.progress.isRunning,
        error: localState.progress.status == PlayerOpeningTreeStatus.error
            ? localState.progress.error
            : null,
      );
      return;
    }

    // Desktop board explorer always sends the line the board just pumped in.
    // `_queryMoves` is that line. Never fall back to an empty tree path after
    // a rebuild miss — that is exactly "No move statistics" past ply 20.
    final exploredMoves = _queryFromInitial ? _queryMoves : const <String>[];

    if (kDebugMode &&
        _queryFromInitial &&
        exploredMoves.isEmpty &&
        _pliesFromFen(requestedFen) > 20) {
      debugPrint(
        '[GamebaseExplorer] WARNING: deep FEN query with empty moves line — '
        'aggregates will be empty. fen=${requestedFen.split(' ').take(2).join(' ')}',
      );
    }

    final cacheKey = _buildCacheKey(
      fen: requestedFen,
      exploredMoves: exploredMoves,
      filters: filtersSnapshot,
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

    // Clear stale aggregates while loading to prevent accidental clicks on
    // moves that are illegal in the NEW position.
    state = state.copyWith(
      isLoading: true,
      error: null,
      moveAggregates: const [],
    );

    try {
      final repository = ref.read(gamebaseRepositoryProvider);
      final aggregates = await _getOrStartAggregatesRequest(
        cacheKey: cacheKey,
        repository: repository,
        fen: requestedFen,
        exploredMoves: exploredMoves,
        filters: filtersSnapshot,
      );

      // Ignore if a newer request started or FEN changed while awaiting.
      if (fetchId != _fetchToken || requestedFen != state.currentFen) return;

      _putCacheEntry(cacheKey, aggregates);
      state = state.copyWith(moveAggregates: aggregates, isLoading: false);

      // Opportunistically prefetch a few likely next positions to make the
      // explorer feel instantaneous even when backend caches are cold.
      // Skip prefetch when filters are active because those paths can be slow.
      if (!_hasActiveFilters(filtersSnapshot) ||
          _isPlayerScopedOnlyFilter(filtersSnapshot)) {
        _prefetchNextPositions(
          repository: repository,
          baseFen: requestedFen,
          exploredMoves: exploredMoves,
          aggregates: aggregates,
          filters: filtersSnapshot,
        );
      }
    } catch (e, st) {
      talker.handle(e, st);
      if (fetchId != _fetchToken) return;
      state = state.copyWith(isLoading: false, error: userFacingError(e));
    }
  }

  void _prefetchNextPositions({
    required GamebaseRepository repository,
    required String baseFen,
    required List<String> exploredMoves,
    required List<MoveAggregate> aggregates,
    required GamebaseFilters filters,
  }) {
    // Keep this conservative: it's a perf win, but we don't want to DDOS our own API.
    // The backend now serves exact indexed explorer data through 30 full moves
    // (60 played plies). Keep normal fanout inside that fast indexed window,
    // then throttle once prefetching the next position would use replay.
    final playerScoped = _isPlayerScopedOnlyFilter(filters);
    final currentPly = _pliesFromFen(baseFen);
    final nextPositionRequiresReplay =
        currentPly >= _kExactIndexedExplorerMaxPly;
    final maxPrefetch = nextPositionRequiresReplay
        ? (playerScoped ? 1 : 0)
        : (playerScoped ? 4 : 3);
    if (maxPrefetch <= 0) return;
    final candidates = aggregates.length <= maxPrefetch
        ? aggregates
        : aggregates.sublist(0, maxPrefetch);

    for (var i = 0; i < candidates.length; i++) {
      final a = candidates[i];
      try {
        final position = Position.setupPosition(
          Rule.chess,
          Setup.parseFen(baseFen),
        );
        final move = NormalMove.fromUci(a.uci);
        if (!position.isLegal(move)) continue;

        final nextPosition = position.play(move);
        final nextFen = normalizeFenForGamebase(nextPosition.fen);
        final nextMoves = <String>[...exploredMoves, a.uci];
        final nextCacheKey = _buildCacheKey(
          fen: nextFen,
          exploredMoves: nextMoves,
          filters: filters,
        );

        if (_getFreshCacheEntry(nextCacheKey) != null ||
            _inFlightAggregateRequests.containsKey(nextCacheKey)) {
          continue;
        }

        // Fire-and-forget; cache fill only.
        unawaited(() async {
          try {
            final prefetched = await _getOrStartAggregatesRequest(
              cacheKey: nextCacheKey,
              repository: repository,
              fen: nextFen,
              exploredMoves: nextMoves,
              filters: filters,
            );
            _putCacheEntry(nextCacheKey, prefetched);

            // Prefetch one extra ply from top branches in player mode only.
            // Skip this in the replay zone to avoid overloading backend.
            if (!nextPositionRequiresReplay &&
                playerScoped &&
                i < 2 &&
                prefetched.isNotEmpty) {
              final reply = prefetched.first;
              final replyPosition = nextPosition;
              final replyMove = NormalMove.fromUci(reply.uci);
              if (replyPosition.isLegal(replyMove)) {
                final nextReplyPosition = replyPosition.play(replyMove);
                final replyFen = normalizeFenForGamebase(nextReplyPosition.fen);
                final replyMoves = <String>[...nextMoves, reply.uci];
                final replyCacheKey = _buildCacheKey(
                  fen: replyFen,
                  exploredMoves: replyMoves,
                  filters: filters,
                );
                if (_getFreshCacheEntry(replyCacheKey) == null &&
                    !_inFlightAggregateRequests.containsKey(replyCacheKey)) {
                  unawaited(
                    _getOrStartAggregatesRequest(
                      cacheKey: replyCacheKey,
                      repository: repository,
                      fen: replyFen,
                      exploredMoves: replyMoves,
                      filters: filters,
                    ),
                  );
                }
              }
            }
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
      final position = Position.setupPosition(Rule.chess, Setup.parseFen(fen));
      final move = NormalMove.fromUci(uci);
      if (position.isLegal(move)) return true;
      final alt = _alternateCastlingMove(position, move);
      return alt != null && position.isLegal(alt);
    } catch (_) {
      return false;
    }
  }

  /// Make a move on the board (UCI format)
  void makeMove(String uci) {
    final normalizedUci = uci.trim().toLowerCase();
    if (!_uciRegex.hasMatch(normalizedUci)) return;

    if (!_isLegalUciForFen(normalizedUci, state.currentFen)) {
      debugPrint(
        '[GamebaseExplorer] Ignoring stale/illegal move: $normalizedUci',
      );
      return;
    }

    try {
      final san = _getSanForUci(normalizedUci);
      if (san != null) _playSfx(san);

      // Replicate Navigator logic
      final playedMove = NormalMove.fromUci(normalizedUci);
      final currentLine = _lineForPointerInGame(state.game!, state.movePointer);
      final currentMove = _moveForPointerInGame(state.game!, state.movePointer);
      final currentIndex = state.movePointer.isEmpty
          ? -1
          : state.movePointer.last;

      // 1. Check if the move is the next move in the current mainline
      if (currentLine != null && currentIndex < currentLine.length - 1) {
        final nextMove = currentLine[currentIndex + 1];
        if (nextMove.uci == normalizedUci) {
          final pointer = List<int>.of(state.movePointer);
          if (pointer.isEmpty) {
            pointer.add(0);
          } else {
            pointer.last = currentIndex + 1;
          }
          state = state.copyWith(
            currentFen: normalizeFenForGamebase(nextMove.fen),
            movePointer: pointer,
          );
          _syncQueryMovesFromTree();
          _scheduleFetch();
          return;
        }
      }

      // 2. Check if the move is an existing variation of the current position
      // For root variations, we check firstMove.variations.
      // For others, we check currentMove.variations.
      final variationsToSearch = currentIndex == -1
          ? (state.game!.mainline.isNotEmpty
                ? state.game!.mainline.first.variations
                : null)
          : currentMove?.variations;

      if (variationsToSearch != null) {
        for (var i = 0; i < variationsToSearch.length; i++) {
          final variation = variationsToSearch[i];
          if (variation.isNotEmpty && variation[0].uci == normalizedUci) {
            final newPointer = state.movePointer.isEmpty
                ? [0, i, 0]
                : [...state.movePointer, i, 0];
            state = state.copyWith(
              currentFen: normalizeFenForGamebase(variation[0].fen),
              movePointer: newPointer,
            );
            _syncQueryMovesFromTree();
            _scheduleFetch();
            return;
          }
        }
      }

      // Create new move/variation
      final position = currentPosition;
      final (newPosition, sanActual) = position.makeSan(playedMove);
      final movingColor = position.turn == Side.white
          ? ChessColor.white
          : ChessColor.black;
      final nextToMove = newPosition.turn == Side.white
          ? ChessColor.white
          : ChessColor.black;

      final moveNumber = currentMove != null
          ? (currentMove.turn == ChessColor.black
                ? currentMove.num + 1
                : currentMove.num)
          : (movingColor == ChessColor.white ? 1 : 1);

      final newChessMove = ChessMove(
        num: moveNumber,
        fen: newPosition.fen,
        san: sanActual,
        uci: normalizedUci,
        turn: nextToMove,
      );

      if (currentIndex == -1) {
        if (state.game!.mainline.isEmpty) {
          state = state.copyWith(
            game: state.game!.copyWith(mainline: [newChessMove]),
            movePointer: [0],
            currentFen: normalizeFenForGamebase(newPosition.fen),
          );
        } else {
          final firstMove = state.game!.mainline.first;
          final updatedVariations = List<ChessLine>.of(
            firstMove.variations ?? <ChessLine>[],
          );
          updatedVariations.add([newChessMove]);

          state = state.copyWith(
            game: state.game!.copyWith(
              mainline: [
                firstMove.copyWith(
                  variations: updatedVariations,
                  overrideVariations: true,
                ),
                ...state.game!.mainline.sublist(1),
              ],
            ),
            movePointer: [0, updatedVariations.length - 1, 0],
            currentFen: normalizeFenForGamebase(newPosition.fen),
          );
        }
      } else if (currentIndex == currentLine!.length - 1) {
        final updatedMainline = _appendMoveAfterPointer(
          state.game!.mainline,
          state.movePointer,
          0,
          newChessMove,
        );
        final newPointer = List<int>.of(state.movePointer);
        newPointer.last = currentIndex + 1;
        state = state.copyWith(
          game: state.game!.copyWith(mainline: updatedMainline),
          movePointer: newPointer,
          currentFen: normalizeFenForGamebase(newPosition.fen),
        );
      } else {
        int? newVariationIndex;
        final updatedMainline = _addVariationToPointer(
          state.game!.mainline,
          state.movePointer,
          0,
          newChessMove,
          (index) => newVariationIndex = index,
        );
        if (newVariationIndex != null) {
          final newPointer = <int>[...state.movePointer, newVariationIndex!, 0];
          state = state.copyWith(
            game: state.game!.copyWith(mainline: updatedMainline),
            movePointer: newPointer,
            currentFen: normalizeFenForGamebase(newPosition.fen),
          );
        }
      }

      _syncQueryMovesFromTree();
      _scheduleFetch(); // Use default debounce
    } catch (e) {
      debugPrint('[GamebaseExplorer] makeMove error for $normalizedUci: $e');
    }
  }

  ChessLine? _lineForPointerInGame(ChessGame game, ChessMovePointer pointer) {
    ChessLine? line = game.mainline;
    ChessMove? move;
    for (var i = 0; i < pointer.length; i++) {
      final index = pointer[i];
      if (i.isEven) {
        if (line == null || index >= line.length) return null;
        move = line[index];
      } else {
        final variations = move?.variations;
        if (variations == null || index >= variations.length) return null;
        line = variations[index];
      }
    }
    return line;
  }

  ChessMove? _moveForPointerInGame(ChessGame game, ChessMovePointer pointer) {
    if (pointer.isEmpty) return null;
    ChessLine? line = game.mainline;
    ChessMove? move;
    for (var i = 0; i < pointer.length; i++) {
      final index = pointer[i];
      if (i.isEven) {
        if (line == null || index >= line.length) return null;
        move = line[index];
      } else {
        final variations = move?.variations;
        if (variations == null || index >= variations.length) return null;
        line = variations[index];
      }
    }
    return move;
  }

  ChessLine _appendMoveAfterPointer(
    ChessLine source,
    ChessMovePointer pointer,
    int pointerIndex,
    ChessMove newMove,
  ) {
    if (pointer.isEmpty) return [...source, newMove];
    final moveIndex = pointer[pointerIndex];
    if (pointerIndex == pointer.length - 1) {
      final newLine = List<ChessMove>.of(source);
      if (moveIndex + 1 >= newLine.length) {
        newLine.add(newMove);
      } else {
        newLine.insert(moveIndex + 1, newMove);
      }
      return newLine;
    }
    final variationIndex = pointer[pointerIndex + 1];
    final move = source[moveIndex];
    final variations = List<ChessLine>.of(move.variations!);
    variations[variationIndex] = _appendMoveAfterPointer(
      variations[variationIndex],
      pointer,
      pointerIndex + 2,
      newMove,
    );
    final newLine = List<ChessMove>.of(source);
    newLine[moveIndex] = move.copyWith(
      variations: variations,
      overrideVariations: true,
    );
    return newLine;
  }

  ChessLine _addVariationToPointer(
    ChessLine source,
    ChessMovePointer pointer,
    int pointerIndex,
    ChessMove newMove,
    void Function(int index) onAdded,
  ) {
    if (pointer.isEmpty) return source;
    final moveIndex = pointer[pointerIndex];
    if (pointerIndex == pointer.length - 1) {
      final move = source[moveIndex];
      final variations = List<ChessLine>.of(move.variations ?? <ChessLine>[]);
      variations.add([newMove]);
      onAdded(variations.length - 1);
      final newLine = List<ChessMove>.of(source);
      newLine[moveIndex] = move.copyWith(
        variations: variations,
        overrideVariations: true,
      );
      return newLine;
    }
    final variationIndex = pointer[pointerIndex + 1];
    final move = source[moveIndex];
    final variations = List<ChessLine>.of(move.variations!);
    variations[variationIndex] = _addVariationToPointer(
      variations[variationIndex],
      pointer,
      pointerIndex + 2,
      newMove,
      onAdded,
    );
    final newLine = List<ChessMove>.of(source);
    newLine[moveIndex] = move.copyWith(
      variations: variations,
      overrideVariations: true,
    );
    return newLine;
  }

  /// Go to previous move
  void goBack() {
    if (!state.canGoBack) return;

    final newPointer = _previousPointer(state.movePointer);
    if (newPointer == null) return;

    final move = _moveForPointerInGame(state.game!, newPointer);
    final fen = move?.fen ?? state.game!.startingFen;

    // Play SFX for the move being undone
    final currentMove = _moveForPointerInGame(state.game!, state.movePointer);
    if (currentMove != null) _playSfx(currentMove.san);

    state = state.copyWith(
      movePointer: newPointer,
      currentFen: normalizeFenForGamebase(fen),
    );

    _syncQueryMovesFromTree();
    _scheduleFetch();
  }

  ChessMovePointer? _previousPointer(ChessMovePointer pointer) {
    if (pointer.isEmpty) return null;
    final previous = List<int>.of(pointer);
    if (previous.last > 0) {
      previous.last--;
      return previous;
    }
    if (previous.length >= 3) {
      previous.removeLast(); // move index
      previous.removeLast(); // variation index
      return previous;
    }
    return const [];
  }

  /// Go to next move.
  void goForward() {
    if (!state.canGoForward) return;

    final nextPointer = state.game != null
        ? _nextPointerInGame(state.game!, state.movePointer)
        : null;

    if (nextPointer != null) {
      final move = _moveForPointerInGame(state.game!, nextPointer);
      if (move != null) {
        _playSfx(move.san);
        state = state.copyWith(
          movePointer: nextPointer,
          currentFen: normalizeFenForGamebase(move.fen),
        );
        _syncQueryMovesFromTree();
        _scheduleFetch();
      }
    } else if (!state.isLoading && state.moveAggregates.isNotEmpty) {
      makeMove(state.moveAggregates.first.uci);
    }
  }

  ChessMovePointer? _nextPointerInGame(
    ChessGame game,
    ChessMovePointer pointer,
  ) {
    if (game.mainline.isEmpty) return null;
    if (pointer.isEmpty) return [0];
    final currentLine = _lineForPointerInGame(game, pointer);
    if (currentLine == null) return null;
    final lastIndex = pointer.last;
    if (lastIndex + 1 < currentLine.length) {
      final next = List<int>.of(pointer);
      next.last = lastIndex + 1;
      return next;
    }
    return null;
  }

  /// Go to first position
  void goToStart() {
    state = state.copyWith(
      movePointer: const [],
      currentFen: state.game!.startingFen,
    );
    _playSfx('');
    _syncQueryMovesFromTree();
    _scheduleFetch();
  }

  /// Go to last position.
  void goToEnd() {
    final currentLine = _lineForPointerInGame(state.game!, state.movePointer);
    if (currentLine == null || currentLine.isEmpty) return;

    final newPointer = List<int>.of(state.movePointer);
    if (newPointer.isEmpty) {
      newPointer.add(currentLine.length - 1);
    } else {
      newPointer.last = currentLine.length - 1;
    }

    final move = _moveForPointerInGame(state.game!, newPointer);
    if (move != null) {
      state = state.copyWith(
        movePointer: newPointer,
        currentFen: normalizeFenForGamebase(move.fen),
      );
      _playSfx('');
      _syncQueryMovesFromTree();
      _scheduleFetch();
    }
  }

  /// Go to specific move index (mainline only for now from original code)
  void goToMove(int index) {
    if (index < -1 || index >= state.game!.mainline.length) return;

    if (index == -1) {
      goToStart();
      return;
    }

    final newPointer = [index];
    final move = state.game!.mainline[index];
    state = state.copyWith(
      movePointer: newPointer,
      currentFen: normalizeFenForGamebase(move.fen),
    );
    _playSfx('');
    _syncQueryMovesFromTree();
    _scheduleFetch();
  }

  /// Go to specific move pointer
  void goToMovePointer(ChessMovePointer pointer) {
    final move = _moveForPointerInGame(state.game!, pointer);
    if (move == null && pointer.isNotEmpty) return;

    final fen = move?.fen ?? state.game!.startingFen;

    state = state.copyWith(
      movePointer: pointer,
      currentFen: normalizeFenForGamebase(fen),
    );
    _playSfx('');
    _syncQueryMovesFromTree();
    _scheduleFetch();
  }

  /// Initialize the explorer pre-filtered to a specific player.
  ///
  /// Sets the player filter and starting position atomically, then fires a
  /// single fetch. Avoids the double-fetch that would occur if [goToStart]
  /// and [addPlayerFilter] were called separately.
  void initializeWithPlayer(GamebasePlayer player) {
    _queryFromInitial = true;
    _queryMoves = const <String>[];
    _accessMoveNumberOffset = 0;
    state = GamebaseExplorerState(
      currentFen: _kInitialFen,
      game: ChessGame(
        gameId: 'explorer_player_${player.id}',
        startingFen: _kInitialFen,
        metadata: {
          'Event': 'Opening Explorer',
          'Site': 'ChessEver',
          'Date': DateTime.now().toIso8601String().split('T')[0],
          'White': 'White',
          'Black': 'Black',
          'Result': '*',
        },
        mainline: const [],
      ),
      movePointer: const [],
      filters: GamebaseFilters(
        playerIds: [player.id],
        selectedPlayers: [player],
      ),
    );
    _scheduleFetch();
  }

  /// Initialize the explorer pre-filtered to a specific player with additional
  /// filters (e.g. time control, rating range) merged in.
  void initializeWithPlayerAndFilters(
    GamebasePlayer player,
    GamebaseFilters filters,
  ) {
    _accessMoveNumberOffset = 0;
    final compatibleFilters = _treeCompatibleFilters(filters);
    state = GamebaseExplorerState(
      currentFen: _kInitialFen,
      game: ChessGame(
        gameId: 'explorer_player_${player.id}',
        startingFen: _kInitialFen,
        metadata: {
          'Event': 'Opening Explorer',
          'Site': 'ChessEver',
          'Date': DateTime.now().toIso8601String().split('T')[0],
          'White': 'White',
          'Black': 'Black',
          'Result': '*',
        },
        mainline: const [],
      ),
      movePointer: const [],
      filters: GamebaseFilters(
        playerIds: [player.id],
        selectedPlayers: [player],
        timeControls: compatibleFilters.timeControls,
        playerColor: compatibleFilters.playerColor,
        isOnline: compatibleFilters.isOnline,
      ),
    );
    _scheduleFetch();
  }

  /// Reset to initial position.
  ///
  /// When [fetch] is false, this is used for exit/teardown paths where we
  /// want local state cleared without firing a new network request.
  void reset({bool fetch = true}) {
    _debounceTimer?.cancel();
    // Invalidate any in-flight response from a previous position.
    _fetchToken++;
    _accessMoveNumberOffset = 0;
    state = GamebaseExplorerState(
      currentFen: _kInitialFen,
      game: ChessGame(
        gameId: 'explorer_reset',
        startingFen: _kInitialFen,
        metadata: {
          'Event': 'Opening Explorer',
          'Site': 'ChessEver',
          'Date': DateTime.now().toIso8601String().split('T')[0],
          'White': 'White',
          'Black': 'Black',
          'Result': '*',
        },
        mainline: const [],
      ),
      movePointer: const [],
    );
    if (fetch) {
      _scheduleFetch();
    }
  }

  /// Set position from FEN (for loading a specific position)
  void setPosition(
    String fen, {
    String? startingFen,
    int minimumMoveNumber = 1,
  }) {
    setPositionWithMoves(
      fen,
      const <String>[],
      startingFen: startingFen,
      minimumMoveNumber: minimumMoveNumber,
    );
  }

  /// Set position from board FEN and full explored move line (UCI).
  ///
  /// **Desktop `NotationOpeningPanel._syncProvider` behaviour:**
  /// - Input `moves` is the board's `lineUcis` (path from start to cursor).
  /// - That line is what the aggregates request must send.
  /// - Local ChessGame rebuild is only for explorer UI navigation.
  void setPositionWithMoves(
    String fen,
    List<String> moves, {
    String? startingFen,
    int minimumMoveNumber = 1,
  }) {
    try {
      final normalized = normalizeFenForGamebase(fen);
      final targetPositionKey = _positionKeyForComparison(normalized);
      final sanitizedMoves = moves
          .map((m) => m.trim().toLowerCase())
          .where((m) => RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$').hasMatch(m))
          .toList(growable: false);

      final actualStartingFen =
          startingFen ??
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      // Prefer treating standard starts as initial even if counters differ.
      final fromInitial = _isInitialFen(actualStartingFen);
      final fenStartingMoveNumber = fromInitial
          ? 1
          : _pliesFromFen(actualStartingFen) + 1;
      final safeFenStartingMoveNumber = fenStartingMoveNumber < 1
          ? 1
          : fenStartingMoveNumber;
      final safeMinimumMoveNumber = minimumMoveNumber < 1
          ? 1
          : minimumMoveNumber;
      final startingMoveNumber =
          safeMinimumMoveNumber > safeFenStartingMoveNumber
          ? safeMinimumMoveNumber
          : safeFenStartingMoveNumber;
      _accessMoveNumberOffset = startingMoveNumber - 1;

      // ═══════════════════════════════════════════════════════════════════
      // CRITICAL: lock the query line BEFORE any tree rebuild logic.
      // Desktop never lets a tree miss clear the lineUcis it just received.
      // ═══════════════════════════════════════════════════════════════════
      _queryFromInitial = fromInitial;
      _queryMoves = fromInitial
          ? List<String>.unmodifiable(sanitizedMoves)
          : const <String>[];

      if (kDebugMode) {
        debugPrint(
          '[GamebaseExplorer] setPosition: '
          '${normalized.split(' ').take(2).join(' ')}... '
          'line=${_queryMoves.length} fromInitial=$fromInitial '
          'castles=${_queryMoves.where((u) => u.startsWith('e1') || u.startsWith('e8')).toList()}',
        );
      }

      // Same FEN + same line + already have rows → skip (desktop early-out).
      if (_positionKeyForComparison(state.currentFen) == targetPositionKey &&
          listEquals(state.exploredMoves, sanitizedMoves) &&
          listEquals(_queryMoves, sanitizedMoves) &&
          state.moveAggregates.isNotEmpty &&
          !state.isLoading) {
        return;
      }

      // ── Rebuild local tree (desktop loop) ─────────────────────────────
      final fullMainline = <ChessMove>[];
      var currentPosition = Position.setupPosition(
        Rule.chess,
        Setup.parseFen(actualStartingFen),
      );

      // Ply index (into fullMainline) after which the board FEN is reached.
      // -1 = target is the starting position; null = the replay never lands on
      // the target (genuine rebuild miss). We track the LONGEST prefix that
      // reaches it so repetitions resolve to the cursor, not the first pass.
      int? reachedAtPly =
          _positionKeyForComparison(
                normalizeFenForGamebase(currentPosition.fen),
              ) ==
              targetPositionKey
          ? -1
          : null;

      for (final uci in sanitizedMoves) {
        var move = NormalMove.fromUci(uci);
        if (!currentPosition.isLegal(move)) {
          final alt = _alternateCastlingMove(currentPosition, move);
          if (alt == null || !currentPosition.isLegal(alt)) {
            debugPrint(
              '[GamebaseExplorer] setPosition illegal $uci — '
              'keeping query line of ${_queryMoves.length} for fetch',
            );
            break;
          }
          move = alt;
        }
        final (nextPos, san) = currentPosition.makeSan(move);
        final nextToMove = nextPos.turn == Side.white
            ? ChessColor.white
            : ChessColor.black;
        fullMainline.add(
          ChessMove(
            num: currentPosition.fullmoves,
            fen: nextPos.fen,
            san: san,
            // Keep the UCI the board sent (repo rewrites castling for API).
            uci: uci,
            turn: nextToMove,
          ),
        );
        currentPosition = nextPos;
        if (_positionKeyForComparison(normalizeFenForGamebase(nextPos.fen)) ==
            targetPositionKey) {
          reachedAtPly = fullMainline.length - 1;
        }
      }

      final pathMatchesTarget = reachedAtPly != null;

      // Trim to the prefix that actually reaches the board FEN. A stale caller
      // can send trailing plies past the cursor; replaying them all and then
      // dropping the whole path for "mismatch" is exactly what emptied deep
      // aggregates past ply 20 ("No move statistics for this position").
      final mainline = reachedAtPly != null
          ? fullMainline.sublist(0, reachedAtPly + 1)
          : const <ChessMove>[];

      // When we reached the target from the initial position, the query line is
      // exactly that prefix — not the longer line a stale caller overshot with.
      // On a genuine rebuild miss keep the caller line: fetch must not depend on
      // tree rebuild success past ply 20 (desktop keeps lineUcis at the panel).
      if (fromInitial && pathMatchesTarget) {
        _queryMoves = List<String>.unmodifiable(
          mainline.map((m) => m.uci).toList(growable: false),
        );
      } else if (!pathMatchesTarget && sanitizedMoves.isNotEmpty) {
        debugPrint(
          '[GamebaseExplorer] tree replay fen mismatch '
          '(target vs ${normalizeFenForGamebase(currentPosition.fen).split(' ').take(4).join(' ')}) — '
          'still querying with line=${_queryMoves.length}',
        );
      }

      state = state.copyWith(
        currentFen: normalized,
        isLoading: true,
        error: null,
        moveAggregates: const [],
        game: ChessGame(
          gameId: 'explorer_sync_${DateTime.now().millisecondsSinceEpoch}',
          // Desktop uses actualStartingFen when path matches; when it does
          // not, desktop sets deep fen which breaks startsFromInitial. We
          // always keep initial when fromInitial so tree helpers stay sane;
          // fetch uses _queryMoves, not tree.
          startingFen: fromInitial
              ? actualStartingFen
              : (pathMatchesTarget ? actualStartingFen : normalized),
          metadata: {
            'Event': 'Opening Explorer',
            'Site': 'ChessEver',
            'Date': DateTime.now().toIso8601String().split('T')[0],
          },
          mainline: pathMatchesTarget ? mainline : const [],
        ),
        movePointer: pathMatchesTarget && mainline.isNotEmpty
            ? [mainline.length - 1]
            : const [],
      );
      _scheduleFetch();
    } catch (e, st) {
      debugPrint('[GamebaseExplorer] setPosition error: $e\n$st');
      state = state.copyWith(error: 'Invalid FEN: $fen', isLoading: false);
    }
  }

  /// King-to-rook ↔ king-to-g/c castling when the other spelling is legal.
  NormalMove? _alternateCastlingMove(Position position, NormalMove move) {
    final piece = position.board.pieceAt(move.from);
    if (piece == null || piece.role != Role.king) return null;
    const pairs = <String, String>{
      'e1h1': 'e1g1',
      'e1g1': 'e1h1',
      'e1a1': 'e1c1',
      'e1c1': 'e1a1',
      'e8h8': 'e8g8',
      'e8g8': 'e8h8',
      'e8a8': 'e8c8',
      'e8c8': 'e8a8',
    };
    final alt = pairs['${move.from.name}${move.to.name}'];
    if (alt == null) return null;
    return NormalMove.fromUci(alt);
  }

  /// Update filters and refetch data
  void updateFilters(GamebaseFilters filters, {bool fetch = true}) {
    final localPlayerId = _localTreePlayerId(filters);
    final nextFilters =
        localPlayerId != null && isLocalPlayerTreeEnabledFor(localPlayerId)
        ? _treeCompatibleFilters(filters)
        : filters;
    state = state.copyWith(filters: nextFilters);
    if (fetch) _scheduleFetch();
  }

  void syncLocalPlayerTree(String playerId) {
    if (!isLocalPlayerTreeEnabledFor(playerId)) return;
    final localState = ref.read(playerOpeningTreeProvider(playerId));
    final localMoves = localState.index.movesForFen(
      state.currentFen,
      filters: _localTreeCriteria(state.filters, playerId),
    );
    state = state.copyWith(
      moveAggregates: localMoves,
      isLoading: localState.progress.isRunning,
      error: localState.progress.status == PlayerOpeningTreeStatus.error
          ? localState.progress.error
          : null,
    );
  }

  void enableLocalPlayerTree(String playerId) {
    final trimmed = playerId.trim();
    if (trimmed.isEmpty) return;
    _enabledLocalPlayerTreeId = trimmed;
    final localPlayerId = _localTreePlayerId(state.filters);
    if (localPlayerId == trimmed) {
      state = state.copyWith(filters: _treeCompatibleFilters(state.filters));
    }
  }

  void disableLocalPlayerTree() {
    _enabledLocalPlayerTreeId = null;
  }

  bool isLocalPlayerTreeEnabledFor(String playerId) {
    final trimmed = playerId.trim();
    return trimmed.isNotEmpty &&
        _enabledLocalPlayerTreeId == trimmed &&
        _localTreePlayerId(state.filters) == trimmed;
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

  /// Toggle player color filter (white/black). Toggles off if already set.
  void togglePlayerColor(GamebasePlayerColor color) {
    final current = state.filters.playerColor;
    updateFilters(
      state.filters.copyWith(playerColor: current == color ? null : color),
    );
  }

  /// Toggle game result filter (1-0/0-1/½-½). Toggles off if already set.
  void toggleGameResult(GamebaseGameResult result) {
    final current = state.filters.gameResult;
    updateFilters(
      state.filters.copyWith(gameResult: current == result ? null : result),
    );
  }

  /// Toggle format filter. [isOnline] = true means Online only, false means OTB
  /// only. Passing the currently-selected value toggles back to "all".
  void toggleFormat(bool isOnline) {
    final current = state.filters.isOnline;
    updateFilters(
      state.filters.copyWith(isOnline: current == isOnline ? null : isOnline),
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
        playerColor: null,
      ),
    );
  }

  /// Clear all filters
  void clearFilters({bool fetch = true}) {
    updateFilters(const GamebaseFilters(), fetch: fetch);
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
    final timeControl = filters.timeControls.isNotEmpty
        ? filters.timeControls.first.name
        : 'any';
    final playerId = filters.playerIds.isNotEmpty
        ? filters.playerIds.first
        : 'any';
    final minRating = filters.minRating?.toString() ?? 'any';
    final maxRating = filters.maxRating?.toString() ?? 'any';

    final color = filters.playerColor?.name ?? 'any';
    final result = filters.gameResult?.apiValue ?? 'any';
    final yearFrom = filters.yearFrom?.toString() ?? 'any';
    final yearTo = filters.yearTo?.toString() ?? 'any';
    final isOnline = filters.isOnline?.toString() ?? 'any';

    return [
      fen,
      exploredMoves.join(','),
      timeControl,
      playerId,
      minRating,
      maxRating,
      color,
      result,
      yearFrom,
      yearTo,
      isOnline,
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
/// Whether any indexed game reaches [fen], asked via the FEN-keyed endpoint.
///
/// Move aggregates are only answerable when the client can supply the move
/// line from the initial position. They come back empty for a position
/// reached without one — a transposition, a board opened at a FEN — and,
/// while the backend's deep FEN aggregate index is gated off, for every
/// position past ply 20. `/api/game-position/fen/games` is not subject to
/// that, so it is the honest answer to "does this position occur in any
/// game", and it keeps the panel from claiming there are none when there are.
final fenPositionHasGamesProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, fen) async {
      if (fen.trim().isEmpty) return false;
      final response = await ref
          .read(gamebaseRepositoryProvider)
          .getFenPositionGames(fen: fen, pageNumber: 0, pageSize: 1);
      return response.data.isNotEmpty;
    });

final gamebaseExplorerProvider =
    StateNotifierProvider.autoDispose<
      GamebaseExplorerNotifier,
      GamebaseExplorerState
    >((ref) => GamebaseExplorerNotifier(ref));

String? _localTreePlayerId(GamebaseFilters filters) {
  if (filters.playerIds.length != 1) return null;
  final playerId = filters.playerIds.first.trim();
  return playerId.isEmpty ? null : playerId;
}

GamebaseFilters _treeCompatibleFilters(GamebaseFilters filters) {
  return filters.copyWith(
    minRating: null,
    maxRating: null,
    gameResult: null,
    yearFrom: null,
    yearTo: null,
  );
}

PlayerOpeningTreeFilterCriteria _localTreeCriteria(
  GamebaseFilters filters,
  String playerId,
) {
  return PlayerOpeningTreeFilterCriteria(
    playerId: playerId,
    timeControl: filters.timeControls.isNotEmpty
        ? filters.timeControls.first
        : null,
    color: filters.playerColor?.name,
    isOnline: filters.isOnline,
  );
}

final playerOpeningTreeProvider = StateNotifierProvider.autoDispose
    .family<PlayerOpeningTreeBuildController, PlayerOpeningTreeState, String>(
      (ref, playerId) => PlayerOpeningTreeBuildController(ref, playerId),
    );

class PlayerOpeningTreeBuildController
    extends StateNotifier<PlayerOpeningTreeState> {
  PlayerOpeningTreeBuildController(this._ref, this._playerId)
    : super(PlayerOpeningTreeState(playerId: _playerId));

  static const int _maxPly = 24;
  static const Duration _initialPollInterval = Duration(seconds: 1);
  static const Duration _maxPollInterval = Duration(seconds: 5);
  static const Duration _maxBuildWait = Duration(minutes: 5);

  final Ref _ref;
  final String _playerId;
  String? get _memorialSourceIdentity =>
      memorialSourceIdentityFromTreeScope(_playerId);
  int _generation = 0;

  void start({bool force = false}) {
    if (!force &&
        (state.progress.status == PlayerOpeningTreeStatus.building ||
            state.progress.status == PlayerOpeningTreeStatus.complete)) {
      return;
    }
    final generation = ++_generation;
    state = PlayerOpeningTreeState(
      playerId: _playerId,
      progress: const PlayerOpeningTreeProgress(
        status: PlayerOpeningTreeStatus.building,
      ),
    );
    unawaited(_run(generation));
  }

  void retry() => start(force: true);

  void cancel() {
    _generation++;
    state = state.copyWith(
      progress: state.progress.copyWith(
        status: PlayerOpeningTreeStatus.canceled,
        error: null,
      ),
    );
  }

  Future<void> _run(int generation) async {
    try {
      final repository = _ref.read(gamebaseRepositoryProvider);
      final memorialSourceIdentity = _memorialSourceIdentity;
      final buildResponse = memorialSourceIdentity == null
          ? await repository.startPlayerOpeningTreeBuild(
              playerId: _playerId,
              maxPly: _maxPly,
              forceRebuild: false,
            )
          : await repository.startMemorialOpeningTreeBuild(
              sourceIdentity: memorialSourceIdentity,
              maxPly: _maxPly,
              forceRebuild: false,
            );
      if (!mounted || generation != _generation) return;

      final buildData = _responseData(buildResponse);
      final treeId = buildData['treeId']?.toString().trim() ?? '';
      if (treeId.isEmpty) {
        throw Exception('Backend did not return a player tree id.');
      }

      state = state.copyWith(treeId: treeId);
      final buildStartedAt = DateTime.now();
      var pollInterval = _initialPollInterval;

      while (mounted && generation == _generation) {
        if (DateTime.now().difference(buildStartedAt) >= _maxBuildWait) {
          throw TimeoutException(
            'Player opening tree build timed out after '
            '${_maxBuildWait.inMinutes} minutes.',
          );
        }

        final statusResponse = memorialSourceIdentity == null
            ? await repository.getPlayerOpeningTreeStatus(
                playerId: _playerId,
                treeId: treeId,
              )
            : await repository.getMemorialOpeningTreeStatus(
                sourceIdentity: memorialSourceIdentity,
                treeId: treeId,
              );
        if (!mounted || generation != _generation) return;

        final statusData = _responseData(statusResponse);
        final status =
            statusData['status']?.toString().trim().toLowerCase() ?? '';
        if (status == 'error') {
          throw Exception(
            statusData['error']?.toString().trim().isNotEmpty == true
                ? statusData['error'].toString()
                : 'Backend tree build failed.',
          );
        }

        final treeIsReady =
            status == 'complete' ||
            status == 'completed' ||
            status == 'ready' ||
            status == 'done';
        if (treeIsReady) {
          final treeResponse = memorialSourceIdentity == null
              ? await repository.getPlayerOpeningTree(
                  playerId: _playerId,
                  treeId: treeId,
                )
              : await repository.getMemorialOpeningTree(
                  sourceIdentity: memorialSourceIdentity,
                  treeId: treeId,
                );
          if (!mounted || generation != _generation) return;
          if (treeResponse != null) {
            _completeFromTreeResponse(treeId, treeResponse);
            return;
          }
        }

        state = state.copyWith(
          treeId: treeId,
          progress: const PlayerOpeningTreeProgress(
            status: PlayerOpeningTreeStatus.building,
          ),
        );
        await Future<void>.delayed(pollInterval);
        final doubledPollInterval = pollInterval * 2;
        pollInterval = doubledPollInterval > _maxPollInterval
            ? _maxPollInterval
            : doubledPollInterval;
      }
    } catch (e) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        progress: state.progress.copyWith(
          status: PlayerOpeningTreeStatus.error,
          error: _playerTreeErrorMessage(e),
        ),
      );
    }
  }

  void _completeFromTreeResponse(
    String treeId,
    Map<String, dynamic> treeResponse,
  ) {
    final snapshot = PlayerOpeningTreeSnapshot.fromJson(
      _responseData(treeResponse),
    );
    final index = PlayerOpeningTreeIndex.fromSnapshot(snapshot);
    state = PlayerOpeningTreeState(
      playerId: _playerId,
      treeId: treeId,
      index: index,
      progress: PlayerOpeningTreeProgress(
        status: PlayerOpeningTreeStatus.complete,
        indexedPositions: index.positionCount,
        error: null,
      ),
    );
  }
}

String _playerTreeErrorMessage(Object error) {
  if (error is DioException) {
    final statusCode = error.response?.statusCode;
    final body = error.response?.data?.toString().trim();
    final bodyText = body == null || body.isEmpty ? '' : ' body=$body';
    return 'HTTP ${statusCode ?? 'unknown'} ${error.type.name}$bodyText';
  }
  return error.toString().replaceFirst('Exception: ', '');
}

Map<String, dynamic> _responseData(Map<String, dynamic> response) {
  final data = response['data'];
  if (data is Map) return Map<String, dynamic>.from(data);
  return response;
}

/// Provider for managing the current page index of the opening explorer panels (0: Moves, 1: Notation).
final explorerPageIndexProvider = StateProvider.autoDispose<int>((ref) => 0);

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
  final String? color;
  final String? result;
  final bool? isOnline;
  final int? minRating;
  final int? maxRating;
  final int? yearFrom;
  final int? yearTo;
  final GamebaseSortField sortBy;
  final GamebaseSortDirection sortDirection;
  final int pageNumber; // 0-indexed
  final int pageSize;

  /// 1–20 asks the backend to attach a `continuation` UCI slice per row,
  /// starting from the queried position. 0 (default) omits it.
  final int notationPlies;

  const GamebasePositionGamesQuery({
    required this.fen,
    this.moves = const <String>[],
    this.uci,
    this.timeControl,
    this.playerId,
    this.color,
    this.result,
    this.isOnline,
    this.minRating,
    this.maxRating,
    this.yearFrom,
    this.yearTo,
    this.sortBy = GamebaseSortField.date,
    this.sortDirection = GamebaseSortDirection.desc,
    this.pageNumber = 0,
    this.pageSize = 20,
    this.notationPlies = 0,
  });

  /// The query the opening explorer asks for a row's games.
  ///
  /// `positionGamesProvider` is a family keyed on this object, so the games
  /// sheet and anything that warms the sheet ahead of a tap have to build a
  /// field-for-field identical query or they address different cache entries
  /// and the warm-up silently buys nothing. Both go through here.
  ///
  /// [sortBy] / [sortDirection] override [filters] for the sheet's own sort
  /// control, which changes the order without touching the explorer filters.
  factory GamebasePositionGamesQuery.fromFilters({
    required String fen,
    required GamebaseFilters filters,
    List<String> moves = const <String>[],
    String? uci,
    GamebaseSortField? sortBy,
    GamebaseSortDirection? sortDirection,
    int pageNumber = 0,
    int pageSize = 20,
  }) {
    return GamebasePositionGamesQuery(
      fen: fen,
      moves: moves,
      uci: uci,
      timeControl:
          filters.timeControls.isNotEmpty ? filters.timeControls.first : null,
      playerId: filters.playerIds.isNotEmpty ? filters.playerIds.first : null,
      color: filters.playerColor?.name,
      result: filters.gameResult?.apiValue,
      isOnline: filters.isOnline,
      minRating: filters.minRating,
      maxRating: filters.maxRating,
      yearFrom: filters.yearFrom,
      yearTo: filters.yearTo,
      sortBy: sortBy ?? filters.sortBy,
      sortDirection: sortDirection ?? filters.sortDirection,
      pageNumber: pageNumber,
      pageSize: pageSize,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GamebasePositionGamesQuery &&
        other.fen == fen &&
        listEquals(other.moves, moves) &&
        other.uci == uci &&
        other.timeControl == timeControl &&
        other.playerId == playerId &&
        other.color == color &&
        other.result == result &&
        other.isOnline == isOnline &&
        other.minRating == minRating &&
        other.maxRating == maxRating &&
        other.yearFrom == yearFrom &&
        other.yearTo == yearTo &&
        other.sortBy == sortBy &&
        other.sortDirection == sortDirection &&
        other.pageNumber == pageNumber &&
        other.pageSize == pageSize &&
        other.notationPlies == notationPlies;
  }

  @override
  int get hashCode => Object.hash(
    fen,
    Object.hashAll(moves),
    uci,
    timeControl,
    playerId,
    color,
    result,
    isOnline,
    minRating,
    maxRating,
    yearFrom,
    yearTo,
    sortBy,
    sortDirection,
    pageNumber,
    pageSize,
    notationPlies,
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
        color: query.color,
        result: query.result,
        isOnline: query.isOnline,
        minRating: query.minRating,
        maxRating: query.maxRating,
        yearFrom: query.yearFrom,
        yearTo: query.yearTo,
        sortBy: query.sortBy,
        sortDirection: query.sortDirection,
        notationPlies: query.notationPlies,
        pageNumber: query.pageNumber,
        pageSize: query.pageSize,
      );
    });
