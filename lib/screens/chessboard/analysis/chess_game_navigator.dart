import 'package:collection/collection.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'chess_game.dart';

typedef ChessMovePointer = List<Number>;

class ChessGameNavigatorState {
  final ChessGame game;
  final ChessMovePointer movePointer;

  ChessGameNavigatorState({required this.game, required this.movePointer});

  ChessMove? get currentMove {
    if (movePointer.isEmpty) {
      return null;
    }

    List<ChessMove>? currentList = game.mainline;
    ChessMove? currentMove;

    for (var i = 0; i < movePointer.length; i++) {
      final index = movePointer[i];

      if (i.isEven) {
        if (currentList == null || index >= currentList.length) {
          return null;
        }
        currentMove = currentList[index];
      } else {
        if (currentMove == null ||
            currentMove.variations == null ||
            index >= currentMove.variations!.length) {
          return null;
        }
        currentList = currentMove.variations![index];
      }
    }

    return currentMove;
  }

  String get currentFen => currentMove?.fen ?? game.startingFen;

  ChessLine? get currentLine {
    if (movePointer.isEmpty) {
      return game.mainline;
    }

    List<ChessMove>? currentLine = game.mainline;
    ChessMove? currentMove;

    for (var i = 0; i < movePointer.length; i++) {
      final index = movePointer[i];

      if (i.isEven) {
        if (currentLine == null || index >= currentLine.length) {
          return null;
        }
        currentMove = currentLine[index];
      } else {
        if (currentMove == null ||
            currentMove.variations == null ||
            index >= currentMove.variations!.length) {
          return null;
        }
        currentLine = currentMove.variations![index];
      }
    }

    return currentLine;
  }

  /// Returns the complete sequence of moves from the start of the game
  /// to the current position, correctly following variations.
  List<ChessMove> get fullMovePath {
    final path = <ChessMove>[];
    if (movePointer.isEmpty) return path;

    List<ChessMove>? currentList = game.mainline;
    ChessMove? currentMove;

    for (var i = 0; i < movePointer.length; i++) {
      final index = movePointer[i];

      if (i.isEven) {
        if (currentList == null || index >= currentList.length) {
          break;
        }
        // All moves in the current list up to and including the index
        // are part of the path (either leading to a variation or the current move).
        path.addAll(currentList.take(index + 1));
        currentMove = currentList[index];
        // If this is the last element, we are done.
        if (i == movePointer.length - 1) {
          break;
        }
      } else {
        // Switching to a variation at currentMove.
        if (currentMove == null ||
            currentMove.variations == null ||
            index >= currentMove.variations!.length) {
          break;
        }
        final variation = currentMove.variations![index];
        if (variation.isNotEmpty) {
          // If the variation move is played by the same color as the current move,
          // it's an alternative TO the current move (e.g. playing d4 instead of e4 at ply 0).
          // Otherwise, it's an alternative to the continuation AFTER the current move.
          if (variation.first.turn == currentMove.turn) {
            path.removeLast();
          }
        }
        currentList = variation;
      }
    }
    return path;
  }

  ChessColor? get currentTurn {
    if (movePointer.isEmpty) {
      return ChessColor.white;
    }

    return currentMove?.turn;
  }

  String? get currentBlackTime {
    if (movePointer.isEmpty || currentLine == null) {
      return game.timeControl;
    }

    final moveIndex = movePointer.last;

    final lastBlackMove = currentLine!.lastWhereIndexedOrNull(
      (index, move) =>
          index <= moveIndex &&
          move.turn == ChessColor.white &&
          move.clockTime != null,
    );

    return lastBlackMove?.clockTime;
  }

  String? get currentWhiteTime {
    if (movePointer.isEmpty) {
      return game.timeControl;
    }

    final moveIndex = movePointer.last;

    final lastWhiteMove = currentLine!.lastWhereIndexedOrNull(
      (index, move) =>
          index <= moveIndex &&
          move.turn == ChessColor.black &&
          move.clockTime != null,
    );

    return lastWhiteMove?.clockTime;
  }

  bool get canGoForward => _nextPointerInGame(game, movePointer) != null;

  bool get canGoBackward => movePointer.isNotEmpty;
}

class ChessGameNavigator extends StateNotifier<ChessGameNavigatorState> {
  ChessGameNavigator(ChessGame game)
    : super(ChessGameNavigatorState(game: game, movePointer: []));

  bool _pointerStartsWith(ChessMovePointer pointer, List<Number> prefix) {
    if (prefix.length > pointer.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (prefix[i] != pointer[i]) return false;
    }
    return true;
  }

  ChessLine _rebuildLine(
    ChessLine source,
    ChessMovePointer pointer,
    int pointerIndex,
    ChessLine Function(ChessLine line, int moveIndex) handler,
  ) {
    if (pointer.isEmpty) {
      return source;
    }

    final moveIndex = pointer[pointerIndex];
    if (pointerIndex == pointer.length - 1) {
      return handler(source, moveIndex);
    }

    if (pointerIndex + 1 >= pointer.length) {
      return source;
    }

    final variationIndex = pointer[pointerIndex + 1];
    final move = source[moveIndex];
    final variations = move.variations;
    if (variations == null || variationIndex >= variations.length) {
      return source;
    }

    final updatedVariation = _rebuildLine(
      variations[variationIndex],
      pointer,
      pointerIndex + 2,
      handler,
    );

    final newVariations = List<ChessLine>.of(variations);
    newVariations[variationIndex] = updatedVariation;
    final updatedMove = move.copyWith(
      variations: newVariations,
      overrideVariations: true,
    );

    final newLine = List<ChessMove>.of(source);
    newLine[moveIndex] = updatedMove;
    return newLine;
  }

  ChessLine _appendMoveAfterPointer(
    ChessLine source,
    ChessMovePointer pointer,
    int pointerIndex,
    ChessMove newMove,
  ) {
    if (pointer.isEmpty) {
      final newLine = List<ChessMove>.of(source);
      newLine.add(newMove);
      return newLine;
    }

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

    if (pointerIndex + 1 >= pointer.length) {
      return source;
    }

    final variationIndex = pointer[pointerIndex + 1];
    final move = source[moveIndex];
    final variations = move.variations;
    if (variations == null || variationIndex >= variations.length) {
      return source;
    }

    final updatedVariation = _appendMoveAfterPointer(
      variations[variationIndex],
      pointer,
      pointerIndex + 2,
      newMove,
    );

    final newVariations = List<ChessLine>.of(variations);
    newVariations[variationIndex] = updatedVariation;
    final updatedMove = move.copyWith(
      variations: newVariations,
      overrideVariations: true,
    );

    final newLine = List<ChessMove>.of(source);
    newLine[moveIndex] = updatedMove;
    return newLine;
  }

  ChessLine _addVariationToPointer(
    ChessLine source,
    ChessMovePointer pointer,
    int pointerIndex,
    ChessMove newMove,
    void Function(int variationIndex) onAdded,
  ) {
    if (pointer.isEmpty) {
      return source;
    }

    final moveIndex = pointer[pointerIndex];
    if (pointerIndex == pointer.length - 1) {
      final move = source[moveIndex];
      final variations = List<ChessLine>.of(
        move.variations ?? const <ChessLine>[],
      );
      variations.add([newMove]);
      onAdded(variations.length - 1);
      final newLine = List<ChessMove>.of(source);
      newLine[moveIndex] = move.copyWith(
        variations: variations,
        overrideVariations: true,
      );
      return newLine;
    }

    if (pointerIndex + 1 >= pointer.length) {
      return source;
    }

    final variationIndex = pointer[pointerIndex + 1];
    final move = source[moveIndex];
    final variations = move.variations;
    if (variations == null || variationIndex >= variations.length) {
      return source;
    }

    final updatedVariation = _addVariationToPointer(
      variations[variationIndex],
      pointer,
      pointerIndex + 2,
      newMove,
      onAdded,
    );

    final newVariations = List<ChessLine>.of(variations);
    newVariations[variationIndex] = updatedVariation;
    final newLine = List<ChessMove>.of(source);
    newLine[moveIndex] = move.copyWith(
      variations: newVariations,
      overrideVariations: true,
    );
    return newLine;
  }

  String _fenAfterNullMove(String fen) {
    final parts = fen.split(' ');
    if (parts.length < 6) {
      return fen;
    }
    final board = parts[0];
    final turn = parts[1];
    final castling = parts[2].isEmpty ? '-' : parts[2];
    final halfmoveClock = (int.tryParse(parts[4]) ?? 0) + 1;
    var fullmove = int.tryParse(parts[5]) ?? 1;
    if (turn == 'b') {
      fullmove += 1;
    }
    final nextTurn = turn == 'w' ? 'b' : 'w';
    return [
      board,
      nextTurn,
      castling,
      '-',
      halfmoveClock.toString(),
      fullmove.toString(),
    ].join(' ');
  }

  void goToNextMove() {
    final nextPointer = _nextPointerFrom(state.movePointer);
    if (nextPointer == null) return;
    replaceState(
      ChessGameNavigatorState(game: state.game, movePointer: nextPointer),
    );
  }

  void goToPreviousMove() {
    final previousPointer = _previousPointerFrom(state.movePointer);
    if (previousPointer == null) return;
    replaceState(
      ChessGameNavigatorState(game: state.game, movePointer: previousPointer),
    );
  }

  void goToHead() {
    // Go to the starting position (before any moves)
    replaceState(
      ChessGameNavigatorState(game: state.game, movePointer: const []),
    );
  }

  void goToTail() {
    final pointer = List.of(state.movePointer);
    final currentLine = state.currentLine;
    if (currentLine == null || currentLine.isEmpty) return;

    if (pointer.isEmpty) {
      pointer.add(currentLine.length - 1);
    } else {
      pointer.last = currentLine.length - 1;
    }

    replaceState(
      ChessGameNavigatorState(game: state.game, movePointer: pointer),
    );
  }

  void goToMovePointerUnchecked(ChessMovePointer movePointer) {
    replaceState(
      ChessGameNavigatorState(game: state.game, movePointer: movePointer),
    );
  }

  void makeOrGoToMove(String uci) {
    debugPrint('🎯 NAVIGATOR makeOrGoToMove: uci=$uci');
    final playedMove = Move.parse(uci);
    final currentLine = state.currentLine;
    final currentMove = state.currentMove;
    final currentIndex =
        state.movePointer.isEmpty ? -1 : state.movePointer.last;

    debugPrint(
      '🎯 NAVIGATOR makeOrGoToMove: playedMove=${playedMove?.uci}, currentIndex=$currentIndex',
    );
    debugPrint(
      '🎯 NAVIGATOR makeOrGoToMove: currentLine length=${currentLine?.length}',
    );
    debugPrint('🎯 NAVIGATOR makeOrGoToMove: currentFen=${state.currentFen}');

    if (playedMove == null || currentLine == null) {
      debugPrint(
        '🎯 NAVIGATOR makeOrGoToMove: FAILED - playedMove or currentLine is null',
      );
      return;
    }

    // Check if next move in current line matches
    if (currentIndex < currentLine.length - 1) {
      final nextMove = currentLine[currentIndex + 1];
      if (nextMove.uci == uci) {
        debugPrint('🎯 NAVIGATOR makeOrGoToMove: Moving to next move in line');
        final pointer = List.of(state.movePointer);
        pointer.last = currentIndex + 1;
        replaceState(
          ChessGameNavigatorState(game: state.game, movePointer: pointer),
        );
        return;
      }
    }

    // Check if move exists in variations
    if (currentMove?.variations != null) {
      debugPrint(
        '🎯 NAVIGATOR makeOrGoToMove: Checking ${currentMove!.variations!.length} variations',
      );
      for (var i = 0; i < currentMove.variations!.length; i++) {
        final variation = currentMove.variations![i];
        if (variation.isNotEmpty && variation[0].uci == uci) {
          debugPrint('🎯 NAVIGATOR makeOrGoToMove: Found move in variation $i');
          replaceState(
            ChessGameNavigatorState(
              game: state.game,
              movePointer:
                  state.movePointer.isEmpty
                      ? [0]
                      : [...state.movePointer, i, 0],
            ),
          );
          return;
        }
      }
    }

    // Create new move/variation
    debugPrint('🎯 NAVIGATOR makeOrGoToMove: Creating new move/variation');
    final position = Position.setupPosition(
      Rule.chess,
      Setup.parseFen(state.currentFen),
    );

    // CRITICAL: Add error handling for illegal moves
    try {
      if (!position.isLegal(playedMove)) {
        debugPrint(
          '🎯 NAVIGATOR makeOrGoToMove: ERROR - Move $uci is ILLEGAL in position ${state.currentFen}',
        );
        debugPrint(
          '🎯 NAVIGATOR makeOrGoToMove: Turn to move: ${position.turn}',
        );
        return;
      }
    } catch (e) {
      debugPrint(
        '🎯 NAVIGATOR makeOrGoToMove: ERROR - Failed to check move legality: $e',
      );
      return;
    }

    final (newPosition, san) = position.makeSan(playedMove);

    // CRITICAL: Preserve move number context when creating variations
    // position.turn = who is about to move (before the move)
    // newPosition.turn = who will move next (after the move)
    final movingColor =
        position.turn == Side.white ? ChessColor.white : ChessColor.black;
    final nextToMove =
        newPosition.turn == Side.white ? ChessColor.white : ChessColor.black;

    // Calculate move number based on previous move
    final moveNumber =
        currentMove != null
            ? (currentMove.turn == ChessColor.black
                ? currentMove.num +
                    1 // Black just played, white is moving -> increment
                : currentMove
                    .num) // White just played, black is moving -> same number
            : (movingColor == ChessColor.white ? 1 : 1); // First move

    final newMove = ChessMove(
      num: moveNumber,
      fen: newPosition.fen,
      san: san,
      uci: uci,
      turn: nextToMove, // Store who is to move after this move
    );

    if (currentIndex == -1) {
      debugPrint('🎯 NAVIGATOR makeOrGoToMove: At starting position');
      if (state.game.mainline.isEmpty) {
        debugPrint(
          '🎯 NAVIGATOR makeOrGoToMove: Creating first move in mainline',
        );
        replaceState(
          ChessGameNavigatorState(
            game: state.game.copyWith(mainline: [newMove]),
            movePointer: [0],
          ),
        );
        return;
      }

      debugPrint('🎯 NAVIGATOR makeOrGoToMove: Adding variation to first move');
      final firstMove = state.game.mainline.first;
      final updatedVariations = List.of(firstMove.variations ?? <ChessLine>[]);
      updatedVariations.add([newMove]);

      replaceState(
        ChessGameNavigatorState(
          game: state.game.copyWith(
            mainline: [
              firstMove.copyWith(
                variations: updatedVariations,
                overrideVariations: true,
              ),
              ...state.game.mainline.sublist(1),
            ],
          ),
          movePointer: [0, updatedVariations.length - 1, 0],
        ),
      );
      return;
    }

    debugPrint('🎯 NAVIGATOR makeOrGoToMove: Adding move at current position');

    final isAtLineEnd = currentIndex == currentLine.length - 1;
    final isOnMainlinePath =
        state.movePointer.isEmpty ||
        state.movePointer.asMap().entries.every((entry) => !entry.key.isOdd);

    if (isAtLineEnd &&
        isOnMainlinePath &&
        state.movePointer.isNotEmpty &&
        !state.game.allowMainlineExtension) {
      debugPrint(
        '🎯 NAVIGATOR makeOrGoToMove: Mainline tail -> force new variation',
      );
      int? newVariationIndex;
      final updatedMainline = _addVariationToPointer(
        state.game.mainline,
        state.movePointer,
        0,
        newMove,
        (index) => newVariationIndex = index,
      );
      if (newVariationIndex == null) {
        debugPrint(
          '🎯 NAVIGATOR makeOrGoToMove: Failed to attach forced mainline variation',
        );
        return;
      }

      final newPointer = <Number>[...state.movePointer, newVariationIndex!, 0];
      replaceState(
        ChessGameNavigatorState(
          game: state.game.copyWith(mainline: updatedMainline),
          movePointer: newPointer,
        ),
      );
      return;
    }

    if (isAtLineEnd) {
      debugPrint(
        '🎯 NAVIGATOR makeOrGoToMove: Appending to end of current line (pointer=${state.movePointer})',
      );
      final updatedMainline = _appendMoveAfterPointer(
        state.game.mainline,
        state.movePointer,
        0,
        newMove,
      );
      final newPointer = List<Number>.of(state.movePointer);
      if (newPointer.isEmpty) {
        newPointer.add(0);
      } else {
        newPointer.last = currentIndex + 1;
      }
      replaceState(
        ChessGameNavigatorState(
          game: state.game.copyWith(mainline: updatedMainline),
          movePointer: newPointer,
        ),
      );
      return;
    }

    debugPrint(
      '🎯 NAVIGATOR makeOrGoToMove: Creating variation branch (mid-line or mainline tail)',
    );
    debugPrint(
      '🎯 NAVIGATOR makeOrGoToMove: Current pointer=${state.movePointer}, will attach variation to move at pointer.last=${state.movePointer.isEmpty ? "EMPTY" : state.movePointer.last}',
    );
    if (state.currentMove != null) {
      debugPrint(
        '🎯 NAVIGATOR makeOrGoToMove: Variation will be attached AFTER move: ${state.currentMove!.san} (move #${state.currentMove!.num})',
      );
    }
    int? newVariationIndex;
    final updatedMainline = _addVariationToPointer(
      state.game.mainline,
      state.movePointer,
      0,
      newMove,
      (index) => newVariationIndex = index,
    );
    if (newVariationIndex == null) {
      debugPrint('🎯 NAVIGATOR makeOrGoToMove: Failed to attach variation');
      return;
    }

    final newPointer = <Number>[...state.movePointer, newVariationIndex!, 0];
    replaceState(
      ChessGameNavigatorState(
        game: state.game.copyWith(mainline: updatedMainline),
        movePointer: newPointer,
      ),
    );
  }

  void deleteVariationAtPointer(ChessMovePointer variationHeadPointer) {
    debugPrint('🎯 NAVIGATOR deleteVariationAtPointer: $variationHeadPointer');
    if (variationHeadPointer.length < 3) {
      debugPrint('🎯 NAVIGATOR deleteVariationAtPointer: invalid pointer');
      return;
    }

    final variationIndexPosition = variationHeadPointer.length - 2;
    final variationIndex = variationHeadPointer[variationIndexPosition];
    final parentPointer = variationHeadPointer.sublist(
      0,
      variationIndexPosition,
    );
    final variationPrefix = variationHeadPointer.sublist(
      0,
      variationIndexPosition + 1,
    );

    final updatedMainline = _rebuildLine(
      state.game.mainline,
      parentPointer,
      0,
      (line, moveIndex) {
        if (line.isEmpty || moveIndex >= line.length) {
          return line;
        }
        final move = line[moveIndex];
        final variations = move.variations?.toList();
        if (variations == null || variationIndex >= variations.length) {
          return line;
        }
        variations.removeAt(variationIndex);
        final updatedMove = move.copyWith(
          variations: variations.isEmpty ? null : variations,
          overrideVariations: true,
        );
        final newLine = List<ChessMove>.of(line);
        newLine[moveIndex] = updatedMove;
        return newLine;
      },
    );

    ChessMovePointer newPointer = state.movePointer;
    if (_pointerStartsWith(newPointer, variationPrefix)) {
      newPointer = parentPointer;
    }

    replaceState(
      ChessGameNavigatorState(
        game: state.game.copyWith(mainline: updatedMainline),
        movePointer: newPointer,
      ),
    );
  }

  void deleteContinuationAfterPointer(ChessMovePointer pointer) {
    if (pointer.isEmpty) {
      return;
    }

    final targetPointer = List<Number>.of(pointer);
    final trimIndex = targetPointer.last.toInt();
    int? keptLength;

    final updatedMainline = _rebuildLine(
      state.game.mainline,
      targetPointer,
      0,
      (line, moveIndex) {
        if (line.isEmpty) {
          keptLength = 0;
          return line;
        }
        final keepLength = trimIndex.clamp(0, line.length);
        keptLength = keepLength;
        if (keepLength == line.length) {
          return line;
        }
        return List<ChessMove>.of(line.take(keepLength));
      },
    );

    if (keptLength == null) {
      debugPrint(
        '🎯 NAVIGATOR deleteContinuationAfterPointer: invalid pointer $pointer',
      );
      return;
    }

    ChessLine prunedMainline = updatedMainline;
    ChessMovePointer newPointer = List<Number>.of(targetPointer);

    if (keptLength == 0) {
      prunedMainline = _removeVariationIfEmpty(prunedMainline, targetPointer);
      if (newPointer.length >= 2) {
        newPointer = newPointer.sublist(0, newPointer.length - 2);
      } else {
        newPointer = const [];
      }
    } else {
      newPointer[newPointer.length - 1] = keptLength! - 1;
    }

    replaceState(
      ChessGameNavigatorState(
        game: state.game.copyWith(mainline: prunedMainline),
        movePointer: newPointer,
      ),
    );
  }

  void promoteVariationToMainline(ChessMovePointer variationHeadPointer) {
    debugPrint('🎯 NAVIGATOR promoteVariation: $variationHeadPointer');
    if (variationHeadPointer.length < 3) {
      debugPrint('🎯 NAVIGATOR promoteVariation: invalid pointer');
      return;
    }

    final variationIndexPosition = variationHeadPointer.length - 2;
    if (!variationIndexPosition.isOdd) {
      debugPrint(
        '🎯 NAVIGATOR promoteVariation: pointer missing variation info',
      );
      return;
    }

    final variationIndex = variationHeadPointer[variationIndexPosition];
    final parentPointer = variationHeadPointer.sublist(
      0,
      variationIndexPosition,
    );

    ChessMovePointer? promotedPointer;

    final updatedMainline = _rebuildLine(state.game.mainline, parentPointer, 0, (
      line,
      moveIndex,
    ) {
      if (line.isEmpty || moveIndex >= line.length) {
        return line;
      }
      final move = line[moveIndex];
      final variations = move.variations;
      if (variations == null || variationIndex >= variations.length) {
        return line;
      }

      final promotedVariationLine = variations[variationIndex];

      // 1. The part of the current line that comes after the junction move
      // will now become a sub-variation.
      final oldMainlineContinuation = line.sublist(moveIndex + 1);

      // 2. Build the new variations list for the junction move.
      // It will contain the old mainline continuation (if not empty),
      // followed by all other existing variations.
      final newVariations = <ChessLine>[];
      if (oldMainlineContinuation.isNotEmpty) {
        newVariations.add(oldMainlineContinuation);
      }

      for (int i = 0; i < variations.length; i++) {
        if (i != variationIndex) {
          newVariations.add(variations[i]);
        }
      }

      // 3. Update the junction move with the new variations list.
      final updatedMove = move.copyWith(
        variations: newVariations.isNotEmpty ? newVariations : null,
        overrideVariations: true,
      );

      // 4. Construct the new line: prefix + updated junction move + promoted variation.
      final newLine = List<ChessMove>.of(line.take(moveIndex));
      newLine.add(updatedMove);
      if (promotedVariationLine.isNotEmpty) {
        newLine.addAll(promotedVariationLine);
      }

      // 5. Update the pointer to point to the first move of the newly promoted line.
      if (promotedVariationLine.isNotEmpty) {
        final pointer = List<Number>.of(parentPointer);
        if (pointer.isEmpty) {
          // Should not happen given the length check, but for safety:
          pointer.add(moveIndex + 1);
        } else {
          pointer[pointer.length - 1] = moveIndex + 1;
        }
        promotedPointer = pointer;
      } else {
        promotedPointer = List<Number>.of(parentPointer);
      }

      return newLine;
    });

    if (promotedPointer == null) {
      debugPrint('🎯 NAVIGATOR promoteVariation: nothing to promote');
      return;
    }

    replaceState(
      ChessGameNavigatorState(
        game: state.game.copyWith(mainline: updatedMainline),
        movePointer: promotedPointer!,
      ),
    );
  }

  ChessLine _removeVariationIfEmpty(
    ChessLine source,
    ChessMovePointer pointer,
  ) {
    if (pointer.length < 3) {
      return source;
    }
    final variationIndexPosition = pointer.length - 2;
    if (!variationIndexPosition.isOdd) {
      return source;
    }
    final variationIndex = pointer[variationIndexPosition];
    final parentPointer = pointer.sublist(0, variationIndexPosition);

    return _rebuildLine(source, parentPointer, 0, (line, moveIndex) {
      if (line.isEmpty || moveIndex >= line.length) {
        return line;
      }
      final move = line[moveIndex];
      final variations = move.variations?.toList();
      if (variations == null || variationIndex >= variations.length) {
        return line;
      }
      variations.removeAt(variationIndex);
      final updatedMove = move.copyWith(
        variations: variations.isEmpty ? null : variations,
      );
      final newLine = List<ChessMove>.of(line);
      newLine[moveIndex] = updatedMove;
      return newLine;
    });
  }

  /// Appends multiple moves as a variation or to the end of the current line.
  /// If at the end of the current line, appends moves to that line.
  /// Otherwise, creates a new variation containing all the moves.
  void appendMovesFromPv({
    required List<Move> moves,
    required List<String> sanMoves,
  }) {
    if (moves.isEmpty || sanMoves.isEmpty) {
      debugPrint('🎯 NAVIGATOR appendMovesFromPv: Empty moves list');
      return;
    }

    final currentLine = state.currentLine;
    if (currentLine == null) {
      debugPrint('🎯 NAVIGATOR appendMovesFromPv: No current line');
      return;
    }

    final currentIndex =
        state.movePointer.isEmpty ? -1 : state.movePointer.last;
    final isAtLineEnd = currentIndex == currentLine.length - 1;

    debugPrint(
      '🎯 NAVIGATOR appendMovesFromPv: ${moves.length} moves, isAtLineEnd=$isAtLineEnd, currentIndex=$currentIndex, lineLength=${currentLine.length}',
    );

    // Build ChessMove objects from the PV moves
    var position = Position.setupPosition(
      Rule.chess,
      Setup.parseFen(state.currentFen),
    );

    final currentMove = state.currentMove;
    var moveNumber =
        currentMove != null
            ? (currentMove.turn == ChessColor.black
                ? currentMove.num + 1
                : currentMove.num)
            : 1;

    final chessMoves = <ChessMove>[];
    for (var i = 0; i < moves.length; i++) {
      final move = moves[i];
      final san = sanMoves[i];

      if (!position.isLegal(move)) {
        debugPrint(
          '🎯 NAVIGATOR appendMovesFromPv: Illegal move ${move.uci} at index $i',
        );
        break;
      }

      final newPosition = position.play(move);
      final movingColor =
          position.turn == Side.white ? ChessColor.white : ChessColor.black;
      final nextToMove =
          newPosition.turn == Side.white ? ChessColor.white : ChessColor.black;

      chessMoves.add(
        ChessMove(
          num: moveNumber,
          fen: newPosition.fen,
          san: san,
          uci: move.uci,
          turn: nextToMove,
        ),
      );

      position = newPosition;
      if (movingColor == ChessColor.white) {
        moveNumber++;
      }
    }

    if (chessMoves.isEmpty) {
      debugPrint('🎯 NAVIGATOR appendMovesFromPv: No valid moves to add');
      return;
    }

    final isOnMainline = state.movePointer.length <= 1;
    final isLiveMainline = isOnMainline && state.game.isLiveGame;

    if (isAtLineEnd && !isLiveMainline) {
      // Append moves to the end of the current line
      debugPrint(
        '🎯 NAVIGATOR appendMovesFromPv: Appending ${chessMoves.length} moves to end of line',
      );

      var updatedMainline = state.game.mainline;
      for (final chessMove in chessMoves) {
        updatedMainline = _appendMoveAfterPointer(
          updatedMainline,
          state.movePointer,
          0,
          chessMove,
        );

        // Update pointer to the new move
        final newPointer = List<Number>.of(state.movePointer);
        if (newPointer.isEmpty) {
          newPointer.add(0);
        } else {
          newPointer.last++;
        }
        state = ChessGameNavigatorState(
          game: state.game.copyWith(mainline: updatedMainline),
          movePointer: newPointer,
        );
      }
    } else {
      // Create a variation with all the moves
      debugPrint(
        '🎯 NAVIGATOR appendMovesFromPv: Creating variation with ${chessMoves.length} moves',
      );

      int? newVariationIndex;
      final updatedMainline = _addVariationToPointer(
        state.game.mainline,
        state.movePointer,
        0,
        chessMoves.first,
        (index) => newVariationIndex = index,
      );

      if (newVariationIndex == null) {
        debugPrint(
          '🎯 NAVIGATOR appendMovesFromPv: Failed to create variation',
        );
        return;
      }

      // Now append remaining moves to the new variation
      final newPointer = <Number>[...state.movePointer, newVariationIndex!, 0];
      var currentMainline = updatedMainline;

      for (var i = 1; i < chessMoves.length; i++) {
        currentMainline = _appendMoveAfterPointer(
          currentMainline,
          newPointer,
          0,
          chessMoves[i],
        );
        newPointer.last++;
      }

      replaceState(
        ChessGameNavigatorState(
          game: state.game.copyWith(mainline: currentMainline),
          movePointer: newPointer,
        ),
      );
    }

    debugPrint(
      '🎯 NAVIGATOR appendMovesFromPv: Completed, new pointer=${state.movePointer}',
    );
  }

  void insertNullMoveAtPointer([ChessMovePointer? pointerOverride]) {
    final pointer = List<Number>.of(pointerOverride ?? state.movePointer);
    final currentLine = state.currentLine;
    if (currentLine == null) {
      return;
    }

    final position = Position.setupPosition(
      Rule.chess,
      Setup.parseFen(state.currentFen),
    );
    final fenAfter = _fenAfterNullMove(state.currentFen);
    final nextToMove =
        fenAfter.split(' ')[1] == 'w' ? ChessColor.white : ChessColor.black;

    final currentMove = state.currentMove;
    final movingColor =
        position.turn == Side.white ? ChessColor.white : ChessColor.black;
    final moveNumber =
        currentMove != null
            ? (currentMove.turn == ChessColor.black
                ? currentMove.num + 1
                : currentMove.num)
            : (movingColor == ChessColor.white ? 1 : 1);

    final newMove = ChessMove(
      num: moveNumber,
      fen: fenAfter,
      san: '--',
      uci: '0000',
      turn: nextToMove,
    );

    final currentIndex = pointer.isEmpty ? -1 : pointer.last;

    if (currentIndex == -1) {
      if (state.game.mainline.isEmpty) {
        replaceState(
          ChessGameNavigatorState(
            game: state.game.copyWith(mainline: [newMove]),
            movePointer: [0],
          ),
        );
        return;
      }

      final firstMove = state.game.mainline.first;
      final updatedVariations = List<ChessLine>.of(
        firstMove.variations ?? const <ChessLine>[],
      );
      updatedVariations.add([newMove]);

      replaceState(
        ChessGameNavigatorState(
          game: state.game.copyWith(
            mainline: [
              firstMove.copyWith(
                variations: updatedVariations,
                overrideVariations: true,
              ),
              ...state.game.mainline.sublist(1),
            ],
          ),
          movePointer: [0, updatedVariations.length - 1, 0],
        ),
      );
      return;
    }

    final newMainline = List<ChessMove>.of(state.game.mainline);
    ChessLine line = newMainline;
    if (line.isEmpty) {
      return;
    }
    ChessMove move = line.first;

    for (var i = 0; i < pointer.length; i++) {
      final index = pointer[i];
      if (i.isEven) {
        if (index >= line.length) {
          return;
        }
        move = line[index];
      } else {
        final variations = move.variations;
        if (variations == null || index >= variations.length) {
          return;
        }
        line = variations[index];
      }
    }

    ChessMovePointer newPointer = List<Number>.of(pointer);

    if (currentIndex == currentLine.length - 1) {
      line.add(newMove);
      newPointer[newPointer.length - 1] = currentIndex + 1;
      replaceState(
        ChessGameNavigatorState(
          game: state.game.copyWith(mainline: newMainline),
          movePointer: newPointer,
        ),
      );
      return;
    }

    final updatedVariations = List<ChessLine>.of(
      move.variations ?? const <ChessLine>[],
    );
    updatedVariations.add([newMove]);
    line[pointer.last] = move.copyWith(
      variations: updatedVariations,
      overrideVariations: true,
    );

    newPointer = <Number>[...pointer, updatedVariations.length - 1, 0];

    replaceState(
      ChessGameNavigatorState(
        game: state.game.copyWith(mainline: newMainline),
        movePointer: newPointer,
      ),
    );
  }

  void updateWithLatestGame(ChessGame latestGame, {bool goToTail = false}) {
    final newMainline = <ChessMove>[];
    final newPointer = List.of(state.movePointer);

    for (var i = 0; i < latestGame.mainline.length; i++) {
      if (i < state.game.mainline.length) {
        if (state.game.mainline[i].uci != latestGame.mainline[i].uci) {
          final localMove = state.game.mainline[i];
          final liveMove = latestGame.mainline[i];

          final updatedMove = liveMove.copyWith(
            variations: [
              state.game.mainline.sublist(i),
              ...localMove.variations ?? const [],
            ],
          );

          newMainline.add(updatedMove);
          newMainline.addAll(latestGame.mainline.sublist(i + 1));

          if (newPointer.isNotEmpty && newPointer.first >= i) {
            newPointer
              ..clear()
              ..addAll([i, 0, state.movePointer.first - i]);
          }

          break;
        }

        newMainline.add(state.game.mainline[i]);
      } else {
        newMainline.add(latestGame.mainline[i]);
      }
    }

    final nextGame = latestGame.copyWith(mainline: newMainline);
    final nextState = ChessGameNavigatorState(
      game: nextGame,
      movePointer: newPointer,
    );

    if (!goToTail) {
      replaceState(nextState);
      return;
    }

    final tailPointer = List.of(nextState.movePointer);
    final currentLine = nextState.currentLine;
    if (currentLine != null && currentLine.isNotEmpty) {
      if (tailPointer.isEmpty) {
        tailPointer.add(currentLine.length - 1);
      } else {
        tailPointer.last = currentLine.length - 1;
      }
    }

    replaceState(
      ChessGameNavigatorState(game: nextGame, movePointer: tailPointer),
    );
  }

  void replaceState(ChessGameNavigatorState newState) {
    state = newState;
  }

  ChessMovePointer? _nextPointerFrom(ChessMovePointer pointer) =>
      _nextPointerInGame(state.game, pointer);

  ChessMovePointer? _previousPointerFrom(ChessMovePointer pointer) =>
      _previousPointer(pointer);
}

// PERF: Added autoDispose to prevent memory buildup during rapid page swiping
// Navigator state is recreated when needed - ChessGame param ensures proper keying
final chessGameNavigatorProvider = StateNotifierProvider.autoDispose
    .family<ChessGameNavigator, ChessGameNavigatorState, ChessGame>(
      (ref, game) => ChessGameNavigator(game),
    );

ChessLine? _lineForPointerInGame(ChessGame game, ChessMovePointer pointer) {
  ChessLine? line = game.mainline;
  ChessMove? move;
  for (var i = 0; i < pointer.length; i++) {
    final index = pointer[i];
    if (i.isEven) {
      if (line == null || index >= line.length) {
        return null;
      }
      move = line[index];
    } else {
      final variations = move?.variations;
      if (variations == null || index >= variations.length) {
        return null;
      }
      line = variations[index];
    }
  }
  return line;
}

ChessMovePointer? _nextPointerInGame(ChessGame game, ChessMovePointer pointer) {
  if (game.mainline.isEmpty) {
    return null;
  }

  if (pointer.isEmpty) {
    return <Number>[0];
  }

  final currentLine = _lineForPointerInGame(game, pointer);
  if (currentLine == null) {
    return null;
  }

  final lastIndex = pointer.last.toInt();
  if (lastIndex + 1 < currentLine.length) {
    final next = List<Number>.of(pointer);
    next.last = lastIndex + 1;
    return next;
  }

  var parentPointer = List<Number>.of(pointer);
  while (parentPointer.length >= 2) {
    parentPointer.removeLast(); // move index
    parentPointer.removeLast(); // variation index
    final parentLine = _lineForPointerInGame(game, parentPointer);
    if (parentLine == null) {
      continue;
    }
    if (parentPointer.isEmpty) {
      continue;
    }
    final parentIndex = parentPointer.last.toInt();
    if (parentIndex + 1 < parentLine.length) {
      final next = List<Number>.of(parentPointer);
      next.last = parentIndex + 1;
      return next;
    }
  }

  return null;
}

ChessMovePointer? _previousPointer(ChessMovePointer pointer) {
  if (pointer.isEmpty) {
    return null;
  }

  final previous = List<Number>.of(pointer);
  if (previous.last > 0) {
    previous.last--;
    return previous;
  }

  if (previous.length >= 3) {
    previous.removeLast(); // move index
    previous.removeLast(); // variation index
    return _previousPointer(previous);
  }

  return const [];
}
