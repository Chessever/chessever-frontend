import 'package:dartchess/dartchess.dart';

typedef Number = int;

typedef ChessLine = List<ChessMove>;

final RegExp _timeRegex = RegExp(r'\[%clk (\d+:\d+:\d+)\]');

class ChessGame {
  static const String metadataIsLiveKey = 'isLiveGame';
  static const String metadataAllowMainlineExtensionKey =
      'allowMainlineExtension';

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

  factory ChessGame.fromJson(Map<String, dynamic> json) {
    return ChessGame(
      gameId: json['id'] as String,
      startingFen: json['sf'] as String,
      metadata: (json['md'] as Map).cast<String, dynamic>(),
      mainline:
          (json['m'] as List)
              .map(
                (move) =>
                    ChessMove.fromJson((move as Map).cast<String, dynamic>()),
              )
              .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': gameId,
    'sf': startingFen,
    'md': metadata,
    'm': mainline.map((move) => move.toJson()).toList(),
  };

  ChessGame copyWith({
    String? gameId,
    String? startingFen,
    Map<String, dynamic>? metadata,
    ChessLine? mainline,
  }) {
    return ChessGame(
      gameId: gameId ?? this.gameId,
      startingFen: startingFen ?? this.startingFen,
      metadata: metadata ?? this.metadata,
      mainline: mainline ?? this.mainline,
    );
  }

  bool get isLiveGame {
    final flag = metadata[metadataIsLiveKey];
    if (flag is bool) return flag;
    if (flag is String) {
      return flag.toLowerCase() == 'true';
    }
    return false;
  }

  bool get allowMainlineExtension =>
      metadata[metadataAllowMainlineExtensionKey] == true;

  String? get timeControl => metadata['TimeControl'] as String?;

  factory ChessGame.fromPgn(String gameId, String pgn) {
    final pgnGame = PgnGame.parsePgn(pgn);
    final startingPosition = PgnGame.startingPosition(pgnGame.headers);

    final mainline = _parsePgnNodes(
      pgnGame.moves.children,
      startingPosition,
    );

    return ChessGame(
      gameId: gameId,
      startingFen: startingPosition.fen,
      metadata: pgnGame.headers,
      mainline: mainline,
    );
  }

  static List<ChessMove> _parsePgnNodes(
    List<PgnNode> siblings,
    Position position,
  ) {
    final result = <ChessMove>[];
    var currentPosition = position;
    var currentSiblings = siblings;

    while (currentSiblings.isNotEmpty) {
      final mainlineNode = currentSiblings.first;
      if (mainlineNode is! PgnChildNode) break;

      final data = mainlineNode.data;
      final move = currentPosition.parseSan(data.san);
      if (move == null) break;

      final nextPosition = currentPosition.play(move);

      // Variations of THIS move are the other siblings
      final variations = <ChessLine>[];
      if (currentSiblings.length > 1) {
        for (final varNode in currentSiblings.skip(1)) {
          // Variations are parsed recursively as their own lines
          variations.add(_parsePgnNodes([varNode], currentPosition));
        }
      }

      String? clockTime;
      if (data.comments != null) {
        for (final comment in data.comments!) {
          final timeMatch = _timeRegex.firstMatch(comment);
          if (timeMatch != null) {
            clockTime = timeMatch.group(1);
            break;
          }
        }
      }

      result.add(
        ChessMove(
          num: currentPosition.fullmoves,
          fen: nextPosition.fen,
          san: data.san,
          uci: move.uci,
          turn:
              currentPosition.turn == Side.black
                  ? ChessColor.black
                  : ChessColor.white,
          clockTime: clockTime,
          comments: data.comments,
          nags: data.nags,
          variations: variations.isNotEmpty ? variations : null,
        ),
      );

      // Move to next position and next set of siblings (children of the current mainline node)
      currentPosition = nextPosition;
      currentSiblings = mainlineNode.children;
    }

    return result;
  }
}

enum ChessColor {
  black('black'),
  white('white');

  final String value;

  const ChessColor(this.value);

  factory ChessColor.fromJson(String value) {
    return ChessColor.values.firstWhere(
      (color) => color.value == value,
      orElse: () => throw ArgumentError('Invalid ChessColor value: $value'),
    );
  }

  String toJson() => value;
}

class ChessMove {
  final Number num;
  final String fen;
  final String san;
  final String uci;
  final ChessColor turn;
  final String? clockTime;
  final List<String>? comments;
  final List<int>? nags;
  final List<ChessLine>? variations;

  ChessMove({
    required this.num,
    required this.fen,
    required this.san,
    required this.uci,
    required this.turn,
    this.clockTime,
    this.comments,
    this.nags,
    this.variations,
  });

  factory ChessMove.fromJson(Map<String, dynamic> json) {
    return ChessMove(
      num: json['n'] as Number,
      fen: json['f'] as String,
      san: json['s'] as String,
      uci: json['u'] as String,
      turn: ChessColor.fromJson(json['t'] as String),
      clockTime: json['ct'] as String?,
      comments: (json['c'] as List?)?.cast<String>(),
      nags: (json['g'] as List?)?.cast<int>(),
      variations:
          json['v'] == null
              ? null
              : (json['v'] as List)
                  .map(
                    (variation) =>
                        (variation as List)
                            .map(
                              (move) => ChessMove.fromJson(
                                (move as Map).cast<String, dynamic>(),
                              ),
                            )
                            .toList(),
                  )
                  .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'n': num,
    'f': fen,
    's': san,
    'u': uci,
    't': turn.toJson(),
    'ct': clockTime,
    if (comments != null) 'c': comments,
    if (nags != null) 'g': nags,
    if (variations != null)
      'v':
          variations!
              .map(
                (variation) => variation.map((move) => move.toJson()).toList(),
              )
              .toList(),
  };

  ChessMove copyWith({
    Number? num,
    String? fen,
    String? san,
    String? uci,
    ChessColor? turn,
    String? clockTime,
    List<String>? comments,
    List<int>? nags,
    List<ChessLine>? variations,
    bool overrideVariations = false,
  }) {
    return ChessMove(
      num: num ?? this.num,
      fen: fen ?? this.fen,
      san: san ?? this.san,
      uci: uci ?? this.uci,
      turn: turn ?? this.turn,
      clockTime: clockTime ?? this.clockTime,
      comments: comments ?? this.comments,
      nags: nags ?? this.nags,
      variations: overrideVariations ? variations : this.variations,
    );
  }
}
