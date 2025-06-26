import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:squares/squares.dart';

class CustomPieceSet extends PieceSet {
  final Map<String, String> pieceAssets;
  final Map<String, WidgetBuilder> pieceBuilders;

  CustomPieceSet(this.pieceAssets)
      : pieceBuilders = _createPieceBuilders(pieceAssets),
        super(pieces: _createPieceBuilders(pieceAssets));

  static Map<String, WidgetBuilder> _createPieceBuilders(Map<String, String> assets) {
    return {
      for (var entry in assets.entries)
        entry.key: (context) => _buildPieceWidget(context, entry.value),
    };
  }

  static Widget _buildPieceWidget(BuildContext context, String assetPath) {
    return SvgPicture.asset(
      assetPath,
      fit: BoxFit.contain,
    );
  }

  @override
  Widget buildPiece(BuildContext context, String piece, double size) {
    final builder = pieceBuilders[piece];
    return builder != null
        ? SizedBox(
            width: size,
            height: size,
            child: builder(context),
          )
        : SizedBox.shrink();
  }
}