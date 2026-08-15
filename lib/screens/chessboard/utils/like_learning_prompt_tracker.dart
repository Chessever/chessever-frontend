import 'dart:async';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Persisted cadence for the contextual "Did you like this game?" reminder.
///
/// Users are asked after [LikeLearningPromptTracker.promptInterval] distinct
/// completed games without a like, and again after each further run of that
/// many. Any confirmed like restarts the cadence, so the reminder only ever
/// reaches someone who has gone a long stretch without liking anything.
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
      nextPromptAt: LikeLearningPromptTracker.promptInterval,
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
    final completedSinceLike =
        (json['completedSinceLike'] as num?)?.toInt().clamp(0, 1 << 30) ?? 0;
    return LikeLearningPromptProgress(
      initialized: json['initialized'] == true,
      hasEverLiked: hasEverLiked,
      completedSinceLike: completedSinceLike,
      nextPromptAt:
          nextPromptAt is num
              // Installs persisted targets from older cadences (introductory
              // prompts at 10 and 20 games, later a 40-game interval). Fold
              // them onto the current schedule.
              ? LikeLearningPromptTracker.normalizePromptTarget(
                nextPromptAt.toInt(),
                completedSinceLike,
              )
              : LikeLearningPromptTracker.promptInterval,
      countedGameIds: LikeLearningPromptTracker.trimTrackedIds(ids),
    );
  }

  final bool initialized;
  final bool hasEverLiked;
  final int completedSinceLike;
  final int nextPromptAt;

  /// Recently counted games, oldest first. Insertion-ordered (Dart sets are
  /// `LinkedHashSet`) and bounded — see
  /// [LikeLearningPromptTracker.maxTrackedGameIds].
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

  /// Completed games without a like between two reminders.
  static const int promptInterval = 30;

  /// How many recently-seen game ids stay on the ledger.
  ///
  /// The ledger exists so re-opening a game you already finished cannot advance
  /// the counter twice. It is deliberately BOUNDED: the whole record is
  /// serialised to SQLite on every finished game, so an unbounded lifetime set
  /// would grow into a six-figure JSON blob that is re-read and re-written each
  /// time a user reaches the end of a game. 256 is several times the
  /// [promptInterval], which is all the protection the counter actually needs.
  static const int maxTrackedGameIds = 256;

  final LikeLearningPromptStore _store;

  /// Serialises read-modify-write cycles. Two boards can reach their end
  /// position in the same frame (swiping fast through finished games); without
  /// this, both would read the same counter and one increment would be lost.
  Future<void> _writeQueue = Future<void>.value();

  /// Users whose one-time seeding has already run in this process, so the
  /// common path costs no extra store read per finished game.
  final Set<String> _seededUserIds = <String>{};

  /// The next stop on the [promptInterval] grid strictly above
  /// [completedSinceLike] — 30, 60, 90, …
  static int scheduledTarget(int completedSinceLike) {
    return ((completedSinceLike ~/ promptInterval) + 1) * promptInterval;
  }

  /// Folds a target persisted under an older cadence onto the current one.
  ///
  /// Takes whichever of the two comes SOONER, so shortening the interval never
  /// makes a user who is already mid-run wait longer than they were promised:
  /// someone 39 games in on the old 40-game target is still asked at 40, while
  /// someone 45 games in on an old 80-game target is asked at 60 rather than
  /// stranded for another 35 games.
  static int normalizePromptTarget(int storedTarget, int completedSinceLike) {
    final scheduled = scheduledTarget(completedSinceLike);
    final target = storedTarget < scheduled ? storedTarget : scheduled;
    return target < promptInterval ? promptInterval : target;
  }

  /// Keeps only the [maxTrackedGameIds] most recent ids, preserving order.
  static Set<String> trimTrackedIds(Set<String> ids) {
    if (ids.length <= maxTrackedGameIds) return ids;
    return ids.skip(ids.length - maxTrackedGameIds).toSet();
  }

  Future<T> _serialised<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

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
  }) {
    if (_seededUserIds.contains(userId)) return Future<void>.value();
    return _serialised(() async {
      final progress = await loadProgress(userId: userId);
      _seededUserIds.add(userId);
      if (progress.initialized) return;

      await _store.write(
        userId,
        progress
            .copyWith(
              initialized: true,
              hasEverLiked: hasExistingLikes,
              nextPromptAt: promptInterval,
            )
            .toJson(),
      );
    });
  }

  /// Records one distinct eligible finished game. Returns true exactly when the
  /// UI should ask the contextual like question.
  Future<bool> recordCompletedGame({
    required String userId,
    required String gameId,
  }) {
    if (gameId.isEmpty) return Future<bool>.value(false);

    return _serialised(() async {
      var progress = await loadProgress(userId: userId);
      if (!progress.initialized) {
        progress = progress.copyWith(initialized: true);
      }
      if (progress.countedGameIds.contains(gameId)) return false;

      final countedIds = trimTrackedIds(
        Set<String>.from(progress.countedGameIds)..add(gameId),
      );
      final completed = progress.completedSinceLike + 1;
      final shouldPrompt = completed >= progress.nextPromptAt;
      // Re-align on the grid after firing, so a target inherited from an older
      // cadence does not carry its offset forward for the rest of the run.
      final nextPromptAt =
          shouldPrompt ? scheduledTarget(completed) : progress.nextPromptAt;

      progress = progress.copyWith(
        completedSinceLike: completed,
        nextPromptAt: nextPromptAt,
        countedGameIds: countedIds,
      );
      await _store.write(userId, progress.toJson());
      return shouldPrompt;
    });
  }

  /// A confirmed new like restarts the inactivity counter. The ledger of
  /// recently counted games survives, so re-opening one of them cannot advance
  /// the fresh count.
  Future<void> recordLike({required String userId}) {
    return _serialised(() async {
      final progress = await loadProgress(userId: userId);
      _seededUserIds.add(userId);
      await _store.write(
        userId,
        progress
            .copyWith(
              initialized: true,
              hasEverLiked: true,
              completedSinceLike: 0,
              nextPromptAt: promptInterval,
            )
            .toJson(),
      );
    });
  }
}

final likeLearningPromptTrackerProvider = Provider<LikeLearningPromptTracker>((
  ref,
) {
  return LikeLearningPromptTracker(
    AppDatabaseLikeLearningPromptStore(AppDatabase.instance),
  );
});
