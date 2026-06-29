import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Verifies the fix for the For You → game card → chess board dropdown showing a
/// wrong/incomplete game list.
///
/// A For You card only carries the top-N preview games for its event, so before
/// the fix the board's game-switcher dropdown rendered that tiny subset. The fix
/// resolves the full event game list (cache-only) at navigation time. These
/// tests assert the resolved `(games, index)` handed to `ChessBoardScreenNew` —
/// which is exactly what the dropdown renders — is the FULL event list in the
/// Games-tab order, with the tapped game's index re-derived.
void main() {
  // Five games across three rounds. Games-tab order is round DESC, then board
  // ASC, so the canonical full order is:
  //   r3-b1, r2-b1, r2-b2, r1-b1, r1-b2
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

  ProviderContainer containerWithCache(List<Games> cached) {
    return ProviderContainer(
      overrides: [
        gamesLocalStorage.overrideWith(
          (ref) => _FakeGamesLocalStorage(ref, cached),
        ),
      ],
    );
  }

  test('pure transform: returns the FULL event list in Games-tab order', () {
    final resolved = sortForYouEventGames(fullEventRawGames());
    expect(
      resolved.map((g) => g.gameId).toList(),
      expectedFullOrder,
      reason: 'every event game must be present, in round/board order',
    );
  });

  test(
    'For You nav expands the preview subset to the full event list (dropdown source)',
    () async {
      final container = containerWithCache(fullEventRawGames());
      addTearDown(container.dispose);

      // The For You card only knew about 2 of the event's 5 games; the tapped
      // game is the first of that preview subset.
      final previewSubset = [modelFor('r3-b1'), modelFor('r2-b1')];

      final (games, index) = await container
          .read(gameCardWrapperProvider)
          .debugResolveForYouNavigation(
            orderedGames: previewSubset,
            gameIndex: 0,
          );

      expect(games.length, 5, reason: 'no longer the 2-game preview subset');
      expect(games.map((g) => g.gameId).toList(), expectedFullOrder);
      // Tapped game stays selected at its position in the full list.
      expect(index, 0);
      expect(games[index].gameId, 'r3-b1');
    },
  );

  test('re-derives the tapped index against the full list', () async {
    final container = containerWithCache(fullEventRawGames());
    addTearDown(container.dispose);

    // Tap the game that sorts LAST in the full event order.
    final previewSubset = [modelFor('r1-b2')];

    final (games, index) = await container
        .read(gameCardWrapperProvider)
        .debugResolveForYouNavigation(orderedGames: previewSubset, gameIndex: 0);

    expect(games.length, 5);
    expect(index, 4);
    expect(games[index].gameId, 'r1-b2');
  });

  test('cold cache falls back to the passed subset (no regression)', () async {
    final container = containerWithCache(const []); // nothing cached
    addTearDown(container.dispose);

    final previewSubset = [modelFor('r3-b1'), modelFor('r2-b1')];

    final (games, index) = await container
        .read(gameCardWrapperProvider)
        .debugResolveForYouNavigation(
          orderedGames: previewSubset,
          gameIndex: 1,
        );

    expect(games.map((g) => g.gameId).toList(), ['r3-b1', 'r2-b1']);
    expect(index, 1);
  });
}

class _FakeGamesLocalStorage extends GamesLocalStorage {
  _FakeGamesLocalStorage(super.ref, this._cached);

  final List<Games> _cached;

  @override
  Future<List<Games>> getCachedGames(String tourId) async => _cached;
}

Games _makeGame({
  required String id,
  required String roundSlug,
  required int boardNr,
}) {
  return Games(
    id: id,
    roundId: roundSlug,
    roundSlug: roundSlug,
    tourId: 'tour-1',
    tourSlug: 'tour-1',
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
