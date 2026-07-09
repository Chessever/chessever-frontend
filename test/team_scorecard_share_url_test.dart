import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildEventShareUrl team scorecard', () {
    test('encodes team path under broadcast slug/id', () {
      final url = buildEventShareUrl(
        id: 'gb-123',
        title: 'Olympiad',
        tourId: 'QXavbhIZ',
        tourSlug: 'olympiad-2024',
        teamName: 'USA',
      );
      expect(
        url,
        'https://chessever.com/broadcast/olympiad-2024/QXavbhIZ/team/USA',
      );
    });

    test('percent-encodes spaces and special characters in team name', () {
      final url = buildEventShareUrl(
        id: 'gb-123',
        title: 'Olympiad',
        tourId: 'tour1',
        tourSlug: 'event',
        teamName: 'Team USA / A',
      );
      expect(url, contains('/team/'));
      expect(url, contains(Uri.encodeComponent('Team USA / A')));
      // Opening pathSegments must round-trip the name.
      final uri = Uri.parse(url);
      expect(uri.pathSegments[0], 'broadcast');
      expect(uri.pathSegments[3], 'team');
      expect(uri.pathSegments[4], 'Team USA / A');
    });

    test('player fide id takes precedence over team name', () {
      final url = buildEventShareUrl(
        id: 'gb',
        title: 'E',
        tourId: 't',
        tourSlug: 's',
        playerFideId: 1503014,
        teamName: 'Norway',
      );
      expect(url.endsWith('/player/1503014'), isTrue);
      expect(url.contains('/team/'), isFalse);
    });
  });

  group('TeamStandingModel averageBoardPoints', () {
    test('divides game points by boards played', () {
      const team = TeamStandingModel(
        teamName: 'A',
        rank: 1,
        matchPoints: 4,
        gamePoints: 6.5,
        matchesWon: 2,
        matchesDrawn: 0,
        matchesLost: 0,
        boardsPlayed: 10,
        players: [],
      );
      expect(team.averageBoardPoints, closeTo(0.65, 1e-9));
      expect(team.averageBoardPointsLabel, '0.65');
    });

    test('returns em dash when no boards played', () {
      const team = TeamStandingModel(
        teamName: 'B',
        rank: 2,
        matchPoints: 0,
        gamePoints: 0,
        matchesWon: 0,
        matchesDrawn: 0,
        matchesLost: 0,
        boardsPlayed: 0,
        players: [],
      );
      expect(team.averageBoardPoints, isNull);
      expect(team.averageBoardPointsLabel, '—');
    });

    test('formats whole averages without trailing decimals', () {
      const team = TeamStandingModel(
        teamName: 'C',
        rank: 1,
        matchPoints: 2,
        gamePoints: 4,
        matchesWon: 1,
        matchesDrawn: 0,
        matchesLost: 0,
        boardsPlayed: 4,
        players: [],
      );
      expect(team.averageBoardPointsLabel, '1');
    });
  });
}
