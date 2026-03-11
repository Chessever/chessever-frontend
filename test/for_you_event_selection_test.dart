import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper to create a minimal [Games] object for testing.
Games _makeGame({
  required String id,
  required String roundId,
  String roundSlug = 'round-1',
  String tourId = 'tour-1',
  String tourSlug = 'tour-slug',
  String? lastMove = 'e2e4',
  DateTime? lastMoveTime,
  DateTime? gameDay,
  DateTime? dateStart,
  String status = '*',
  int? boardNr,
  List<Player>? players,
}) {
  return Games(
    id: id,
    roundId: roundId,
    roundSlug: roundSlug,
    tourId: tourId,
    tourSlug: tourSlug,
    lastMove: lastMove,
    lastMoveTime: lastMoveTime,
    gameDay: gameDay,
    dateStart: dateStart,
    status: status,
    boardNr: boardNr,
    players: players ??
        [
          Player(
            name: 'White $id',
            title: 'GM',
            rating: 2700,
            fideId: 1,
            fed: 'USA',
            clock: 0,
            team: '',
          ),
          Player(
            name: 'Black $id',
            title: 'GM',
            rating: 2700,
            fideId: 2,
            fed: 'USA',
            clock: 0,
            team: '',
          ),
        ],
  );
}

void main() {
  group('selectForYouEventGames', () {
    test(
      'latest round has 4+ started games — returns exactly 4 from that round',
      () {
        final now = DateTime(2025, 6, 1, 12, 0);
        final games = List.generate(
          6,
          (i) => _makeGame(
            id: 'game-$i',
            roundId: 'round-5',
            roundSlug: 'round-5',
            lastMoveTime: now,
            boardNr: i + 1,
          ),
        );

        final result = selectForYouEventGames(
          allStartedGames: games,
          pinnedIds: [],
          formatStrings: ['9-round Swiss'],
        );

        expect(result.length, 4);
        expect(result.every((g) => g.roundId == 'round-5'), isTrue);
      },
    );

    test('latest round has 2 games — fills from older rounds', () {
      final now = DateTime(2025, 6, 1, 12, 0);
      final older = now.subtract(const Duration(hours: 2));

      final games = [
        // 2 games in latest round
        _makeGame(
          id: 'g1',
          roundId: 'r2',
          roundSlug: 'round-2',
          lastMoveTime: now,
          boardNr: 1,
        ),
        _makeGame(
          id: 'g2',
          roundId: 'r2',
          roundSlug: 'round-2',
          lastMoveTime: now,
          boardNr: 2,
        ),
        // 3 games in older round
        _makeGame(
          id: 'g3',
          roundId: 'r1',
          roundSlug: 'round-1',
          lastMoveTime: older,
          boardNr: 1,
        ),
        _makeGame(
          id: 'g4',
          roundId: 'r1',
          roundSlug: 'round-1',
          lastMoveTime: older,
          boardNr: 2,
        ),
        _makeGame(
          id: 'g5',
          roundId: 'r1',
          roundSlug: 'round-1',
          lastMoveTime: older,
          boardNr: 3,
        ),
      ];

      final result = selectForYouEventGames(
        allStartedGames: games,
        pinnedIds: [],
        formatStrings: ['9-round Swiss'],
      );

      expect(result.length, 4);
      // First 2 from latest round
      expect(result[0].roundId, 'r2');
      expect(result[1].roundId, 'r2');
      // Next 2 filled from older round
      expect(result[2].roundId, 'r1');
      expect(result[3].roundId, 'r1');
    });

    test('multi-tour event: games from different tours fill to 4', () {
      final now = DateTime(2025, 6, 1, 12, 0);

      final games = [
        // Tour A, round 3 (latest)
        _makeGame(
          id: 'a1',
          roundId: 'r3a',
          roundSlug: 'round-3',
          tourId: 'tour-a',
          lastMoveTime: now,
          boardNr: 1,
        ),
        _makeGame(
          id: 'a2',
          roundId: 'r3a',
          roundSlug: 'round-3',
          tourId: 'tour-a',
          lastMoveTime: now,
          boardNr: 2,
        ),
        // Tour B, round 2 (slightly older)
        _makeGame(
          id: 'b1',
          roundId: 'r2b',
          roundSlug: 'round-2',
          tourId: 'tour-b',
          lastMoveTime: now.subtract(const Duration(minutes: 30)),
          boardNr: 1,
        ),
        _makeGame(
          id: 'b2',
          roundId: 'r2b',
          roundSlug: 'round-2',
          tourId: 'tour-b',
          lastMoveTime: now.subtract(const Duration(minutes: 30)),
          boardNr: 2,
        ),
      ];

      final result = selectForYouEventGames(
        allStartedGames: games,
        pinnedIds: [],
        formatStrings: ['9-round Swiss', '6-round Swiss'],
      );

      expect(result.length, 4);
      // Primary round from tour A first
      expect(result.where((g) => g.tourId == 'tour-a').length, 2);
      // Filled from tour B
      expect(result.where((g) => g.tourId == 'tour-b').length, 2);
    });

    test('match format: returns latest 4 across entire match', () {
      final now = DateTime(2025, 6, 1, 12, 0);
      final matchPlayers = [
        Player(
          name: 'Carlsen',
          title: 'GM',
          rating: 2830,
          fideId: 1,
          fed: 'NOR',
          clock: 0,
          team: '',
        ),
        Player(
          name: 'Nepo',
          title: 'GM',
          rating: 2790,
          fideId: 2,
          fed: 'RUS',
          clock: 0,
          team: '',
        ),
      ];

      // 6 games across 6 different rounds (game-1 through game-6)
      final games = List.generate(
        6,
        (i) => _makeGame(
          id: 'match-$i',
          roundId: 'game-${i + 1}',
          roundSlug: 'game-${i + 1}',
          lastMoveTime: now.subtract(Duration(days: 5 - i)),
          players: matchPlayers,
          status: i < 5 ? '1/2-1/2' : '*',
        ),
      );

      final result = selectForYouEventGames(
        allStartedGames: games,
        pinnedIds: [],
        formatStrings: ['12-game Match'],
      );

      expect(result.length, 4);
      // Should not be restricted to a single round
      final roundIds = result.map((g) => g.roundId).toSet();
      expect(roundIds.length, greaterThan(1));
    });

    test('event with fewer than 4 started games returns only available', () {
      final now = DateTime(2025, 6, 1, 12, 0);

      // 0 games
      expect(
        selectForYouEventGames(
          allStartedGames: [],
          pinnedIds: [],
          formatStrings: [],
        ),
        isEmpty,
      );

      // 1 game
      final result1 = selectForYouEventGames(
        allStartedGames: [
          _makeGame(id: 'g1', roundId: 'r1', lastMoveTime: now),
        ],
        pinnedIds: [],
        formatStrings: ['Swiss'],
      );
      expect(result1.length, 1);

      // 3 games
      final result3 = selectForYouEventGames(
        allStartedGames: List.generate(
          3,
          (i) => _makeGame(
            id: 'g-$i',
            roundId: 'r1',
            roundSlug: 'round-1',
            lastMoveTime: now,
            boardNr: i,
          ),
        ),
        pinnedIds: [],
        formatStrings: ['Swiss'],
      );
      expect(result3.length, 3);
    });

    test('pinned game from non-primary round gets priority', () {
      final now = DateTime(2025, 6, 1, 12, 0);
      final older = now.subtract(const Duration(hours: 2));

      final games = [
        // 3 games in latest round
        _makeGame(
          id: 'new1',
          roundId: 'r2',
          roundSlug: 'round-2',
          lastMoveTime: now,
          boardNr: 1,
        ),
        _makeGame(
          id: 'new2',
          roundId: 'r2',
          roundSlug: 'round-2',
          lastMoveTime: now,
          boardNr: 2,
        ),
        _makeGame(
          id: 'new3',
          roundId: 'r2',
          roundSlug: 'round-2',
          lastMoveTime: now,
          boardNr: 3,
        ),
        // 2 games in older round, one is pinned
        _makeGame(
          id: 'old-pinned',
          roundId: 'r1',
          roundSlug: 'round-1',
          lastMoveTime: older,
          boardNr: 1,
        ),
        _makeGame(
          id: 'old2',
          roundId: 'r1',
          roundSlug: 'round-1',
          lastMoveTime: older,
          boardNr: 2,
        ),
      ];

      final result = selectForYouEventGames(
        allStartedGames: games,
        pinnedIds: ['old-pinned'],
        formatStrings: ['9-round Swiss'],
      );

      expect(result.length, 4);
      // Primary round (r2) contributes 3 games; the pinned game from r1 fills
      // the 4th slot. The pinned game should be present in the result.
      expect(result.any((g) => g.id == 'old-pinned'), isTrue);
    });
  });
}
