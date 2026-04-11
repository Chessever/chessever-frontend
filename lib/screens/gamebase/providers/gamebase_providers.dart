import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:dartchess/dartchess.dart';
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
  GamebaseExplorerNotifier(this.ref)
      : super(
          GamebaseExplorerState(
            currentFen:
                'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
            game: ChessGame(
              gameId: 'explorer_initial',
              startingFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
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
  Position get currentPosition => Position.setupPosition(Rule.chess, Setup.parseFen(state.currentFen));

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
      if (playedMove == null) return null;
      if (!currentPosition.isLegal(playedMove)) return null;
      final (_, san) = currentPosition.makeSan(playedMove);
      return san;
    } catch (_) {
      return null;
    }
  }

  void _scheduleFetch([Duration delay = const Duration(milliseconds: 200)]) {
    _debounceTimer?.cancel();

    if (delay == Duration.zero) {
      Future.microtask(_fetchMoveAggregates);
      return;
    }

    _debounceTimer = Timer(delay, _fetchMoveAggregates);
  }

  bool _isPlayerScopedOnlyFilter(GamebaseFilters f) {
    // Safe aggressive prefetch mode: player-scoped explorer with no extra
    // filters (color is fine — same player, same index). Keeps load bounded
    // while making per-move navigation feel instant.
    return f.playerIds.length == 1 &&
        f.timeControls.isEmpty &&
        f.minRating == null &&
        f.maxRating == null;
  }

  bool _hasActiveFilters(GamebaseFilters f) {
    return f.playerIds.isNotEmpty ||
        f.timeControls.isNotEmpty ||
        f.minRating != null ||
        f.maxRating != null ||
        f.playerColor != null ||
        f.gameResult != null;
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

    final timeControlFilter =
        filters.timeControls.isNotEmpty ? filters.timeControls.first : null;
    final playerIdFilter =
        filters.playerIds.isNotEmpty ? filters.playerIds.first : null;

    final colorFilter =
        filters.playerColor != null ? filters.playerColor!.name : null;
    final resultFilter =
        filters.gameResult != null ? filters.gameResult!.apiValue : null;

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
      );

      final aggregates = response.data.moves
          .where((m) => _isLegalUciForFen(m.uci, fen))
          .toList(growable: false);
      aggregates.sort((a, b) => b.total.compareTo(a.total));
      return aggregates;
    }();

    _inFlightAggregateRequests[cacheKey] = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_inFlightAggregateRequests[cacheKey], future)) {
          _inFlightAggregateRequests.remove(cacheKey);
        }
      }),
    );

    return future;
  }

  /// Fetch move aggregates for current position
  Future<void> _fetchMoveAggregates() async {
    final fetchId = ++_fetchToken;
    final requestedFen = state.currentFen;
    final filtersSnapshot = state.filters;

    final exploredMoves = state.exploredMoves;

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

    state = state.copyWith(isLoading: true, error: null);

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
    required GamebaseFilters filters,
  }) {
    // Keep this conservative: it's a perf win, but we don't want to DDOS our own API.
    // With the current backend architecture (indexed through ~20 plies + rest),
    // deep-node requests can be heavier. Reduce fanout once we enter deep lines.
    final playerScoped = _isPlayerScopedOnlyFilter(filters);
    final currentPly = _pliesFromFen(baseFen);
    final isDeepRestZone = currentPly >= 20;
    final maxPrefetch =
        isDeepRestZone ? (playerScoped ? 1 : 0) : (playerScoped ? 4 : 3);
    if (maxPrefetch <= 0) return;
    final candidates =
        aggregates.length <= maxPrefetch
            ? aggregates
            : aggregates.sublist(0, maxPrefetch);

    for (var i = 0; i < candidates.length; i++) {
      final a = candidates[i];
      try {
        final position = Position.setupPosition(Rule.chess, Setup.parseFen(baseFen));
        final move = NormalMove.fromUci(a.uci);
        if (move == null) continue;
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
            // Skip this in deep rest zone to avoid overloading backend.
            if (!isDeepRestZone &&
                playerScoped &&
                i < 2 &&
                prefetched.isNotEmpty) {
              final reply = prefetched.first;
              final replyPosition = nextPosition;
              final replyMove = NormalMove.fromUci(reply.uci);
              if (replyMove != null && replyPosition.isLegal(replyMove)) {
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
      return move != null && position.isLegal(move);
    } catch (_) {
      return false;
    }
  }

  /// Make a move on the board (UCI format)
  void makeMove(String uci) {
    final normalizedUci = uci.trim().toLowerCase();
    if (!_uciRegex.hasMatch(normalizedUci)) return;

    if (!_isLegalUciForFen(normalizedUci, state.currentFen)) {
      debugPrint('[GamebaseExplorer] Ignoring stale/illegal move: $normalizedUci');
      return;
    }

    try {
      final san = _getSanForUci(normalizedUci);
      if (san != null) _playSfx(san);

      // Replicate Navigator logic
      final playedMove = NormalMove.fromUci(normalizedUci)!;
      final currentLine = _lineForPointerInGame(state.game!, state.movePointer);
      final currentMove = _moveForPointerInGame(state.game!, state.movePointer);
      final currentIndex = state.movePointer.isEmpty ? -1 : state.movePointer.last;

      if (currentLine != null && currentIndex < currentLine.length - 1) {
        final nextMove = currentLine[currentIndex + 1];
        if (nextMove.uci == normalizedUci) {
          final pointer = List<int>.of(state.movePointer);
          pointer.last = currentIndex + 1;
          state = state.copyWith(
            currentFen: nextMove.fen,
            movePointer: pointer,
          );
          _scheduleFetch(Duration.zero);
          return;
        }
      }

      if (currentMove?.variations != null) {
        for (var i = 0; i < currentMove!.variations!.length; i++) {
          final variation = currentMove.variations![i];
          if (variation.isNotEmpty && variation[0].uci == normalizedUci) {
            final newPointer = state.movePointer.isEmpty ? [0] : [...state.movePointer, i, 0];
            state = state.copyWith(
              currentFen: variation[0].fen,
              movePointer: newPointer,
            );
            _scheduleFetch(Duration.zero);
            return;
          }
        }
      }

      // Create new move/variation
      final position = currentPosition;
      final (newPosition, sanActual) = position.makeSan(playedMove);
      final movingColor = position.turn == Side.white ? ChessColor.white : ChessColor.black;
      final nextToMove = newPosition.turn == Side.white ? ChessColor.white : ChessColor.black;

      final moveNumber = currentMove != null
          ? (currentMove.turn == ChessColor.black ? currentMove.num + 1 : currentMove.num)
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
            currentFen: newPosition.fen,
          );
        } else {
          final firstMove = state.game!.mainline.first;
          final updatedVariations = List<ChessLine>.of(firstMove.variations ?? <ChessLine>[]);
          updatedVariations.add([newChessMove]);

          state = state.copyWith(
            game: state.game!.copyWith(
              mainline: [
                firstMove.copyWith(variations: updatedVariations, overrideVariations: true),
                ...state.game!.mainline.sublist(1),
              ],
            ),
            movePointer: [0, updatedVariations.length - 1, 0],
            currentFen: newPosition.fen,
          );
        }
      } else if (currentIndex == currentLine!.length - 1) {
        final updatedMainline = _appendMoveAfterPointer(state.game!.mainline, state.movePointer, 0, newChessMove);
        final newPointer = List<int>.of(state.movePointer);
        newPointer.last = currentIndex + 1;
        state = state.copyWith(
          game: state.game!.copyWith(mainline: updatedMainline),
          movePointer: newPointer,
          currentFen: newPosition.fen,
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
            currentFen: newPosition.fen,
          );
        }
      }

      _scheduleFetch(Duration.zero);
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

  ChessLine _appendMoveAfterPointer(ChessLine source, ChessMovePointer pointer, int pointerIndex, ChessMove newMove) {
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
    variations[variationIndex] = _appendMoveAfterPointer(variations[variationIndex], pointer, pointerIndex + 2, newMove);
    final newLine = List<ChessMove>.of(source);
    newLine[moveIndex] = move.copyWith(variations: variations, overrideVariations: true);
    return newLine;
  }

  ChessLine _addVariationToPointer(ChessLine source, ChessMovePointer pointer, int pointerIndex, ChessMove newMove, void Function(int index) onAdded) {
    if (pointer.isEmpty) return source;
    final moveIndex = pointer[pointerIndex];
    if (pointerIndex == pointer.length - 1) {
      final move = source[moveIndex];
      final variations = List<ChessLine>.of(move.variations ?? <ChessLine>[]);
      variations.add([newMove]);
      onAdded(variations.length - 1);
      final newLine = List<ChessMove>.of(source);
      newLine[moveIndex] = move.copyWith(variations: variations, overrideVariations: true);
      return newLine;
    }
    final variationIndex = pointer[pointerIndex + 1];
    final move = source[moveIndex];
    final variations = List<ChessLine>.of(move.variations!);
    variations[variationIndex] = _addVariationToPointer(variations[variationIndex], pointer, pointerIndex + 2, newMove, onAdded);
    final newLine = List<ChessMove>.of(source);
    newLine[moveIndex] = move.copyWith(variations: variations, overrideVariations: true);
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

    _scheduleFetch(Duration.zero);
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

    final nextPointer = state.game != null ? _nextPointerInGame(state.game!, state.movePointer) : null;

    if (nextPointer != null) {
      final move = _moveForPointerInGame(state.game!, nextPointer);
      if (move != null) {
        _playSfx(move.san);
        state = state.copyWith(
          movePointer: nextPointer,
          currentFen: normalizeFenForGamebase(move.fen),
        );
        _scheduleFetch(Duration.zero);
      }
    } else if (!state.isLoading && state.moveAggregates.isNotEmpty) {
      makeMove(state.moveAggregates.first.uci);
    }
  }

  ChessMovePointer? _nextPointerInGame(ChessGame game, ChessMovePointer pointer) {
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
    _scheduleFetch(Duration.zero);
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
      _scheduleFetch(Duration.zero);
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
    _scheduleFetch(Duration.zero);
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
    _scheduleFetch(Duration.zero);
  }


  /// Initialize the explorer pre-filtered to a specific player.
  ///
  /// Sets the player filter and starting position atomically, then fires a
  /// single fetch. Avoids the double-fetch that would occur if [goToStart]
  /// and [addPlayerFilter] were called separately.
  void initializeWithPlayer(GamebasePlayer player) {
    state = GamebaseExplorerState(
      currentFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      game: ChessGame(
        gameId: 'explorer_player_${player.id}',
        startingFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
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
    _scheduleFetch(Duration.zero);
  }

  /// Initialize the explorer pre-filtered to a specific player with additional
  /// filters (e.g. time control, rating range) merged in.
  void initializeWithPlayerAndFilters(
    GamebasePlayer player,
    GamebaseFilters filters,
  ) {
    state = GamebaseExplorerState(
      currentFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      game: ChessGame(
        gameId: 'explorer_player_${player.id}',
        startingFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
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
        timeControls: filters.timeControls,
        minRating: filters.minRating,
        maxRating: filters.maxRating,
        playerColor: filters.playerColor,
        gameResult: filters.gameResult,
        yearFrom: filters.yearFrom,
        yearTo: filters.yearTo,
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
    state = GamebaseExplorerState(
      currentFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      game: ChessGame(
        gameId: 'explorer_reset',
        startingFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
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
      
      // If we already have a game tree and the moves match a path in it, 
      // we should just update the pointer.
      // But usually this is called when opening the explorer.
      
      // Build a simple ChessGame from these moves if current game is empty or different starting position
      final currentExploredMoves = state.exploredMoves;
      if (listEquals(currentExploredMoves, sanitizedMoves) && state.currentFen == normalized) {
        return;
      }

      debugPrint('[GamebaseExplorer] setPosition: ${normalized.split(' ').take(2).join(' ')}...');

      // Build a new ChessGame with these moves as mainline
      final mainline = <ChessMove>[];
      var currentPosition = Position.setupPosition(Rule.chess, Setup.parseFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'));
      
      for (final uci in sanitizedMoves) {
        final move = NormalMove.fromUci(uci);
        if (move == null || !currentPosition.isLegal(move)) break;
        final (nextPos, san) = currentPosition.makeSan(move);
        final movingColor = currentPosition.turn == Side.white ? ChessColor.white : ChessColor.black;
        final nextToMove = nextPos.turn == Side.white ? ChessColor.white : ChessColor.black;
        
        mainline.add(ChessMove(
          num: movingColor == ChessColor.white ? currentPosition.fullmoves : currentPosition.fullmoves,
          fen: nextPos.fen,
          san: san,
          uci: uci,
          turn: nextToMove,
        ));
        currentPosition = nextPos;
      }

      state = state.copyWith(
        currentFen: normalized,
        game: ChessGame(
          gameId: 'explorer_sync_${DateTime.now().millisecondsSinceEpoch}',
          startingFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
          metadata: {
            'Event': 'Opening Explorer',
            'Site': 'ChessEver',
            'Date': DateTime.now().toIso8601String().split('T')[0],
          },
          mainline: mainline,
        ),
        movePointer: mainline.isEmpty ? const [] : [mainline.length - 1],
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

  /// Toggle player color filter (white/black). Toggles off if already set.
  void togglePlayerColor(GamebasePlayerColor color) {
    final current = state.filters.playerColor;
    updateFilters(
      state.filters.copyWith(
        playerColor: current == color ? null : color,
      ),
    );
  }

  /// Toggle game result filter (1-0/0-1/½-½). Toggles off if already set.
  void toggleGameResult(GamebaseGameResult result) {
    final current = state.filters.gameResult;
    updateFilters(
      state.filters.copyWith(
        gameResult: current == result ? null : result,
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
        playerColor: null,
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

    final color = filters.playerColor?.name ?? 'any';
    final result = filters.gameResult?.apiValue ?? 'any';
    final yearFrom = filters.yearFrom?.toString() ?? 'any';
    final yearTo = filters.yearTo?.toString() ?? 'any';

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
  final String? color;
  final String? result;
  final int? minRating;
  final int? maxRating;
  final int? yearFrom;
  final int? yearTo;
  final GamebaseSortField sortBy;
  final GamebaseSortDirection sortDirection;
  final int pageNumber; // 0-indexed
  final int pageSize;

  const GamebasePositionGamesQuery({
    required this.fen,
    this.moves = const <String>[],
    this.uci,
    this.timeControl,
    this.playerId,
    this.color,
    this.result,
    this.minRating,
    this.maxRating,
    this.yearFrom,
    this.yearTo,
    this.sortBy = GamebaseSortField.date,
    this.sortDirection = GamebaseSortDirection.desc,
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
        other.color == color &&
        other.result == result &&
        other.minRating == minRating &&
        other.maxRating == maxRating &&
        other.yearFrom == yearFrom &&
        other.yearTo == yearTo &&
        other.sortBy == sortBy &&
        other.sortDirection == sortDirection &&
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
    color,
    result,
    minRating,
    maxRating,
    yearFrom,
    yearTo,
    sortBy,
    sortDirection,
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
        color: query.color,
        result: query.result,
        minRating: query.minRating,
        maxRating: query.maxRating,
        yearFrom: query.yearFrom,
        yearTo: query.yearTo,
        sortBy: query.sortBy,
        sortDirection: query.sortDirection,
        pageNumber: query.pageNumber,
        pageSize: query.pageSize,
      );
    });
