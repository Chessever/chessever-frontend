import 'package:flutter/material.dart';

class ChessArrow {
  final String startSquare;
  final String endSquare;
  final Color? color;

  ChessArrow({
    required this.startSquare,
    required this.endSquare,
    Color? color,
  }) : color = color ?? Colors.amber.withAlpha(128);

  @override
  bool operator ==(Object other) {
    return other is ChessArrow &&
        startSquare == other.startSquare &&
        endSquare == other.endSquare &&
        color == other.color;
  }

  @override
  int get hashCode =>
      startSquare.hashCode ^ endSquare.hashCode ^ color.hashCode;
}
