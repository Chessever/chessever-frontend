import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ChessPlayer maps ranking fields and selected ratings', () {
    final player = ChessPlayer.fromMap({
      'fideid': 1503014,
      'name': 'Carlsen, Magnus',
      'title': 'GM',
      'rating': 2839,
      'rapid_rating': 2824,
      'blitz_rating': 2881,
      'country': 'NOR',
      'sex': 'M',
      'birthday': 1990,
      'flag': 'i',
    });

    expect(player.ratingFor(RankingTimeControl.classical), 2839);
    expect(player.ratingFor(RankingTimeControl.rapid), 2824);
    expect(player.ratingFor(RankingTimeControl.blitz), 2881);
    expect(player.isInactive, isTrue);
    expect(player.sex, 'M');
    expect(player.birthYear, 1990);
  });
}
