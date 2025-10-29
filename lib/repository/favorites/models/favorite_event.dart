import 'package:dart_mappable/dart_mappable.dart';

part 'favorite_event.mapper.dart';

@MappableClass()
class FavoriteEvent with FavoriteEventMappable {
  final String id;
  final String userId;
  final String eventId;
  final String eventName;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FavoriteEvent({
    required this.id,
    required this.userId,
    required this.eventId,
    required this.eventName,
    required this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create FavoriteEvent from Supabase response
  factory FavoriteEvent.fromSupabase(Map<String, dynamic> json) {
    return FavoriteEvent(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      eventId: json['event_id'] as String,
      eventName: json['event_name'] as String,
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
      'event_id': eventId,
      'event_name': eventName,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Convert to Supabase format for insert (without id, timestamps auto-generated)
  Map<String, dynamic> toSupabaseInsert() {
    return {
      'user_id': userId,
      'event_id': eventId,
      'event_name': eventName,
      'metadata': metadata,
    };
  }
}
