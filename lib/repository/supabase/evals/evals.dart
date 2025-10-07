class Evals {
  final int? id;
  final int positionId;
  final int knodes;
  final int depth;
  final List<dynamic> pvs;

  Evals({
    this.id,
    required this.positionId,
    required this.knodes,
    required this.depth,
    required this.pvs,
  });

  factory Evals.fromJson(Map<String, dynamic> json) => Evals(
    id: json['id'],
    positionId: json['position_id'],
    knodes: json['knodes'],
    depth: json['depth'],
    pvs: json['pvs'] ?? [],
  );

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'position_id': positionId,
    'knodes': knodes,
    'depth': depth,
    'pvs': pvs,
    'pvs_count': pvs.length,
  };
}
