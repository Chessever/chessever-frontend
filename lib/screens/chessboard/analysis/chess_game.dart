import 'package:dartchess/dartchess.dart';
import 'package:chessever2/utils/pgn_clock_utils.dart';

typedef Number = int;

typedef ChessLine = List<ChessMove>;

final RegExp _evalRegex = RegExp(r'\[%eval ([^\]]+)\]');

/// Whether [variation] replaces [host] itself rather than the move after it.
///
/// The model hangs every branch on a move. A branch whose first move leaves
/// the same side to move as [host] does is an alternative TO [host]; that is
/// the only form an alternative to a line's first move can take (a PGN's
/// `92... Rb2 (92... Kf6)` on a position start, or a reader's other first
/// move). Every other branch is an alternative to the move after [host].
/// Read from the FEN, never [ChessMove.turn], which PGN-parsed and
/// navigator-made moves fill differently.
bool isAlternativeToMove(ChessMove host, ChessLine variation) {
  if (variation.isEmpty) return false;
  final hostSide = _fenSideToMove(host.fen);
  return hostSide != null && hostSide == _fenSideToMove(variation.first.fen);
}

String? _fenSideToMove(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  return parts.length > 1 ? parts[1] : null;
}

class ChessGame {
  static const String metadataIsLiveKey = 'isLiveGame';
  static const String metadataAllowMainlineExtensionKey =
      'allowMainlineExtension';

  final String gameId;
  final String startingFen;
  final Map<String, dynamic> metadata;
  final ChessLine mainline;

  /// The PGN's game comment: text before the first move. A game shared from
  /// a position (a book's fragment starting at move 92) explains that
  /// position here. Same field and JSON key (`rc`) as the desktop app, so a
  /// saved game keeps it on both.
  final List<String> rootComments;

  /// Remember explicit clearing in saved games so cached reports stay opt-in.
  final bool analysisCleared;
  final ChessAnalysisBackup? analysisBackup;

  ChessGame({
    required this.gameId,
    required this.startingFen,
    required this.metadata,
    required this.mainline,
    this.rootComments = const [],
    this.analysisCleared = false,
    this.analysisBackup,
  });

  factory ChessGame.fromJson(Map<String, dynamic> json) {
    return ChessGame(
      gameId: json['id'] as String,
      startingFen: json['sf'] as String,
      metadata: (json['md'] as Map).cast<String, dynamic>(),
      rootComments: (json['rc'] as List?)?.cast<String>() ?? const [],
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
    )._restoreClassificationHeader();
  }

  Map<String, dynamic> toJson() => {
    'id': gameId,
    'sf': startingFen,
    'md': metadata,
    'm': mainline.map((move) => move.toJson()).toList(),
    if (rootComments.isNotEmpty) 'rc': rootComments,
    if (analysisCleared) 'analysisCleared': true,
    if (analysisBackup != null) 'analysisBackup': analysisBackup!.toJson(),
  };

  ChessGame copyWith({
    String? gameId,
    String? startingFen,
    Map<String, dynamic>? metadata,
    ChessLine? mainline,
    List<String>? rootComments,
    bool? analysisCleared,
    ChessAnalysisBackup? analysisBackup,
    bool overrideAnalysisBackup = false,
  }) {
    return ChessGame(
      gameId: gameId ?? this.gameId,
      startingFen: startingFen ?? this.startingFen,
      metadata: metadata ?? this.metadata,
      mainline: mainline ?? this.mainline,
      rootComments: rootComments ?? this.rootComments,
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
    rootComments: const [],
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

  /// Desktop's external-compatible PGN carries exact report classes in a
  /// private header because standard NAGs cannot distinguish all eight badges.
  /// Normalize both PGN imports and older saved JSON into native move NAGs, so
  /// every consumer (board, notation, report and export) sees the same verdict.
  ChessGame _restoreClassificationHeader() {
    final headerKeys = metadata.keys
        .where((key) => key.toLowerCase() == 'chesseverclassification')
        .toSet();
    if (headerKeys.isEmpty) return this;

    final codes = <String, int>{};
    final keyPattern = RegExp(r'^\d+(?:v\d+\.\d+)*$');
    final header = metadata[headerKeys.first]?.toString() ?? '';
    for (final part in header.split(RegExp(r'[\s,]+'))) {
      final pair = part.split('=');
      if (pair.length != 2 || !keyPattern.hasMatch(pair[0])) continue;
      final code = int.tryParse(pair[1]);
      if (code == null || !_isClassificationNag(code)) continue;
      codes.putIfAbsent(pair[0], () => code);
    }

    // Once restored, the native NAGs own the verdict. Keeping the carrier in
    // metadata would let a later clear/edit revive stale classes on reopen.
    return copyWith(
      metadata: {
        for (final entry in metadata.entries)
          if (!headerKeys.contains(entry.key)) entry.key: entry.value,
      },
      mainline: analysisCleared || codes.isEmpty
          ? mainline
          : _restoreClassificationLine(mainline, codes),
    );
  }

  static bool _isClassificationNag(int nag) => nag >= 240 && nag <= 247;

  static ChessLine _restoreClassificationLine(
    ChessLine line,
    Map<String, int> codes, {
    String prefix = '',
  }) => [
    for (var i = 0; i < line.length; i++)
      (() {
        final move = line[i];
        final code = codes['$prefix${i + 1}'];
        final nags = move.nags ?? const <int>[];
        return move.copyWith(
          nags: code != null && !nags.any(_isClassificationNag)
              ? [...nags, code]
              : move.nags,
          variations: () {
            // The header addresses a branch from the move it replaces and
            // numbers the branches of that move. A branch that replaces this
            // move itself (an alternative to a line's first move) is
            // numbered among those, the rest among the next move's.
            final variations = move.variations ?? const <ChessLine>[];
            var alternativesToThis = 0;
            var alternativesToNext = 0;
            return [
              for (final variation in variations)
                isAlternativeToMove(move, variation)
                    ? _restoreClassificationLine(
                        variation,
                        codes,
                        prefix: '$prefix${i + 1}v${++alternativesToThis}.',
                      )
                    : _restoreClassificationLine(
                        variation,
                        codes,
                        // The model hangs an alternative on the preceding
                        // move; the header addresses it from the move it
                        // replaces.
                        prefix: '$prefix${i + 2}v${++alternativesToNext}.',
                      ),
            ];
          }(),
          overrideVariations: move.variations != null,
        );
      })(),
  ];

  factory ChessGame.fromPgn(String gameId, String pgn) {
    final pgnGame = PgnGame.parsePgn(pgn);
    final startingPosition = PgnGame.startingPosition(pgnGame.headers);

    final mainline = _parsePgnNodes(pgnGame.moves.children, startingPosition);

    return ChessGame(
      gameId: gameId,
      startingFen: startingPosition.fen,
      metadata: pgnGame.headers,
      mainline: mainline,
      rootComments: List<String>.unmodifiable(pgnGame.comments),
    )._restoreClassificationHeader();
  }

  static List<ChessMove> _parsePgnNodes(
    List<PgnNode> siblings,
    Position position,
  ) {
    if (siblings.isEmpty) return const [];

    final mainlineNode = siblings.first;
    if (mainlineNode is! PgnChildNode) return const [];

    final mainline = _parsePgnLineFromChild(mainlineNode, position);
    if (mainline.isEmpty || siblings.length < 2) return mainline;

    // Alternatives to the first move (`92... Rb2 (92... Kf6 93. Rd7)`) are
    // siblings of it in the PGN tree. The model hangs them on the first move
    // itself, where [isAlternativeToMove] tells them from the branches that
    // replace the second move, as the navigator does for a reader's own
    // other first move.
    final alternatives = <ChessLine>[
      for (final sibling in siblings.skip(1))
        if (sibling is PgnChildNode<PgnNodeData>)
          _parsePgnLineFromChild(sibling, position),
    ].where((line) => line.isNotEmpty).toList();
    if (alternatives.isEmpty) return mainline;

    final first = mainline.first;
    return [
      first.copyWith(
        variations: [...?first.variations, ...alternatives],
        overrideVariations: true,
      ),
      ...mainline.skip(1),
    ];
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
      startingComments: data.startingComments,
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

  /// PGN comments written before the move: the lead-in of a variation
  /// (`( { Instead } 93. h5 ... )`). Same field and JSON key (`sc`) as the
  /// desktop app.
  final List<String>? startingComments;
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
    this.startingComments,
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
      startingComments: (json['sc'] as List?)?.cast<String>(),
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
    if (startingComments != null) 'sc': startingComments,
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
    List<String>? startingComments,
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
      startingComments: startingComments ?? this.startingComments,
      comments: comments ?? this.comments,
      nags: nags ?? this.nags,
      variations: overrideVariations ? variations : this.variations,
    );
  }
}
