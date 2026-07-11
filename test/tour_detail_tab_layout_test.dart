import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_tabs.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tournament detail tab layouts', () {
    test('regular individual events expose three explicit modes', () {
      expect(regularTournamentDetailModes, const [
        TournamentDetailScreenMode.about,
        TournamentDetailScreenMode.games,
        TournamentDetailScreenMode.standings,
      ]);
    });

    test('individual knockouts insert Bracket before Standings', () {
      expect(knockoutTournamentDetailModes, const [
        TournamentDetailScreenMode.about,
        TournamentDetailScreenMode.games,
        TournamentDetailScreenMode.bracket,
        TournamentDetailScreenMode.standings,
      ]);
    });

    test('team events preserve Standings then Players', () {
      expect(teamTournamentDetailModes, const [
        TournamentDetailScreenMode.about,
        TournamentDetailScreenMode.games,
        TournamentDetailScreenMode.standings,
        TournamentDetailScreenMode.players,
      ]);
    });

    test('page mappings use the visible list rather than enum order', () {
      expect(
        tournamentDetailPageForMode(
          regularTournamentDetailModes,
          TournamentDetailScreenMode.standings,
        ),
        2,
      );
      expect(
        tournamentDetailPageForMode(
          knockoutTournamentDetailModes,
          TournamentDetailScreenMode.standings,
        ),
        3,
      );
      expect(
        tournamentDetailModeForPage(knockoutTournamentDetailModes, 2),
        TournamentDetailScreenMode.bracket,
      );
      expect(
        tournamentDetailModeForPage(teamTournamentDetailModes, 2),
        TournamentDetailScreenMode.standings,
      );
    });

    test('an unavailable mode safely normalizes to Games', () {
      expect(
        normalizeTournamentDetailMode(
          regularTournamentDetailModes,
          TournamentDetailScreenMode.bracket,
        ),
        TournamentDetailScreenMode.games,
      );
      expect(
        tournamentDetailPageForMode(
          regularTournamentDetailModes,
          TournamentDetailScreenMode.bracket,
        ),
        1,
      );
      expect(
        tournamentDetailModeForPage(regularTournamentDetailModes, 99),
        TournamentDetailScreenMode.games,
      );
    });

    test('provisional layouts retain unresolved deep-link modes', () {
      expect(
        provisionalTournamentDetailLayoutForMode(
          TournamentDetailScreenMode.bracket,
        ),
        TournamentDetailLayout.individualKnockout,
      );
      expect(
        provisionalTournamentDetailLayoutForMode(
          TournamentDetailScreenMode.players,
        ),
        TournamentDetailLayout.team,
      );
      expect(
        provisionalTournamentDetailLayoutForMode(
          TournamentDetailScreenMode.standings,
        ),
        TournamentDetailLayout.regular,
      );
    });
  });

  group('tour-keyed layout tracking', () {
    test('retains knockout layout across transient unresolved state', () {
      final tracker = TournamentDetailLayoutTracker();

      expect(
        tracker.resolve(tourId: 'world-cup-round-3', isKnockout: true),
        TournamentDetailLayout.individualKnockout,
      );
      expect(
        tracker.resolve(tourId: null),
        TournamentDetailLayout.individualKnockout,
      );
      expect(
        tracker.resolve(tourId: 'world-cup-round-3'),
        TournamentDetailLayout.individualKnockout,
      );
    });

    test('retains team layout without leaking it to a different tour', () {
      final tracker = TournamentDetailLayoutTracker();

      expect(
        tracker.resolve(tourId: 'team-event', isTeam: true),
        TournamentDetailLayout.team,
      );
      expect(
        tracker.resolve(tourId: 'regular-event'),
        TournamentDetailLayout.regular,
      );
      expect(
        tracker.resolve(tourId: 'team-event'),
        TournamentDetailLayout.team,
      );
    });

    test('upgrades a tour when inferred knockout detection arrives', () {
      final tracker = TournamentDetailLayoutTracker();

      expect(
        tracker.resolve(tourId: 'inferred-event'),
        TournamentDetailLayout.regular,
      );
      expect(
        tracker.resolve(tourId: 'inferred-event', isKnockout: true),
        TournamentDetailLayout.individualKnockout,
      );
      expect(
        tracker.resolve(tourId: 'inferred-event'),
        TournamentDetailLayout.individualKnockout,
      );
    });

    test('team detection wins when both signals are supplied', () {
      expect(
        tournamentDetailLayoutForDetection(isTeam: true, isKnockout: true),
        TournamentDetailLayout.team,
      );
    });

    test('keeps a requested Bracket layout while detection is pending', () {
      final tracker = TournamentDetailLayoutTracker();

      expect(
        tracker.resolve(
          tourId: 'loading-knockout',
          isDetectionPending: true,
          unresolvedLayout: TournamentDetailLayout.individualKnockout,
        ),
        TournamentDetailLayout.individualKnockout,
      );
      expect(
        tracker.resolve(tourId: 'loading-knockout', isKnockout: true),
        TournamentDetailLayout.individualKnockout,
      );
    });

    test('team overrides remembered knockout and can never be downgraded', () {
      final tracker = TournamentDetailLayoutTracker();

      expect(
        tracker.resolve(tourId: 'team-cup', isKnockout: true),
        TournamentDetailLayout.individualKnockout,
      );
      expect(
        tracker.resolve(tourId: 'team-cup', isTeam: true, isKnockout: true),
        TournamentDetailLayout.team,
      );
      expect(
        tracker.resolve(tourId: 'team-cup', isKnockout: true),
        TournamentDetailLayout.team,
      );
    });
  });

  group('knockout stage metadata evidence', () {
    test('team format keeps precedence over knockout round metadata', () {
      expect(
        isIndividualKnockoutFromEvidence(
          isTeamEvent: true,
          explicitFormat: false,
          roundMetadata: true,
          inferredFromGames: false,
        ),
        isFalse,
      );
    });

    test('explicit regular format vetoes a Finals name', () {
      expect(
        hasTrustworthyKnockoutStageMetadata(
          rounds: const [],
          tourName: 'National League Finals',
        ),
        isTrue,
      );
      expect(
        isIndividualKnockoutFromEvidence(
          isTeamEvent: false,
          explicitFormat: false,
          explicitNonKnockoutFormat: true,
          roundMetadata: true,
          inferredFromGames: false,
        ),
        isFalse,
      );
    });

    test('accepts a decimal first leg before a second game is published', () {
      expect(
        hasTrustworthyKnockoutStageMetadata(
          rounds: [_metadataRound('r3-1', 'Round 3.1', 'round-31')],
          tourName: 'Turkish Cup',
        ),
        isTrue,
      );
    });

    test('accepts an empty stage-scoped tour', () {
      expect(
        hasTrustworthyKnockoutStageMetadata(
          rounds: const [],
          tourName: 'FIDE World Cup 2025 | Round 3',
        ),
        isTrue,
      );
    });

    test('accepts a generic leg when the tour names its stage', () {
      expect(
        hasTrustworthyKnockoutStageMetadata(
          rounds: [_metadataRound('g1', 'Game 1', 'game-1')],
          tourName: 'Invitational | Semifinals',
        ),
        isTrue,
      );
    });

    test('does not classify ordinary numbered rounds or generic games', () {
      expect(
        hasTrustworthyKnockoutStageMetadata(
          rounds: [_metadataRound('r3', 'Round 3', 'round-3')],
          tourName: 'Swiss Championship',
        ),
        isFalse,
      );
      expect(
        hasTrustworthyKnockoutStageMetadata(
          rounds: [_metadataRound('g1', 'Game 1', 'game-1')],
          tourName: 'Invitational',
        ),
        isFalse,
      );
    });
  });

  group('mode affordances', () {
    test('search is hidden on About and Bracket only', () {
      expect(
        tournamentDetailModeHasSearch(TournamentDetailScreenMode.about),
        isFalse,
      );
      expect(
        tournamentDetailModeHasSearch(TournamentDetailScreenMode.bracket),
        isFalse,
      );
      expect(
        tournamentDetailModeHasSearch(TournamentDetailScreenMode.games),
        isTrue,
      );
      expect(
        tournamentDetailModeHasSearch(TournamentDetailScreenMode.standings),
        isTrue,
      );
      expect(
        tournamentDetailModeHasSearch(TournamentDetailScreenMode.players),
        isTrue,
      );
    });

    test('search visibility interpolates around Bracket', () {
      expect(
        tournamentDetailSearchVisibility(knockoutTournamentDetailModes, 1),
        1,
      );
      expect(
        tournamentDetailSearchVisibility(knockoutTournamentDetailModes, 1.5),
        0.5,
      );
      expect(
        tournamentDetailSearchVisibility(knockoutTournamentDetailModes, 2),
        0,
      );
      expect(
        tournamentDetailSearchVisibility(knockoutTournamentDetailModes, 2.5),
        0.5,
      );
      expect(
        tournamentDetailSearchVisibility(knockoutTournamentDetailModes, 3),
        1,
      );
    });

    test('tab query helpers map every explicit mode', () {
      for (final mode in TournamentDetailScreenMode.values) {
        expect(
          tournamentDetailModeFromTabQuery(
            tournamentDetailTabQueryForMode(mode),
          ),
          mode,
        );
      }
      expect(
        tournamentDetailModeFromTabQuery(' BRACKET '),
        TournamentDetailScreenMode.bracket,
      );
      expect(tournamentDetailModeFromTabQuery('unknown'), isNull);
      expect(tournamentDetailModeFromTabQuery(null), isNull);
    });
  });
}

Round _metadataRound(String id, String name, String slug) => Round(
  id: id,
  slug: slug,
  tourId: 'tour',
  tourSlug: 'tour',
  name: name,
  createdAt: DateTime.utc(2026, 1, 1),
  startsAt: DateTime.utc(2026, 1, 1),
  url: 'https://lichess.org/broadcast/tour/$slug/$id',
);
