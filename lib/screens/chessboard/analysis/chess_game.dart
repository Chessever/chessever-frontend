import 'package:dartchess/dartchess.dart';
import 'package:chessever2/utils/pgn_clock_utils.dart';

typedef Number = int;

typedef ChessLine = List<ChessMove>;

final RegExp _evalRegex = RegExp(r'\[%eval ([^\]]+)\]');

class ChessGame {
  static const String metadataIsLiveKey = 'isLiveGame';
  static const String metadataAllowMainlineExtensionKey =
      'allowMainlineExtension';

  final String gameId;
  final String startingFen;
  final Map<String, dynamic> metadata;
  final ChessLine mainline;

  /// Remember explicit clearing in saved games so cached reports stay opt-in.
  final bool analysisCleared;
  final ChessAnalysisBackup? analysisBackup;

  ChessGame({
    required this.gameId,
    required this.startingFen,
    required this.metadata,
    required this.mainline,
    this.analysisCleared = false,
    this.analysisBackup,
  });

  factory ChessGame.fromJson(Map<String, dynamic> json) {
    return ChessGame(
      gameId: json['id'] as String,
      startingFen: json['sf'] as String,
      metadata: (json['md'] as Map).cast<String, dynamic>(),
      analysisCleared: json['analysisCleared'] == true,
      analysisBackup:
          json['analysisBackup'] is Map
              ? ChessAnalysisBackup.fromJson(
                (json['analysisBackup'] as Map).cast<String, dynamic>(),
              )
              : null,
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
    if (analysisCleared) 'analysisCleared': true,
    if (analysisBackup != null) 'analysisBackup': analysisBackup!.toJson(),
  };

  ChessGame copyWith({
    String? gameId,
    String? startingFen,
    Map<String, dynamic>? metadata,
    ChessLine? mainline,
    bool? analysisCleared,
    ChessAnalysisBackup? analysisBackup,
    bool overrideAnalysisBackup = false,
  }) {
    return ChessGame(
      gameId: gameId ?? this.gameId,
      startingFen: startingFen ?? this.startingFen,
      metadata: metadata ?? this.metadata,
      mainline: mainline ?? this.mainline,
      analysisCleared: analysisCleared ?? this.analysisCleared,
      analysisBackup:
          overrideAnalysisBackup ? analysisBackup : this.analysisBackup,
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

  /// Keeps only the played mainline and game headers. Reconstructing moves
  /// also drops clock/eval fields, which PGN export would turn into comments.
  ChessGame withoutAnalysis({
    Map<String, String> variationComments = const {},
    Map<String, List<int>> moveNags = const {},
  }) => copyWith(
    analysisCleared: true,
    analysisBackup:
        (analysisCleared ? analysisBackup : null) ??
        ChessAnalysisBackup(
          game: copyWith(analysisCleared: false, overrideAnalysisBackup: true),
          variationComments: Map.of(variationComments),
          moveNags: {
            for (final entry in moveNags.entries)
              entry.key: List.of(entry.value),
          },
        ),
    overrideAnalysisBackup: true,
    mainline: [
      for (final move in mainline)
        ChessMove(
          num: move.num,
          fen: move.fen,
          san: move.san.replaceAll(RegExp(r'[!?]+$'), ''),
          uci: move.uci,
          turn: move.turn,
        ),
    ],
  );

  bool get allowMainlineExtension =>
      metadata[metadataAllowMainlineExtensionKey] == true;

  String? get timeControl => metadata['TimeControl'] as String?;

  factory ChessGame.fromPgn(String gameId, String pgn) {
    final pgnGame = PgnGame.parsePgn(pgn);
    final startingPosition = PgnGame.startingPosition(pgnGame.headers);

    final mainline = _parsePgnNodes(pgnGame.moves.children, startingPosition);

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
    if (siblings.isEmpty) return const [];

    final mainlineNode = siblings.first;
    if (mainlineNode is! PgnChildNode) return const [];

    return _parsePgnLineFromChild(mainlineNode, position);
  }

  static List<ChessMove> _parsePgnLineFromChild(
    PgnChildNode<PgnNodeData> node,
    Position position,
  ) {
    final data = node.data;
    final move = position.parseSan(data.san);
    if (move == null) return const [];

    final nextPosition = position.play(move);

    final variations = <ChessLine>[];
    if (node.children.length > 1) {
      for (final variationNode in node.children.skip(1)) {
        variations.add(_parsePgnLineFromChild(variationNode, nextPosition));
      }
    }

    String? clockTime;
    String? eval;
    if (data.comments != null) {
      for (final comment in data.comments!) {
        final parsedClock = extractPgnClockStringFromComment(comment);
        if (parsedClock != null) {
          clockTime = parsedClock;
        }
        final evalMatch = _evalRegex.firstMatch(comment);
        if (evalMatch != null) {
          eval = evalMatch.group(1);
        }
      }
    }

    final currentMove = ChessMove(
      num: position.fullmoves,
      fen: nextPosition.fen,
      san: data.san,
      uci: move.uci,
      turn: position.turn == Side.black ? ChessColor.black : ChessColor.white,
      clockTime: clockTime,
      eval: eval,
      comments: data.comments,
      nags: data.nags,
      variations: variations.isNotEmpty ? variations : null,
    );

    final line = <ChessMove>[currentMove];
    if (node.children.isNotEmpty) {
      line.addAll(_parsePgnLineFromChild(node.children.first, nextPosition));
    }

    return line;
  }
}

/// Retained only by an explicitly cleared game. Never emitted into PGN.
class ChessAnalysisBackup {
  const ChessAnalysisBackup({
    required this.game,
    this.variationComments = const {},
    this.moveNags = const {},
  });

  final ChessGame game;
  final Map<String, String> variationComments;
  final Map<String, List<int>> moveNags;

  factory ChessAnalysisBackup.fromJson(Map<String, dynamic> json) =>
      ChessAnalysisBackup(
        game: ChessGame.fromJson((json['game'] as Map).cast<String, dynamic>()),
        variationComments:
            (json['comments'] as Map? ?? {}).cast<String, String>(),
        moveNags: {
          for (final entry in (json['nags'] as Map? ?? {}).entries)
            entry.key as String: (entry.value as List).cast<int>(),
        },
      );

  Map<String, dynamic> toJson() => {
    'game': game.toJson(),
    'comments': variationComments,
    'nags': moveNags,
  };
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
  final String? eval;
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
    this.eval,
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
      eval: json['e'] as String?,
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
    'e': eval,
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
    String? eval,
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
      eval: eval ?? this.eval,
      comments: comments ?? this.comments,
      nags: nags ?? this.nags,
      variations: overrideVariations ? variations : this.variations,
    );
  }
}
