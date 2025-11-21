import 'package:dart_mappable/dart_mappable.dart';

part 'library_folder.mapper.dart';

@MappableClass()
class LibraryFolder with LibraryFolderMappable {
  final String id;
  final String userId;
  final String name;
  final String color;
  final String icon;
  final int orderIndex;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LibraryFolder({
    required this.id,
    required this.userId,
    required this.name,
    required this.color,
    required this.icon,
    required this.orderIndex,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create LibraryFolder from Supabase response
  factory LibraryFolder.fromSupabase(Map<String, dynamic> json) {
    return LibraryFolder(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      color: json['color'] as String? ?? '#0FB4E5',
      icon: json['icon'] as String? ?? 'folder',
      orderIndex: json['order_index'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert to Supabase format (for updates)
  Map<String, dynamic> toSupabase() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'color': color,
      'icon': icon,
      'order_index': orderIndex,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Convert to Supabase format for insert (without id, timestamps auto-generated)
  Map<String, dynamic> toSupabaseInsert() {
    return {
      'user_id': userId,
      'name': name,
      'color': color,
      'icon': icon,
      'order_index': orderIndex,
    };
  }

}
