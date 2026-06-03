import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
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
}

ProviderContainer _container(_FakeLibraryRepository repository) {
  return ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(_currentUser),
      libraryRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

GamesTourModel _game() {
  final white = PlayerCard(
    name: 'White',
    federation: 'USA',
    title: '',
    rating: 0,
    countryCode: 'USA',
    team: null,
  );
  final black = PlayerCard(
    name: 'Black',
    federation: 'USA',
    title: '',
    rating: 0,
    countryCode: 'USA',
    team: null,
  );

  return GamesTourModel(
    gameId: 'game-1',
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
    tags: const [],
    notes: null,
    isFavorite: false,
    createdAt: now,
    updatedAt: now,
  );
}
