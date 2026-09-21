import 'dart:collection';

import 'package:chessever2/screens/chessboard/utils/game_list_snapshot.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter_test/flutter_test.dart';

GamesTourModel _game(String id) => GamesTourModel(
  gameId: id,
  whitePlayer: _player,
  blackPlayer: _player,
  whiteTimeDisplay: '',
  blackTimeDisplay: '',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: GameStatus.ongoing,
  roundId: 'round',
  tourId: 'tour',
);

final _player = PlayerCard(
  name: 'Player',
  federation: '',
  title: '',
  rating: 2500,
  countryCode: '',
  team: null,
);

class _CountingGames extends ListBase<GamesTourModel> {
  _CountingGames(int count) : games = List.generate(count, (i) => _game('g$i'));
  final List<GamesTourModel> games;
  int reads = 0;
  @override
  int get length => games.length;
  @override
  GamesTourModel operator [](int index) {
    reads++;
    return games[index];
  }

  @override
  set length(int value) => throw UnsupportedError('test list');
  @override
  void operator []=(int index, GamesTourModel value) =>
      throw UnsupportedError('test list');
}

void main() {
  test('live updates do not scan or copy an 8,000-game navigation catalog', () {
    final games = _CountingGames(8000);
    final cache = BoardGameListCache();
    final catalog = _CountingGames(8000);
    final merged = cache.merge(games, catalog);
    expect(merged, hasLength(8000));
    games.reads = catalog.reads = 0;
    for (var tick = 0; tick < 100; tick++) {
      final current = cache.merge(games, catalog);
      final snapshot = GameListSnapshot(
        current,
        updates: {
          3999: _game('g3999'),
          4000: _game('g4000'),
          4001: _game('g4001'),
        },
      );
      expect(snapshot[4000].gameId, 'g4000');
      expect(snapshot[7999].gameId, 'g7999');
    }
    expect(games.reads, 0);
    expect(catalog.reads, 0);
  });

  test(
    'card snapshots only read requested rows and preserve previous updates',
    () {
      final games = _CountingGames(8000);
      final first = _game('g2').copyWith(whiteClockSeconds: 120);
      final second = first.copyWith(whiteClockSeconds: 119);
      final updates = {2: first};
      final oldSnapshot = GameListSnapshot(games, updates: updates);
      updates[2] = second;
      final newSnapshot = GameListSnapshot(games, updates: updates);
      expect(games.reads, 0);
      expect(oldSnapshot[2], same(first));
      expect(newSnapshot[2], same(second));
      expect(games.reads, 0);
      expect(newSnapshot[7999].gameId, 'g7999');
      expect(games.reads, 1);
      expect(() => oldSnapshot[2] = second, throwsUnsupportedError);
      expect(() => oldSnapshot.length = 0, throwsUnsupportedError);
      expect(() => oldSnapshot[-1], throwsRangeError);
      expect(() => oldSnapshot[8000], throwsRangeError);
    },
  );

  test(
    'catalog replacement refreshes data without widening or reordering navigation',
    () {
      final a = _game('a'), b = _game('b'), c = _game('c');
      final cache = BoardGameListCache();
      final originals = [b, a];
      final updatedA = a.copyWith(whiteClockSeconds: 30);
      final first = cache.merge(originals, [updatedA, c]);
      expect(first, [b, updatedA]);
      final updatedB = b.copyWith(gameStatus: GameStatus.draw);
      final second = cache.merge(originals, [updatedB, c]);
      expect(second, [updatedB, a]);
      expect(first, [b, updatedA]);
      expect(cache.merge([a], [updatedA, c]), [updatedA]);
    },
  );

  test('all team matchups reuse one event-wide navigation index', () {
    final games = _CountingGames(8000);
    final model = GamesScreenModel(gamesTourModels: games, pinnedGamedIs: []);
    final index = model.gameIndexById;
    expect(index['g7999'], 7999);
    games.reads = 0;
    for (var match = 0; match < 2000; match++) {
      expect(model.gameIndexById, same(index));
    }
    expect(games.reads, 0);
    expect(() => index['g0'] = 1, throwsUnsupportedError);
  });
}
