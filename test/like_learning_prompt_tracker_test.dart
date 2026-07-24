import 'package:chessever2/screens/chessboard/utils/like_learning_prompt_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LikeLearningPromptTracker', () {
    test('prompts at 10, 20, 40, then every 40 completed games', () async {
      final tracker = LikeLearningPromptTracker(_MemoryStore());
      await tracker.initialize(userId: 'user-1', hasExistingLikes: false);

      final promptGames = <int>[];
      for (var game = 1; game <= 120; game++) {
        final shouldPrompt = await tracker.recordCompletedGame(
          userId: 'user-1',
          gameId: 'game-$game',
        );
        if (shouldPrompt) promptGames.add(game);
      }

      expect(promptGames, [10, 20, 40, 80, 120]);
    });

    test('a confirmed like restarts the next prompt at 40 games', () async {
      final tracker = LikeLearningPromptTracker(_MemoryStore());
      await tracker.initialize(userId: 'user-1', hasExistingLikes: false);

      for (var game = 1; game <= 20; game++) {
        await tracker.recordCompletedGame(
          userId: 'user-1',
          gameId: 'before-like-$game',
        );
      }
      await tracker.recordLike(userId: 'user-1');

      for (var game = 1; game < 40; game++) {
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
          gameId: 'after-like-40',
        ),
        isTrue,
      );
    });

    test('any later like restarts an active 40-game interval', () async {
      final tracker = LikeLearningPromptTracker(_MemoryStore());
      await tracker.initialize(userId: 'user-1', hasExistingLikes: true);

      for (var game = 1; game <= 25; game++) {
        await tracker.recordCompletedGame(
          userId: 'user-1',
          gameId: 'first-run-$game',
        );
      }
      await tracker.recordLike(userId: 'user-1');

      for (var game = 1; game < 40; game++) {
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
          gameId: 'second-run-40',
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

        for (var game = 1; game <= 9; game++) {
          expect(
            await tracker.recordCompletedGame(
              userId: 'user-1',
              gameId: 'game-$game',
            ),
            isFalse,
          );
        }
        expect(
          await tracker.recordCompletedGame(userId: 'user-1', gameId: 'game-9'),
          isFalse,
        );

        final restoredTracker = LikeLearningPromptTracker(store);
        expect(
          await restoredTracker.recordCompletedGame(
            userId: 'user-1',
            gameId: 'game-10',
          ),
          isTrue,
        );
      },
    );

    test(
      'existing liked games start directly on the 40-game cadence',
      () async {
        final tracker = LikeLearningPromptTracker(_MemoryStore());
        await tracker.initialize(userId: 'user-1', hasExistingLikes: true);

        for (var game = 1; game < 40; game++) {
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
            gameId: 'game-40',
          ),
          isTrue,
        );
      },
    );

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
        expect(progress.nextPromptAt, 40);
      },
    );
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
