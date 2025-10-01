import 'package:chessever2/screens/chessboard/chessboard_with_analysis_screen/chess_game.dart';
import 'package:collection/collection.dart';
import 'package:dartchess/dartchess.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef ChessMovePointer = List<Number>;

class ChessGameNavigatorState {
  final ChessGame game;
  final ChessMovePointer movePointer;

  ChessGameNavigatorState({
    required this.game,
    required this.movePointer,
  });

  ChessMove? get currentMove {
    if (movePointer.isEmpty) {
      return null;
    }

    List<ChessMove>? currentList = game.mainline;
    ChessMove? currentMove;

    for (Number i = 0; i < movePointer.length; i++) {
      Number index = movePointer[i];

      if (i % 2 == 0) {
        // Even index points to a move.
        if (currentList == null || index >= currentList.length) {
          return null;
        }
        currentMove = currentList[index];
      } else {
        // Odd index points to a variation.
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

    for (Number i = 0; i < movePointer.length; i++) {
      Number index = movePointer[i];

      if (i % 2 == 0) {
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

    final move = currentMove;

    if (move == null) {
      return null;
    }

    return move.turn;
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

    if (currentLine == null) {
      return;
    }

    if (state.movePointer.isEmpty) {
      replaceState(ChessGameNavigatorState(
        game: state.game,
        movePointer: [0],
      ));

      return;
    }

    if (state.movePointer.last + 1 < currentLine.length) {
      final nextMovePointer = List.of(state.movePointer);

      nextMovePointer.last++;

      replaceState(ChessGameNavigatorState(
        game: state.game,
        movePointer: nextMovePointer,
      ));
    }
  }

  void goToPreviousMove() {
    if (state.movePointer.isEmpty) {
      return;
    }

    final previousPointer = List.of(state.movePointer);

    if (previousPointer.last > 0) {
      previousPointer.last--;
    } else {
      // Step back out of a variation or go to the start
      if (previousPointer.length > 1) {
        previousPointer.removeRange(
          previousPointer.length - 2,
          previousPointer.length + 1,
        );
      } else {
        previousPointer.clear();
      }
    }

    replaceState(ChessGameNavigatorState(
      game: state.game,
      movePointer: previousPointer,
    ));
  }

  void goToHead() {
    replaceState(ChessGameNavigatorState(
      game: state.game,
      movePointer: state.game.mainline.isNotEmpty ? [0] : [],
    ));
  }

  void goToTail() {
    List<Number> newPointer = List.from(state.movePointer);
    final currentLine = state.currentLine;

    if (currentLine == null) {
      return;
    }

    if (newPointer.isEmpty) {
      newPointer.add(currentLine.length - 1);
    } else if (newPointer.last < currentLine.length) {
      newPointer.last = currentLine.length - 1;
    }

    replaceState(ChessGameNavigatorState(
      game: state.game,
      movePointer: newPointer,
    ));
  }

  void goToMovePointerUnChecked(ChessMovePointer movePointer) {
    replaceState(ChessGameNavigatorState(
      game: state.game,
      movePointer: movePointer,
    ));
  }

  void makeOrGoToMove(final String uci) {
    final playedNove = Move.parse(uci);

    final currentLine = state.currentLine;
    final currentMove = state.movePointer.isEmpty
        ? currentLine?.firstOrNull
        : state.currentMove;
    final currentMoveVariations = currentMove?.variations;
    final currentMoveIndex =
        state.movePointer.isEmpty ? -1 : state.movePointer.last;

    if (playedNove == null || currentLine == null) {
      return;
    }

    // Check if move made matches the next move in current line
    if (currentMoveIndex < currentLine.length - 1) {
      final nextMove = currentLine[currentMoveIndex + 1];
      if (nextMove.uci == uci) {
        final newMovePointer = List.of(state.movePointer);

        newMovePointer.last = currentMoveIndex + 1;

        replaceState(ChessGameNavigatorState(
          game: state.game,
          movePointer: newMovePointer,
        ));

        return;
      }
    }

    // Check variations of current move
    if (currentMove != null && currentMoveVariations != null) {
      for (Number i = 0; i < currentMoveVariations.length; i++) {
        final variation = currentMoveVariations[i];
        if (variation.isNotEmpty && variation[0].uci == uci) {
          replaceState(ChessGameNavigatorState(
            game: state.game,
            movePointer:
                state.movePointer.isEmpty ? [0] : [...state.movePointer, i, 0],
          ));
          return;
        }
      }
    }

    final currentPosition = Position.setupPosition(
      Rule.chess,
      Setup.parseFen(state.currentFen),
    );

    final (newPosition, san) = currentPosition.makeSan(playedNove);

    final newMove = ChessMove(
      num: newPosition.fullmoves,
      fen: newPosition.fen,
      san: san,
      uci: uci,
      turn:
          newPosition.turn == Side.white ? ChessColor.white : ChessColor.black,
    );

    // if we are at the root
    if (currentMoveIndex == -1) {
      // if the mainline is empty just add the move and return
      if (state.game.mainline.isEmpty) {
        replaceState(ChessGameNavigatorState(
          game: state.game.copyWith(mainline: [newMove]),
          movePointer: [0],
        ));

        return;
      } else {
        final firstMove = state.game.mainline.first;

        final List<ChessLine> updateVariations = firstMove.variations ?? [];

        updateVariations.add([newMove]);

        replaceState(ChessGameNavigatorState(
          game: state.game.copyWith(mainline: [
            firstMove.copyWith(
              variations: updateVariations,
            ),
            ...state.game.mainline.slice(1),
          ]),
          movePointer: [
            0,
            updateVariations.length - 1,
            0,
          ],
        ));
      }

      return;
    }

    final newMainline = List.of(state.game.mainline);
    final List<Number> tPointer = List.of(state.movePointer);

    ChessLine tLine = newMainline;
    ChessMove tMove = tLine.first;

    for (Number i = 0; i < tPointer.length; i++) {
      if (i % 2 == 0) {
        tMove = tLine[tPointer[i]];
      } else {
        tLine = tMove.variations?[tPointer[i]] ?? [];
      }
    }

    if (currentMoveIndex == currentLine.length - 1) {
      tLine.add(newMove);
      tPointer.last++;
    } else {
      ChessMove nextMove = tLine[tPointer.last + 1];

      final List<ChessLine> updatedVariations = nextMove.variations ?? [];

      updatedVariations.add([newMove]);

      tLine[tPointer.last + 1] = nextMove.copyWith(
        variations: updatedVariations,
      );

      tPointer.last++;
      tPointer.add(updatedVariations.length - 1);
      tPointer.add(0);
    }

    replaceState(ChessGameNavigatorState(
      game: state.game.copyWith(
        mainline: newMainline,
      ),
      movePointer: tPointer,
    ));
  }

  void updateMainlineWithGame(final ChessGame latestGame) {
    final ChessLine newMainline = [];
    final ChessMovePointer newMovePointer = List.of(state.movePointer);

    for (Number i = 0; i < latestGame.mainline.length; i++) {
      if (i < state.game.mainline.length) {
        if (state.game.mainline[i].uci != latestGame.mainline[i].uci) {
          final localMove = state.game.mainline[i];

          final liveMove = latestGame.mainline[i];

          final updatedMove = liveMove.copyWith(
            variations: [
              state.game.mainline.slice(i),
              ...localMove.variations ?? [],
            ],
          );

          newMainline.add(updatedMove);

          newMainline.addAll(latestGame.mainline.slice(i + 1));

          if (newMovePointer.isNotEmpty && newMovePointer.first >= i) {
            newMovePointer.clear();

            newMovePointer.addAll([i, 0, state.movePointer.first - i]);
          }

          break;
        }

        newMainline.add(state.game.mainline[i]);
      } else {
        newMainline.add(latestGame.mainline[i]);
      }
    }

    replaceState(ChessGameNavigatorState(
      game: latestGame.copyWith(
        mainline: newMainline,
      ),
      movePointer: newMovePointer,
    ));
  }

  void replaceState(final ChessGameNavigatorState newState) {
    state = newState;
  }
}

final chessGameNavigatorProvider = StateNotifierProvider.family<
    ChessGameNavigator, ChessGameNavigatorState, ChessGame>(
  (ref, game) => ChessGameNavigator(game),
);
