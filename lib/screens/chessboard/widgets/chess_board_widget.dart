// import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
// import 'package:chessever2/screens/chessboard/utils/board_theme.dart';
// import 'package:chessever2/screens/chessboard/view_model/chess_viewmodel.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_svg/flutter_svg.dart';
// import 'package:squares/squares.dart';

// class ChessBoardWidget extends StatefulWidget {
//   final ChessViewModel viewModel;
//   final Function(void Function()) setState;
//   final bool flipBoard;
//   final BoardColor boardColor;
//   final String pieceStyle;

//   const ChessBoardWidget({
//     super.key,
//     required this.viewModel,
//     required this.setState,
//     required this.flipBoard,
//     required this.boardColor,
//     required this.pieceStyle,
//   });

//   static const Map<String, String> _pieceAssets = {
//     'P': 'assets/svgs/pieces/wP.svg',
//     'N': 'assets/svgs/pieces/wN.svg',
//     'B': 'assets/svgs/pieces/wB.svg',
//     'R': 'assets/svgs/pieces/wR.svg',
//     'Q': 'assets/svgs/pieces/wQ.svg',
//     'K': 'assets/svgs/pieces/wK.svg',
//     'p': 'assets/svgs/pieces/bP.svg',
//     'n': 'assets/svgs/pieces/bN.svg',
//     'b': 'assets/svgs/pieces/bB.svg',
//     'r': 'assets/svgs/pieces/bR.svg',
//     'q': 'assets/svgs/pieces/bQ.svg',
//     'k': 'assets/svgs/pieces/bK.svg',
//   };

//   @override
//   State<ChessBoardWidget> createState() => _ChessBoardWidgetState();
// }

// class _ChessBoardWidgetState extends State<ChessBoardWidget> {
//   late final PieceSet _pieceSet;

//   @override
//   void initState() {
//     super.initState();
//     _pieceSet = PieceSet(
//       // pieces: {
//       //   for (var entry in ChessBoardWidget._pieceAssets.entries)
//       //     entry.key: (context) => _buildPieceWidget(context, entry.value),
//       // },
//       pieces: {
//         // Test with simple colored boxes first
//         'P': (context) => Container(color: Colors.red, width: 40, height: 40),
//         'N': (context) => Container(color: Colors.blue, width: 40, height: 40),
//         'B': (context) => Container(color: Colors.green, width: 40, height: 40),
//         'R':
//             (context) => Container(color: Colors.yellow, width: 40, height: 40),
//         'Q':
//             (context) => Container(color: Colors.purple, width: 40, height: 40),
//         'K':
//             (context) => Container(color: Colors.orange, width: 40, height: 40),
//         'p':
//             (context) =>
//                 Container(color: Colors.red[800], width: 40, height: 40),
//         'n':
//             (context) =>
//                 Container(color: Colors.blue[800], width: 40, height: 40),
//         'b':
//             (context) =>
//                 Container(color: Colors.green[800], width: 40, height: 40),
//         'r':
//             (context) =>
//                 Container(color: Colors.yellow[800], width: 40, height: 40),
//         'q':
//             (context) =>
//                 Container(color: Colors.purple[800], width: 40, height: 40),
//         'k':
//             (context) =>
//                 Container(color: Colors.orange[800], width: 40, height: 40),
//       },
//     );
//   }

//   Widget _buildPieceWidget(BuildContext context, String assetPath) {
//     try {
//       return SvgPicture.asset(
//         assetPath,
//         fit: BoxFit.contain,
//         placeholderBuilder: (context) => _buildPlaceholderPiece(),
//       );
//     } catch (e) {
//       debugPrint('Error loading $assetPath: $e');
//       return _buildPlaceholderPiece();
//     }
//   }

//   Widget _buildPlaceholderPiece() {
//     return Container(
//       color: Colors.grey[300],
//       child: Center(child: Icon(Icons.error, size: 20)),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     final themePair =
//         boardThemes[widget.boardColor] ?? boardThemes[BoardColor.defaultColor]!;

//     return BoardController(
//       state:
//           widget.flipBoard
//               ? widget.viewModel.state.board.flipped()
//               : widget.viewModel.state.board,
//       playState: widget.viewModel.state.state,
//       pieceSet: _pieceSet,
//       theme: BoardTheme(
//         lightSquare: themePair.lightSquare,
//         darkSquare: themePair.darkSquare,
//         check: Colors.transparent,
//         checkmate: Colors.transparent,
//         previous: Colors.transparent,
//         selected: Colors.transparent,
//         premove: Colors.transparent,
//       ),
//       moves: widget.viewModel.state.moves,
//       onMove: (move) => widget.viewModel.makeMove(move, widget.setState),
//       // onPremain: (move) => widget.viewModel.makeMove(move, widget.setState),
//       markerTheme: MarkerTheme(
//         empty: MarkerTheme.dot,
//         piece: MarkerTheme.corners(),
//       ),
//       promotionBehaviour: PromotionBehaviour.autoPremove,
//     );
//   }
// }
import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/screens/chessboard/utils/board_theme.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:squares/squares.dart';

class ChessBoardWidget extends StatefulWidget {
  final ChessViewModel viewModel;
  final VoidCallback setState; // Changed to VoidCallback
  final bool flipBoard;
  final BoardColor boardColor;
  final String pieceStyle;

  const ChessBoardWidget({
    super.key,
    required this.viewModel,
    required this.setState,
    required this.flipBoard,
    required this.boardColor,
    required this.pieceStyle,
  });

  static const Map<String, String> _pieceAssets = {
    'P': 'assets/svgs/wQ.svg',
    'N': 'assets/svgs/apple_logo.svg',
    'B': 'assets/svgs/pieces/wB.svg',
    'R': 'assets/svgs/pieces/wR.svg',
    'Q': 'assets/svgs/pieces/wQ.svg',
    'K': 'assets/svgs/pieces/wK.svg',
    'p': 'assets/svgs/pieces/bP.svg',
    'n': 'assets/svgs/pieces/bN.svg',
    'b': 'assets/svgs/pieces/bB.svg',
    'r': 'assets/svgs/pieces/bR.svg',
    'q': 'assets/svgs/pieces/bQ.svg',
    'k': 'assets/svgs/pieces/bK.svg',
  };

  @override
  State<ChessBoardWidget> createState() => _ChessBoardWidgetState();
}

class _ChessBoardWidgetState extends State<ChessBoardWidget> {
  late PieceSet _pieceSet;
  bool _assetsReady = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializePieceSet();
  }

  @override
  void didUpdateWidget(ChessBoardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Force rebuild when the widget updates
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _initializePieceSet() async {
    try {
      await DefaultAssetBundle.of(
        context,
      ).load(ChessBoardWidget._pieceAssets['P']!);

      _pieceSet = PieceSet(
        pieces: {
          for (var entry in ChessBoardWidget._pieceAssets.entries)
            entry.key: (context) => _buildSvgPiece(entry.value),
        },
      );
    } catch (e) {
      debugPrint('Failed to load SVG pieces: $e');
      setState(() {
        _errorMessage = 'SVG pieces failed to load. Using fallback.';
        _pieceSet = _createFallbackPieceSet();
      });
    } finally {
      if (mounted) {
        setState(() => _assetsReady = true);
      }
    }
  }

  Widget _buildSvgPiece(String assetPath) {
    return SvgPicture.asset(
      assetPath,
      fit: BoxFit.contain,
      placeholderBuilder: (context) => _buildErrorWidget(assetPath),
    );
  }

  Widget _buildErrorWidget(String assetPath) {
    return Container(
      color: Colors.grey[300],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 20),
            Text(
              assetPath.split('/').last,
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  PieceSet _createFallbackPieceSet() {
    return PieceSet.merida();
  }

  @override
  Widget build(BuildContext context) {
    if (!_assetsReady) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      debugPrint(_errorMessage!);
    }

    final boardState =
        widget.flipBoard
            ? widget.viewModel.state.board.flipped()
            : widget.viewModel.state.board;

    final themePair =
        boardThemes[widget.boardColor] ?? boardThemes[BoardColor.defaultColor]!;

    return BoardController(
      state: boardState,
      playState: widget.viewModel.state.state,
      // pieceSet: _pieceSet, // Use custom piece set instead of PieceSet.merida()
      pieceSet: PieceSet.merida(),
      theme: BoardTheme(
        lightSquare: themePair.lightSquare,
        darkSquare: themePair.darkSquare,
        check: Colors.yellow.withOpacity(0.4),
        checkmate: Colors.red.withOpacity(0.4),
        previous: Colors.blue.withOpacity(0.2),
        selected: Colors.green.withOpacity(0.4),
        premove: Colors.purple.withOpacity(0.4),
      ),
      moves: widget.viewModel.state.moves,
      onMove: (move) {
        widget.viewModel.makeMove(move, widget.setState);
      },
      markerTheme: MarkerTheme(
        empty: MarkerTheme.dot,
        piece: MarkerTheme.corners(),
      ),
      promotionBehaviour: PromotionBehaviour.autoPremove,
    );
  }
}
