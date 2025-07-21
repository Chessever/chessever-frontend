class Evals {
  final int? id;
  final int positionId;
  final int knodes;
  final int depth;
  final int? pvsCount;
  final List<dynamic> pvs;

  Evals({
    this.id,
    required this.positionId,
    required this.knodes,
    required this.depth,
    this.pvsCount,
    required this.pvs,
  });

  factory Evals.fromJson(Map<String, dynamic> json) => Evals(
    id: json['id'],
    positionId: json['position_id'],
    knodes: json['knodes'],
    depth: json['depth'],
    pvsCount: json['pvs_count'],
    pvs: json['pvs'] ?? [],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'position_id': positionId,
    'knodes': knodes,
    'depth': depth,
    'pvs_count': pvsCount,
    'pvs': pvs,
  };
}
