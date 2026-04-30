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
    this.epSquare,
    this.halfmoves = 0,
    this.fullmoves = 1,
    this.selectedPiece,
    this.pointerMode = EditorPointerMode.drag,
    this.isDeleteMode = false,
    this.selectedDragSquare,
  });

  final Pieces pieces;
  final Side orientation;
  final Side sideToMove;
  final bool whiteKingsideCastle;
  final bool whiteQueensideCastle;
  final bool blackKingsideCastle;
  final bool blackQueensideCastle;
  final Square? epSquare;
  final int halfmoves;
  final int fullmoves;
  final Piece? selectedPiece;
  final EditorPointerMode pointerMode;
  final bool isDeleteMode;
  final Square? selectedDragSquare;

  /// Whether the position is a legal chess position that can be evaluated.
  ///
  /// Validates using dartchess to ensure the FEN won't crash Stockfish.
  /// Requires both kings, no pawns on back ranks, and the side not to move
  /// must not have their king in check.
  bool get isEvaluatable {
    // Quick pre-check: need both kings
    bool hasWhiteKing = false;
    bool hasBlackKing = false;
    for (final piece in pieces.values) {
      if (piece.role == Role.king) {
        if (piece.color == Side.white) hasWhiteKing = true;
        if (piece.color == Side.black) hasBlackKing = true;
      }
    }
    if (!hasWhiteKing || !hasBlackKing) return false;

    // Full legality check via dartchess
    try {
      final setup = Setup.parseFen(fullFen);
      Chess.fromSetup(setup, ignoreImpossibleCheck: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  String get boardFen => writeFen(pieces);

  String get fullFen {
    final board = boardFen;
    final turn = sideToMove == Side.white ? 'w' : 'b';
    final castling = _castlingString;
    final ep = epSquare?.name ?? '-';
    return '$board $turn $castling $ep $halfmoves $fullmoves';
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
    Square? Function()? epSquare,
    int? halfmoves,
    int? fullmoves,
    Piece? Function()? selectedPiece,
    EditorPointerMode? pointerMode,
    bool? isDeleteMode,
    Square? Function()? selectedDragSquare,
  }) {
    return BoardEditorState(
      pieces: pieces ?? this.pieces,
      orientation: orientation ?? this.orientation,
      sideToMove: sideToMove ?? this.sideToMove,
      whiteKingsideCastle: whiteKingsideCastle ?? this.whiteKingsideCastle,
      whiteQueensideCastle: whiteQueensideCastle ?? this.whiteQueensideCastle,
      blackKingsideCastle: blackKingsideCastle ?? this.blackKingsideCastle,
      blackQueensideCastle: blackQueensideCastle ?? this.blackQueensideCastle,
      epSquare: epSquare != null ? epSquare() : this.epSquare,
      halfmoves: halfmoves ?? this.halfmoves,
      fullmoves: fullmoves ?? this.fullmoves,
      selectedPiece:
          selectedPiece != null ? selectedPiece() : this.selectedPiece,
      pointerMode: pointerMode ?? this.pointerMode,
      isDeleteMode: isDeleteMode ?? this.isDeleteMode,
      selectedDragSquare:
          selectedDragSquare != null
              ? selectedDragSquare()
              : this.selectedDragSquare,
    );
  }
}

class BoardEditorNotifier extends StateNotifier<BoardEditorState> {
  BoardEditorNotifier()
    : super(BoardEditorState(pieces: readFen(_startingFen)));

  void reset() {
    state = BoardEditorState(pieces: readFen(_startingFen));
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

  void onTapSquare(Square square) {
    if (state.pointerMode == EditorPointerMode.edit) return;

    final selected = state.selectedDragSquare;

    if (selected == null) {
      // No square selected yet — select if there's a piece
      if (state.pieces.containsKey(square)) {
        state = state.copyWith(selectedDragSquare: () => square);
      }
    } else if (selected == square) {
      // Same square tapped again — deselect
      state = state.copyWith(selectedDragSquare: () => null);
    } else {
      // Different square tapped — move the piece
      final piece = state.pieces[selected];
      if (piece != null) {
        final newPieces = Map<Square, Piece>.of(state.pieces);
        newPieces.remove(selected);
        newPieces[square] = piece;
        state = _withBoardMutation(
          pieces: newPieces,
          clearDragSquare: true,
        );
      } else {
        state = state.copyWith(selectedDragSquare: () => null);
      }
    }
  }

  void onEditedSquare(Square square) {
    final newPieces = Map<Square, Piece>.of(state.pieces);
    if (state.isDeleteMode) {
      newPieces.remove(square);
    } else if (state.selectedPiece != null) {
      newPieces[square] = state.selectedPiece!;
    }
    state = _withBoardMutation(pieces: newPieces, clearDragSquare: true);
  }

  void onDroppedPiece(Square? origin, Square destination, Piece piece) {
    final newPieces = Map<Square, Piece>.of(state.pieces);
    if (origin != null) {
      newPieces.remove(origin);
    }
    newPieces[destination] = piece;
    state = _withBoardMutation(pieces: newPieces, clearDragSquare: true);
  }

  void onDiscardedPiece(Square square) {
    final newPieces = Map<Square, Piece>.of(state.pieces);
    newPieces.remove(square);
    state = _withBoardMutation(pieces: newPieces, clearDragSquare: true);
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
    final Setup setup;
    try {
      setup = Setup.parseFen(fen);
    } catch (_) {
      return;
    }

    final pieces = <Square, Piece>{};
    for (final (square, piece) in setup.board.pieces) {
      pieces[square] = piece;
    }

    state = state.copyWith(
      pieces: pieces,
      sideToMove: setup.turn,
      whiteKingsideCastle: _hasCastling(setup, Side.white, kingside: true),
      whiteQueensideCastle: _hasCastling(setup, Side.white, kingside: false),
      blackKingsideCastle: _hasCastling(setup, Side.black, kingside: true),
      blackQueensideCastle: _hasCastling(setup, Side.black, kingside: false),
      epSquare: () => setup.epSquare,
      halfmoves: setup.halfmoves,
      fullmoves: setup.fullmoves,
      selectedPiece: () => null,
      pointerMode: EditorPointerMode.drag,
      isDeleteMode: false,
    );
  }

  // Any board mutation invalidates the en-passant target and the
  // halfmove/fullmove counters parsed from a pasted FEN — they describe
  // a specific move history that no longer applies.
  BoardEditorState _withBoardMutation({
    required Pieces pieces,
    bool clearDragSquare = false,
  }) {
    return state.copyWith(
      pieces: pieces,
      epSquare: () => null,
      halfmoves: 0,
      fullmoves: 1,
      selectedDragSquare: clearDragSquare ? () => null : null,
    );
  }

  // Castling rights in dartchess point at rook squares, which lets us
  // round-trip Shredder-FEN / X-FEN (e.g. "HAha"). Compare each rook
  // square to the king's file rather than only checking a1/h1/a8/h8.
  static bool _hasCastling(Setup setup, Side side, {required bool kingside}) {
    final castling = setup.castlingRights & SquareSet.backrankOf(side);
    if (castling.isEmpty) return false;
    final king = setup.board.kingOf(side);
    if (king == null) {
      final rank = side == Side.white ? Rank.first : Rank.eighth;
      final fallback = Square.fromCoords(
        kingside ? File.h : File.a,
        rank,
      );
      return castling.has(fallback);
    }
    for (final sq in castling.squares) {
      if (kingside ? sq > king : sq < king) return true;
    }
    return false;
  }
}

final boardEditorProvider =
    StateNotifierProvider.autoDispose<BoardEditorNotifier, BoardEditorState>(
      (ref) => BoardEditorNotifier(),
    );
