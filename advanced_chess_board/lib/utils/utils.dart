import 'package:advanced_chess_board/constants/global_constants.dart';
import 'package:advanced_chess_board/constants/image_constants.dart';
import 'package:chess/chess.dart';
import 'package:flutter/material.dart';

Widget getChessPieceWidget(final Piece chessPiece) {
  if (chessPiece.color == Color.WHITE) {
    switch (chessPiece.type) {
      case PieceType.BISHOP:
        return _getPieceImageWidget(PieceImages.whiteBishop);
      case PieceType.KING:
        return _getPieceImageWidget(PieceImages.whiteKing);
      case PieceType.KNIGHT:
        return _getPieceImageWidget(PieceImages.whiteKnight);
      case PieceType.PAWN:
        return _getPieceImageWidget(PieceImages.whitePawn);
      case PieceType.QUEEN:
        return _getPieceImageWidget(PieceImages.whiteQueen);
      case PieceType.ROOK:
        return _getPieceImageWidget(PieceImages.whiteRook);
    }
  } else {
    switch (chessPiece.type) {
      case PieceType.BISHOP:
        return _getPieceImageWidget(PieceImages.blackBishop);
      case PieceType.KING:
        return _getPieceImageWidget(PieceImages.blackKing);
      case PieceType.KNIGHT:
        return _getPieceImageWidget(PieceImages.blackKnight);
      case PieceType.PAWN:
        return _getPieceImageWidget(PieceImages.blackPawn);
      case PieceType.QUEEN:
        return _getPieceImageWidget(PieceImages.blackQueen);
      case PieceType.ROOK:
        return _getPieceImageWidget(PieceImages.blackRook);
    }
  }
  return const Text("No piece found");
}

Widget _getPieceImageWidget(final assetPath) {
  return Image.asset(
    assetPath,
    package: packageName,
    fit: BoxFit.contain,
  );
}

String pieceTypeToString(final PieceType pieceType) {
  switch (pieceType) {
    case PieceType.BISHOP:
      return "b";
    case PieceType.KING:
      return "k";
    case PieceType.KNIGHT:
      return "n";
    case PieceType.PAWN:
      return "p";
    case PieceType.QUEEN:
      return "q";
    case PieceType.ROOK:
      return "r";
  }
  return "q";
}
