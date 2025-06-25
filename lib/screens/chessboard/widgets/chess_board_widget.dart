import 'package:chessever2/screens/chessboard/view_model/chess_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:squares/squares.dart';
// import 'chess_viewmodel.dart';

class ChessBoardWidget extends StatelessWidget {
  final ChessViewModel viewModel;
  final Function(void Function()) setState;
  final bool flipBoard;

  const ChessBoardWidget({
    super.key,
    required this.viewModel,
    required this.setState,
    required this.flipBoard,
  });

  @override
  Widget build(BuildContext context) {
    return BoardController(
      state:
          flipBoard ? viewModel.state.board.flipped() : viewModel.state.board,
      playState: viewModel.state.state,
      pieceSet: PieceSet.merida(),
      theme: BoardTheme.blueGrey,
      moves: viewModel.state.moves,
      onMove: (move) => viewModel.makeMove(move, setState),
      onPremove: (move) => viewModel.makeMove(move, setState),
      markerTheme: MarkerTheme(
        empty: MarkerTheme.dot,
        piece: MarkerTheme.corners(),
      ),
      promotionBehaviour: PromotionBehaviour.autoPremove,
    );
  }
}
