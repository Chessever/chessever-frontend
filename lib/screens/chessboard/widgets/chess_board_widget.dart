import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/screens/chessboard/utils/board_theme.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:squares/squares.dart';

class ChessBoardWidget extends ConsumerStatefulWidget {
  final BoardColor boardColor;
  final String pieceStyle;

  const ChessBoardWidget({
    super.key,
    required this.boardColor,
    required this.pieceStyle,
  });

  static const Map<String, String> _pieceAssets = {
    'P': 'assets/pngs/pieces/wP.png',
    'N': 'assets/pngs/pieces/wN.png',
    'B': 'assets/pngs/pieces/wB.png',
    'R': 'assets/pngs/pieces/wR.png',
    'Q': 'assets/pngs/pieces/wQ.png',
    'K': 'assets/pngs/pieces/wK.png',
    'p': 'assets/pngs/pieces/bP.png',
    'n': 'assets/pngs/pieces/bN.png',
    'b': 'assets/pngs/pieces/bB.png',
    'r': 'assets/pngs/pieces/bR.png',
    'q': 'assets/pngs/pieces/bQ.png',
    'k': 'assets/pngs/pieces/bK.png',
  };

  @override
  ConsumerState<ChessBoardWidget> createState() => _ChessBoardWidgetState();
}

class _ChessBoardWidgetState extends ConsumerState<ChessBoardWidget> {
  PieceSet? _pieceSet;

  @override
  void initState() {
    _initializePieceSet();
    super.initState();
  }

  Future<void> _initializePieceSet() async {
    try {
      await DefaultAssetBundle.of(
        context,
      ).load(ChessBoardWidget._pieceAssets['K']!);

      if (mounted) {
        setState(() {
          _pieceSet = PieceSet(
            pieces: {
              for (var entry in ChessBoardWidget._pieceAssets.entries)
                entry.key:
                    (context) => Image.asset(entry.value, fit: BoxFit.contain),
            },
          );
        });
      }
    } catch (e) {
      debugPrint('Failed to load custom pieces: $e');
      if (mounted) {
        setState(() => _pieceSet = PieceSet.merida());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pieceSet == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final chessState = ref.watch(chessViewModelProvider);
    final flipBoard = ref.watch(flipBoardProvider);
    final boardState =
        flipBoard
            ? chessState.squaresState.board.flipped()
            : chessState.squaresState.board;
    final themePair =
        boardThemes[widget.boardColor] ?? boardThemes[BoardColor.defaultColor]!;

    return BoardController(
      state: boardState,
      playState: chessState.squaresState.state,
      pieceSet: _pieceSet!,
      theme: BoardTheme(
        lightSquare: themePair.lightSquare,
        darkSquare: themePair.darkSquare,
        check: Colors.yellow.withOpacity(0.4),
        checkmate: Colors.red.withOpacity(0.4),
        previous: Colors.blue.withOpacity(0.2),
        selected: Colors.green.withOpacity(0.4),
        premove: Colors.purple.withOpacity(0.4),
      ),
      moves: chessState.squaresState.moves,
      onMove:
          (move) => ref.read(chessViewModelProvider.notifier).makeMove(move),
      markerTheme: MarkerTheme(
        empty: MarkerTheme.dot,
        piece: MarkerTheme.corners(),
      ),
      promotionBehaviour: PromotionBehaviour.autoPremove,
    );
  }
}
