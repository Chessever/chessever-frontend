import 'package:supabase_flutter/supabase_flutter.dart';

class AppUser {
  final String id;
  final String? email; // Nullable for anonymous users
  final String? displayName;
  final String? avatarUrl;
  final DateTime createdAt;
  final bool isAnonymous;

  const AppUser({
    required this.id,
    this.email, // Now nullable
    this.displayName,
    this.avatarUrl,
    required this.createdAt,
    this.isAnonymous = false,
  });

  factory AppUser.fromSupabaseUser(User user) {
    final isAnonymous = user.isAnonymous;

    return AppUser(
      id: user.id,
      email: user.email, // No more null assertion
      displayName:
          user.userMetadata?['full_name'] ??
          user.userMetadata?['name'] ??
          user.email?.split('@').first ??
          (isAnonymous ? 'Anonymous User' : null),
      avatarUrl:
          user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'],
      createdAt: DateTime.parse(user.createdAt),
      isAnonymous: isAnonymous,
    );
  }

  AppUser copyWith({
    String? id,
    String? email,
    String? displayName,
    String? avatarUrl,
    DateTime? createdAt,
    bool? isAnonymous,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
      isAnonymous: isAnonymous ?? this.isAnonymous,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppUser && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
