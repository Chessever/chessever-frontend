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
  final int cp;   // centipawns (positive = white advantage)

  Pv({required this.moves, required this.cp});

  factory Pv.fromJson(Map<String, dynamic> json) {
    final moves = json['moves'] as String;

    int cp;
    if (json.containsKey('mate')) {
      // convert “mate in X” to a big centipawn score
      final mate = int.parse(json['mate'].toString());
      cp = mate.sign * 100_000;
    } else {
      // normal centipawn score
      cp = int.parse(json['cp'].toString());
    }

    return Pv(moves: moves, cp: cp);
  }

  Map<String, dynamic> toJson() =>
      {'moves': moves, if (cp.abs() != 100_000) 'cp': cp};
}