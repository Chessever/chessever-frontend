import 'package:chessever2/screens/for_you/discovery/data/missed_chance_topic.dart';
import 'package:flutter_test/flutter_test.dart';

const _sans = ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5', 'd3', 'd6'];
String pgn({
  List<String?> clocks = const ['0:00:09', '0:00:09', '0:00:09', '0:00:09'],
  List<String?> evals = const ['0', '3.50', '0', '0'],
  String timeControl = '180+2',
  String variation = '',
}) {
  final text = StringBuffer(
    '[TimeControl "$timeControl"]\n[Result "1/2-1/2"]\n\n',
  );
  for (var i = 0; i < clocks.length; i++) {
    if (i.isEven) text.write('${i ~/ 2 + 1}. ');
    text.write('${_sans[i]} {');
    if (clocks[i] != null) text.write('[%clk ${clocks[i]}] ');
    if (i < evals.length && evals[i] != null) {
      text.write('[%eval ${evals[i]}] ');
    }
    text.write('} ');
    if (i == 0) text.write(variation);
  }
  text.write('1/2-1/2');
  return text.toString();
}

Map<String, Object?> story({
  List<int> plies = const [3],
  String result = '1/2-1/2',
}) => {
  'result': result,
  'tags': ['missed_chance'],
  'evidence': [
    for (final ply in plies) {'type': 'missed_chance', 'fromPly': ply},
  ],
};

void main() {
  group('Missed Chance topic historical clocks', () {
    test('both below ten excludes the opportunity', () {
      expect(missedChanceTopicSelection(story(), pgn()), (
        include: false,
        ply: null,
      ));
    });
    test('exactly ten seconds on both clocks excludes', () {
      expect(
        missedChanceTopicSelection(
          story(),
          pgn(clocks: ['0:00:10', '0:00:10', '0:00:10', '0:00:10']),
        ),
        (include: false, ply: null),
      );
    });
    test('either clock above ten, including subsecond precision, keeps it', () {
      for (final pair in [
        ['0:00:10.001', '0:00:10'],
        ['0:00:10', '0:00:10.000001'],
        ['0:00:11', '0:00:09'],
        ['0:00:09', '0:00:11'],
        ['0:00:11', '0:00:12'],
      ]) {
        expect(
          missedChanceTopicSelection(
            story(),
            pgn(clocks: [...pair, '0:00:01', '0:00:01']),
          ),
          (include: true, ply: 3),
          reason: '$pair',
        );
      }
    });
    test('unknown, malformed, negative and duplicate clocks never exclude', () {
      for (final bad in <String?>[
        null,
        '',
        'unknown',
        '-0:00:01',
        'NaN',
        '0:00:60',
        '0:60:00',
        '0:00:09] [%clk 0:00:08',
      ]) {
        for (final side in [0, 1]) {
          final clocks = <String?>['0:00:09', '0:00:09', '0:00:09', '0:00:09'];
          clocks[side] = bad;
          expect(
            missedChanceTopicSelection(story(), pgn(clocks: clocks)),
            (include: true, ply: 3),
            reason: '$side $bad',
          );
        }
      }
    });
    test(
      'zero is valid; two-part clocks are minutes/seconds, not centiseconds',
      () {
        expect(
          missedChanceTopicSelection(
            story(),
            pgn(clocks: ['0:00', '0:10', '0:02', '0:02']),
          ),
          (include: false, ply: null),
        );
        expect(
          missedChanceTopicSelection(
            story(),
            pgn(clocks: ['1:00', '0:10', '0:02', '0:02']),
          ),
          (include: true, ply: 3),
        );
      },
    );
    test(
      'White miss uses the two clocks BEFORE the miss, not final or post-move',
      () {
        // White has 20s when Black offers the chance, spends 19s, earns 2s.
        expect(
          missedChanceTopicSelection(
            story(),
            pgn(clocks: ['0:00:20', '0:00:09', '0:00:03', '0:00:01']),
          ),
          (include: true, ply: 3),
        );
        // White starts with 9s; its own following 5s increment is not available
        // at the opportunity. The opponent's already-earned increment IS.
        expect(
          missedChanceTopicSelection(
            story(),
            pgn(
              clocks: ['0:00:09', '0:00:09', '0:00:14', '0:00:20'],
              timeControl: '180+5',
            ),
          ),
          (include: false, ply: null),
        );
        expect(
          missedChanceTopicSelection(
            story(),
            pgn(
              clocks: ['0:00:09', '0:00:14', '0:00:01', '0:00:01'],
              timeControl: '180+5',
            ),
          ),
          (include: true, ply: 3),
        );
      },
    );
    test('Black miss is aligned to Black and White preceding moves', () {
      const evals = ['0', '0', '-3.5', '0'];
      expect(
        missedChanceTopicSelection(
          story(plies: [4]),
          pgn(
            clocks: ['0:01:00', '0:00:10', '0:00:09', '0:00:15'],
            evals: evals,
            timeControl: '180+5',
          ),
        ),
        (include: false, ply: null),
      );
      expect(
        missedChanceTopicSelection(
          story(plies: [4]),
          pgn(
            clocks: ['0:00:01', '0:00:11', '0:00:09', '0:00:01'],
            evals: evals,
          ),
        ),
        (include: true, ply: 4),
      );
      expect(
        missedChanceTopicSelection(
          story(plies: [4]),
          pgn(
            clocks: ['0:00:01', '0:00:09', '0:00:11', '0:00:01'],
            evals: evals,
          ),
        ),
        (include: true, ply: 4),
      );
    });
    test('missing immediate clock cannot borrow an older or later sample', () {
      expect(
        missedChanceTopicSelection(
          story(plies: [4]),
          pgn(
            clocks: ['0:00:09', null, '0:00:09', '0:00:09'],
            evals: ['0', '0', '-3.5', '0'],
          ),
        ),
        (include: true, ply: 4),
      );
      expect(missedChanceTopicSelection(story(plies: [2]), pgn()), (
        include: true,
        ply: 2,
      ));
    });
    test(
      'variations, prose, elapsed time and root clocks cannot shift plies',
      () {
        final text = pgn(
          variation:
              '(1. d4 {[%clk 0:09:00] [%eval 3.5]} d5 {[%clk 0:08:00]}) ',
        );
        expect(missedChanceTopicSelection(story(), text), (
          include: false,
          ply: null,
        ));
        expect(
          missedChanceTopicSelection(
            story(),
            text.replaceFirst('[%clk 0:00:09]', '[%emt 0:00:09]'),
          ),
          (include: true, ply: 3),
        );
      },
    );
    test(
      'later eligible miss survives the first excluded stored-only evidence',
      () {
        final text = pgn(
          clocks: [
            '0:00:09',
            '0:00:09',
            '0:00:12',
            '0:00:12',
            '0:00:08',
            '0:00:08',
          ],
          evals: ['0', '3.5', '0', '3.5', '0', '0'],
          timeControl: '180+5',
        );
        expect(missedChanceTopicSelection(story(), text), (
          include: true,
          ply: 5,
        ));
        expect(missedChanceTopicSelection(story(plies: [5, 3]), text), (
          include: true,
          ply: 5,
        ));
      },
    );
    test('later Black miss, forced mate and unknown clock also survive', () {
      for (final score in ['-3.5', '#-2']) {
        final text = pgn(
          clocks: ['0:00:09', '0:00:09', '0:00:12', '0:00:12', null, '0:00:08'],
          evals: ['0', '3.5', '0', '0', score, '0'],
        );
        expect(missedChanceTopicSelection(story(), text), (
          include: true,
          ply: 6,
        ));
      }
    });
    test(
      'all misses excluded means no topic game; no broad game scramble rule',
      () {
        final text = pgn(
          clocks: List.filled(6, '0:00:09'),
          evals: ['0', '3.5', '0', '3.5', '0', '0'],
        );
        expect(missedChanceTopicSelection(story(), text), (
          include: false,
          ply: null,
        ));
        final usefulFirst = text.replaceFirst(
          '[%clk 0:00:09]',
          '[%clk 0:00:11]',
        );
        expect(missedChanceTopicSelection(story(), usefulFirst), (
          include: true,
          ply: 3,
        ));
      },
    );
    test(
      'later inferred chances obey the existing story floors and result',
      () {
        for (final scores in [
          ['0', '3.5', '0', '2.99', '0', '0'],
          ['0', '3.5', '0', '3.5', '0.51', '0'],
          ['0', '3.5', '0', null, '0', '0'],
        ]) {
          final text = pgn(
            clocks: [
              '0:00:09',
              '0:00:09',
              '0:00:12',
              '0:00:12',
              '0:00:08',
              '0:00:08',
            ],
            evals: scores,
          );
          expect(missedChanceTopicSelection(story(), text), (
            include: false,
            ply: null,
          ));
        }
        // Do not infer a recovered miss for the eventual winning side.
        final text = pgn(
          clocks: [
            '0:00:09',
            '0:00:09',
            '0:00:12',
            '0:00:12',
            '0:00:12',
            '0:00:08',
          ],
          evals: ['0', '3.5', '0', '0', '-3.5', '0'],
        );
        expect(missedChanceTopicSelection(story(result: '0-1'), text), (
          include: false,
          ply: null,
        ));
      },
    );
    test(
      'secondary periods are credited at the opportunity, with the playoff fit guard',
      () {
        String longGame({required bool classical}) {
          final text = StringBuffer('[Result "1/2-1/2"]\n\n');
          const cycle = ['Nf3', 'Nf6', 'Ng1', 'Ng8'];
          for (var i = 0; i < 82; i++) {
            if (i.isEven) text.write('${i ~/ 2 + 1}. ');
            final clock = i < 2 && classical ? '1:29:00' : '0:00:09';
            text.write('${cycle[i % 4]} {[%clk $clock] [%eval 0]} ');
          }
          return '${text}1/2-1/2';
        }

        const tc = '90 min / 40 moves + 30 min + 30 sec / move';
        expect(
          missedChanceTopicSelection(
            story(plies: [81]),
            longGame(classical: true),
            timeControlText: tc,
          ),
          (include: true, ply: 81),
        );
        // At ply79 Black has not completed move40, so no bonus is due yet.
        expect(
          missedChanceTopicSelection(
            story(plies: [79]),
            longGame(classical: true),
            timeControlText: tc,
          ),
          (include: false, ply: null),
        );
        // A shorter playoff under the same event must not inherit its 30min.
        expect(
          missedChanceTopicSelection(
            story(plies: [81]),
            longGame(classical: false),
            timeControlText: tc,
          ),
          (include: false, ply: null),
        );
      },
    );

    test('malformed/missing evidence and unsupported PGN do not exclude', () {
      for (final metadata in <Object?>[
        null,
        {},
        {'evidence': 'bad'},
        story(plies: []),
      ]) {
        expect(missedChanceTopicSelection(metadata, pgn()).include, isTrue);
      }
      expect(missedChanceTopicSelection(story(), '[Event "bad'), (
        include: true,
        ply: 3,
      ));
      expect(
        missedChanceTopicSelection(story(plies: [99]), pgn()).include,
        isTrue,
      );
    });
  });
}
