enum FavoriteType { event, player, tournamentPlayer }

class UnifiedFavoriteModel {
  final String id;
  final FavoriteType type;
  final String name;
  final String? subtitle;
  final String? imageUrl;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const UnifiedFavoriteModel({
    required this.id,
    required this.type,
    required this.name,
    this.subtitle,
    this.imageUrl,
    required this.metadata,
    required this.createdAt,
  });

  factory UnifiedFavoriteModel.fromEvent({
    required String eventId,
    required String eventName,
    required String? timeControl,
    required int? maxAvgElo,
    required String? dates,
  }) {
    return UnifiedFavoriteModel(
      id: eventId,
      type: FavoriteType.event,
      name: eventName,
      subtitle: timeControl,
      metadata: {
        'maxAvgElo': maxAvgElo,
        'dates': dates,
        'timeControl': timeControl,
      },
      createdAt: DateTime.now(),
    );
  }

  factory UnifiedFavoriteModel.fromPlayer({
    required String fideId,
    required String playerName,
    required String? countryCode,
    required int? rating,
    required String? title,
  }) {
    return UnifiedFavoriteModel(
      id: fideId,
      type: FavoriteType.player,
      name: playerName,
      subtitle: title != null && title.isNotEmpty ? title : null,
      metadata: {
        'countryCode': countryCode,
        'rating': rating,
        'title': title,
      },
      createdAt: DateTime.now(),
    );
  }

  factory UnifiedFavoriteModel.fromTournamentPlayer({
    required String playerName,
    required String? countryCode,
    required int score,
    required int scoreChange,
    required String? matchScore,
    required String? title,
  }) {
    return UnifiedFavoriteModel(
      id: 'tournament_$playerName',
      type: FavoriteType.tournamentPlayer,
      name: playerName,
      subtitle: title != null && title.isNotEmpty ? title : null,
      metadata: {
        'countryCode': countryCode,
        'score': score,
        'scoreChange': scoreChange,
        'matchScore': matchScore,
        'title': title,
      },
      createdAt: DateTime.now(),
    );
  }

  factory UnifiedFavoriteModel.fromJson(Map<String, dynamic> json) {
    return UnifiedFavoriteModel(
      id: json['id'] as String,
      type: FavoriteType.values[json['type'] as int],
      name: json['name'] as String,
      subtitle: json['subtitle'] as String?,
      imageUrl: json['imageUrl'] as String?,
      metadata: Map<String, dynamic>.from(json['metadata'] as Map),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.index,
      'name': name,
      'subtitle': subtitle,
      'imageUrl': imageUrl,
      'metadata': metadata,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UnifiedFavoriteModel &&
        other.id == id &&
        other.type == type;
  }

  @override
  int get hashCode => Object.hash(id, type);

  UnifiedFavoriteModel copyWith({
    String? id,
    FavoriteType? type,
    String? name,
    String? subtitle,
    String? imageUrl,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
  }) {
    return UnifiedFavoriteModel(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      subtitle: subtitle ?? this.subtitle,
      imageUrl: imageUrl ?? this.imageUrl,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}