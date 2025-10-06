import 'package:collection/collection.dart';
import 'package:dartchess/dartchess.dart';
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
    final playedMove = Move.parse(uci);
    final currentLine = state.currentLine;
    final currentMove = state.currentMove;
    final currentIndex =
        state.movePointer.isEmpty ? -1 : state.movePointer.last;

    if (playedMove == null || currentLine == null) return;

    if (currentIndex < currentLine.length - 1) {
      final nextMove = currentLine[currentIndex + 1];
      if (nextMove.uci == uci) {
        final pointer = List.of(state.movePointer);
        pointer.last = currentIndex + 1;
        replaceState(
          ChessGameNavigatorState(game: state.game, movePointer: pointer),
        );
        return;
      }
    }

    if (currentMove?.variations != null) {
      for (var i = 0; i < currentMove!.variations!.length; i++) {
        final variation = currentMove.variations![i];
        if (variation.isNotEmpty && variation[0].uci == uci) {
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

    final position = Position.setupPosition(
      Rule.chess,
      Setup.parseFen(state.currentFen),
    );

    final (newPosition, san) = position.makeSan(playedMove);
    final newMove = ChessMove(
      num: newPosition.fullmoves,
      fen: newPosition.fen,
      san: san,
      uci: uci,
      turn:
          newPosition.turn == Side.white ? ChessColor.white : ChessColor.black,
    );

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
      line.add(newMove);
      pointer.last++;
    } else {
      final nextMove = line[pointer.last + 1];
      final updatedVariations = List.of(nextMove.variations ?? <ChessLine>[]);
      updatedVariations.add([newMove]);

      line[pointer.last + 1] = nextMove.copyWith(variations: updatedVariations);

      pointer.last++;
      pointer.add(updatedVariations.length - 1);
      pointer.add(0);
    }

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
}

final chessGameNavigatorProvider = StateNotifierProvider.family<
  ChessGameNavigator,
  ChessGameNavigatorState,
  ChessGame
>((ref, game) => ChessGameNavigator(game));
