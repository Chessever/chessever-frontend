import 'package:dartchess/dartchess.dart';

typedef Number = int;

class ChessGame {
  final String gameId;
  final String startingFen;
  final Map<String, dynamic> metadata;
  final ChessLine mainline;

  ChessGame({
    required this.gameId,
    required this.startingFen,
    required this.metadata,
    required this.mainline,
  });

  ChessGame copyWith({
    final String? gameId,
    final String? startingFen,
    final Map<String, dynamic>? metadata,
    final ChessLine? mainline,
  }) {
    return ChessGame(
      gameId: gameId ?? this.gameId,
      startingFen: startingFen ?? this.startingFen,
      metadata: metadata ?? this.metadata,
      mainline: mainline ?? this.mainline,
    );
  }

  factory ChessGame.fromPgn(final String gameId, final String pgn) {
    final pgnGame = PgnGame.parsePgn(pgn);
    final startingPosition = PgnGame.startingPosition(pgnGame.headers);
    final mainline = pgnGame.moves.mainline();

    var currentPosition = startingPosition;

    final List<ChessMove> parsedMainline = [];

    for (final mainlineNode in mainline) {
      final currentMove = currentPosition.parseSan(mainlineNode.san);

      if (currentMove == null) {
        break;
      }

      currentPosition = currentPosition.play(currentMove);

      parsedMainline.add(
        ChessMove(
          num: currentPosition.fullmoves,
          fen: currentPosition.fen,
          san: mainlineNode.san,
          uci: currentMove.uci,
          turn: currentPosition.turn == Side.black
              ? ChessColor.black
              : ChessColor.white,
        ),
      );
    }

    return ChessGame(
      gameId: gameId,
      metadata: pgnGame.headers,
      mainline: parsedMainline,
      startingFen: startingPosition.fen,
    );
  }
}

typedef ChessLine = List<ChessMove>;

class ChessMove {
  final Number num;
  final String fen;
  final String san;
  final String uci;
  final ChessColor turn;
  final List<ChessLine>? variations;

  ChessMove({
    required this.num,
    required this.fen,
    required this.san,
    required this.uci,
    required this.turn,
    this.variations,
  });

  ChessMove copyWith({
    final Number? num,
    final String? fen,
    final String? san,
    final String? uci,
    final ChessColor? turn,
    final List<ChessLine>? variations,
  }) {
    return ChessMove(
      num: num ?? this.num,
      fen: fen ?? this.fen,
      san: san ?? this.san,
      uci: uci ?? this.uci,
      turn: turn ?? this.turn,
      variations: variations ?? this.variations,
    );
  }
}

enum ChessColor {
  black("black"),
  white("white");

  final String value;

  const ChessColor(this.value);

  @override
  String toString() {
    return value;
  }
}
