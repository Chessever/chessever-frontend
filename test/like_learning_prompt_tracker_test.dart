import 'package:chessever2/screens/chessboard/utils/like_learning_prompt_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

const int _interval = LikeLearningPromptTracker.promptInterval;

void main() {
  group('LikeLearningPromptTracker', () {
    test('the reminder interval is 30 completed games', () {
      expect(_interval, 30);
    });

    test('prompts every $_interval completed games without a like', () async {
      final tracker = LikeLearningPromptTracker(_MemoryStore());
      await tracker.initialize(userId: 'user-1', hasExistingLikes: false);

      final promptGames = <int>[];
      for (var game = 1; game <= _interval * 3; game++) {
        final shouldPrompt = await tracker.recordCompletedGame(
          userId: 'user-1',
          gameId: 'game-$game',
        );
        if (shouldPrompt) promptGames.add(game);
      }

      expect(promptGames, [_interval, _interval * 2, _interval * 3]);
    });

    test('a confirmed like restarts the next prompt at $_interval games', () async {
      final tracker = LikeLearningPromptTracker(_MemoryStore());
      await tracker.initialize(userId: 'user-1', hasExistingLikes: false);

      for (var game = 1; game <= 20; game++) {
        await tracker.recordCompletedGame(
          userId: 'user-1',
          gameId: 'before-like-$game',
        );
      }
      await tracker.recordLike(userId: 'user-1');

      for (var game = 1; game < _interval; game++) {
        expect(
          await tracker.recordCompletedGame(
            userId: 'user-1',
            gameId: 'after-like-$game',
          ),
          isFalse,
        );
      }
      expect(
        await tracker.recordCompletedGame(
          userId: 'user-1',
          gameId: 'after-like-$_interval',
        ),
        isTrue,
      );
    });

    test('any later like restarts an active $_interval-game interval', () async {
      final tracker = LikeLearningPromptTracker(_MemoryStore());
      await tracker.initialize(userId: 'user-1', hasExistingLikes: true);

      for (var game = 1; game <= 25; game++) {
        await tracker.recordCompletedGame(
          userId: 'user-1',
          gameId: 'first-run-$game',
        );
      }
      await tracker.recordLike(userId: 'user-1');

      for (var game = 1; game < _interval; game++) {
        expect(
          await tracker.recordCompletedGame(
            userId: 'user-1',
            gameId: 'second-run-$game',
          ),
          isFalse,
        );
      }
      expect(
        await tracker.recordCompletedGame(
          userId: 'user-1',
          gameId: 'second-run-$_interval',
        ),
        isTrue,
      );
    });

    test(
      'counts each completed game only once across tracker instances',
      () async {
        final store = _MemoryStore();
        final tracker = LikeLearningPromptTracker(store);
        await tracker.initialize(userId: 'user-1', hasExistingLikes: false);

        for (var game = 1; game <= _interval - 1; game++) {
          expect(
            await tracker.recordCompletedGame(
              userId: 'user-1',
              gameId: 'game-$game',
            ),
            isFalse,
          );
        }
        // Re-opening a game already on the ledger must not advance the count.
        expect(
          await tracker.recordCompletedGame(
            userId: 'user-1',
            gameId: 'game-${_interval - 1}',
          ),
          isFalse,
        );

        final restoredTracker = LikeLearningPromptTracker(store);
        expect(
          await restoredTracker.recordCompletedGame(
            userId: 'user-1',
            gameId: 'game-$_interval',
          ),
          isTrue,
        );
      },
    );

    test(
      'existing liked games start directly on the $_interval-game cadence',
      () async {
        final tracker = LikeLearningPromptTracker(_MemoryStore());
        await tracker.initialize(userId: 'user-1', hasExistingLikes: true);

        for (var game = 1; game < _interval; game++) {
          expect(
            await tracker.recordCompletedGame(
              userId: 'user-1',
              gameId: 'game-$game',
            ),
            isFalse,
          );
        }
        expect(
          await tracker.recordCompletedGame(
            userId: 'user-1',
            gameId: 'game-$_interval',
          ),
          isTrue,
        );
      },
    );

    test(
      'migrates an old introductory target to the $_interval-game minimum',
      () async {
        final store = _MemoryStore();
        await store.write('user-1', <String, Object?>{
          'initialized': true,
          'hasEverLiked': false,
          'completedSinceLike': 12,
          'nextPromptAt': 20,
          'countedGameIds': List.generate(12, (index) => 'game-${index + 1}'),
        });
        final tracker = LikeLearningPromptTracker(store);

        for (var game = 13; game < _interval; game++) {
          expect(
            await tracker.recordCompletedGame(
              userId: 'user-1',
              gameId: 'game-$game',
            ),
            isFalse,
          );
        }
        expect(
          await tracker.recordCompletedGame(
            userId: 'user-1',
            gameId: 'game-$_interval',
          ),
          isTrue,
        );
      },
    );

    test('a persisted 40-game target still fires at 40, not 60', () async {
      final store = _MemoryStore();
      await store.write('user-1', <String, Object?>{
        'initialized': true,
        'hasEverLiked': false,
        'completedSinceLike': 38,
        'nextPromptAt': 40,
        'countedGameIds': List.generate(38, (index) => 'game-${index + 1}'),
      });
      final tracker = LikeLearningPromptTracker(store);

      expect(
        await tracker.recordCompletedGame(userId: 'user-1', gameId: 'game-39'),
        isFalse,
      );
      expect(
        await tracker.recordCompletedGame(userId: 'user-1', gameId: 'game-40'),
        isTrue,
      );
      // …and the run that follows re-aligns onto the 30-game grid.
      final progress = await tracker.loadProgress(userId: 'user-1');
      expect(progress.nextPromptAt, 60);
    });

    test('a persisted 80-game target is pulled forward to 60', () async {
      final store = _MemoryStore();
      await store.write('user-1', <String, Object?>{
        'initialized': true,
        'hasEverLiked': false,
        'completedSinceLike': 45,
        'nextPromptAt': 80,
        'countedGameIds': List.generate(45, (index) => 'game-${index + 1}'),
      });
      final tracker = LikeLearningPromptTracker(store);

      for (var game = 46; game < 60; game++) {
        expect(
          await tracker.recordCompletedGame(
            userId: 'user-1',
            gameId: 'game-$game',
          ),
          isFalse,
        );
      }
      expect(
        await tracker.recordCompletedGame(userId: 'user-1', gameId: 'game-60'),
        isTrue,
      );
    });

    test(
      'initialization is one-time and does not repeatedly reset progress',
      () async {
        final tracker = LikeLearningPromptTracker(_MemoryStore());
        await tracker.initialize(userId: 'user-1', hasExistingLikes: true);
        for (var game = 1; game <= 12; game++) {
          await tracker.recordCompletedGame(
            userId: 'user-1',
            gameId: 'game-$game',
          );
        }

        await tracker.initialize(userId: 'user-1', hasExistingLikes: true);
        final progress = await tracker.loadProgress(userId: 'user-1');

        expect(progress.completedSinceLike, 12);
        expect(progress.nextPromptAt, _interval);
      },
    );

    // The ledger is re-serialised to SQLite on every finished game. Left
    // unbounded it grows without limit for heavy users, so it keeps only a
    // recent window — several times the longest interval.
    test('the counted-game ledger stays bounded and keeps the newest ids', () async {
      final store = _MemoryStore();
      final tracker = LikeLearningPromptTracker(store);
      await tracker.initialize(userId: 'user-1', hasExistingLikes: true);

      const total = LikeLearningPromptTracker.maxTrackedGameIds + 60;
      for (var game = 1; game <= total; game++) {
        await tracker.recordCompletedGame(
          userId: 'user-1',
          gameId: 'game-$game',
        );
      }

      final progress = await tracker.loadProgress(userId: 'user-1');
      expect(
        progress.countedGameIds.length,
        LikeLearningPromptTracker.maxTrackedGameIds,
      );
      expect(progress.countedGameIds.contains('game-$total'), isTrue);
      expect(progress.countedGameIds.contains('game-1'), isFalse);
      // Trimming the ledger never rewrites the counter itself.
      expect(progress.completedSinceLike, total);
    });

    test('concurrent records never lose an increment', () async {
      final tracker = LikeLearningPromptTracker(_MemoryStore());
      await tracker.initialize(userId: 'user-1', hasExistingLikes: true);

      // Fired without awaiting between them — two boards can reach their end
      // position in the same frame while swiping through finished games.
      await Future.wait(
        List.generate(
          30,
          (i) => tracker.recordCompletedGame(
            userId: 'user-1',
            gameId: 'race-$i',
          ),
        ),
      );

      final progress = await tracker.loadProgress(userId: 'user-1');
      expect(progress.completedSinceLike, 30);
      expect(progress.countedGameIds.length, 30);
    });

    test('an empty game id is never counted', () async {
      final tracker = LikeLearningPromptTracker(_MemoryStore());
      await tracker.initialize(userId: 'user-1', hasExistingLikes: false);

      expect(
        await tracker.recordCompletedGame(userId: 'user-1', gameId: ''),
        isFalse,
      );
      final progress = await tracker.loadProgress(userId: 'user-1');
      expect(progress.completedSinceLike, 0);
    });
  });
}

class _MemoryStore implements LikeLearningPromptStore {
  final Map<String, Map<String, Object?>> _data = {};

  @override
  Future<Map<String, Object?>?> read(String userId) async {
    final value = _data[userId];
    return value == null ? null : Map<String, Object?>.from(value);
  }

  @override
  Future<void> write(String userId, Map<String, Object?> value) async {
    _data[userId] = Map<String, Object?>.from(value);
  }
}
