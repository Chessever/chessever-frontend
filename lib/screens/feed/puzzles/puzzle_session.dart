import 'package:chessever2/screens/feed/puzzles/feed_puzzle_model.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

/// How a solver's move was judged.
enum PuzzleVerdict {
  /// The solution move; the opponent answers next.
  correct,

  /// The move that ends the puzzle: the last solution move, or any mate.
  solved,

  /// Not the solution. The position does not change.
  wrong,
}

/// One move the solver tried, with the position it led to.
@immutable
class PuzzleAttempt {
  const PuzzleAttempt({
    required this.move,
    required this.san,
    required this.verdict,
    required this.before,
    required this.after,
  });

  /// The move as played, in standard form (castling is king-two-squares).
  final NormalMove move;
  final String san;
  final PuzzleVerdict verdict;
  final Position before;

  /// Where the move leads. For a [PuzzleVerdict.wrong] move this is only what
  /// the board shows before the piece goes back; the session stays put.
  final Position after;
}

/// A move the session played itself: the opponent's reply, or a solution
/// move while the answer is being shown.
typedef PuzzleStep = ({NormalMove move, String san, bool bySolver});

/// The rules of one puzzle run, free of widgets and timers so tests can
/// drive it move by move.
///
/// Matches Lichess: the solver must find each solution move, except that any
/// move that checkmates wins outright (Lichess accepts every mating move).
/// Castling is accepted in either encoding and promotions must match.
class PuzzleSession {
  PuzzleSession._({
    required this.puzzle,
    required this.setupPosition,
    required this.setupMove,
    required this.setupSan,
    required this.startPosition,
    required this._solution,
  }) : _position = startPosition,
       _lastMove = setupMove;

  /// Builds a session; throws [FormatException] when the puzzle's moves do
  /// not replay legally from its position.
  factory PuzzleSession(FeedPuzzle puzzle) {
    final Position setup;
    try {
      setup = Chess.fromSetup(Setup.parseFen(puzzle.fen));
    } catch (error) {
      throw FormatException('Puzzle ${puzzle.id}: bad FEN ($error)');
    }

    var position = setup;
    NormalMove? setupMove;
    String? setupSan;
    final initial = puzzle.initialMoveUci;
    if (initial != null) {
      final move = _legal(position, initial);
      if (move == null) {
        throw FormatException('Puzzle ${puzzle.id}: illegal setup $initial');
      }
      final (next, san) = position.makeSan(move);
      setupMove = standardMove(position, move);
      setupSan = san;
      position = next;
    }
    final start = position;

    final solution = <NormalMove>[];
    for (final uci in puzzle.solution) {
      final move = _legal(position, uci);
      if (move == null) {
        throw FormatException('Puzzle ${puzzle.id}: illegal solution $uci');
      }
      solution.add(standardMove(position, move));
      position = position.play(move);
    }
    if (solution.isEmpty) {
      throw FormatException('Puzzle ${puzzle.id}: empty solution');
    }

    return PuzzleSession._(
      puzzle: puzzle,
      setupPosition: setup,
      setupMove: setupMove,
      setupSan: setupSan,
      startPosition: start,
      solution: solution,
    );
  }

  final FeedPuzzle puzzle;

  /// Before the opponent's setup move (what the board shows first).
  final Position setupPosition;
  final NormalMove? setupMove;
  final String? setupSan;

  /// The puzzle position: the solver to move.
  final Position startPosition;

  final List<NormalMove> _solution;
  Position _position;
  NormalMove? _lastMove;
  int _step = 0;
  bool _solved = false;
  bool _revealing = false;

  Position get position => _position;
  NormalMove? get lastMove => _lastMove;

  /// The side the viewer plays.
  Side get solver => startPosition.turn;

  /// Solution moves already on the board.
  int get step => _step;

  /// Every solution move is on the board (solved or shown).
  bool get isComplete => _step >= _solution.length;

  /// The solver found it (the last solution move, or a mate).
  bool get isSolved => _solved;

  bool get isSolverTurn => !isComplete && !_solved && _position.turn == solver;

  /// How many moves the solver has to find.
  int get solverMoveCount => (_solution.length + 1) ~/ 2;

  /// How many of them are already on the board.
  int get solverMovesPlayed => isComplete ? solverMoveCount : (_step + 1) ~/ 2;

  /// The move the solver should play now; null when it is not their turn.
  NormalMove? get hint => isSolverTurn ? _solution[_step] : null;

  /// The opponent's scripted reply, due now.
  bool get replyDue => !isComplete && !_solved && _position.turn != solver;

  /// Judges and, when right, plays [move]. Null for an illegal move or when
  /// it is not the solver's turn.
  PuzzleAttempt? play(Move move) {
    if (!isSolverTurn || move is! NormalMove) return null;
    final before = _position;
    if (!before.isLegal(move) || _missingPromotion(before, move)) return null;
    final (after, san) = before.makeSan(move);
    final played = standardMove(before, move);

    PuzzleAttempt attempt(PuzzleVerdict verdict) => PuzzleAttempt(
      move: played,
      san: san,
      verdict: verdict,
      before: before,
      after: after,
    );

    if (after.isCheckmate) {
      _commit(after, played);
      _step = _solution.length;
      _solved = true;
      return attempt(PuzzleVerdict.solved);
    }

    final expected = _solution[_step];
    if (after.fen != before.play(expected).fen) {
      return attempt(PuzzleVerdict.wrong);
    }

    _commit(after, played);
    _step++;
    if (isComplete) {
      _solved = true;
      return attempt(PuzzleVerdict.solved);
    }
    return attempt(PuzzleVerdict.correct);
  }

  /// Plays the next solution move for whoever is to move: the opponent's
  /// reply, or the answer while it is being shown. Null once complete.
  PuzzleStep? advance() {
    if (isComplete || _solved) return null;
    final move = _solution[_step];
    final bySolver = _position.turn == solver;
    final (after, san) = _position.makeSan(move);
    _commit(after, move);
    _step++;
    if (isComplete && !_revealing) _solved = true;
    return (move: move, san: san, bySolver: bySolver);
  }

  /// From now on [advance] plays the solver's moves too, without counting
  /// the puzzle as solved.
  void beginReveal() => _revealing = true;

  /// Whether the answer was shown rather than found.
  bool get isRevealed => _revealing;

  /// Back to the puzzle position, as if nothing had been tried.
  void reset() {
    _position = startPosition;
    _lastMove = setupMove;
    _step = 0;
    _solved = false;
    _revealing = false;
  }

  /// Jumps to the final position without playing anything out (a puzzle
  /// finished earlier in this session).
  void finish({required bool solved}) {
    reset();
    while (!isComplete) {
      final move = _solution[_step];
      _commit(_position.play(move), move);
      _step++;
    }
    _solved = solved;
    _revealing = !solved;
  }

  void _commit(Position after, NormalMove move) {
    _position = after;
    _lastMove = move;
  }

  static NormalMove? _legal(Position position, String uci) {
    final move = Move.parse(uci);
    if (move is! NormalMove ||
        !position.isLegal(move) ||
        _missingPromotion(position, move)) {
      return null;
    }
    return move;
  }

  /// dartchess accepts a pawn step onto the last rank with no promotion
  /// piece; a puzzle move never is one.
  static bool _missingPromotion(Position position, NormalMove move) =>
      move.promotion == null &&
      position.board.pawns.has(move.from) &&
      SquareSet.backranks.has(move.to);
}

/// [move] with castling spelled king-two-squares (e1g1), the way Lichess
/// writes it and the board highlights it, rather than dartchess's
/// king-takes-rook form (e1h1).
NormalMove standardMove(Position position, NormalMove move) {
  if (move.promotion != null) return move;
  final piece = position.board.pieceAt(move.from);
  final target = position.board.pieceAt(move.to);
  if (piece == null ||
      piece.role != Role.king ||
      target == null ||
      target.color != piece.color ||
      target.role != Role.rook) {
    return move;
  }
  final file = move.to.file > move.from.file ? File.g : File.c;
  return NormalMove(
    from: move.from,
    to: Square.fromCoords(file, move.from.rank),
  );
}
