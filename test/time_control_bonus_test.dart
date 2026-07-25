import 'package:chessever2/utils/time_control_bonus.dart';
import 'package:flutter_test/flutter_test.dart';

/// Trello #1005 — "Our app misses 40 move time adding logic".
///
/// Broadcast relays credit the FIDE 40-move time bonus late: the `[%clk]` value
/// recorded on move 40 is the pre-bonus reading, and the jump only appears on
/// move 41 (sometimes move 43, when an arbiter adds it by hand). These tests
/// pin both the free-text parser and the double-credit guard.
void main() {
  group('parseSecondaryTimePeriod — real tours.info->>\'tc\' strings', () {
    void expectPeriod(String tc, int afterMoves, int bonusMinutes) {
      final parsed = parseSecondaryTimePeriod(tc);
      expect(
        parsed,
        TimeControlSecondaryPeriod(
          afterMoves: afterMoves,
          bonusSeconds: bonusMinutes * 60,
        ),
        reason: 'tc: "$tc"',
      );
    }

    test('canonical FIDE spellings', () {
      expectPeriod('90 min / 40 moves + 30 min + 30 sec / move', 40, 30);
      expectPeriod('90 min / 40 moves + 15 min + 30 sec / move', 40, 15);
      expectPeriod('90min / 40 moves + 30 min + 30 sec / move', 40, 30);
      expectPeriod('90min/40moves+30min/end+30sec increment per move', 40, 30);
      expectPeriod('90min/40moves + 30min/end + 30s/move', 40, 30);
      expectPeriod('Classical: 90min/40moves + 30min + 30sec/move', 40, 30);
      expectPeriod('100 min / 40 moves + 40 min + 30 sec / move', 40, 40);
      expectPeriod('60 min / 40 moves + 30 min + 30 sec / move', 40, 30);
      expectPeriod('75 min / 40 moves + 15 min + 30 sec / move', 40, 15);
      expectPeriod('120 min / 40 moves + 30 min', 40, 30);
    });

    test('prime notation (90\' / 40 moves + 30\' + 30\'\'/move)', () {
      expectPeriod("90' / 40 moves + 30' + 30'' / move", 40, 30);
      expectPeriod("90'/40 moves + 30' + 30'' per move", 40, 30);
      expectPeriod("100'/40 moves + 40' + 30'' bonus from 1st move", 40, 40);
    });

    test('increment stated before the move count', () {
      expectPeriod('90min + 30sec / 40move + 30min', 40, 30);
      expectPeriod('(100min + 30sec)/40 moves + (30min+30sec)', 40, 30);
      expectPeriod('90min/40moves + 30s/move + 30min/all', 40, 30);
    });

    test('bonus stated after the move count in prose', () {
      expectPeriod('90 min + 30 sec, +15 min after 40 moves', 40, 15);
      expectPeriod('90 min + 30 sec, +30 min after 40 moves', 40, 30);
      expectPeriod('90 min + 30 sec/m + 30 min after 40 moves', 40, 30);
      expectPeriod("90' + 30'' per move + 30 minutes after 40 moves", 40, 30);
      expectPeriod('90min/all + 30s/move +30min/40moves', 40, 30);
    });

    test('"N moves in T" puts the base period after the move count', () {
      expectPeriod(
        '40 moves in 2 hours f.b. 1 hour to complete the game',
        40,
        60,
      );
      expectPeriod(
        '40 moves in 90 min f.b. 30 minutes with 30 seconds added per move',
        40,
        30,
      );
    });

    test('non-40 move counts are read from the string, not assumed', () {
      expectPeriod('105 min / 35 moves + 30 min', 35, 30);
      expectPeriod('60 min / 30 moves + 30 min', 30, 30);
    });

    test('German and multi-period spellings', () {
      expectPeriod('90min/40 Züge + 30sec, 30min', 40, 30);
      expectPeriod('90 min/40 Züge  + 30 min /Rest + 30 sec pro Zug', 40, 30);
      expectPeriod('90 Min / 40 Züge + 15 Min Rest + 30 sec. pro Zug', 40, 15);
      // Only the first secondary period matters for the move-40 display.
      expectPeriod(
        '100 min / 40 moves + 50 min / 20 moves + 15 min / rest + 30 sec / move',
        40,
        50,
      );
      expectPeriod(
        '60 min / 30 moves + 30 min / 20 moves + 30 min / rest',
        30,
        30,
      );
    });

    test('hour-prefixed base', () {
      expectPeriod('1h40/40 moves + 30min (+30sec/move)', 40, 30);
      expectPeriod("1h30/40 - 30' + [30'']", 40, 30);
      expectPeriod('2x 1,5 h/40 + 30 min + 30 s/move', 40, 30);
    });

    test('abbreviated slash form with a bare move count', () {
      expectPeriod("90'/40 + 30' + 30'' per move", 40, 30);
      expectPeriod("90'/40+30'+30''", 40, 30);
      expectPeriod("90'/40 + 15' + 30\"", 40, 15);
      expectPeriod('90\'/40m + 30\'/end & 30"/m', 40, 30);
      expectPeriod("90' x 40 mvs. + 15' + 30'' bonus", 40, 15);
      expectPeriod('90 min/40 mov + 30 min + 30 sec for each move', 40, 30);
      expectPeriod('90 min / 40 drag + 30 min + 30 sek / drag', 40, 30);
    });

    test('prose naming the move rather than a move count', () {
      expectPeriod('90+30 (15 minutes added after move 40)', 40, 15);
      expectPeriod('90 min + 30 sec/move, 30 min after move 40', 40, 30);
      expectPeriod("90'+30'' (+30' after move 40)", 40, 30);
      expectPeriod('90 min + 30 sec + 30 min at move 40.', 40, 30);
      expectPeriod('90 min + 15 min after move 40 + 30 sec / move', 40, 15);
      expectPeriod('90 min + 15 min at move 40. 30 sec from move 1.', 40, 15);
      expectPeriod(
        '90 minutes + 30 minutes on move 40, with 30 seconds increment '
        'from move 1.',
        40,
        30,
      );
      // "from move 41" and "after move 40" describe the same instant.
      expectPeriod(
        '90  min + 30 sec for first 40 moves+30 mins from move no 41',
        40,
        30,
      );
    });

    test('US sudden-death notation', () {
      expectPeriod('40/90, SD/30; +30', 40, 30);
      expectPeriod('40/90,SD/30;+30', 40, 30);
      expectPeriod('40/90, SD/30; d30', 40, 30);
      expectPeriod('40/80/d30, SD30/d30', 40, 30);
    });

    test('other real spellings round out coverage', () {
      expectPeriod(
        '90mins/40moves + 30mins, 30secs increment all moves.',
        40,
        30,
      );
      expectPeriod(
        '90 min for 40 moves + 30 min for the rest of the game, '
        'with 30-second increment',
        40,
        30,
      );
      expectPeriod('90+30 for 40 moves then 15 minutes', 40, 15);
      expectPeriod(
        '90  min + 30 sec for first 40 moves+30 mins from move no 41',
        40,
        30,
      );
      expectPeriod(
        '120 min / 40 moves + 30 min / rest + 30 sec / move '
        'starting 41',
        40,
        30,
      );
      expectPeriod(
        '90 min / 40 moves, then 30\' till end, with a 30-sec '
        'increment',
        40,
        30,
      );
    });
  });

  group('parseSecondaryTimePeriod — must decline rather than guess', () {
    void expectNoPeriod(String? tc) {
      expect(parseSecondaryTimePeriod(tc), isNull, reason: 'tc: "$tc"');
    }

    test('single-period controls have no bonus', () {
      expectNoPeriod('90 min + 30 sec / move');
      expectNoPeriod("90' + 30\"/move");
      expectNoPeriod('3 min + 2 sec / move');
      expectNoPeriod('15 min + 10 sec / move');
      expectNoPeriod('90 minutes with 30 second increment from move 1');
      expectNoPeriod('10+5');
      expectNoPeriod('Classical');
    });

    test('a move count without a stated bonus is not a bonus', () {
      // These name 40 moves but never grant an extra block of minutes.
      expectNoPeriod('90 min / 40 moves + 30 sec / move');
      expectNoPeriod('90min/40moves + 30sec/move');
      expectNoPeriod('90 min/ 40 moves + 15 sec +30 sec / move');
    });

    test('an increment that starts at move 41 is not a bonus', () {
      // The riskiest near-miss: "from move 41" here scopes the *increment*,
      // not an extra block of time.
      expectNoPeriod('120 min + 10 sec / move from move 41');
      expectNoPeriod('120 min + 10 sec / move starting 41');
      expectNoPeriod('90 min + 30 sec increment from move 1');
    });

    test('US "game in N" notation has no secondary period', () {
      expectNoPeriod('G/90;+30');
      expectNoPeriod('G/15;+3');
      expectNoPeriod('G/60;10d');
      expectNoPeriod('G/90; d10');
      expectNoPeriod('90/90 + 30sipm');
    });

    test('unrelated numbers never read as a time control', () {
      expectNoPeriod('14-game match');
      expectNoPeriod('8-team Knockout');
      expectNoPeriod('20 Teams');
      expectNoPeriod('January 25-29');
      expectNoPeriod(r'$36,000 in prizes');
      expectNoPeriod('40 min + 15 sec / move');
      expectNoPeriod(
        '40 minutes per game with 15 seconds increment from '
        'move 1',
      );
    });

    test('per-round time controls are rejected outright', () {
      expectNoPeriod(
        'Round 1-3: 25 min + 10 sec | Round 4-7: 90 min / 40 moves + 15 min '
        '+ 30 sec',
      );
    });

    test('empty and junk input', () {
      expectNoPeriod(null);
      expectNoPeriod('');
      expectNoPeriod('   ');
      expectNoPeriod('TBA');
    });
  });

  group('secondaryBonusOffsetSeconds', () {
    const period = TimeControlSecondaryPeriod(
      afterMoves: 40,
      bonusSeconds: 1800,
    );

    List<int?> series(int count, {int start = 5400, int step = -100}) {
      return List<int?>.generate(count, (i) => start + (step * i));
    }

    test('no bonus before the qualifying move', () {
      expect(
        secondaryBonusOffsetSeconds(
          period: period,
          playerClocks: series(39),
          completedMoves: 39,
        ),
        0,
      );
    });

    test('bonus applied the moment the side completes move 40', () {
      expect(
        secondaryBonusOffsetSeconds(
          period: period,
          playerClocks: series(40),
          completedMoves: 40,
        ),
        1800,
      );
    });

    test('no bonus when the source already credited it at move 41', () {
      final clocks = series(40);
      // Move 41 shows the jump the relay finally delivered.
      clocks.add(clocks.last! + 1800 - 60);
      expect(
        secondaryBonusOffsetSeconds(
          period: period,
          playerClocks: clocks,
          completedMoves: 41,
        ),
        0,
        reason: 'adding again would double-count the bonus',
      );
    });

    test(
      'bonus still applied on move 40 even though move 41 shows the jump',
      () {
        final clocks = series(40);
        clocks.add(clocks.last! + 1800 - 60);
        // Viewing the position after move 40: the credit lands at index 40.
        expect(
          secondaryBonusOffsetSeconds(
            period: period,
            playerClocks: clocks,
            completedMoves: 40,
          ),
          1800,
        );
      },
    );

    test('late arbiter credit (move 43) keeps moves 40-42 corrected', () {
      final clocks = series(42);
      clocks.add(clocks.last! + 1800 - 120); // credit finally lands on move 43

      for (final moves in [40, 41, 42]) {
        expect(
          secondaryBonusOffsetSeconds(
            period: period,
            playerClocks: clocks,
            completedMoves: moves,
          ),
          1800,
          reason: 'move $moves is past the qualifying move but uncredited',
        );
      }
      expect(
        secondaryBonusOffsetSeconds(
          period: period,
          playerClocks: clocks,
          completedMoves: 43,
        ),
        0,
      );
    });

    test('a normal increment gain is never mistaken for the bonus', () {
      // Player moves instantly for several moves, gaining the 30s increment.
      final clocks = <int?>[for (var i = 0; i < 45; i++) 600 + (i * 30)];
      expect(
        secondaryBonusOffsetSeconds(
          period: period,
          playerClocks: clocks,
          completedMoves: 44,
        ),
        1800,
        reason: '30s increments must not read as a 30 minute credit',
      );
    });

    test('null period leaves clocks untouched', () {
      expect(
        secondaryBonusOffsetSeconds(
          period: null,
          playerClocks: series(50),
          completedMoves: 50,
        ),
        0,
      );
    });
  });

  group('applySecondaryBonusToMoveClocks', () {
    const period = TimeControlSecondaryPeriod(
      afterMoves: 40,
      bonusSeconds: 1800,
    );

    /// Builds a ply-indexed display list where every move burns 60 seconds.
    List<String> buildDisplays(int plies) {
      return List<String>.generate(plies, (ply) {
        final moveIndex = ply ~/ 2;
        final seconds = 5400 - ((moveIndex + 1) * 60);
        final h = seconds ~/ 3600;
        final m = (seconds % 3600) ~/ 60;
        final s = seconds % 60;
        return h == 0
            ? '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
            : '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      });
    }

    test('moves 1-39 are untouched, move 40 onward gains the bonus', () {
      final displays = buildDisplays(82);
      final adjusted = applySecondaryBonusToMoveClocks(displays, period);

      // White move 39 -> ply 76.
      expect(adjusted[76], displays[76]);
      // Black move 39 -> ply 77.
      expect(adjusted[77], displays[77]);
      // White move 40 -> ply 78 gains 30 minutes (3000s -> 4800s).
      expect(displays[78], '50:00');
      expect(adjusted[78], '1:20:00');
      // Black move 40 -> ply 79.
      expect(adjusted[79], '1:20:00');
    });

    test('placeholders pass through untouched', () {
      final displays = buildDisplays(82);
      displays[78] = '-:--:--';
      final adjusted = applySecondaryBonusToMoveClocks(displays, period);
      expect(adjusted[78], '-:--:--');
    });

    test('stops correcting once the source credit appears', () {
      final displays = buildDisplays(84);
      // Ply 80 = White move 41, where the relay finally shows the jump.
      displays[80] = '1:19:00';
      final adjusted = applySecondaryBonusToMoveClocks(displays, period);

      expect(adjusted[78], '1:20:00', reason: 'move 40 still needs the credit');
      expect(adjusted[80], '1:19:00', reason: 'move 41 already has it');
    });

    test('null period is a no-op and preserves identity', () {
      final displays = buildDisplays(82);
      expect(applySecondaryBonusToMoveClocks(displays, null), same(displays));
    });

    test('games shorter than the qualifying move are untouched', () {
      final displays = buildDisplays(40);
      expect(applySecondaryBonusToMoveClocks(displays, period), same(displays));
    });
  });

  group('applySecondaryBonusToLiveClocks — real broadcast PGNs', () {
    const period = TimeControlSecondaryPeriod(
      afterMoves: 40,
      bonusSeconds: 1800,
    );

    // Abridged from game nlpJisXF (47th Rhineland Championship 2026). The relay
    // credits the bonus on move 41, so the move-40 reading is 30 minutes short.
    const pgnCreditedOnMove41 = '''
1. e4 { [%clk 1:30:57] } 1... d5 { [%clk 1:30:53] }
39. Nxe4 { [%clk 0:02:26] } 39... Nf4 { [%clk 0:02:01] }
40. c4 { [%clk 0:01:30] } 40... g5 { [%clk 0:02:06] }
''';

    const pgnAfterMove41 = '''
1. e4 { [%clk 1:30:57] } 1... d5 { [%clk 1:30:53] }
39. Nxe4 { [%clk 0:02:26] } 39... Nf4 { [%clk 0:02:01] }
40. c4 { [%clk 0:01:30] } 40... g5 { [%clk 0:02:06] }
41. Kg1 { [%clk 0:24:46] } 41... Kc8 { [%clk 0:28:45] }
''';

    test('move 40 reading is topped up by the missing 30 minutes', () {
      // The abridged movetext holds 6 plies; both sides have "completed"
      // 3 moves there, so drive the qualifying count from a full-length series.
      final clocks = applySecondaryBonusToLiveClocks(
        pgn: _padPgnToMove(pgnCreditedOnMove41, plies: 80),
        whiteSeconds: 90,
        blackSeconds: 126,
        period: period,
      );
      expect(clocks.white, 90 + 1800);
      expect(clocks.black, 126 + 1800);
    });

    test('once move 41 lands, the source value is used as-is', () {
      final clocks = applySecondaryBonusToLiveClocks(
        pgn: _padPgnToMove(pgnAfterMove41, plies: 82),
        whiteSeconds: 1486,
        blackSeconds: 1725,
        period: period,
      );
      expect(clocks.white, 1486, reason: 'bonus already inside the reading');
      expect(clocks.black, 1725);
    });

    test('null period and empty pgn are no-ops', () {
      expect(
        applySecondaryBonusToLiveClocks(
          pgn: pgnAfterMove41,
          whiteSeconds: 100,
          blackSeconds: 200,
          period: null,
        ),
        (white: 100, black: 200),
      );
      expect(
        applySecondaryBonusToLiveClocks(
          pgn: '',
          whiteSeconds: 100,
          blackSeconds: 200,
          period: period,
        ),
        (white: 100, black: 200),
      );
    });
  });

  group('completedMovesForSide', () {
    test('splits plies across the two sides', () {
      expect(completedMovesForSide(0, 0), 0);
      expect(completedMovesForSide(0, 1), 0);
      expect(completedMovesForSide(79, 0), 40);
      expect(completedMovesForSide(79, 1), 39);
      expect(completedMovesForSide(80, 0), 40);
      expect(completedMovesForSide(80, 1), 40);
    });
  });

  group('playerClockSeriesFromPgn', () {
    test('splits the clock tags by side', () {
      const pgn =
          '1. e4 { [%clk 1:30:00] } 1... e5 { [%clk 1:29:00] } '
          '2. Nf3 { [%clk 1:28:00] } 2... Nc6 { [%clk 1:27:00] }';
      expect(playerClockSeriesFromPgn(pgn, 0), [5400, 5280]);
      expect(playerClockSeriesFromPgn(pgn, 1), [5340, 5220]);
    });

    test('empty input yields an empty series', () {
      expect(playerClockSeriesFromPgn(null, 0), isEmpty);
      expect(playerClockSeriesFromPgn('', 1), isEmpty);
    });
  });
}

/// Pads [pgn] with leading filler clock tags so the movetext carries [plies]
/// clock samples in total, letting a short excerpt stand in for a full game.
String _padPgnToMove(String pgn, {required int plies}) {
  final existing = RegExp(r'\[%clk').allMatches(pgn).length;
  final missing = plies - existing;
  if (missing <= 0) return pgn;
  final filler = List<String>.generate(
    missing,
    (i) => '{ [%clk 1:${(29 - (i % 25)).toString().padLeft(2, '0')}:00] }',
  ).join(' ');
  return '$filler $pgn';
}
