import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? scoreOf(double? score, int played) => PlayerStandingModel.fromPlayer(
    TournamentPlayer(name: 'Player', played: played, score: score, rank: 1),
  ).matchScore;

  test('a published row without a games count shows its score alone', () {
    expect(scoreOf(12.5, 0), '12.5');
    expect(scoreOf(4, 0), '4');
  });

  test('a row with games played keeps score / played', () {
    expect(scoreOf(12.5, 15), '12.5 / 15');
    expect(scoreOf(null, 3), '0.0 / 3');
    expect(scoreOf(null, 0), isNull);
  });
}
