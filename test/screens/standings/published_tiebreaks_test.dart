import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> publishedPlayer() => {
  'name': 'Published player',
  'played': 4,
  'rank': 2,
  'score': 3,
  'tiebreaks': [
    {'points': 9.5, 'description': 'Buchholz Cut-1', 'extendedCode': 'TB1'},
    {'points': 0, 'description': 'Direct encounter', 'extendedCode': 'TB2'},
  ],
};

void main() {
  test('published tiebreaks survive roster, standings and cached copies', () {
    final roster = TournamentPlayer.fromJson(publishedPlayer());
    expect(roster.toJson()['tiebreaks'], publishedPlayer()['tiebreaks']);
    final standing = PlayerStandingModel.fromPlayer(
      roster.copyWith(rating: 2100),
    );
    final cached = PlayerStandingModel.fromJson(
      standing.copyWith(overallRank: 2).toJson(),
    );
    expect(cached.toJson()['tiebreaks'], publishedPlayer()['tiebreaks']);
    expect(cached.copyWith(), cached);
    final changed = publishedPlayer();
    (changed['tiebreaks'] as List)[0]['points'] = 10;
    expect(TournamentPlayer.fromJson(changed), isNot(roster));
    expect(
      PlayerStandingModel.fromPlayer(TournamentPlayer.fromJson(changed)),
      isNot(standing),
    );
  });

  test('invalid or incomplete tiebreaks never become displayed zeroes', () {
    for (final invalid in [
      null,
      '9.5',
      [
        {'points': 9.5},
      ],
      [
        {'points': double.nan, 'description': 'Buchholz'},
      ],
      [
        {'points': -1, 'description': 'Buchholz'},
      ],
      [
        {'points': 2, 'description': '  '},
      ],
      [
        {'points': 2, 'description': 'BH', 'extendedCode': 'TB1'},
        {'points': 3, 'description': 'BH', 'extendedCode': 'TB1'},
      ],
    ]) {
      final row = TournamentPlayer.fromJson({
        ...publishedPlayer(),
        'tiebreaks': invalid,
      });
      expect(row.toJson()['tiebreaks'], isNull);
    }
  });
}
