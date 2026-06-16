import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
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
  int updateTagCalls = 0;
  int likedViewCalls = 0;
  String? lastLikedViewTag;
  final List<List<String>> tagUpdates = <List<String>>[];

  @override
  Future<LibraryFolder> ensureLikedGamesFolder() async => _likedFolder;

  @override
  Future<List<SavedAnalysis>> getSavedAnalyses({
    String? folderId,
    bool? isFavorite,
  }) async {
    return List<SavedAnalysis>.from(_saved);
  }

  @override
  Future<SavedAnalysis> createSavedAnalysis(SavedAnalysis analysis) async {
    createCalls++;
    if (!createStarted.isCompleted) createStarted.complete();
    await allowCreate.future;

    final created = SavedAnalysis(
      id: 'created-$createCalls',
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
  Future<void> deleteSavedAnalysis(String analysisId) async {
    deleteCalls++;
    if (!deleteStarted.isCompleted) deleteStarted.complete();
    await allowDelete.future;
    _saved.removeWhere((item) => item.id == analysisId);
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
    String? tag,
  }) async {
    likedViewCalls++;
    lastLikedViewTag = tag;

    var rows = _saved.where((item) => item.folderId == folderId).toList();
    final selectedTag = tag?.trim();
    if (selectedTag != null && selectedTag.isNotEmpty) {
      rows = rows.where((item) => item.tags.contains(selectedTag)).toList();
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
      anonKey: 'placeholder-anon-key',
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

  test('tag writes are normalized and capped at three labels', () async {
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

    const expectedTags = ['Trap', 'Beautiful Mate', 'Blunder'];
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

    container.read(myLikesFilterProvider.notifier).selectTag('Beautiful Mate');

    final data = await container.read(myLikesViewProvider.future);

    expect(repository.likedViewCalls, 1);
    expect(repository.lastLikedViewTag, 'Beautiful Mate');
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
}

ProviderContainer _container(_FakeLibraryRepository repository) {
  return ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(_currentUser),
      libraryRepositoryProvider.overrideWithValue(repository),
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
      subscriptionProvider.overrideWith((ref) => _TestSubscriptionNotifier()),
    ],
  );
}

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
