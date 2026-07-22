import 'dart:async';

import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart'
    show ChessboardView;
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Proves the open path is not gated on cold full-event fetch/materialize:
/// [debugBeginBoardNavigation] returns the immediate card list synchronously
/// while expand (including a hanging network fetch) runs separately. Also
/// proves that when expand does complete, the full event list is still
/// produced for the switcher.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      anonKey: 'placeholder-anon-key',
    );
  });

  List<Games> fullEventRawGames() => [
    _makeGame(id: 'r2-b1', roundSlug: 'round-2', boardNr: 1),
    _makeGame(id: 'r2-b2', roundSlug: 'round-2', boardNr: 2),
    _makeGame(id: 'r1-b1', roundSlug: 'round-1', boardNr: 1),
    _makeGame(id: 'r1-b2', roundSlug: 'round-1', boardNr: 2),
    _makeGame(id: 'r3-b1', roundSlug: 'round-3', boardNr: 1),
  ];

  const expectedFullOrder = ['r3-b1', 'r2-b1', 'r2-b2', 'r1-b1', 'r1-b2'];

  GamesTourModel modelFor(String id) =>
      GamesTourModel.fromGame(fullEventRawGames().firstWhere((g) => g.id == id));

  test(
    'beginBoardNavigation returns immediate subset without awaiting cold fetch',
    () async {
      final fetchStarted = Completer<void>();
      final releaseFetch = Completer<List<Games>>();

      final container = ProviderContainer(
        overrides: [
          gamesLocalStorage.overrideWith(
            (ref) => _HangingFetchGamesLocalStorage(
              ref,
              onFetchStarted: () {
                if (!fetchStarted.isCompleted) fetchStarted.complete();
              },
              fetchResult: releaseFetch.future,
            ),
          ),
          gameRepositoryProvider.overrideWithValue(_NoopGameRepository()),
        ],
      );
      addTearDown(container.dispose);

      final previewSubset = [modelFor('r3-b1'), modelFor('r2-b1')];

      // This must return without waiting for the hanging fetch.
      final launch = container
          .read(gameCardWrapperProvider)
          .debugBeginBoardNavigation(
            orderedGames: previewSubset,
            gameIndex: 1,
            viewSource: ChessboardView.forYou,
          );

      expect(
        launch.immediateGames.map((g) => g.gameId).toList(),
        ['r3-b1', 'r2-b1'],
        reason: 'push-critical path must open on the card list as-is',
      );
      expect(launch.immediateIndex, 1);
      expect(launch.immediateGames[launch.immediateIndex].gameId, 'r2-b1');

      // Expand work is already in flight (fetch started) but not completed.
      await fetchStarted.future.timeout(const Duration(seconds: 2));
      var expandedCompleted = false;
      unawaited(
        launch.expanded.then((_) {
          expandedCompleted = true;
        }),
      );
      // Yield a few event-loop turns; hanging fetch must keep expand pending.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(
        expandedCompleted,
        isFalse,
        reason: 'cold fetch must not complete expand before release',
      );

      // Release the network; expand must still produce the full event list.
      releaseFetch.complete(fullEventRawGames());
      final expanded = await launch.expanded.timeout(
        const Duration(seconds: 5),
      );

      expect(expanded.games.map((g) => g.gameId).toList(), expectedFullOrder);
      expect(expanded.index, 1);
      expect(expanded.games[expanded.index].gameId, 'r2-b1');
    },
  );

  test(
    'beginBoardNavigation expanded future still hydrates full event from cache',
    () async {
      final container = ProviderContainer(
        overrides: [
          gamesLocalStorage.overrideWith(
            (ref) => _CachedGamesLocalStorage(ref, fullEventRawGames()),
          ),
          gameRepositoryProvider.overrideWithValue(_NoopGameRepository()),
        ],
      );
      addTearDown(container.dispose);

      final previewSubset = [modelFor('r1-b2')];
      final launch = container
          .read(gameCardWrapperProvider)
          .debugBeginBoardNavigation(
            orderedGames: previewSubset,
            gameIndex: 0,
            viewSource: ChessboardView.forYou,
          );

      expect(launch.immediateGames.map((g) => g.gameId).toList(), ['r1-b2']);
      expect(launch.immediateIndex, 0);

      final expanded = await launch.expanded;
      expect(expanded.games.map((g) => g.gameId).toList(), expectedFullOrder);
      expect(expanded.index, 4);
      expect(expanded.games[expanded.index].gameId, 'r1-b2');
    },
  );

  test(
    'immediate open is not gated on selected-game getGameWithPGN',
    () async {
      final pgnStarted = Completer<void>();
      final releasePgn = Completer<Games>();

      final container = ProviderContainer(
        overrides: [
          // Already multi-round single-tour → expand is a passthrough; only
          // selected-game hydrate would block the old path.
          gamesLocalStorage.overrideWith(
            (ref) => _CachedGamesLocalStorage(ref, const []),
          ),
          gameRepositoryProvider.overrideWithValue(
            _HangingGameRepository(
              onRequest: () {
                if (!pgnStarted.isCompleted) pgnStarted.complete();
              },
              result: releasePgn.future,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final multiRound = [
        modelFor('r3-b1'),
        modelFor('r2-b1'),
        modelFor('r1-b1'),
      ];

      final launch = container
          .read(gameCardWrapperProvider)
          .debugBeginBoardNavigation(
            orderedGames: multiRound,
            gameIndex: 1,
            viewSource: ChessboardView.tour,
          );

      expect(launch.immediateGames.map((g) => g.gameId).toList(), [
        'r3-b1',
        'r2-b1',
        'r1-b1',
      ]);
      expect(launch.immediateIndex, 1);

      await pgnStarted.future.timeout(const Duration(seconds: 2));
      var done = false;
      unawaited(launch.expanded.then((_) => done = true));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);

      releasePgn.complete(
        _makeGame(id: 'r2-b1', roundSlug: 'round-2', boardNr: 1),
      );
      final expanded = await launch.expanded.timeout(
        const Duration(seconds: 5),
      );
      expect(expanded.index, 1);
      expect(expanded.games[expanded.index].gameId, 'r2-b1');
    },
  );
}

class _HangingFetchGamesLocalStorage extends GamesLocalStorage {
  _HangingFetchGamesLocalStorage(
    super.ref, {
    required this.onFetchStarted,
    required this.fetchResult,
  });

  final void Function() onFetchStarted;
  final Future<List<Games>> fetchResult;

  @override
  Future<List<Games>> getCachedGames(String tourId) async => const [];

  @override
  Future<List<Games>> fetchAndSaveGames(
    String tourId, {
    bool forceRefresh = false,
  }) {
    onFetchStarted();
    return fetchResult;
  }
}

class _CachedGamesLocalStorage extends GamesLocalStorage {
  _CachedGamesLocalStorage(super.ref, this._cached);

  final List<Games> _cached;

  @override
  Future<List<Games>> getCachedGames(String tourId) async => _cached;

  @override
  Future<List<Games>> fetchAndSaveGames(
    String tourId, {
    bool forceRefresh = false,
  }) async => _cached;
}

class _NoopGameRepository extends GameRepository {
  @override
  Future<Games> getGameWithPGN(String gameId) async {
    throw StateError('getGameWithPGN should not be required for expand-only');
  }
}

class _HangingGameRepository extends GameRepository {
  _HangingGameRepository({required this.onRequest, required this.result});

  final void Function() onRequest;
  final Future<Games> result;

  @override
  Future<Games> getGameWithPGN(String gameId) {
    onRequest();
    return result;
  }
}

Games _makeGame({
  required String id,
  required String roundSlug,
  required int boardNr,
  String tourId = 'tour-1',
}) {
  return Games(
    id: id,
    roundId: roundSlug,
    roundSlug: roundSlug,
    tourId: tourId,
    tourSlug: tourId,
    players: [
      _player(name: 'White $id'),
      _player(name: 'Black $id', fideId: 2),
    ],
    boardNr: boardNr,
    status: '*',
    lastMove: 'e2e4',
  );
}

Player _player({required String name, int fideId = 1}) {
  return Player(
    name: name,
    title: 'GM',
    rating: 2700,
    fideId: fideId,
    fed: 'USA',
    clock: 0,
    team: '',
  );
}
