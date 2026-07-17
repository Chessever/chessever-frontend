import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TourInfo round-trips the authoritative Lichess team marker', () {
    final info = TourInfo.fromJson(const {
      'format': '7-round Swiss',
      'teamTable': true,
    });

    expect(info.teamTable, isTrue);
    expect(info.toJson()['teamTable'], isTrue);
  });

  test('authoritative team marker identifies a Swiss team event', () {
    expect(
      resolveTeamEventClassification(
        teamTable: true,
        formatSaysTeam: false,
        formatSaysPlayer: false,
        allPlayersHaveTeam: false,
      ),
      isTrue,
    );
  });

  test('authoritative false overrides heuristic team evidence', () {
    expect(
      resolveTeamEventClassification(
        teamTable: false,
        formatSaysTeam: true,
        formatSaysPlayer: false,
        allPlayersHaveTeam: true,
      ),
      isFalse,
    );
  });

  test('legacy rows still use bounded format and player heuristics', () {
    expect(
      resolveTeamEventClassification(
        teamTable: null,
        formatSaysTeam: false,
        formatSaysPlayer: false,
        allPlayersHaveTeam: true,
      ),
      isTrue,
    );
  });
}
