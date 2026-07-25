import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Trello #1005 — end-to-end wiring of the 40-move time bonus into the model
/// that every clock surface reads (game cards, For You, the board header).
///
/// The util itself is covered by `time_control_bonus_test.dart`; this pins that
/// `tours.info->>'tc'` actually reaches [GamesTourModel] and moves the numbers.
void main() {
  Player player(String name, {int clock = 0}) => Player(
    name: name,
    title: '',
    rating: 2500,
    fideId: 1,
    fed: 'GER',
    clock: clock,
    team: '',
  );

  /// Builds movetext with [plies] clocked moves. Each side burns 60s a move
  /// from 90 minutes, so after move 40 a side shows 50:00 — the pre-bonus
  /// reading a relay publishes.
  String buildPgn(int plies, {String? overrideLast, int? overrideLastPly}) {
    final buffer = StringBuffer();
    for (var ply = 0; ply < plies; ply++) {
      final moveNumber = (ply ~/ 2) + 1;
      final seconds = 5400 - (moveNumber * 60);
      final h = seconds ~/ 3600;
      final m = (seconds % 3600) ~/ 60;
      final s = seconds % 60;
      final clock =
          overrideLastPly == ply
              ? overrideLast!
              : '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      if (ply.isEven) buffer.write('$moveNumber. ');
      buffer.write('Nf3 { [%clk $clock] } ');
    }
    return buffer.toString();
  }

  Games game({
    required String? tc,
    required String pgn,
    required int lastClockWhite,
    required int lastClockBlack,
  }) {
    return Games(
      id: 'g1',
      roundId: 'r1',
      roundSlug: 'round-1',
      tourId: 't1',
      tourSlug: 'tour-1',
      players: [player('White'), player('Black')],
      lastMove: 'e2e4',
      status: '*',
      pgn: pgn,
      lastClockWhite: lastClockWhite,
      lastClockBlack: lastClockBlack,
      timeControl: 'standard',
      timeControlText: tc,
    );
  }

  test(
    '40-move event: both sides gain the bonus once they complete move 40',
    () {
      final model = GamesTourModel.fromGame(
        game(
          tc: '90 min / 40 moves + 30 min + 30 sec / move',
          pgn: buildPgn(80),
          lastClockWhite: 3000, // 50:00, the relay's pre-bonus reading
          lastClockBlack: 3000,
        ),
      );

      expect(model.whiteClockSeconds, 3000 + 1800);
      expect(model.blackClockSeconds, 3000 + 1800);
      // 4800s = 80 minutes; the model only switches to `NhMMm` past 99 minutes.
      expect(model.whiteTimeDisplay, '80:00');
      expect(model.blackTimeDisplay, '80:00');
    },
  );

  test('same event before move 40: clocks are left exactly as relayed', () {
    final model = GamesTourModel.fromGame(
      game(
        tc: '90 min / 40 moves + 30 min + 30 sec / move',
        pgn: buildPgn(78), // both sides have completed 39 moves
        lastClockWhite: 3060,
        lastClockBlack: 3060,
      ),
    );

    expect(model.whiteClockSeconds, 3060);
    expect(model.blackClockSeconds, 3060);
    expect(model.whiteTimeDisplay, '51:00');
  });

  test('White completes move 40 before Black — only White is credited', () {
    final model = GamesTourModel.fromGame(
      game(
        tc: '90 min / 40 moves + 30 min + 30 sec / move',
        pgn: buildPgn(79), // White has 40 moves, Black 39
        lastClockWhite: 3000,
        lastClockBlack: 3060,
      ),
    );

    expect(model.whiteClockSeconds, 3000 + 1800);
    expect(model.blackClockSeconds, 3060);
  });

  test('no bonus is invented for a single-period event', () {
    final model = GamesTourModel.fromGame(
      game(
        tc: '90 min + 30 sec / move',
        pgn: buildPgn(80),
        lastClockWhite: 3000,
        lastClockBlack: 3000,
      ),
    );

    expect(model.whiteClockSeconds, 3000);
    expect(model.blackClockSeconds, 3000);
  });

  test('a missing time control text leaves clocks untouched', () {
    final model = GamesTourModel.fromGame(
      game(
        tc: null,
        pgn: buildPgn(80),
        lastClockWhite: 3000,
        lastClockBlack: 3000,
      ),
    );

    expect(model.whiteClockSeconds, 3000);
  });

  test('once the relay credits the bonus itself, it is not added twice', () {
    // Ply 80 is White's move 41 and carries the jump the relay finally sent.
    final pgn = buildPgn(82, overrideLast: '1:19:00', overrideLastPly: 80);

    final model = GamesTourModel.fromGame(
      game(
        tc: '90 min / 40 moves + 30 min + 30 sec / move',
        pgn: pgn,
        lastClockWhite: 4740, // 1:19:00 — already includes the 30 minutes
        lastClockBlack: 2940,
      ),
    );

    expect(
      model.whiteClockSeconds,
      4740,
      reason: 'White was already credited by the source',
    );
    expect(
      model.blackClockSeconds,
      2940 + 1800,
      reason: 'Black is still uncredited',
    );
  });

  test('secondaryTimePeriod is exposed for the board and share paths', () {
    final model = GamesTourModel.fromGame(
      game(
        tc: '90 min / 40 moves + 15 min + 30 sec / move',
        pgn: buildPgn(10),
        lastClockWhite: 5000,
        lastClockBlack: 5000,
      ),
    );

    expect(model.timeControlText, '90 min / 40 moves + 15 min + 30 sec / move');
    expect(model.secondaryTimePeriod?.afterMoves, 40);
    expect(model.secondaryTimePeriod?.bonusSeconds, 900);
  });

  test('Games.fromJson lifts tc out of the tours embed', () {
    final parsed = Games.fromJson({
      'id': 'g1',
      'round_id': 'r1',
      'round_slug': 'round-1',
      'tour_id': 't1',
      'tour_slug': 'tour-1',
      'tours': {
        'avg_elo': 2600,
        'tc': '90 min / 40 moves + 30 min + 30 sec / move',
        'group_broadcasts': {'time_control': 'standard'},
      },
    });

    expect(
      parsed.timeControlText,
      '90 min / 40 moves + 30 min + 30 sec / move',
    );
    expect(parsed.avgElo, 2600);
    expect(parsed.timeControl, 'standard');
  });

  group('gameIdsNeedingSecondaryPeriodPgn', () {
    Games row({
      required String id,
      required String? tc,
      required String status,
      String? pgn,
    }) => Games(
      id: id,
      roundId: 'r1',
      roundSlug: 'round-1',
      tourId: 't1',
      tourSlug: 'tour-1',
      status: status,
      pgn: pgn,
      timeControlText: tc,
    );

    const bonusTc = '90 min / 40 moves + 30 min + 30 sec / move';

    test('picks only ongoing, pgn-less rows from 40-move events', () {
      final ids = gameIdsNeedingSecondaryPeriodPgn([
        row(id: 'wanted', tc: bonusTc, status: '*'),
        row(id: 'finished', tc: bonusTc, status: '1-0'),
        row(id: 'already-has-pgn', tc: bonusTc, status: '*', pgn: '1. e4'),
        row(
          id: 'no-secondary-period',
          tc: '90 min + 30 sec / move',
          status: '*',
        ),
        row(id: 'no-tc', tc: null, status: '*'),
      ]);

      expect(ids, ['wanted']);
    });

    test('an all-finished page costs no extra round trip', () {
      final ids = gameIdsNeedingSecondaryPeriodPgn([
        row(id: 'a', tc: bonusTc, status: '1-0'),
        row(id: 'b', tc: bonusTc, status: '0-1'),
      ]);

      expect(ids, isEmpty);
    });

    test('an empty page is handled', () {
      expect(gameIdsNeedingSecondaryPeriodPgn(const []), isEmpty);
    });
  });
}
