class Evals {
  final int? id;
  final int positionId;
  final int knodes;
  final int depth;
  final List<dynamic> pvs;
  final int? multiPv; // Number of principal variations

  Evals({
    this.id,
    required this.positionId,
    required this.knodes,
    required this.depth,
    required this.pvs,
    this.multiPv,
  });

  factory Evals.fromJson(Map<String, dynamic> json) => Evals(
    id: json['id'],
    positionId: json['position_id'],
    knodes: json['knodes'],
    depth: json['depth'],
    pvs: json['pvs'] ?? [],
    multiPv: json['multi_pv'],
  );

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'position_id': positionId,
    'knodes': knodes,
    'depth': depth,
    'pvs': pvs,
    if (multiPv != null) 'multi_pv': multiPv,
  };

  Evals copyWith({List<dynamic>? pvs, int? multiPv}) => Evals(
    id: id,
    positionId: positionId,
    knodes: knodes,
    depth: depth,
    pvs: pvs ?? this.pvs,
    multiPv: multiPv ?? this.multiPv,
  );
}
