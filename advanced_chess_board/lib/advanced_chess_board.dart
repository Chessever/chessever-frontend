library;

import 'dart:math';

import 'package:advanced_chess_board/chess_board_controller.dart';
import 'package:advanced_chess_board/models/chess_arrow.dart';
import 'package:advanced_chess_board/utils/utils.dart';
import 'package:advanced_chess_board/widgets/chess_piece_widget.dart';
import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess;
import 'constants/global_constants.dart';
import 'models/enums.dart';
import 'utils/arrow_painter.dart';
import 'widgets/chess_square.dart';
import 'widgets/highlight_overlay.dart';

class AdvancedChessBoard extends StatefulWidget {
  final Color lightSquareColor;
  final Color darkSquareColor;
  final Color? kingBackgroundColorOnCheckmate;
  final String? initialFEN;
  final PlayerColor boardOrientation;
  final ChessBoardController controller;
  final bool enableMoves;
  final bool highlightLastMove;
  final List<ChessArrow> arrows;
  final String? lastMoveFrom;
  final String? lastMoveTo;
  final Color? lastMoveFromColor;
  final Color? lastMoveToColor;

  const AdvancedChessBoard({
    super.key,
    this.lightSquareColor = const Color(0xFFEBECD0),
    this.darkSquareColor = const Color(0xFF739552),
    this.initialFEN,
    this.boardOrientation = PlayerColor.white,
    required this.controller,
    this.enableMoves = true,
    this.highlightLastMove = true,
    this.arrows = const [],
    this.kingBackgroundColorOnCheckmate,
    this.lastMoveFrom,
    this.lastMoveTo,
    this.lastMoveFromColor,
    this.lastMoveToColor,
  });

  @override
  State<AdvancedChessBoard> createState() => _AdvancedChessBoardState();
}

class _AdvancedChessBoardState extends State<AdvancedChessBoard> {
  late chess.Chess game;
  Set<String> legalMoves = {};
  String? selectedSquare;
  bool isPieceDragging = false;

  @override
  void initState() {
    super.initState();
    game = widget.controller.game;
    if (widget.initialFEN != null) {
      widget.controller.loadGameFromFEN(widget.initialFEN!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, boxConstraints) {
        final squareSize =
            min(boxConstraints.maxWidth, boxConstraints.maxHeight) / 8;
        return AspectRatio(
          aspectRatio: 1,
          child: Stack(
            children: [
              _buildChessBoard(squareSize),
              IgnorePointer(
                child: CustomPaint(
                  painter: ArrowPainter(widget.arrows, widget.boardOrientation),
                  child: Container(),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  bool _isMoveValid(final String from, final String to) {
    final validMoves = Set<String>.from(game.moves({squareKey: from}));
    return _isSquarePartOfValidMoves(validMoves, to);
  }

  Future<bool> _makeMove(final String from, final String to) async {
    final promotion = (_isPromotionMove(from, to))
        ? pieceTypeToString(await _showPromotionDialog(context, 60))
        : null;
    return widget.controller.makeMove(from: from, to: to, promotion: promotion);
  }

  bool _isPromotionMove(String from, String to) {
    final piece = game.get(from);
    return piece != null &&
        piece.type == chess.PieceType.PAWN &&
        ((piece.color == chess.Color.WHITE && to[1] == "8") ||
            (piece.color == chess.Color.BLACK && to[1] == "1"));
  }

  Widget _buildChessBoard(final double squareSize) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 64,
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
      itemBuilder: (context, index) {
        final row = index ~/ 8;
        final col = index % 8;
        final rank = widget.boardOrientation == PlayerColor.white
            ? (7 - row) + 1
            : row + 1;
        final file = widget.boardOrientation == PlayerColor.white
            ? files[col]
            : files[7 - col];
        final square = "$file$rank";
        final isLightSquare = (row % 2) == (col % 2);
        final squareColor =
            isLightSquare ? widget.lightSquareColor : widget.darkSquareColor;
        final invertColor =
            isLightSquare ? widget.darkSquareColor : widget.lightSquareColor;
        return _buildSquareWithDragTarget(
          square,
          squareColor,
          invertColor,
          squareSize,
        );
      },
    );
  }

  Widget _buildSquareWithDragTarget(
    final String square,
    final Color squareColor,
    final Color invertColor,
    final double squareSize,
  ) {
    final piece = game.get(square);
    final hasPiece = piece != null;
    return DragTarget<String>(
      onWillAcceptWithDetails: (data) {
        final fromSquare = data.data;
        return _isMoveValid(fromSquare, square);
      },
      onAcceptWithDetails: (fromSquare) async {
        await _makeMove(fromSquare.data, square);
        selectedSquare = null;
        legalMoves = {};
        setState(() {});
      },
      builder: (context, candidateData, rejectedData) {
        return GestureDetector(
          onTap: () => _handleTap(square),
          child: MouseRegion(
            cursor: isPieceDragging
                ? SystemMouseCursors.grabbing
                : SystemMouseCursors.basic,
            child: Stack(
              children: [
                ChessSquare(
                  color: squareColor,
                  invertColor: invertColor,
                  square: square,
                  boardOrientation: widget.boardOrientation,
                  squareSize: squareSize,
                ),
                if (square == selectedSquare && hasPiece)
                  _buildSelectedPieceOverlay(),
                if (piece != null) _buildCheckmateKingOverlay(piece),
                if (_isSquarePartOfValidMoves(legalMoves, square))
                  HighlightOverlay(hasPiece: hasPiece, squareSize: squareSize),
                if (widget.highlightLastMove &&
                    widget.lastMoveFrom != null &&
                    widget.lastMoveTo != null)
                  _buildLastMoveHighlight(square),
                if (hasPiece) _buildPiece(square, squareSize, piece),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPiece(
    final String square,
    final double squareSize,
    final chess.Piece piece,
  ) {
    const dragFeedbackScaleFactor = 1.15;
    return Draggable<String>(
      data: square,
      maxSimultaneousDrags: widget.enableMoves ? null : 0,
      onDragStarted: () {
        setState(() {
          _setSelectedSquareAndFindLegalMoves(square);
          isPieceDragging = true;
        });
      },
      onDragEnd: (_) {
        setState(() {
          isPieceDragging = false;
        });
      },
      feedback: ChessPieceWidget(
        piece: piece,
        squareSize: squareSize * dragFeedbackScaleFactor,
        isDragging: isPieceDragging,
        isBoardEnabled: widget.enableMoves,
      ),
      childWhenDragging: Container(),
      // Empty space while dragging
      child: ChessPieceWidget(
        piece: piece,
        squareSize: squareSize,
        isDragging: isPieceDragging,
        isBoardEnabled: widget.enableMoves,
        onTap: () => _handleTap(square),
      ),
    );
  }

  Widget _buildSelectedPieceOverlay() {
    return Container(
      color: Colors.yellow.withAlpha(155),
    );
  }

  bool _isSquarePartOfValidMoves(
      final Set<String> validMoves, final String square) {
    return validMoves.any((move) => move.contains(square)) ||
        (game.turn == chess.Color.WHITE &&
            square == "g1" &&
            validMoves.contains("O-O")) ||
        (game.turn == chess.Color.WHITE &&
            square == "c1" &&
            validMoves.contains("O-O-O")) ||
        (game.turn == chess.Color.BLACK &&
            square == "g8" &&
            validMoves.contains("O-O")) ||
        (game.turn == chess.Color.BLACK &&
            square == "c8" &&
            validMoves.contains("O-O-O"));
  }

  Future<void> _handleTap(String square) async {
    if (!widget.enableMoves) {
      return;
    }
    if (selectedSquare == null ||
        (selectedSquare != square && game.turn == game.get(square)?.color)) {
      // Select a piece and highlight legal moves
      _setSelectedSquareAndFindLegalMoves(square);
    } else if (selectedSquare == square) {
      // Deselect if tapping on the same square
      selectedSquare = null;
      legalMoves = {};
    } else {
      // Attempt to make a move
      if (_isMoveValid(selectedSquare!, square)) {
        await _makeMove(selectedSquare!, square);
      }
      selectedSquare = null;
      legalMoves = {};
    }
    setState(() {});
  }

  void _setSelectedSquareAndFindLegalMoves(String square) {
    selectedSquare = square;
    legalMoves = Set<String>.from(game.moves({squareKey: square}));
  }

  Future<chess.PieceType> _showPromotionDialog(
    BuildContext context,
    final double squareSize,
  ) async {
    return await showDialog<chess.PieceType>(
          context: context,
          builder: (context) {
            return AlertDialog(
              content: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  chess.PieceType.QUEEN,
                  chess.PieceType.ROOK,
                  chess.PieceType.BISHOP,
                  chess.PieceType.KNIGHT
                ].map((pieceType) {
                  return ChessPieceWidget(
                    piece: chess.Piece(pieceType, game.turn),
                    squareSize: squareSize,
                    onTap: () => Navigator.of(context).pop(pieceType),
                    isBoardEnabled: widget.enableMoves,
                  );
                }).toList(),
              ),
            );
          },
        ) ??
        chess.PieceType.QUEEN; // Default to queen if dialog is dismissed
  }

  Widget _buildLastMoveHighlight(final String square) {
    // Check if we have explicit last move squares
    if (widget.lastMoveFrom != null && widget.lastMoveTo != null) {
      if (square == widget.lastMoveFrom && widget.lastMoveFromColor != null) {
        return Container(color: widget.lastMoveFromColor);
      } else if (square == widget.lastMoveTo && widget.lastMoveToColor != null) {
        return Container(color: widget.lastMoveToColor);
      }
    } else if (game.history.isNotEmpty) {
      // Fallback to game history
      final lastMove = game.history.last.move;
      if (square == lastMove.fromAlgebraic || square == lastMove.toAlgebraic) {
        return Container(color: Colors.yellow.withAlpha(128));
      }
    }
    return Container();
  }

  Widget _buildCheckmateKingOverlay(final chess.Piece piece) {
    if (game.in_checkmate &&
        piece.type == chess.PieceType.KING &&
        piece.color == game.turn) {
      return Container(
        color:
            widget.kingBackgroundColorOnCheckmate ?? Colors.red.withAlpha(155),
      );
    }
    return Container();
  }
}
