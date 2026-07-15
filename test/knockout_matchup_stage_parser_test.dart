import 'package:chessever2/screens/tour_detail/bracket/utils/knockout_stage_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('matchup-labeled knockout stage rounds', () {
    test('Women\'s Speed Chess RO16 matchup resolves to Round of 16', () {
      final stage = resolveLogicalKnockoutStage(
        'Round of 16: Ju Wenjun vs Pham Le Thao Nguyen',
        'round-of-16-ju-wenjun-vs-pham-le-thao-nguyen',
      );
      expect(stage?.key, 'round-of-16');
      expect(stage?.label, 'Round of 16');
    });

    test('slug alone (empty name) still resolves the pairing', () {
      final stage = resolveLogicalKnockoutStage(
        '',
        'round-of-16-vaishali-rameshbabu-vs-anna-muzychuk',
      );
      expect(stage?.key, 'round-of-16');
    });

    test('numbered + named matchup rounds resolve', () {
      expect(
        resolveLogicalKnockoutStage('Round 3: A vs B', 'round-3-a-vs-b')?.key,
        'round-3',
      );
      expect(
        resolveLogicalKnockoutStage(
          'Quarterfinals: Carlsen vs Nakamura',
          'quarterfinals-carlsen-vs-nakamura',
        )?.key,
        'quarterfinals',
      );
      expect(
        resolveLogicalKnockoutStage('Finals: A vs B', 'finals-a-vs-b')?.key,
        'finals',
      );
    });

    test('clean stage rounds still resolve (no regression)', () {
      expect(resolveLogicalKnockoutStage('Quarterfinals', 'quarterfinals')?.key,
          'quarterfinals');
      expect(resolveLogicalKnockoutStage('Semifinals', 'semifinals')?.key,
          'semifinals');
      expect(resolveLogicalKnockoutStage('Finals', 'finals')?.key, 'finals');
    });

    test('non-stage matchup stays unresolved', () {
      // A plain 1v1 match with no stage token must NOT be forced into a stage.
      expect(
        resolveLogicalKnockoutStage(
          'Magnus Carlsen vs Hikaru Nakamura',
          'magnus-carlsen-vs-hikaru-nakamura',
        ),
        isNull,
      );
    });
  });
}
