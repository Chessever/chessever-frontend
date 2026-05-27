import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/game_display_sort.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sortGamesForEventDisplay', () {
    test(
      'promotes pinned games while ordering pinned peers by board number',
      () {
        final games = [
          _game('board20', boardNr: 20),
          _game('board1', boardNr: 1),
          _game('board10', boardNr: 10),
          _game('board3', boardNr: 3),
        ];

        final sorted = sortGamesForEventDisplay(
          games,
          pinnedIds: ['board20', 'board10', 'board3'],
        );

        expect(sorted.map((game) => game.id), [
          'board3',
          'board10',
          'board20',
          'board1',
        ]);
      },
    );

    test('keeps non-pinned games in board order after pinned games', () {
      final games = [
        _game('board30', boardNr: 30),
        _game('board2', boardNr: 2),
        _game('board20', boardNr: 20),
        _game('board10', boardNr: 10),
      ];

      final sorted = sortGamesForEventDisplay(games, pinnedIds: ['board20']);

      expect(sorted.map((game) => game.id), [
        'board20',
        'board2',
        'board10',
        'board30',
      ]);
    });

    test('places missing board numbers after numbered games in each group', () {
      final games = [
        _game('pinnedMissing'),
        _game('unpinnedMissing'),
        _game('pinned10', boardNr: 10),
        _game('unpinned5', boardNr: 5),
      ];

      final sorted = sortGamesForEventDisplay(
        games,
        pinnedIds: ['pinnedMissing', 'pinned10'],
      );

      expect(sorted.map((game) => game.id), [
        'pinned10',
        'pinnedMissing',
        'unpinned5',
        'unpinnedMissing',
      ]);
    });
  });
}

Games _game(String id, {int? boardNr}) {
  return Games(
    id: id,
    roundId: 'round-3',
    roundSlug: 'round-3',
    tourId: 'tour',
    tourSlug: 'tour-slug',
    boardNr: boardNr,
    status: '*',
  );
}
