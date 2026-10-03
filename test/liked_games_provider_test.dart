import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/utils/like_learning_prompt_tracker.dart';
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeLibraryRepository extends LibraryRepository {
  _FakeLibraryRepository({List<SavedAnalysis> initial = const []})
    : _saved = List<SavedAnalysis>.from(initial);

  final List<SavedAnalysis> _saved;
  final Completer<void> createStarted = Completer<void>();
  final Completer<void> allowCreate = Completer<void>();
  final Completer<void> deleteStarted = Completer<void>();
  final Completer<void> allowDelete = Completer<void>();
  int createCalls = 0;
  int deleteCalls = 0;
  String? lastDeleteFolderId;
  int updateTagCalls = 0;
  int likedViewCalls = 0;
  int folderLookups = 0;
  int listReads = 0;

  /// The folder the lookup answers with; swapped to stand in for another
  /// account.
  LibraryFolder folder = _likedFolder;

  /// Holds the liked-list read until it completes.
  Future<void>? listGate;

  /// Thrown by the folder lookup, the liked-list read, the delete or the
  /// create while set.
  Object? folderError;
  Object? listError;
  Object? deleteError;
  Object? createError;
  List<String>? lastLikedViewTags;
  final List<List<String>> tagUpdates = <List<String>>[];

  @override
  Future<LibraryFolder> ensureLikedGamesFolder() async {
    folderLookups++;
    final error = folderError;
    if (error != null) throw error;
    return folder;
  }

  @override
  Future<List<SavedAnalysis>> getSavedAnalyses({
    String? folderId,
    bool? isFavorite,
  }) async {
    listReads++;
    // Read when asked, answered when the gate opens: a write that lands in
    // between is not in the answer, as with a real request.
    final rows = [
      for (final item in _saved)
        if (folderId == null || item.folderId == folderId) item,
    ];
    await listGate;
    final error = listError;
    if (error != null) throw error;
    return rows;
  }

  List<String> get savedIds => [for (final item in _saved) item.id];

  /// Rewrites the folder of the row itself, unseen by this session: a move
  /// made on another device.
  void moveToFolder(String analysisId, String folderId) {
    final index = _saved.indexWhere((item) => item.id == analysisId);
    _saved[index] = _saved[index].copyWith(folderId: folderId);
  }

  /// What "Move to database" and its Undo call.
  @override
  Future<void> moveAnalysisToFolder(String analysisId, String folderId) async {
    moveToFolder(analysisId, folderId);
    announceAnalysisMove(analysisId, folderId);
  }

  @override
  Future<SavedAnalysis> createSavedAnalysis(SavedAnalysis analysis) async {
    final call = ++createCalls;
    if (!createStarted.isCompleted) createStarted.complete();
    await allowCreate.future;
    final error = createError;
    if (error != null) throw error;

    final created = SavedAnalysis(
      id: 'created-$call',
      userId: analysis.userId,
      folderId: analysis.folderId,
      title: analysis.title,
      sourceGameId: analysis.sourceGameId,
      sourceTournamentId: analysis.sourceTournamentId,
      chessGame: analysis.chessGame,
      analysisState: analysis.analysisState,
      variationComments: analysis.variationComments,
      moveNags: analysis.moveNags,
      lastViewedPosition: analysis.lastViewedPosition,
      tags: analysis.tags,
      notes: analysis.notes,
      isFavorite: analysis.isFavorite,
      createdAt: analysis.createdAt,
      updatedAt: analysis.updatedAt,
    );
    _saved
      ..removeWhere((item) => item.sourceGameId == analysis.sourceGameId)
      ..insert(0, created);
    return created;
  }

  @override
  Future<void> deleteSavedAnalysis(
    String analysisId, {
    String? folderId,
  }) async {
    deleteCalls++;
    lastDeleteFolderId = folderId;
    if (!deleteStarted.isCompleted) deleteStarted.complete();
    await allowDelete.future;
    final error = deleteError;
    if (error != null) throw error;
    // Scoped the way the real delete is: a row outside [folderId] stays.
    _saved.removeWhere(
      (item) =>
          item.id == analysisId &&
          (folderId == null || item.folderId == folderId),
    );
  }

  @override
  Future<SavedAnalysis> updateSavedAnalysisTags({
    required String analysisId,
    required List<String> tags,
  }) async {
    updateTagCalls++;
    tagUpdates.add(List<String>.from(tags));

    final index = _saved.indexWhere((item) => item.id == analysisId);
    if (index == -1) {
      throw Exception('Saved analysis not found');
    }

    final updated = _saved[index].copyWith(
      tags: List<String>.from(tags),
      updatedAt: DateTime(2026, 1, 1, 0, updateTagCalls),
    );
    _saved[index] = updated;
    return updated;
  }

  @override
  Future<List<SavedAnalysis>> getLikedAnalysesForView({
    required String folderId,
    required GameFilter filter,
    String search = '',
    List<String> tags = const <String>[],
  }) async {
    likedViewCalls++;
    lastLikedViewTags = List<String>.from(tags);

    var rows = _saved.where((item) => item.folderId == folderId).toList();
    final selectedTags =
        tags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toSet();
    if (selectedTags.isNotEmpty) {
      rows =
          rows.where((item) => item.tags.any(selectedTags.contains)).toList();
    }
    return rows;
  }

  @override
  Future<int> getOwnedAnalysisCountInFolder(String folderId) async {
    return _saved.where((item) => item.folderId == folderId).length;
  }

  @override
  Future<Map<String, int>> getTagCountsInFolder({
    required String folderId,
    bool isSubscribed = false,
  }) async {
    final counts = <String, int>{};
    for (final item in _saved.where((item) => item.folderId == folderId)) {
      for (final tag in item.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    return counts;
  }
}

class _TestSubscriptionNotifier extends SubscriptionNotifier {
  _TestSubscriptionNotifier() : super() {
    state = SubscriptionState(isSubscribed: true);
  }

  // RevenueCat has no plugin under test, so its async init lands as "not
  // subscribed" mid-test. Hold the premium state this test set up.
  @override
  set state(SubscriptionState value) =>
      super.state = value.copyWith(isSubscribed: true, isLoading: false);
}

final _currentUser = AppUser(
  id: 'user-1',
  createdAt: DateTime(2026, 1, 1),
  isAnonymous: true,
);

final _likedFolder = LibraryFolder(
  id: 'liked-folder',
  userId: _currentUser.id,
  name: 'Liked Games',
  color: '#F43F5E',
  icon: 'heart',
  orderIndex: 0,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  isLikedGames: true,
);

const _pgn = '''
[Event "Test"]
[Site "?"]
[Date "2026.01.01"]
[Round "1"]
[White "White"]
[Black "Black"]
[Result "*"]

1. e4 e5 *
''';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder-publishable-key',
    );
  });

  test('rapid repeated likes create one liked game', () async {
    final repository = _FakeLibraryRepository();
    final container = _container(repository);
    addTearDown(container.dispose);

    await container.read(likedGamesProvider.future);
    final notifier = container.read(likedGamesProvider.notifier);
    final game = _game();

    final toggles = List.generate(6, (_) => notifier.toggle(game));
    await repository.createStarted.future;

    expect(repository.createCalls, 1);

    repository.allowCreate.complete();
    await Future.wait(toggles);

    expect(repository.createCalls, 1);
    expect(repository.deleteCalls, 0);
    expect(container.read(likedGamesProvider).valueOrNull, hasLength(1));
    expect(
      container.read(likedGamesProvider).valueOrNull!.single.sourceGameId,
      game.gameId,
    );
  });

  test('a confirmed new like resets the reminder cadence', () async {
    final repository = _FakeLibraryRepository();
    final promptTracker = LikeLearningPromptTracker(_MemoryLikePromptStore());
    await promptTracker.initialize(
      userId: _currentUser.id,
      hasExistingLikes: false,
    );
    for (var game = 1; game <= 12; game++) {
      await promptTracker.recordCompletedGame(
        userId: _currentUser.id,
        gameId: 'completed-$game',
      );
    }

    final container = _container(repository, promptTracker: promptTracker);
    addTearDown(container.dispose);
    await container.read(likedGamesProvider.future);

    final toggle = container.read(likedGamesProvider.notifier).toggle(_game());
    await repository.createStarted.future;
    repository.allowCreate.complete();
    expect(await toggle, isTrue);

    final progress = await promptTracker.loadProgress(userId: _currentUser.id);
    expect(progress.hasEverLiked, isTrue);
    expect(progress.completedSinceLike, 0);
    expect(progress.nextPromptAt, LikeLearningPromptTracker.promptInterval);
  });

  test('rapid repeated unlikes delete one liked game', () async {
    final game = _game();
    final repository = _FakeLibraryRepository(
      initial: [_savedAnalysis(game: game, id: 'saved-1')],
    );
    final container = _container(repository);
    addTearDown(container.dispose);

    await container.read(likedGamesProvider.future);
    final notifier = container.read(likedGamesProvider.notifier);

    final toggles = List.generate(6, (_) => notifier.toggle(game));
    await repository.deleteStarted.future;

    expect(repository.deleteCalls, 1);

    repository.allowDelete.complete();
    await Future.wait(toggles);

    expect(repository.createCalls, 0);
    expect(repository.deleteCalls, 1);
    expect(container.read(likedGamesProvider).valueOrNull, isEmpty);
  });

  test('tag selected during like creation lands on created row', () async {
    final repository = _FakeLibraryRepository();
    final container = _container(repository);
    addTearDown(container.dispose);

    await container.read(likedGamesProvider.future);
    final notifier = container.read(likedGamesProvider.notifier);
    final game = _game();

    final toggle = notifier.toggle(game);
    await repository.createStarted.future;

    final tagUpdate = notifier.setTagsForLikeId(game.likeId, const [
      'Sacrifice',
    ]);

    expect(container.read(likedGamesProvider).valueOrNull!.single.tags, const [
      'Sacrifice',
    ]);

    repository.allowCreate.complete();
    await toggle;
    expect(await tagUpdate, isTrue);

    expect(repository.updateTagCalls, 1);
    expect(repository.tagUpdates.single, const ['Sacrifice']);
    expect(container.read(likedGamesProvider).valueOrNull!.single.tags, const [
      'Sacrifice',
    ]);
  });

  test('tag chosen before the liked row exists still persists', () async {
    // Mirrors the real device flow: the post-like roulette tag is picked while
    // the like is still in flight, before its optimistic row lands in state.
    // Calling toggle() then setTagsForLikeId() in the same synchronous turn
    // reproduces that ordering — toggle has only run up to its first await, so
    // no row exists yet when the tag write begins.
    final repository = _FakeLibraryRepository();
    final container = _container(repository);
    addTearDown(container.dispose);

    await container.read(likedGamesProvider.future);
    final notifier = container.read(likedGamesProvider.notifier);
    final game = _game();

    final toggle = notifier.toggle(game);
    final tagUpdate = notifier.setTagsForLikeId(game.likeId, const [
      'Sacrifice',
    ]);

    // The selection is visible immediately via the pending overlay.
    expect(container.read(likedGameTagsProvider(game.likeId)), const [
      'Sacrifice',
    ]);

    repository.allowCreate.complete();
    await toggle;
    expect(await tagUpdate, isTrue);

    expect(repository.updateTagCalls, 1);
    expect(repository.tagUpdates.single, const ['Sacrifice']);
    expect(container.read(likedGamesProvider).valueOrNull!.single.tags, const [
      'Sacrifice',
    ]);
  });

  test('rapid tag changes persist in selection order and last wins', () async {
    final game = _game();
    final repository = _FakeLibraryRepository(
      initial: [_savedAnalysis(game: game, id: 'saved-1')],
    );
    final container = _container(repository);
    addTearDown(container.dispose);

    await container.read(likedGamesProvider.future);
    final notifier = container.read(likedGamesProvider.notifier);

    final first = notifier.setTagsForLikeId(game.likeId, const ['Trap']);
    final second = notifier.setTagsForLikeId(game.likeId, const ['Blunder']);

    expect(await first, isTrue);
    expect(await second, isTrue);

    expect(repository.tagUpdates, const [
      ['Trap'],
      ['Blunder'],
    ]);
    expect(container.read(likedGamesProvider).valueOrNull!.single.tags, const [
      'Blunder',
    ]);
  });

  test('tag writes are normalized without capping labels', () async {
    final game = _game();
    final repository = _FakeLibraryRepository(
      initial: [_savedAnalysis(game: game, id: 'saved-1')],
    );
    final container = _container(repository);
    addTearDown(container.dispose);

    await container.read(likedGamesProvider.future);
    final notifier = container.read(likedGamesProvider.notifier);

    final update = notifier.setTagsForLikeId(game.likeId, const [
      ' Trap ',
      'Beautiful Mate',
      'Trap',
      'Blunder',
      'Sacrifice',
    ]);

    const expectedTags = ['Trap', 'Beautiful Mate', 'Blunder', 'Sacrifice'];
    expect(container.read(likedGameTagsProvider(game.likeId)), expectedTags);
    expect(await update, isTrue);

    expect(repository.tagUpdates.single, expectedTags);
    expect(
      container.read(likedGamesProvider).valueOrNull!.single.tags,
      expectedTags,
    );
  });

  test('pending tag is visible before liked list finishes loading', () async {
    final game = _game();
    final repository = _FakeLibraryRepository(
      initial: [_savedAnalysis(game: game, id: 'saved-1')],
    );
    final container = _container(repository);
    addTearDown(container.dispose);

    final notifier = container.read(likedGamesProvider.notifier);
    final update = notifier.setTagsForLikeId(game.likeId, const [
      'Combination',
    ]);

    expect(container.read(likedGameTagsProvider(game.likeId)), const [
      'Combination',
    ]);

    await container.read(likedGamesProvider.future);
    expect(await update, isTrue);
    expect(container.read(likedGameTagsProvider(game.likeId)), const [
      'Combination',
    ]);
  });

  test('my likes tag filter is sent to repository query', () async {
    final repository = _FakeLibraryRepository(
      initial: [
        _savedAnalysis(
          game: _game(gameId: 'game-1', whiteName: 'Mate'),
          id: 'saved-1',
          tags: const ['Beautiful Mate'],
        ),
        _savedAnalysis(
          game: _game(gameId: 'game-2', whiteName: 'Trap'),
          id: 'saved-2',
          tags: const ['Trap'],
        ),
      ],
    );
    final container = _containerWithSubscription(repository);
    addTearDown(container.dispose);

    container.read(myLikesFilterProvider.notifier).toggleTag('Beautiful Mate');

    // The view is auto-dispose: hold a listener so it is not disposed while
    // its first load is still in flight.
    final view = container.listen(myLikesViewProvider, (_, __) {});
    addTearDown(view.close);
    final data = await container.read(myLikesViewProvider.future);

    expect(repository.likedViewCalls, 1);
    expect(repository.lastLikedViewTags, const ['Beautiful Mate']);
    expect(data.totalLiked, 2);
    expect(data.visibleCount, 1);
    expect(data.sections.single.value.single.analysis.tags, const [
      'Beautiful Mate',
    ]);

    // The SubscriptionNotifier constructor starts its real async initializer.
    // Let it settle while the fake notifier is still mounted so teardown does
    // not receive a late state write from RevenueCat's MissingPlugin path.
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  group('settled writes', () {
    test('the write revision moves when a write lands, not on the optimistic '
        'change', () async {
      final repository = _FakeLibraryRepository();
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(likedGamesProvider.future);
      final notifier = container.read(likedGamesProvider.notifier);
      final game = _game();
      int revision() => container.read(likedGamesWriteRevisionProvider);

      final like = notifier.toggle(game);
      await repository.createStarted.future;
      expect(container.read(likedGamesProvider).valueOrNull, hasLength(1));
      expect(revision(), 0, reason: 'the row is not on the server yet');
      repository.allowCreate.complete();
      expect(await like, isTrue);
      expect(revision(), 1);

      final tagged = notifier.setTagsForLikeId(game.likeId, const ['Trap']);
      expect(await tagged, isTrue);
      expect(revision(), 2);

      final unlike = notifier.toggle(game);
      await repository.deleteStarted.future;
      expect(container.read(likedGamesProvider).valueOrNull, isEmpty);
      expect(revision(), 2, reason: 'the row is still on the server');
      repository.allowDelete.complete();
      expect(await unlike, isFalse);
      expect(revision(), 3);
    });

    test('My Likes lists a like that was still saving when it '
        'opened', () async {
      final repository = _FakeLibraryRepository();
      final container = _containerWithSubscription(repository);
      addTearDown(container.dispose);

      await container.read(likedGamesProvider.future);
      final view = container.listen(myLikesViewProvider, (_, __) {});
      addTearDown(view.close);

      final like = container.read(likedGamesProvider.notifier).toggle(_game());
      await repository.createStarted.future;
      // Opened mid-save: the server has no row to list yet.
      final opened = await container.read(myLikesViewProvider.future);
      expect(opened.visibleCount, 0);

      repository.allowCreate.complete();
      expect(await like, isTrue);

      // No re-entry, no invalidate: the saved like brings the list up to date.
      final settled = await container.read(myLikesViewProvider.future);
      expect(settled.visibleCount, 1);
      expect(settled.totalLiked, 1);
      expect(repository.likedViewCalls, 2);

      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    test('a list read that was out while a like was saved does not drop '
        'it', () async {
      final repository = _FakeLibraryRepository();
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(likedGamesProvider.future);
      final notifier = container.read(likedGamesProvider.notifier);

      // The read is taken now, with no likes, and answered later.
      final gate = Completer<void>();
      repository.listGate = gate.future;
      final reload = notifier.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(repository.listReads, 2);

      repository.allowCreate.complete();
      expect(await notifier.toggle(_game()), isTrue);

      gate.complete();
      await reload;
      expect(repository.listReads, 3, reason: 'read again, after the like');
      expect(_ids(container.read(likedGamesProvider).requireValue), [
        'created-1',
      ]);
    });

    test('an unlike is not brought back by a list read that was out while '
        'it was deleted', () async {
      final game = _game();
      final repository = _FakeLibraryRepository(
        initial: [_savedAnalysis(game: game, id: 'saved-1')],
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(likedGamesProvider.future);
      final notifier = container.read(likedGamesProvider.notifier);

      final unlike = notifier.toggle(game);
      await repository.deleteStarted.future;
      // The delete has not landed, so a read still returns the row.
      await notifier.refresh();
      expect(_ids(container.read(likedGamesProvider).requireValue), [
        'saved-1',
      ]);

      repository.allowDelete.complete();
      expect(await unlike, isFalse);
      expect(container.read(likedGamesProvider).requireValue, isEmpty);
    });
  });

  group('a list that is not loaded', () {
    test('a tap before the list has loaded waits for it, and never '
        'unlikes', () async {
      final liked = _game(gameId: 'game-1');
      final repository = _FakeLibraryRepository(
        initial: [
          _savedAnalysis(game: liked, id: 'saved-1'),
          _savedAnalysis(
            game: _game(gameId: 'game-2'),
            id: 'saved-2',
          ),
        ],
      );
      final gate = Completer<void>();
      repository.listGate = gate.future;
      final container = _container(repository);
      addTearDown(container.dispose);
      final notifier = container.read(likedGamesProvider.notifier);

      // The game is liked, but the list that says so is still loading, so its
      // heart reads empty: the tap asks for a like. So does one on a game that
      // is not liked.
      final toggle = notifier.toggle(liked);
      final other = notifier.toggle(_game(gameId: 'game-3'));
      await Future<void>.delayed(Duration.zero);
      expect(repository.createCalls, 0, reason: 'not read as "not liked"');
      expect(repository.deleteCalls, 0);

      gate.complete();
      repository.allowCreate.complete();
      expect(await toggle, isTrue);
      expect(await other, isTrue);

      expect(repository.deleteCalls, 0, reason: 'a like is never taken away');
      expect(repository.createCalls, 1, reason: 'only the game not yet liked');
      expect(_ids(container.read(likedGamesProvider).requireValue), [
        'created-1',
        'saved-1',
        'saved-2',
      ]);
    });

    test('a tap on the list of the previous account is not acted '
        'on', () async {
      final game = _game();
      final repository = _FakeLibraryRepository(
        initial: [_savedAnalysis(game: game, id: 'saved-1')],
      );
      final user = StateProvider<AppUser?>((ref) => _currentUser);
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith((ref) => ref.watch(user)),
          libraryRepositoryProvider.overrideWithValue(repository),
          likeLearningPromptTrackerProvider.overrideWithValue(
            LikeLearningPromptTracker(_MemoryLikePromptStore()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(likedGamesProvider.future);
      final notifier = container.read(likedGamesProvider.notifier);

      // Another account signs in. Its list, with no likes, is still loading,
      // and the one held until then says this game is liked.
      final gate = Completer<void>();
      repository
        ..folder = _folderOf('user-2', id: 'liked-folder-2')
        ..listGate = gate.future;
      container.read(user.notifier).state = AppUser(
        id: 'user-2',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(notifier.isLiked(game.likeId), isTrue);

      // The tap asked to unlike it. It is not this account's like to remove,
      // and the tap must not turn into a like.
      final toggle = notifier.toggle(game);
      gate.complete();
      expect(await toggle, isFalse);
      expect(repository.createCalls, 0);
      expect(repository.deleteCalls, 0);
      expect(container.read(likedGamesProvider).requireValue, isEmpty);
    });

    test('a tap fails, and writes nothing, while the list cannot be '
        'read', () async {
      final liked = _game(gameId: 'game-1');
      final like = _savedAnalysis(game: liked, id: 'saved-1');
      final repository = _FakeLibraryRepository(
        initial: [
          like,
          _savedAnalysis(
            game: _game(gameId: 'game-2'),
            id: 'saved-2',
          ),
        ],
      )..listError = Exception('offline');
      final container = _container(repository);
      addTearDown(container.dispose);

      await expectLater(
        container.read(likedGamesProvider.future),
        throwsException,
      );
      final notifier = container.read(likedGamesProvider.notifier);

      await expectLater(notifier.toggle(liked), throwsException);
      expect(await notifier.removeAnalysis(like), isFalse);
      expect(repository.createCalls, 0);
      expect(repository.deleteCalls, 0);
      expect(
        container.read(likedGamesProvider).hasValue,
        isFalse,
        reason: 'never replaced by a one-game or an empty list',
      );

      // Back online: the same tap reloads the list first. It was made on a
      // heart that read empty, so it finds the like and leaves it alone.
      repository.listError = null;
      expect(await notifier.toggle(liked), isTrue);
      expect(repository.createCalls, 0);
      expect(repository.deleteCalls, 0);
      expect(_ids(container.read(likedGamesProvider).requireValue), [
        'saved-1',
        'saved-2',
      ]);

      // With the list loaded and the heart filled, the next tap is an unlike.
      repository.allowDelete.complete();
      expect(await notifier.toggle(liked), isFalse);
      expect(_ids(container.read(likedGamesProvider).requireValue), [
        'saved-2',
      ]);
    });

    test('a failed folder lookup is asked again, not kept for the whole '
        'run', () async {
      final game = _game();
      final repository = _FakeLibraryRepository()
        ..folderError = Exception('offline');
      final container = _container(repository);
      addTearDown(container.dispose);

      await expectLater(
        container.read(likedGamesProvider.future),
        throwsException,
      );
      final notifier = container.read(likedGamesProvider.notifier);
      expect(repository.folderLookups, 1);

      // Still offline: the like asks again, fails, and writes nothing.
      await expectLater(notifier.toggle(game), throwsException);
      expect(repository.folderLookups, 2);
      expect(repository.createCalls, 0);

      // Back online, the tap itself recovers the folder and the list, and a
      // tag chosen right behind it still waits for the like.
      repository.folderError = null;
      final like = notifier.toggle(game);
      final tagged = notifier.setTagsForLikeId(game.likeId, const ['Trap']);
      repository.allowCreate.complete();
      expect(await like, isTrue);
      expect(await tagged, isTrue);
      expect(repository.folderLookups, 3);
      expect(
        container.read(likedGamesProvider).requireValue.single.tags,
        const ['Trap'],
      );
    });

    test('a reload that fails keeps the list it had', () async {
      final repository = _FakeLibraryRepository(
        initial: [_savedAnalysis(game: _game(), id: 'saved-1')],
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(likedGamesProvider.future);

      repository.listError = Exception('offline');
      await container.read(likedGamesProvider.notifier).refresh();

      final state = container.read(likedGamesProvider);
      expect(state.hasError, isFalse);
      expect(_ids(state.requireValue), ['saved-1']);
    });

    test('a write that fails is taken back, even when the reload fails '
        'too', () async {
      final liked = _game(gameId: 'game-1');
      final like = _savedAnalysis(game: liked, id: 'saved-1');
      final repository = _FakeLibraryRepository(initial: [like]);
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(likedGamesProvider.future);
      final notifier = container.read(likedGamesProvider.notifier);

      // Offline: the writes fail, and so does the reload after each.
      repository
        ..listError = Exception('offline')
        ..createError = Exception('offline')
        ..deleteError = Exception('offline');
      repository.allowCreate.complete();
      repository.allowDelete.complete();

      // A like that was not saved does not stay in the list.
      expect(await notifier.toggle(_game(gameId: 'game-2')), isFalse);
      // An unlike and a remove that were not deleted do not leave it.
      expect(await notifier.toggle(liked), isTrue);
      expect(await notifier.removeAnalysis(like), isFalse);

      final state = container.read(likedGamesProvider);
      expect(state.hasError, isFalse);
      expect(_ids(state.requireValue), ['saved-1']);
    });

    test('two likes saved at once both stay in the list', () async {
      final repository = _FakeLibraryRepository();
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(likedGamesProvider.future);
      final notifier = container.read(likedGamesProvider.notifier);

      final first = notifier.toggle(_game(gameId: 'game-1'));
      final second = notifier.toggle(_game(gameId: 'game-2'));
      await repository.createStarted.future;
      await Future<void>.delayed(Duration.zero);

      List<String?> liked() => [
        for (final a in container.read(likedGamesProvider).requireValue)
          a.sourceGameId,
      ];
      // Each inserted into the list as it was after its own PGN resolve.
      expect(liked(), unorderedEquals(['game-1', 'game-2']));

      repository.allowCreate.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(liked(), unorderedEquals(['game-1', 'game-2']));
      expect(
        _ids(container.read(likedGamesProvider).requireValue),
        unorderedEquals(['created-1', 'created-2']),
      );
    });
  });

  group('account scoping', () {
    test('the liked folder is looked up again when the account '
        'changes', () async {
      final repository = _FakeLibraryRepository();
      final user = StateProvider<AppUser?>((ref) => _currentUser);
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith((ref) => ref.watch(user)),
          libraryRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      expect(
        (await container.read(likedGamesFolderProvider.future)).id,
        'liked-folder',
      );
      await container.read(likedGamesProvider.future);
      expect(repository.folderLookups, 1);
      expect(repository.listReads, 1);

      // A token refresh hands out a new user object for the same account.
      container.read(user.notifier).state = AppUser(
        id: _currentUser.id,
        createdAt: DateTime(2026, 1, 1),
        isAnonymous: true,
      );
      await container.read(likedGamesProvider.future);
      expect(repository.folderLookups, 1);
      expect(repository.listReads, 1);

      // The guest signs in: another account, another folder, another list.
      repository.folder = _folderOf('user-2', id: 'liked-folder-2');
      container.read(user.notifier).state = AppUser(
        id: 'user-2',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(
        (await container.read(likedGamesFolderProvider.future)).id,
        'liked-folder-2',
      );
      await container.read(likedGamesProvider.future);
      expect(repository.folderLookups, 2);
      expect(repository.listReads, 2);

      // The app-level user going missing is not a sign-out: the folder stays.
      container.read(user.notifier).state = null;
      expect(
        (await container.read(likedGamesFolderProvider.future)).id,
        'liked-folder-2',
      );
      expect(repository.folderLookups, 2);
    });

    test('a missing app-level user is not an account change', () async {
      final liked = _game(gameId: 'game-1');
      final repository = _FakeLibraryRepository(
        initial: [_savedAnalysis(game: liked, id: 'saved-1')],
      );
      final user = StateProvider<AppUser?>((ref) => _currentUser);
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith((ref) => ref.watch(user)),
          libraryRepositoryProvider.overrideWithValue(repository),
          likeLearningPromptTrackerProvider.overrideWithValue(
            LikeLearningPromptTracker(_MemoryLikePromptStore()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(likedGamesProvider.future);
      final notifier = container.read(likedGamesProvider.notifier);

      // A token refresh that failed offline, or a sign-in sheet that is open or
      // was backed out of: the app-level state has no user, the session lives.
      container.read(user.notifier).state = null;

      final state = container.read(likedGamesProvider);
      expect(state.isLoading, isFalse, reason: 'the list is not read again');
      expect(state.hasError, isFalse);
      expect(container.read(isGameLikedProvider(liked.likeId)), isTrue);
      expect(
        (await container.read(likedGamesFolderProvider.future)).id,
        'liked-folder',
      );
      expect(repository.folderLookups, 1);
      expect(repository.listReads, 1);

      // Likes and unlikes still go to the folder's own account.
      repository.allowCreate.complete();
      repository.allowDelete.complete();
      expect(await notifier.toggle(_game(gameId: 'game-2')), isTrue);
      expect(await notifier.toggle(liked), isFalse);
      final saved = container.read(likedGamesProvider).requireValue.single;
      expect(saved.id, 'created-1');
      expect(saved.userId, _currentUser.id);
      expect(saved.folderId, _likedFolder.id);

      // The same account comes back: nothing to look up, nothing to reload.
      container.read(user.notifier).state = AppUser(
        id: _currentUser.id,
        createdAt: DateTime(2026, 1, 1),
        isAnonymous: true,
      );
      await container.read(likedGamesProvider.future);
      expect(repository.folderLookups, 1);
      expect(repository.listReads, 1);
    });

    test("a like is never written into another account's folder", () async {
      final game = _game();
      final repository = _FakeLibraryRepository(
        initial: [_savedAnalysis(game: game, id: 'saved-1')],
      )..folder = _folderOf('someone-else');
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(likedGamesProvider.future);
      final notifier = container.read(likedGamesProvider.notifier);

      await expectLater(
        notifier.toggle(_game(gameId: 'game-2')),
        throwsException,
      );
      await expectLater(notifier.toggle(game), throwsException);
      expect(repository.createCalls, 0);
      expect(repository.deleteCalls, 0);

      // The stale folder is dropped, so the next read looks it up again.
      await container.read(likedGamesFolderProvider.future);
      expect(repository.folderLookups, greaterThan(1));
    });
  });

  group('a like moved to a database', () {
    test('is not deleted by the card it left behind', () async {
      final game = _game();
      final like = _savedAnalysis(game: game, id: 'saved-1');
      final repository = _FakeLibraryRepository(initial: [like]);
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(likedGamesProvider.future);
      final notifier = container.read(likedGamesProvider.notifier);

      // The liked row itself was re-filed where this session did not see it.
      repository.moveToFolder('saved-1', 'my-database');
      repository.allowDelete.complete();

      // The session list still holds the row, so a double-tap reads as an
      // unlike. It is scoped to the liked folder and leaves the database copy.
      expect(await notifier.toggle(game), isFalse);
      expect(repository.lastDeleteFolderId, _likedFolder.id);
      expect(repository.savedIds, ['saved-1']);

      // So is swipe-Remove on the card still on screen.
      repository.lastDeleteFolderId = null;
      expect(await notifier.removeAnalysis(like), isTrue);
      expect(repository.lastDeleteFolderId, _likedFolder.id);
      expect(repository.savedIds, ['saved-1']);
    });

    test('leaves the list on the move and returns to it on Undo, with no '
        'screen reporting back', () async {
      final game = _game();
      final repository = _FakeLibraryRepository(
        initial: [
          _savedAnalysis(game: game, id: 'saved-1'),
          _savedAnalysis(
            game: _game(gameId: 'game-2'),
            id: 'filed',
          ).copyWith(folderId: 'my-database'),
        ],
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(likedGamesProvider.future);
      final notifier = container.read(likedGamesProvider.notifier);
      int revision() => container.read(likedGamesWriteRevisionProvider);

      await repository.moveAnalysisToFolder('saved-1', 'my-database');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(likedGamesProvider).requireValue, isEmpty);
      expect(container.read(isGameLikedProvider(game.likeId)), isFalse);
      expect(revision(), 1, reason: 'My Likes reads the server again');
      expect(repository.listReads, 1, reason: 'nothing to fetch for a removal');

      // Undo runs after the sheet that offered it has closed: only the
      // repository hears of it.
      await repository.moveAnalysisToFolder('saved-1', _likedFolder.id);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(_ids(container.read(likedGamesProvider).requireValue), [
        'saved-1',
      ]);
      expect(revision(), 2);

      // It is a like again, so a tap unlikes it and does not save it twice.
      repository.allowDelete.complete();
      expect(await notifier.toggle(game), isFalse);
      expect(repository.createCalls, 0);

      expect(revision(), 3);

      // A move between two databases is none of this list's business.
      await repository.moveAnalysisToFolder('filed', 'other-database');
      await Future<void>.delayed(Duration.zero);
      expect(revision(), 3);
      expect(repository.listReads, 2, reason: 'the Undo only');
    });

    test('leaves the list and the view on refreshMyLikes', () async {
      final repository = _FakeLibraryRepository(
        initial: [_savedAnalysis(game: _game(), id: 'saved-1')],
      );
      final container = _containerWithSubscription(repository);
      addTearDown(container.dispose);
      await container.read(likedGamesProvider.future);
      final view = container.listen(myLikesViewProvider, (_, __) {});
      addTearDown(view.close);
      final listed = await container.read(myLikesViewProvider.future);
      expect(listed.visibleCount, 1);

      repository.moveToFolder('saved-1', 'my-database');
      // What the My Likes menus pass as the move sheet's onMoved.
      refreshMyLikes(container);

      final after = await container.read(myLikesViewProvider.future);
      expect(after.visibleCount, 0);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(likedGamesProvider).requireValue, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  });
}

class _MemoryLikePromptStore implements LikeLearningPromptStore {
  final Map<String, Map<String, Object?>> _values = {};

  @override
  Future<Map<String, Object?>?> read(String userId) async {
    final value = _values[userId];
    return value == null ? null : Map<String, Object?>.from(value);
  }

  @override
  Future<void> write(String userId, Map<String, Object?> value) async {
    _values[userId] = Map<String, Object?>.from(value);
  }
}

ProviderContainer _container(
  _FakeLibraryRepository repository, {
  LikeLearningPromptTracker? promptTracker,
}) {
  final resolvedPromptTracker =
      promptTracker ?? LikeLearningPromptTracker(_MemoryLikePromptStore());
  return ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(_currentUser),
      libraryRepositoryProvider.overrideWithValue(repository),
      likeLearningPromptTrackerProvider.overrideWithValue(
        resolvedPromptTracker,
      ),
    ],
  );
}

ProviderContainer _containerWithSubscription(
  _FakeLibraryRepository repository,
) {
  return ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(_currentUser),
      libraryRepositoryProvider.overrideWithValue(repository),
      likeLearningPromptTrackerProvider.overrideWithValue(
        LikeLearningPromptTracker(_MemoryLikePromptStore()),
      ),
      subscriptionProvider.overrideWith((ref) => _TestSubscriptionNotifier()),
    ],
  );
}

List<String> _ids(Iterable<SavedAnalysis> analyses) => [
  for (final analysis in analyses) analysis.id,
];

LibraryFolder _folderOf(String userId, {String id = 'liked-folder'}) =>
    LibraryFolder(
      id: id,
      userId: userId,
      name: 'Liked Games',
      color: '#F43F5E',
      icon: 'heart',
      orderIndex: 0,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      isLikedGames: true,
    );

GamesTourModel _game({
  String gameId = 'game-1',
  String whiteName = 'White',
  String blackName = 'Black',
}) {
  final white = PlayerCard(
    name: whiteName,
    federation: 'USA',
    title: '',
    rating: 0,
    countryCode: 'USA',
    team: null,
  );
  final black = PlayerCard(
    name: blackName,
    federation: 'USA',
    title: '',
    rating: 0,
    countryCode: 'USA',
    team: null,
  );

  return GamesTourModel(
    gameId: gameId,
    source: GameSource.supabase,
    whitePlayer: white,
    blackPlayer: black,
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.ongoing,
    roundId: 'round-1',
    tourId: 'tour-1',
    pgn: _pgn,
  );
}

SavedAnalysis _savedAnalysis({
  required GamesTourModel game,
  required String id,
  List<String> tags = const [],
}) {
  final now = DateTime(2026, 1, 1);
  return SavedAnalysis(
    id: id,
    userId: _currentUser.id,
    folderId: _likedFolder.id,
    title: '${game.whitePlayer.name} vs ${game.blackPlayer.name}',
    sourceGameId: game.gameId,
    sourceTournamentId: game.tourId,
    chessGame: ChessGame.fromPgn(game.gameId, _pgn),
    analysisState: const {},
    variationComments: const {},
    lastViewedPosition: -1,
    tags: tags,
    notes: null,
    isFavorite: false,
    createdAt: now,
    updatedAt: now,
  );
}
