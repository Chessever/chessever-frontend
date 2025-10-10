class CloudEval {
  final String fen;
  final int knodes;
  final int depth;
  final List<Pv> pvs;

  CloudEval({
    required this.fen,
    required this.knodes,
    required this.depth,
    required this.pvs,
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
    );
  }

  Map<String, dynamic> toJson() => {
    'fen': fen,
    'knodes': knodes,
    'depth': depth,
    'pvs': pvs.map((e) => e.toJson()).toList(),
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
    final moves = json['moves'] as String;

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
