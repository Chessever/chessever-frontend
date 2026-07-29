import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Persisted cadence for the contextual "Did you like this game?" teaching.
///
/// New users are prompted after 10, 20, and 40 distinct completed games. After
/// that, prompts repeat every 40 games. Any confirmed like restarts the cadence
/// at 40 games.
class LikeLearningPromptProgress {
  const LikeLearningPromptProgress({
    required this.initialized,
    required this.hasEverLiked,
    required this.completedSinceLike,
    required this.nextPromptAt,
    required this.countedGameIds,
  });

  factory LikeLearningPromptProgress.initial() {
    return const LikeLearningPromptProgress(
      initialized: false,
      hasEverLiked: false,
      completedSinceLike: 0,
      nextPromptAt: 10,
      countedGameIds: <String>{},
    );
  }

  factory LikeLearningPromptProgress.fromJson(Map<String, Object?> json) {
    final rawIds = json['countedGameIds'];
    final ids =
        rawIds is List
            ? rawIds.whereType<String>().where((id) => id.isNotEmpty).toSet()
            : <String>{};
    final hasEverLiked = json['hasEverLiked'] == true;
    final nextPromptAt = json['nextPromptAt'];
    return LikeLearningPromptProgress(
      initialized: json['initialized'] == true,
      hasEverLiked: hasEverLiked,
      completedSinceLike:
          (json['completedSinceLike'] as num?)?.toInt().clamp(0, 1 << 30) ?? 0,
      nextPromptAt:
          nextPromptAt is num
              ? nextPromptAt.toInt().clamp(1, 1 << 30)
              : (hasEverLiked ? 40 : 10),
      countedGameIds: ids,
    );
  }

  final bool initialized;
  final bool hasEverLiked;
  final int completedSinceLike;
  final int nextPromptAt;
  final Set<String> countedGameIds;

  Map<String, Object?> toJson() => <String, Object?>{
    'initialized': initialized,
    'hasEverLiked': hasEverLiked,
    'completedSinceLike': completedSinceLike,
    'nextPromptAt': nextPromptAt,
    'countedGameIds': countedGameIds.toList(growable: false),
  };

  LikeLearningPromptProgress copyWith({
    bool? initialized,
    bool? hasEverLiked,
    int? completedSinceLike,
    int? nextPromptAt,
    Set<String>? countedGameIds,
  }) {
    return LikeLearningPromptProgress(
      initialized: initialized ?? this.initialized,
      hasEverLiked: hasEverLiked ?? this.hasEverLiked,
      completedSinceLike: completedSinceLike ?? this.completedSinceLike,
      nextPromptAt: nextPromptAt ?? this.nextPromptAt,
      countedGameIds: countedGameIds ?? this.countedGameIds,
    );
  }
}

abstract class LikeLearningPromptStore {
  Future<Map<String, Object?>?> read(String userId);

  Future<void> write(String userId, Map<String, Object?> value);
}

class AppDatabaseLikeLearningPromptStore implements LikeLearningPromptStore {
  AppDatabaseLikeLearningPromptStore(this._database);

  static const String _keyPrefix = 'like_learning_prompt_v1';
  final AppDatabase _database;

  String _key(String userId) => '$_keyPrefix:$userId';

  @override
  Future<Map<String, Object?>?> read(String userId) async {
    final value = await _database.getJson<Object>(_key(userId));
    if (value is! Map) return null;
    return value.map(
      (key, dynamic item) => MapEntry(key.toString(), item as Object?),
    );
  }

  @override
  Future<void> write(String userId, Map<String, Object?> value) {
    return _database.setJson(_key(userId), value);
  }
}

class LikeLearningPromptTracker {
  LikeLearningPromptTracker(this._store);

  final LikeLearningPromptStore _store;

  Future<LikeLearningPromptProgress> loadProgress({
    required String userId,
  }) async {
    final stored = await _store.read(userId);
    return stored == null
        ? LikeLearningPromptProgress.initial()
        : LikeLearningPromptProgress.fromJson(stored);
  }

  /// Seeds the cadence once for users who already had likes before this feature
  /// shipped. Repeated initialization never resets accumulated progress.
  Future<void> initialize({
    required String userId,
    required bool hasExistingLikes,
  }) async {
    final progress = await loadProgress(userId: userId);
    if (progress.initialized) return;

    await _store.write(
      userId,
      progress
          .copyWith(
            initialized: true,
            hasEverLiked: hasExistingLikes,
            nextPromptAt: hasExistingLikes ? 40 : 10,
          )
          .toJson(),
    );
  }

  /// Records one distinct eligible finished game. Returns true exactly when the
  /// UI should ask the contextual like question.
  Future<bool> recordCompletedGame({
    required String userId,
    required String gameId,
  }) async {
    if (gameId.isEmpty) return false;

    var progress = await loadProgress(userId: userId);
    if (!progress.initialized) {
      progress = progress.copyWith(initialized: true);
    }
    if (progress.countedGameIds.contains(gameId)) return false;

    final countedIds = Set<String>.from(progress.countedGameIds)..add(gameId);
    final completed = progress.completedSinceLike + 1;
    final shouldPrompt = completed >= progress.nextPromptAt;
    final nextPromptAt =
        shouldPrompt
            ? _nextPromptTarget(progress.nextPromptAt)
            : progress.nextPromptAt;

    progress = progress.copyWith(
      completedSinceLike: completed,
      nextPromptAt: nextPromptAt,
      countedGameIds: countedIds,
    );
    await _store.write(userId, progress.toJson());
    return shouldPrompt;
  }

  /// A confirmed new like restarts the inactivity counter. The lifetime set of
  /// counted games remains, so reopening an old game cannot advance the count.
  Future<void> recordLike({required String userId}) async {
    final progress = await loadProgress(userId: userId);
    await _store.write(
      userId,
      progress
          .copyWith(
            initialized: true,
            hasEverLiked: true,
            completedSinceLike: 0,
            nextPromptAt: 40,
          )
          .toJson(),
    );
  }

  int _nextPromptTarget(int currentTarget) {
    if (currentTarget < 20) return 20;
    if (currentTarget < 40) return 40;
    return currentTarget + 40;
  }
}

final likeLearningPromptTrackerProvider = Provider<LikeLearningPromptTracker>((
  ref,
) {
  return LikeLearningPromptTracker(
    AppDatabaseLikeLearningPromptStore(AppDatabase.instance),
  );
});
