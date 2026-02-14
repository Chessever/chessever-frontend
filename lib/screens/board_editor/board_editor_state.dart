import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _startingFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

class BoardEditorState {
  const BoardEditorState({
    this.pieces = const {},
    this.orientation = Side.white,
    this.sideToMove = Side.white,
    this.whiteKingsideCastle = true,
    this.whiteQueensideCastle = true,
    this.blackKingsideCastle = true,
    this.blackQueensideCastle = true,
    this.selectedPiece,
    this.pointerMode = EditorPointerMode.drag,
    this.isDeleteMode = false,
  });

  final Pieces pieces;
  final Side orientation;
  final Side sideToMove;
  final bool whiteKingsideCastle;
  final bool whiteQueensideCastle;
  final bool blackKingsideCastle;
  final bool blackQueensideCastle;
  final Piece? selectedPiece;
  final EditorPointerMode pointerMode;
  final bool isDeleteMode;

  /// Whether the position has both kings — minimum requirement for engine eval.
  bool get isEvaluatable {
    bool hasWhiteKing = false;
    bool hasBlackKing = false;
    for (final piece in pieces.values) {
      if (piece.role == Role.king) {
        if (piece.color == Side.white) hasWhiteKing = true;
        if (piece.color == Side.black) hasBlackKing = true;
        if (hasWhiteKing && hasBlackKing) return true;
      }
    }
    return false;
  }

  String get boardFen => writeFen(pieces);

  String get fullFen {
    final board = boardFen;
    final turn = sideToMove == Side.white ? 'w' : 'b';
    final castling = _castlingString;
    return '$board $turn $castling - 0 1';
  }

  String get _castlingString {
    final buf = StringBuffer();
    if (whiteKingsideCastle) buf.write('K');
    if (whiteQueensideCastle) buf.write('Q');
    if (blackKingsideCastle) buf.write('k');
    if (blackQueensideCastle) buf.write('q');
    final result = buf.toString();
    return result.isEmpty ? '-' : result;
  }

  BoardEditorState copyWith({
    Pieces? pieces,
    Side? orientation,
    Side? sideToMove,
    bool? whiteKingsideCastle,
    bool? whiteQueensideCastle,
    bool? blackKingsideCastle,
    bool? blackQueensideCastle,
    Piece? Function()? selectedPiece,
    EditorPointerMode? pointerMode,
    bool? isDeleteMode,
  }) {
    return BoardEditorState(
      pieces: pieces ?? this.pieces,
      orientation: orientation ?? this.orientation,
      sideToMove: sideToMove ?? this.sideToMove,
      whiteKingsideCastle: whiteKingsideCastle ?? this.whiteKingsideCastle,
      whiteQueensideCastle: whiteQueensideCastle ?? this.whiteQueensideCastle,
      blackKingsideCastle: blackKingsideCastle ?? this.blackKingsideCastle,
      blackQueensideCastle: blackQueensideCastle ?? this.blackQueensideCastle,
      selectedPiece: selectedPiece != null ? selectedPiece() : this.selectedPiece,
      pointerMode: pointerMode ?? this.pointerMode,
      isDeleteMode: isDeleteMode ?? this.isDeleteMode,
    );
  }
}

class BoardEditorNotifier extends StateNotifier<BoardEditorState> {
  BoardEditorNotifier() : super(const BoardEditorState(
    pieces: {},
    whiteKingsideCastle: false,
    whiteQueensideCastle: false,
    blackKingsideCastle: false,
    blackQueensideCastle: false,
  ));

  void reset() {
    state = BoardEditorState(
      pieces: readFen(_startingFen),
    );
  }

  void clear() {
    state = const BoardEditorState(
      pieces: {},
      whiteKingsideCastle: false,
      whiteQueensideCastle: false,
      blackKingsideCastle: false,
      blackQueensideCastle: false,
    );
  }

  void flipBoard() {
    state = state.copyWith(
      orientation: state.orientation == Side.white ? Side.black : Side.white,
    );
  }

  void selectPiece(Piece? piece) {
    if (piece == null) {
      // Deselect
      state = state.copyWith(
        selectedPiece: () => null,
        pointerMode: EditorPointerMode.drag,
        isDeleteMode: false,
      );
    } else if (state.selectedPiece == piece && !state.isDeleteMode) {
      // Tap same piece again → deselect
      state = state.copyWith(
        selectedPiece: () => null,
        pointerMode: EditorPointerMode.drag,
        isDeleteMode: false,
      );
    } else {
      state = state.copyWith(
        selectedPiece: () => piece,
        pointerMode: EditorPointerMode.edit,
        isDeleteMode: false,
      );
    }
  }

  void toggleDeleteMode() {
    if (state.isDeleteMode) {
      state = state.copyWith(
        isDeleteMode: false,
        selectedPiece: () => null,
        pointerMode: EditorPointerMode.drag,
      );
    } else {
      state = state.copyWith(
        isDeleteMode: true,
        selectedPiece: () => null,
        pointerMode: EditorPointerMode.edit,
      );
    }
  }

  void onEditedSquare(Square square) {
    final newPieces = Map<Square, Piece>.of(state.pieces);
    if (state.isDeleteMode) {
      newPieces.remove(square);
    } else if (state.selectedPiece != null) {
      newPieces[square] = state.selectedPiece!;
    }
    state = state.copyWith(pieces: newPieces);
  }

  void onDroppedPiece(Square? origin, Square destination, Piece piece) {
    final newPieces = Map<Square, Piece>.of(state.pieces);
    if (origin != null) {
      newPieces.remove(origin);
    }
    newPieces[destination] = piece;
    state = state.copyWith(pieces: newPieces);
  }

  void onDiscardedPiece(Square square) {
    final newPieces = Map<Square, Piece>.of(state.pieces);
    newPieces.remove(square);
    state = state.copyWith(pieces: newPieces);
  }

  void setSideToMove(Side side) {
    state = state.copyWith(sideToMove: side);
  }

  void toggleCastling({
    bool? whiteKingside,
    bool? whiteQueenside,
    bool? blackKingside,
    bool? blackQueenside,
  }) {
    state = state.copyWith(
      whiteKingsideCastle: whiteKingside ?? state.whiteKingsideCastle,
      whiteQueensideCastle: whiteQueenside ?? state.whiteQueensideCastle,
      blackKingsideCastle: blackKingside ?? state.blackKingsideCastle,
      blackQueensideCastle: blackQueenside ?? state.blackQueensideCastle,
    );
  }

  void loadFen(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return;

    final pieces = readFen(parts[0]);
    final sideToMove = parts.length > 1 && parts[1] == 'b'
        ? Side.black
        : Side.white;

    bool wK = false, wQ = false, bK = false, bQ = false;
    if (parts.length > 2) {
      final c = parts[2];
      wK = c.contains('K');
      wQ = c.contains('Q');
      bK = c.contains('k');
      bQ = c.contains('q');
    }

    state = state.copyWith(
      pieces: pieces,
      sideToMove: sideToMove,
      whiteKingsideCastle: wK,
      whiteQueensideCastle: wQ,
      blackKingsideCastle: bK,
      blackQueensideCastle: bQ,
      selectedPiece: () => null,
      pointerMode: EditorPointerMode.drag,
      isDeleteMode: false,
    );
  }
}

final boardEditorProvider =
    StateNotifierProvider.autoDispose<BoardEditorNotifier, BoardEditorState>(
  (ref) => BoardEditorNotifier(),
);
