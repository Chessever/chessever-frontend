import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart'
    show ChessboardView;
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Verifies the fix for the game card → chess board dropdown showing a
/// wrong/incomplete game list.
///
/// Many entry points (For You, smart events, brackets, single-round pins, …)
/// hand the board only a subset of one event's games, so the game-switcher /
/// round timeline would render just the tapped game's round. The resolver
/// expands any single-event subset to the FULL event at navigation time —
/// cache-first, then a one-off network fetch when the event was never cached
/// (e.g. reached only through For You, whose feed never warms the games cache).
/// These tests assert the resolved `(games, index)` handed to
/// `ChessBoardScreenNew` — exactly what the dropdown renders — is the full event
/// list in Games-tab order with the tapped game's index re-derived, and that
/// the safe guards (cross-event, multi-round, fetch failure) leave it alone.
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

  ProviderContainer containerWithCache(
    List<Games> cached, {
    List<Games> network = const [],
    bool failFetch = false,
  }) {
    return ProviderContainer(
      overrides: [
        gamesLocalStorage.overrideWith(
          (ref) => _FakeGamesLocalStorage(
            ref,
            cached,
            network: network,
            failFetch: failFetch,
          ),
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

  test('cold cache fetches the full event once, then expands', () async {
    // Nothing cached (the For You feed never warmed the games cache), but the
    // network has the full event.
    final container = containerWithCache(const [], network: fullEventRawGames());
    addTearDown(container.dispose);

    final previewSubset = [modelFor('r3-b1'), modelFor('r2-b1')];

    final (games, index) = await container
        .read(gameCardWrapperProvider)
        .debugResolveForYouNavigation(
          orderedGames: previewSubset,
          gameIndex: 1,
        );

    expect(games.map((g) => g.gameId).toList(), expectedFullOrder);
    expect(index, 1); // tapped 'r2-b1' re-derived in the full list
    expect(games[index].gameId, 'r2-b1');
  });

  test('cold cache + fetch failure falls back to the passed subset', () async {
    final container = containerWithCache(const [], failFetch: true);
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

  test(
    'any route: a single-round single-event subset expands to the full event',
    () async {
      final container = containerWithCache(fullEventRawGames());
      addTearDown(container.dispose);

      // A non-For-You entry (e.g. a smart event / pin) opening one round only.
      final oneRoundSubset = [modelFor('r1-b2')];

      final (games, index) = await container
          .read(gameCardWrapperProvider)
          .debugResolveNavigation(
            orderedGames: oneRoundSubset,
            gameIndex: 0,
            viewSource: ChessboardView.tour,
          );

      expect(games.map((g) => g.gameId).toList(), expectedFullOrder);
      expect(index, 4);
      expect(games[index].gameId, 'r1-b2');
    },
  );

  test('any route: a multi-round list is left untouched (no refetch)', () async {
    // Already covers 2 rounds → treated as the full/curated list; passthrough.
    final container = containerWithCache(const []); // would throw if it fetched
    addTearDown(container.dispose);

    final multiRound = [modelFor('r3-b1'), modelFor('r2-b1'), modelFor('r1-b1')];

    final (games, index) = await container
        .read(gameCardWrapperProvider)
        .debugResolveNavigation(
          orderedGames: multiRound,
          gameIndex: 1,
          viewSource: ChessboardView.tour,
        );

    expect(games.map((g) => g.gameId).toList(), [
      'r3-b1',
      'r2-b1',
      'r1-b1',
    ]);
    expect(index, 1);
  });

  test('cross-event list (multiple tours) is left untouched', () async {
    final container = containerWithCache(const []);
    addTearDown(container.dispose);

    // Player-profile / favorites style: games from two different events.
    final crossEvent = [
      GamesTourModel.fromGame(
        _makeGame(
          id: 'a1',
          roundSlug: 'round-1',
          boardNr: 1,
          tourId: 'tour-A',
        ),
      ),
      GamesTourModel.fromGame(
        _makeGame(
          id: 'b1',
          roundSlug: 'round-1',
          boardNr: 1,
          tourId: 'tour-B',
        ),
      ),
    ];

    final (games, index) = await container
        .read(gameCardWrapperProvider)
        .debugResolveNavigation(
          orderedGames: crossEvent,
          gameIndex: 0,
          viewSource: ChessboardView.playerProfile,
        );

    expect(games.map((g) => g.gameId).toList(), ['a1', 'b1']);
    expect(index, 0);
  });
}

class _FakeGamesLocalStorage extends GamesLocalStorage {
  _FakeGamesLocalStorage(
    super.ref,
    this._cached, {
    this.network = const [],
    this.failFetch = false,
  });

  final List<Games> _cached;
  final List<Games> network;
  final bool failFetch;

  @override
  Future<List<Games>> getCachedGames(String tourId) async => _cached;

  @override
  Future<List<Games>> fetchAndSaveGames(
    String tourId, {
    bool forceRefresh = false,
  }) async {
    if (failFetch) throw Exception('network down');
    return network;
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
