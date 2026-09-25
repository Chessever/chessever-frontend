import 'package:supabase_flutter/supabase_flutter.dart';

/// `user_metadata` key holding the Lichess username linked on My Profile.
const String kLichessUsernameMetadataKey = 'lichess_username';

/// `user_metadata` key holding the Chess.com username linked on My Profile.
const String kChesscomUsernameMetadataKey = 'chesscom_username';

class AppUser {
  final String id;
  final String? email; // Nullable for anonymous users
  final String? displayName;
  final String? avatarUrl;
  final DateTime createdAt;
  final bool isAnonymous;

  /// Lichess username the user linked on My Profile, from auth
  /// `user_metadata`. Null when none is set.
  final String? lichessUsername;

  /// Chess.com username the user linked on My Profile, from auth
  /// `user_metadata`. Null when none is set.
  final String? chesscomUsername;

  const AppUser({
    required this.id,
    this.email, // Now nullable
    this.displayName,
    this.avatarUrl,
    required this.createdAt,
    this.isAnonymous = false,
    this.lichessUsername,
    this.chesscomUsername,
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
          (isAnonymous ? 'Guest' : null),
      avatarUrl:
          user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'],
      createdAt: DateTime.parse(user.createdAt),
      isAnonymous: isAnonymous,
      lichessUsername: metadataUsername(
        user.userMetadata,
        kLichessUsernameMetadataKey,
      ),
      chesscomUsername: metadataUsername(
        user.userMetadata,
        kChesscomUsernameMetadataKey,
      ),
    );
  }

  /// A linked-site username read from `user_metadata`: a trimmed, non-empty
  /// string, or null. Anything else under [key] (a number, a map, blank text
  /// from an older write) reads as "not set" rather than throwing.
  static String? metadataUsername(Map<String, dynamic>? metadata, String key) {
    final value = metadata?[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  AppUser copyWith({
    String? id,
    String? email,
    String? displayName,
    String? avatarUrl,
    DateTime? createdAt,
    bool? isAnonymous,
    String? lichessUsername,
    String? chesscomUsername,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      lichessUsername: lichessUsername ?? this.lichessUsername,
      chesscomUsername: chesscomUsername ?? this.chesscomUsername,
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
