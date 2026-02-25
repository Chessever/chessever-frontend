class GroupBroadcast {
  final String id;
  final DateTime createdAt;
  final String name;
  final List<String> search;
  final int? maxAvgElo;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final String? timeControl;

  GroupBroadcast({
    required this.id,
    required this.createdAt,
    required this.name,
    required this.search,
    this.maxAvgElo,
    this.dateStart,
    this.dateEnd,
    this.timeControl,
  });

  factory GroupBroadcast.fromJson(Map<String, dynamic> json) => GroupBroadcast(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    name: json['name'] as String,
    search: _parseStringList(json['search']),
    maxAvgElo: _parseInt(json['max_avg_elo']),
    dateStart:
        json['date_start'] == null
            ? null
            : DateTime.parse(json['date_start'] as String),
    dateEnd:
        json['date_end'] == null
            ? null
            : DateTime.parse(json['date_end'] as String),
    timeControl: json['time_control'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'created_at': createdAt.toIso8601String(),
    'name': name,
    'search': search,
    'max_avg_elo': maxAvgElo,
    'date_start': dateStart?.toIso8601String(),
    'date_end': dateEnd?.toIso8601String(),
    'time_control': timeControl,
  };

  @override
  String toString() =>
      'GroupBroadcast($id, $name, search:$search, elo:$maxAvgElo)';
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

List<String> _parseStringList(dynamic value) {
  if (value is List) {
    return value.map((item) => item.toString()).toList();
  }
  return <String>[];
}
