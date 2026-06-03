import 'package:dart_mappable/dart_mappable.dart';

part 'library_folder.mapper.dart';

@MappableClass()
class LibraryFolder with LibraryFolderMappable {
  static const nodeTypeFolder = 'folder';
  static const nodeTypeDatabase = 'database';

  final String id;
  final String userId;
  final String name;
  final String color;
  final String icon;
  final int orderIndex;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? shareToken;
  final String? ownerDisplayName;
  final String? parentId;
  final String nodeType;

  /// Client-side only — true when this folder was fetched via subscription.
  /// Not stored in DB; set by the provider layer.
  final bool isSubscribed;

  /// True for the special per-user "Liked Games" folder (auto-created for
  /// everyone, undeletable, unrenamable). Persisted as `is_liked_games`.
  final bool isLikedGames;

  const LibraryFolder({
    required this.id,
    required this.userId,
    required this.name,
    required this.color,
    required this.icon,
    required this.orderIndex,
    required this.createdAt,
    required this.updatedAt,
    this.shareToken,
    this.ownerDisplayName,
    this.parentId,
    this.nodeType = nodeTypeDatabase,
    this.isSubscribed = false,
    this.isLikedGames = false,
  });

  /// Convert Supabase JSON to LibraryFolder
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
      shareToken: json['share_token'] as String?,
      parentId: json['parent_id'] as String?,
      nodeType: json['node_type'] as String? ?? nodeTypeDatabase,
      isLikedGames: (json['is_liked_games'] as bool?) ?? false,
    );
  }

  /// Convert to Supabase format for insert (without id, timestamps auto-generated)
  Map<String, dynamic> toSupabaseInsert() {
    return {
      'user_id': userId,
      'name': name,
      'color': color,
      'icon': icon,
      'order_index': orderIndex,
      'parent_id': parentId,
      'node_type': nodeType,
    };
  }

  /// Convert to regular map for other uses
  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'color': color,
      'icon': icon,
      'order_index': orderIndex,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'parent_id': parentId,
      'node_type': nodeType,
    };
  }

  bool get isDatabase => nodeType == nodeTypeDatabase;
  bool get isFolder => nodeType == nodeTypeFolder;

  /// User-facing label. The special liked-games collection is branded
  /// "My Likes" everywhere, regardless of the stored row name (legacy rows
  /// were created as "Liked Games"). For all other folders this is just [name].
  String get displayName => isLikedGames ? 'My Likes' : name;
}
