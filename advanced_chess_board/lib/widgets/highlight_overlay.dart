import 'package:flutter/material.dart';

class HighlightOverlay extends StatelessWidget {
  const HighlightOverlay({
    super.key,
    required this.squareSize,
    required this.hasPiece,
  });

  final double squareSize;
  final bool hasPiece;

  @override
  Widget build(BuildContext context) {
    final smallDotSize = squareSize * 0.3;
    final circleSize = squareSize * 0.98;
    return Align(
      alignment: Alignment.center,
      child: hasPiece
          ? Container(
              width: circleSize,
              height: circleSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.black12.withAlpha(75),
                  width: squareSize * 0.1,
                ),
              ),
            )
          : Container(
              width: smallDotSize,
              height: smallDotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black12.withAlpha(100),
              ),
            ),
    );
  }
}
