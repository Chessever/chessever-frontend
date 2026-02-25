class CloudEval {
  final String fen;
  final int knodes;
  final int depth;
  final List<Pv> pvs;
  final int? requestedMultiPv;

  CloudEval({
    required this.fen,
    required this.knodes,
    required this.depth,
    required this.pvs,
    this.requestedMultiPv,
  });

  factory CloudEval.fromJson(Map<String, dynamic> json) {
    return CloudEval(
      fen: json['fen'] as String,
      knodes: json['knodes'] as int,
      depth: json['depth'] as int,
      pvs:
          (json['pvs'] as List)
              .map((e) => Pv.fromJson(e as Map<String, dynamic>))
              .toList(),
      requestedMultiPv: json['requestedMultiPv'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'fen': fen,
    'knodes': knodes,
    'depth': depth,
    'pvs': pvs.map((e) => e.toJson()).toList(),
    if (requestedMultiPv != null) 'requestedMultiPv': requestedMultiPv,
  };
}

class Pv {
  final String moves;
  final int cp; // centipawns (positive = white advantage)
  final bool isMate;
  final int? mate;
  final bool whitePerspective;

  Pv({
    required this.moves,
    required this.cp,
    this.isMate = false,
    this.mate,
    bool? whitePerspective,
  }) : whitePerspective = whitePerspective ?? true;

  factory Pv.fromJson(Map<String, dynamic> json) {
    // Lichess may return moves as an array (preferred) or as a space-separated string.
    final dynamic movesField = json['moves'];
    String moves;
    if (movesField is List) {
      // Convert array of UCI moves to a single space-separated string
      moves = movesField
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .join(' ');
    } else if (movesField is String) {
      moves = movesField;
    } else {
      moves = '';
    }

    int cp = 0;
    bool isMate = false;
    int? mate;

    final dynamic mateValue = json['mate'];
    if (mateValue != null) {
      final parsedMate = int.tryParse(mateValue.toString());
      if (parsedMate != null) {
        cp = parsedMate.sign * 100_000;
        isMate = true;
        mate = parsedMate;
      }
    }

    if (!isMate) {
      final dynamic cpValue = json['cp'];
      if (cpValue is int) {
        cp = cpValue;
      } else if (cpValue != null) {
        cp = int.tryParse(cpValue.toString()) ?? 0;
      }
    }

    final bool perspective = (json['whitePerspective'] as bool?) ?? true;

    return Pv(
      moves: moves,
      cp: cp,
      isMate: isMate,
      mate: mate,
      whitePerspective: perspective,
    );
  }

  Map<String, dynamic> toJson() => {
    'moves': moves,
    if (cp.abs() != 100_000) 'cp': cp,
    'isMate': isMate,
    'mate': mate,
    'whitePerspective': whitePerspective,
  };
}

int _countHalfMoves(String moves) {
  if (moves.isEmpty) return 0;
  final tokens =
      moves.trim().isEmpty
          ? const <String>[]
          : moves.trim().split(RegExp(r'\s+'));
  return tokens.length;
}

extension PvQuality on Pv {
  int get halfMoveCount => _countHalfMoves(moves);

  int get fullMoveCount => (halfMoveCount / 2).floor();

  bool hasMinFullMoves(int minFullMoves) => fullMoveCount >= minFullMoves;
}

extension CloudEvalQuality on CloudEval {
  bool meetsPersistenceThreshold({int minDepth = 20, int minFullMoves = 8}) {
    if (depth < minDepth) return false;
    if (pvs.isEmpty) return false;
    return pvs.first.hasMinFullMoves(minFullMoves);
  }
}
