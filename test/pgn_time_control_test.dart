import 'package:chessever2/utils/pgn_time_control.dart';
import 'package:flutter_test/flutter_test.dart';

/// `[TimeControl "standard"]` is not a time control — it is a category label,
/// and it shipped in every PGN we exported. ChessBase converts `[%clk]` into
/// its own elapsed-time annotation using the time control, so an unparseable
/// tag costs the reader every clock in the game. Lichess and chess.com read
/// `[%clk]` directly and never noticed.
void main() {
  group('pgnTimeControlField', () {
    test('classical FIDE text becomes a two-period field', () {
      expect(
        pgnTimeControlField('90 min / 40 moves + 30 min + 30 sec / move'),
        '40/5400+30:1800+30',
      );
    });

    test('abbreviated broadcast shorthand parses the same', () {
      expect(pgnTimeControlField("90'/40 + 30' + 30''"), '40/5400+30:1800+30');
    });

    test('single period with increment', () {
      expect(pgnTimeControlField('90 min + 30 sec / move'), '5400+30');
      expect(pgnTimeControlField('15 min + 10 sec'), '900+10');
    });

    test('sudden death has no increment', () {
      expect(pgnTimeControlField('15 min'), '900');
      expect(pgnTimeControlField('2 hours'), '7200');
    });

    test('bare base+increment shorthand reads the base as minutes', () {
      expect(pgnTimeControlField('3+2'), '180+2');
      expect(pgnTimeControlField('90+30'), '5400+30');
      expect(pgnTimeControlField('5+0'), '300');
    });

    test('a move count written first still binds to its period', () {
      expect(pgnTimeControlField('40 moves / 100 min + 50 min'), '40/6000:3000');
    });

    test('category words yield nothing — omit the tag, never guess', () {
      for (final category in ['standard', 'rapid', 'blitz', 'classical', '']) {
        expect(
          pgnTimeControlField(category),
          isNull,
          reason: '"$category" is a speed label, not a time control',
        );
      }
      expect(pgnTimeControlField(null), isNull);
      expect(pgnTimeControlField('unknown'), isNull);
    });

    test('an already-valid field passes through unchanged', () {
      for (final field in [
        '40/5400+30:1800+30',
        '300+3',
        '600',
        '*180',
        '40/9000',
      ]) {
        expect(pgnTimeControlField(field), field);
        expect(isValidPgnTimeControl(field), isTrue);
      }
    });

    test('isValidPgnTimeControl rejects what broke ChessBase', () {
      expect(isValidPgnTimeControl('standard'), isFalse);
      expect(isValidPgnTimeControl('Blitz'), isFalse);
      expect(isValidPgnTimeControl('90 min + 30 sec'), isFalse);
      expect(isValidPgnTimeControl(null), isFalse);
      expect(isValidPgnTimeControl(''), isFalse);
      // The standard's own "unknown" and "none" markers stay legal.
      expect(isValidPgnTimeControl('?'), isTrue);
      expect(isValidPgnTimeControl('-'), isTrue);
    });

    test('the shapes tours actually publish', () {
      // Taken verbatim from `tours.info->>'tc'` in production, most common
      // first. Feeds write time controls in prose, in three languages, with
      // primes, double-primes and no units at all — the tag we emit has to be
      // machine-readable no matter which.
      const cases = <String, String?>{
        '90 min + 30 sec / move': '5400+30',
        '90 min / 40 moves + 30 min + 30 sec / move': '40/5400+30:1800+30',
        '90 min + 30 sec': '5400+30',
        '3 min + 2 sec / move': '180+2',
        "90' + 30\"/move": '5400+30',
        '60 min + 30 sec / move': '3600+30',
        '15 min + 10 sec / move': '900+10',
        '10 min + 5 sec / move': '600+5',
        '90+30': '5400+30',
        '90 min + 30 seg': '5400+30',
        '90 min / 40 moves + 15 min + 30 sec / move': '40/5400+30:900+30',
        '90 mins + 30 secs increment.': '5400+30',
        '5+0': '300',
        '3+2': '180+2',
        '90 minutes with 30 seconds increment per move from move 1': '5400+30',
        '10 min, no increment': '600',
        '90mins/40moves + 30mins, 30secs increment all moves.':
            '40/5400+30:1800+30',
        '90min + 30sec / 40move + 30min': '40/5400+30:1800+30',
        '90 min / 40 moves + 30 min / rest of the game, with 30 sec increment from move 1':
            '40/5400+30:1800+30',
        '90min/40moves+30min/end+30sec increment per move starting from move 1':
            '40/5400+30:1800+30',
        '25mins, 5secs increment all moves.': '1500+5',
        'G: 90 min + 30 sec': '5400+30',
        '3 minutos + 2 segundos por jugada': '180+2',
        '20 min + 5 seg /move': '1200+5',
        '110 min + 10 sec / move': '6600+10',
        '10 min': '600',
        // Category labels are not time controls — the tag must be omitted.
        'Classical': null,
        'Rapid': null,
        'Blitz': null,
        // Unparseable vendor shorthand: omit rather than invent.
        'g25d5': null,
      };

      cases.forEach((text, expected) {
        expect(pgnTimeControlField(text), expected, reason: 'tc = "$text"');
      });
    });

    test('prime and double-prime notation', () {
      expect(pgnTimeControlField("90'+30''"), '5400+30');
      expect(pgnTimeControlField('90\'+30"'), '5400+30');
      expect(pgnTimeControlField('30\'+30"'), '1800+30');
      expect(pgnTimeControlField('15\' + 10"/move'), '900+10');
      expect(pgnTimeControlField("90' / 40 moves + 30' + 30'' / move"),
          '40/5400+30:1800+30');
    });

    test('periods expose the numbers, not just the rendered field', () {
      final periods = parsePgnTimeControlPeriods(
        '90 min / 40 moves + 30 min + 30 sec / move',
      );
      expect(periods.length, 2);
      expect(periods.first.moves, 40);
      expect(periods.first.seconds, 5400);
      // The increment is credited on every move, so it rides both periods.
      expect(periods.first.incrementSeconds, 30);
      expect(periods.last.seconds, 1800);
      expect(periods.last.moves, isNull);
      expect(periods.last.incrementSeconds, 30);
    });
  });
}
