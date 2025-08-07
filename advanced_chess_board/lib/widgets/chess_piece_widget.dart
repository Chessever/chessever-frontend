import 'package:advanced_chess_board/utils/utils.dart';
import 'package:flutter/material.dart';

import 'package:chess/chess.dart' as chess;

class ChessPieceWidget extends StatelessWidget {
  final chess.Piece piece;
  final double squareSize;
  final bool isDragging;
  final bool isBoardEnabled;
  final void Function()? onTap;

  const ChessPieceWidget({
    super.key,
    required this.piece,
    required this.squareSize,
    required this.isBoardEnabled,
    this.isDragging = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: isDragging
          ? SystemMouseCursors.grabbing
          : isBoardEnabled
              ? SystemMouseCursors.grab
              : SystemMouseCursors.basic,
      child: SizedBox(
        width: squareSize,
        height: squareSize,
        child: _buildPiece(),
      ),
    );
  }

  Widget _buildPiece() {
    return Center(
      child: GestureDetector(
        onTapDown: (_) => onTap == null ? null : onTap!(),
        child: getChessPieceWidget(piece),
      ),
    );
  }
}
