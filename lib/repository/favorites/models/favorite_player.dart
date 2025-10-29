import 'package:dart_mappable/dart_mappable.dart';

part 'favorite_player.mapper.dart';

@MappableClass()
class FavoritePlayer with FavoritePlayerMappable {
  final String id;
  final String userId;
  final String? fideId;
  final String playerName;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FavoritePlayer({
    required this.id,
    required this.userId,
    this.fideId,
    required this.playerName,
    required this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create FavoritePlayer from Supabase response
  factory FavoritePlayer.fromSupabase(Map<String, dynamic> json) {
    return FavoritePlayer(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      fideId: json['fide_id'] as String?,
      playerName: json['player_name'] as String,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert to Supabase format (for updates)
  Map<String, dynamic> toSupabase() {
    return {
      'id': id,
      'user_id': userId,
      'fide_id': fideId,
      'player_name': playerName,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Convert to Supabase format for insert (without id, timestamps auto-generated)
  Map<String, dynamic> toSupabaseInsert() {
    return {
      'user_id': userId,
      'fide_id': fideId,
      'player_name': playerName,
      'metadata': metadata,
    };
  }
}
