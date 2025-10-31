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
}

class ChessGameNavigator extends StateNotifier<ChessGameNavigatorState> {
  ChessGameNavigator(ChessGame game)
    : super(ChessGameNavigatorState(game: game, movePointer: []));

  void goToNextMove() {
    final currentLine = state.currentLine;
    if (currentLine == null) return;

    if (state.movePointer.isEmpty) {
      replaceState(ChessGameNavigatorState(game: state.game, movePointer: [0]));
      return;
    }

    if (state.movePointer.last + 1 < currentLine.length) {
      final nextPointer = List.of(state.movePointer);
      nextPointer.last++;
      replaceState(
        ChessGameNavigatorState(game: state.game, movePointer: nextPointer),
      );
    }
  }

  void goToPreviousMove() {
    if (state.movePointer.isEmpty) return;

    final previousPointer = List.of(state.movePointer);

    if (previousPointer.last > 0) {
      previousPointer.last--;
    } else {
      if (previousPointer.length > 1) {
        previousPointer.removeRange(
          previousPointer.length - 2,
          previousPointer.length,
        );
      } else {
        previousPointer.clear();
      }
    }

    replaceState(
      ChessGameNavigatorState(game: state.game, movePointer: previousPointer),
    );
  }

  void goToHead() {
    // Go to the starting position (before any moves)
    replaceState(
      ChessGameNavigatorState(
        game: state.game,
        movePointer: const [],
      ),
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

    debugPrint('🎯 NAVIGATOR makeOrGoToMove: playedMove=${playedMove?.uci}, currentIndex=$currentIndex');
    debugPrint('🎯 NAVIGATOR makeOrGoToMove: currentLine length=${currentLine?.length}');
    debugPrint('🎯 NAVIGATOR makeOrGoToMove: currentFen=${state.currentFen}');

    if (playedMove == null || currentLine == null) {
      debugPrint('🎯 NAVIGATOR makeOrGoToMove: FAILED - playedMove or currentLine is null');
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
      debugPrint('🎯 NAVIGATOR makeOrGoToMove: Checking ${currentMove!.variations!.length} variations');
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
        debugPrint('🎯 NAVIGATOR makeOrGoToMove: ERROR - Move $uci is ILLEGAL in position ${state.currentFen}');
        debugPrint('🎯 NAVIGATOR makeOrGoToMove: Turn to move: ${position.turn}');
        return;
      }
    } catch (e) {
      debugPrint('🎯 NAVIGATOR makeOrGoToMove: ERROR - Failed to check move legality: $e');
      return;
    }

    final (newPosition, san) = position.makeSan(playedMove);

    // CRITICAL: Preserve move number context when creating variations
    // position.turn = who is about to move (before the move)
    // newPosition.turn = who will move next (after the move)
    // The move being made is by position.turn
    final movingColor = position.turn == Side.white ? ChessColor.white : ChessColor.black;

    // Calculate move number based on previous move
    final moveNumber = currentMove != null
        ? (currentMove.turn == ChessColor.black
            ? currentMove.num + 1  // Black just played, white is moving -> increment
            : currentMove.num)      // White just played, black is moving -> same number
        : (movingColor == ChessColor.white ? 1 : 1);  // First move

    final newMove = ChessMove(
      num: moveNumber,
      fen: newPosition.fen,
      san: san,
      uci: uci,
      turn: movingColor,  // Store who made this move
    );

    if (currentIndex == -1) {
      debugPrint('🎯 NAVIGATOR makeOrGoToMove: At starting position');
      if (state.game.mainline.isEmpty) {
        debugPrint('🎯 NAVIGATOR makeOrGoToMove: Creating first move in mainline');
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
              firstMove.copyWith(variations: updatedVariations),
              ...state.game.mainline.sublist(1),
            ],
          ),
          movePointer: [0, updatedVariations.length - 1, 0],
        ),
      );
      return;
    }

    debugPrint('🎯 NAVIGATOR makeOrGoToMove: Adding move at current position');
    final newMainline = List.of(state.game.mainline);
    final pointer = List.of(state.movePointer);

    ChessLine line = newMainline;
    ChessMove move = line.first;

    for (var i = 0; i < pointer.length; i++) {
      if (i.isEven) {
        move = line[pointer[i]];
      } else {
        line = move.variations![pointer[i]];
      }
    }

    if (currentIndex == currentLine.length - 1) {
      debugPrint('🎯 NAVIGATOR makeOrGoToMove: Appending to end of line');
      line.add(newMove);
      pointer.last++;
    } else {
      debugPrint('🎯 NAVIGATOR makeOrGoToMove: Creating variation mid-line');
      final nextMove = line[pointer.last + 1];
      final updatedVariations = List.of(nextMove.variations ?? <ChessLine>[]);
      updatedVariations.add([newMove]);

      line[pointer.last + 1] = nextMove.copyWith(variations: updatedVariations);

      pointer.last++;
      pointer.add(updatedVariations.length - 1);
      pointer.add(0);
    }

    debugPrint('🎯 NAVIGATOR makeOrGoToMove: Successfully created move');
    replaceState(
      ChessGameNavigatorState(
        game: state.game.copyWith(mainline: newMainline),
        movePointer: pointer,
      ),
    );
  }

  void updateWithLatestGame(ChessGame latestGame) {
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

    replaceState(
      ChessGameNavigatorState(
        game: latestGame.copyWith(mainline: newMainline),
        movePointer: newPointer,
      ),
    );
  }

  void replaceState(ChessGameNavigatorState newState) {
    state = newState;
  }

  // Removes a variation line that starts at the given pointer (which should end with ..., varIndex, 0)
  void deleteVariationAtPointer(ChessMovePointer pointerToVariationHead) {
    if (pointerToVariationHead.length < 3) return; // must point into a variation
    final ptr = List<int>.from(pointerToVariationHead);
    // parent pointer of the move that owns the variations list
    final ownerPtr = List<int>.from(ptr)..removeRange(ptr.length - 2, ptr.length);
    final varIndex = ptr[ptr.length - 2];

    // Navigate to the owner move whose variations we will modify
    final newMainline = List<ChessMove>.from(state.game.mainline);
    List<ChessLine> stack = [newMainline];
    ChessMove? ownerMove;
    for (int i = 0; i < ownerPtr.length; i++) {
      if (i.isEven) {
        ownerMove = stack.last[ownerPtr[i]];
      } else {
        stack.add(List<ChessMove>.from(ownerMove!.variations![ownerPtr[i]]));
      }
    }
    if (ownerMove == null) return;
    final variations = List<ChessLine>.from(ownerMove.variations ?? const []);
    if (varIndex < 0 || varIndex >= variations.length) return;
    variations.removeAt(varIndex);
    final updatedOwner = ownerMove.copyWith(
      variations: variations.isEmpty ? null : variations,
    );

    // Write back updated owner move into the structure
    List<ChessLine> writeStack = [newMainline];
    ChessMove? writeMove;
    for (int i = 0; i < ownerPtr.length; i++) {
      if (i.isEven) {
        final l = writeStack.last;
        if (i == ownerPtr.length - 1) {
          l[ownerPtr[i]] = updatedOwner;
        } else {
          writeMove = l[ownerPtr[i]];
        }
      } else {
        writeStack.add(List<ChessMove>.from(writeMove!.variations![ownerPtr[i]]));
      }
    }

    // New pointer after deletion: move to the owner move
    final newPointer = ownerPtr;
    replaceState(
      ChessGameNavigatorState(
        game: state.game.copyWith(mainline: newMainline),
        movePointer: newPointer,
      ),
    );
  }

  // Promote a variation to mainline at the branching point
  void promoteVariationToMainline(ChessMovePointer pointerToVariationHead) {
    if (pointerToVariationHead.length < 3) return;
    final ptr = List<int>.from(pointerToVariationHead);
    final ownerPtr = List<int>.from(ptr)..removeRange(ptr.length - 2, ptr.length);
    final varIndex = ptr[ptr.length - 2];

    // Navigate to owner move and fetch current mainline segment and variation to promote
    final newMainline = List<ChessMove>.from(state.game.mainline);
    List<ChessLine> stack = [newMainline];
    ChessMove? ownerMove;
    for (int i = 0; i < ownerPtr.length; i++) {
      if (i.isEven) {
        ownerMove = stack.last[ownerPtr[i]];
      } else {
        stack.add(List<ChessMove>.from(ownerMove!.variations![ownerPtr[i]]));
      }
    }
    if (ownerMove == null) return;
    final variations = List<ChessLine>.from(ownerMove.variations ?? const []);
    if (varIndex < 0 || varIndex >= variations.length) return;
    final promoted = List<ChessMove>.from(variations[varIndex]);

    // Determine current line (the line right after ownerPtr in structure)
    // The owner move is followed by a mainline move at some index; variations are stored on that move
    // We replace from that next move onward with the promoted line and push the replaced segment as a sibling variation.
    // Find the line that contains the move whose variations we modified: it's the line at ownerPtr context.
    List<ChessLine> cursorStack = [newMainline];
    ChessMove? ctxMove;
    for (int i = 0; i < ownerPtr.length; i++) {
      if (i.isEven) {
        ctxMove = cursorStack.last[ownerPtr[i]];
      } else {
        cursorStack.add(List<ChessMove>.from(ctxMove!.variations![ownerPtr[i]]));
      }
    }
    final lineAtContext = cursorStack.last;
    final followingIndex = ownerPtr.isNotEmpty ? ownerPtr.last + 1 : 0;
    if (followingIndex >= lineAtContext.length) return; // nothing to promote against
    final replacedTail = lineAtContext.sublist(followingIndex);

    // Update the head move (the first move after branch) to host new variations: replacedTail + remaining variations except promoted
    final headMove = lineAtContext[followingIndex];
    final remainingVariations = List<ChessLine>.from(variations)
      ..removeAt(varIndex)
      ..insert(0, replacedTail);
    final updatedHead = headMove.copyWith(
      variations: remainingVariations,
    );

    // Splice promoted line into mainline
    lineAtContext
      ..removeRange(followingIndex, lineAtContext.length)
      ..addAll(promoted);

    // Write back updated head
    lineAtContext[followingIndex] = updatedHead;

    // New pointer to the head of promoted line
    final newPointer = List<int>.from(ownerPtr)..addAll([followingIndex]);
    replaceState(
      ChessGameNavigatorState(
        game: state.game.copyWith(mainline: newMainline),
        movePointer: newPointer,
      ),
    );
  }
}

final chessGameNavigatorProvider = StateNotifierProvider.family<
  ChessGameNavigator,
  ChessGameNavigatorState,
  ChessGame
>((ref, game) => ChessGameNavigator(game));
