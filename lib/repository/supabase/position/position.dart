class Position {
  final int id;
  final String fen;
  final DateTime createdAt;

  Position({required this.id, required this.fen, required this.createdAt});

  factory Position.fromJson(Map<String, dynamic> json) => Position(
    id: json['id'],
    fen: json['fen'],
    createdAt: DateTime.parse(json['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'fen': fen,
    'created_at': createdAt.toIso8601String(),
  };
}