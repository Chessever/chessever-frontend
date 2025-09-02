import 'dart:math';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';

class AnalysisMode extends StatefulWidget {
  // Optional initial position - can be FEN string or PGN
  final String? initialFen;
  final String? initialPgn;
  final double size;
  const AnalysisMode({super.key, this.initialFen, this.initialPgn, required this.size});

  @override
  State<AnalysisMode> createState() => _AnalysisModeState();
}

class _AnalysisModeState extends State<AnalysisMode> {
  late Position position;
  Side orientation = Side.white;
  String fen = kInitialBoardFEN;
  NormalMove? lastMove;
  NormalMove? promotionMove;
  ValidMoves validMoves = IMap(const {});
  List<Position> positionHistory = [];
  List<String> moveHistory = []; // Store moves in SAN notation
  List<Move?> actualMoves =[]; // Store actual move objects for lastMove highlighting
  int currentMoveIndex = -1;

  @override
  void initState() {
    super.initState();
    _initializePosition();
  }

  void _initializePosition() {
    if (widget.initialPgn != null) {
      // Parse PGN and set up position
      try {
        _parsePgnAndBuildHistory(widget.initialPgn!);
      } catch (e) {
        position = Chess.initial;
        fen = position.fen;
        validMoves = makeLegalMoves(position);
        positionHistory = [position];
        moveHistory = [];
        actualMoves = [null];
        currentMoveIndex = 0;
      }
    } else if (widget.initialFen != null) {
      // Use provided FEN
      try {
        position = Position.setupPosition(
          Rule.chess,
          Setup.parseFen(widget.initialFen!),
        );
        fen = position.fen;
        validMoves = makeLegalMoves(position);
        positionHistory = [position];
        moveHistory = [];
        actualMoves = [null];
        currentMoveIndex = 0;
      } catch (e) {
        position = Chess.initial;
        fen = position.fen;
        validMoves = makeLegalMoves(position);
        positionHistory = [position];
        moveHistory = [];
        actualMoves = [null];
        currentMoveIndex = 0;
      }
    } else {
      // Start with initial position
      position = Chess.initial;
      fen = position.fen;
      validMoves = makeLegalMoves(position);
      positionHistory = [position];
      moveHistory = [];
      actualMoves = [null];
      currentMoveIndex = 0;
    }
  }

  // Parse PGN and build complete history
  void _parsePgnAndBuildHistory(String pgn) {
    Position pos = Chess.initial;
    positionHistory = [pos];
    moveHistory = [];
    actualMoves = [null];

    final moves = _extractMovesFromPgn(pgn);

    for (String moveStr in moves) {
      try {
        final move = pos.parseSan(moveStr);
        if (move != null && pos.isLegal(move)) {
          pos = pos.playUnchecked(move);
          positionHistory.add(pos);
          moveHistory.add(moveStr);
          actualMoves.add(move);
        }
      } catch (e) {
        break;
      }
    }

    position = positionHistory.last;
    fen = position.fen;
    validMoves = makeLegalMoves(position);
    currentMoveIndex = positionHistory.length - 1;
  }

  List<String> _extractMovesFromPgn(String pgn) {
    // Remove move numbers and clean up
    String cleanPgn = pgn.replaceAll(RegExp(r'\d+\.'), '');
    cleanPgn = cleanPgn.replaceAll(RegExp(r'\{[^}]*\}'), ''); // Remove comments
    cleanPgn = cleanPgn.replaceAll(
      RegExp(r'\([^)]*\)'),
      '',
    ); // Remove variations

    return cleanPgn
        .split(RegExp(r'\s+'))
        .where(
          (move) =>
              move.isNotEmpty && !['1-0', '0-1', '1/2-1/2', '*'].contains(move),
        )
        .toList();
  }

  void _playMove(NormalMove move, {bool? isDrop, bool? isPremove}) {
    if (isPromotionPawnMove(move)) {
      setState(() {
        promotionMove = move;
      });
    } else if (position.isLegal(move)) {
      setState(() {
        // Remove any future moves if we're in the middle of history
        if (currentMoveIndex < positionHistory.length - 1) {
          positionHistory = positionHistory.sublist(0, currentMoveIndex + 1);
          moveHistory = moveHistory.sublist(0, currentMoveIndex);
          actualMoves = actualMoves.sublist(0, currentMoveIndex + 1);
        }

        final newPosition = position.playUnchecked(move);
        final sanMove = position.toSan(move);

        position = newPosition;
        lastMove = move;
        fen = position.fen;
        validMoves = makeLegalMoves(position);
        promotionMove = null;

        // Add to history
        positionHistory.add(position);
        moveHistory.add(sanMove);
        actualMoves.add(move);
        currentMoveIndex++;
      });
    }
  }

  void _onPromotionSelection(Role? role) {
    if (role == null) {
      setState(() {
        promotionMove = null;
      });
    } else if (promotionMove != null) {
      final move = promotionMove!.withPromotion(role);
      setState(() {
        // Remove any future moves if we're in the middle of history
        if (currentMoveIndex < positionHistory.length - 1) {
          positionHistory = positionHistory.sublist(0, currentMoveIndex + 1);
          moveHistory = moveHistory.sublist(0, currentMoveIndex);
          actualMoves = actualMoves.sublist(0, currentMoveIndex + 1);
        }

        final newPosition = position.playUnchecked(move);
        final sanMove = position.toSan(move);

        position = newPosition;
        lastMove = move;
        fen = position.fen;
        validMoves = makeLegalMoves(position);
        promotionMove = null;

        // Add to history
        positionHistory.add(position);
        moveHistory.add(sanMove);
        actualMoves.add(move);
        currentMoveIndex++;
      });
    }
  }

  void _flipBoard() {
    setState(() {
      orientation = orientation.opposite;
    });
  }

  void _goBack() {
    if (currentMoveIndex > 0) {
      setState(() {
        currentMoveIndex--;
        position = positionHistory[currentMoveIndex];
        fen = position.fen;
        validMoves = makeLegalMoves(position);
        lastMove =
            currentMoveIndex > 0
                ? actualMoves[currentMoveIndex] as NormalMove?
                : null;
      });
    }
  }

  void _goForward() {
    if (currentMoveIndex < positionHistory.length - 1) {
      setState(() {
        currentMoveIndex++;
        position = positionHistory[currentMoveIndex];
        fen = position.fen;
        validMoves = makeLegalMoves(position);
        lastMove = actualMoves[currentMoveIndex] as NormalMove?;
      });
    }
  }

  void _goToStart() {
    if (currentMoveIndex > 0) {
      setState(() {
        currentMoveIndex = 0;
        position = positionHistory[0];
        fen = position.fen;
        validMoves = makeLegalMoves(position);
        lastMove = null;
      });
    }
  }

  void _goToEnd() {
    if (currentMoveIndex < positionHistory.length - 1) {
      setState(() {
        currentMoveIndex = positionHistory.length - 1;
        position = positionHistory[currentMoveIndex];
        fen = position.fen;
        validMoves = makeLegalMoves(position);
        lastMove =
            currentMoveIndex > 0
                ? actualMoves[currentMoveIndex] as NormalMove?
                : null;
      });
    }
  }

  void _resetPosition() {
    setState(() {
      position = Chess.initial;
      fen = position.fen;
      validMoves = makeLegalMoves(position);
      lastMove = null;
      positionHistory = [position];
      moveHistory = [];
      actualMoves = [null];
      currentMoveIndex = 0;
    });
  }

  void _jumpToMove(int moveIndex) {
    if (moveIndex >= 0 && moveIndex < positionHistory.length) {
      setState(() {
        currentMoveIndex = moveIndex;
        position = positionHistory[moveIndex];
        fen = position.fen;
        validMoves = makeLegalMoves(position);
        lastMove =
            currentMoveIndex > 0
                ? actualMoves[currentMoveIndex] as NormalMove?
                : null;
      });
    }
  }

  bool isPromotionPawnMove(NormalMove move) {
    return move.promotion == null &&
        position.board.roleAt(move.from) == Role.pawn &&
        ((move.to.rank == Rank.first && position.turn == Side.black) ||
            (move.to.rank == Rank.eighth && position.turn == Side.white));
  }

  @override
  Widget build(BuildContext context) {
    return Chessboard(
      size: widget.size,
      settings: ChessboardSettings(
        enableCoordinates: true,
        animationDuration: const Duration(milliseconds: 200),
        dragFeedbackScale: 1.2,
        dragTargetKind: DragTargetKind.circle,
        pieceShiftMethod: PieceShiftMethod.either,
        autoQueenPromotionOnPremove: false,
        pieceOrientationBehavior: PieceOrientationBehavior.facingUser,
      ),
      orientation: orientation,
      fen: fen,
      lastMove: lastMove,
      game: GameData(
        // Allow both sides to move
        playerSide:
            position.turn == Side.white ? PlayerSide.white : PlayerSide.black,
        validMoves: validMoves, // This shows legal moves highlighting
        sideToMove: position.turn,
        isCheck: position.isCheck,
        promotionMove: promotionMove,
        onMove: _playMove,
        onPromotionSelection: _onPromotionSelection,
      ),
    );

    // Position info and PGN display
  }
}
