import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/team_avg_elo.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/tour_detail/team_tour/widgets/team_event_share_image_card.dart';
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

  group('normalizeEventTimeControlBucket', () {
    test('maps compact broadcast enums', () {
      expect(normalizeEventTimeControlBucket('standard'), 'standard');
      expect(normalizeEventTimeControlBucket('rapid'), 'rapid');
      expect(normalizeEventTimeControlBucket('blitz'), 'blitz');
    });

    test('detects free-form clock strings', () {
      expect(
        normalizeEventTimeControlBucket('45 min + 10 sec'),
        'standard', // no rapid/blitz token → classical default
      );
      expect(
        normalizeEventTimeControlBucket('15+10 rapid'),
        'rapid',
      );
      expect(normalizeEventTimeControlBucket('3+2 Blitz'), 'blitz');
      expect(
        normalizeEventTimeControlBucket('90min/40moves classical'),
        'standard',
      );
    });
  });

  group('team average Elo', () {
    test('averages positive standings ratings and ignores zeros', () {
      const team = TeamStandingModel(
        teamName: 'USA',
        rank: 1,
        matchPoints: 4,
        gamePoints: 10,
        matchesWon: 2,
        matchesDrawn: 0,
        matchesLost: 0,
        boardsPlayed: 8,
        players: [
          PlayerStandingModel(
            countryCode: 'USA',
            name: 'A',
            score: 2800,
            scoreChange: 0,
            matchScore: null,
          ),
          PlayerStandingModel(
            countryCode: 'USA',
            name: 'B',
            score: 2700,
            scoreChange: 0,
            matchScore: null,
          ),
          PlayerStandingModel(
            countryCode: 'USA',
            name: 'C',
            score: 0,
            scoreChange: 0,
            matchScore: null,
          ),
        ],
      );
      expect(teamAverageEloFromStandings(team), 2750);
      expect(formatTeamAvgElo(2750), '2750');
    });

    test('returns null when roster has no ratings', () {
      const team = TeamStandingModel(
        teamName: 'X',
        rank: 2,
        matchPoints: 0,
        gamePoints: 0,
        matchesWon: 0,
        matchesDrawn: 0,
        matchesLost: 0,
        boardsPlayed: 0,
        players: [
          PlayerStandingModel(
            countryCode: '',
            name: 'Unknown',
            score: 0,
            scoreChange: 0,
            matchScore: null,
          ),
        ],
      );
      expect(teamAverageEloFromStandings(team), isNull);
      expect(formatTeamAvgElo(null), '—');
    });

    test('averagePositiveRatings rounds half up via round()', () {
      expect(averagePositiveRatings([2700, 2701]), 2701);
      expect(averagePositiveRatings(const <int>[]), isNull);
    });
  });

  group('TeamEventShareImageCard player labels', () {
    test('compact share label uses title and surname', () {
      expect(
        TeamEventShareImageCard.playerShareLabel(
          const PlayerStandingModel(
            countryCode: 'NOR',
            title: 'GM',
            name: 'Carlsen, Magnus',
            score: 2830,
            scoreChange: 0,
            matchScore: null,
          ),
        ),
        'GM Carlsen',
      );
      expect(
        TeamEventShareImageCard.playerShareLabel(
          const PlayerStandingModel(
            countryCode: 'USA',
            name: 'Fabiano Caruana',
            score: 2780,
            scoreChange: 0,
            matchScore: null,
          ),
        ),
        'Caruana',
      );
    });
  });
}
