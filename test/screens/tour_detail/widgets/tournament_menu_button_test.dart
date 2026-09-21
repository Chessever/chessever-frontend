import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/widgets/tournament_menu_button.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('liveFocusOrderingMenuLabel', () {
    test('off-state live-focus menu label is Live games first', () {
      expect(kLiveGamesFirstMenuLabel, 'Live games first');
      expect(
        liveFocusOrderingMenuLabel(isFocusingLiveGames: false),
        'Live games first',
      );
    });

    test('on-state live-focus menu label is Board order', () {
      expect(kBoardOrderMenuLabel, 'Board order');
      expect(
        liveFocusOrderingMenuLabel(isFocusingLiveGames: true),
        'Board order',
      );
    });
  });

  group('standingsShareActionsFor', () {
    test('games tab never includes standings share actions', () {
      expect(
        standingsShareActionsFor(
          mode: TournamentDetailScreenMode.games,
          isTeamEvent: false,
        ),
        isEmpty,
      );
      expect(
        standingsShareActionsFor(
          mode: TournamentDetailScreenMode.games,
          isTeamEvent: true,
        ),
        isEmpty,
      );
    });

    test('about and bracket tabs never include standings share actions', () {
      for (final mode in [
        TournamentDetailScreenMode.about,
        TournamentDetailScreenMode.bracket,
      ]) {
        expect(
          standingsShareActionsFor(mode: mode, isTeamEvent: false),
          isEmpty,
        );
        expect(
          standingsShareActionsFor(mode: mode, isTeamEvent: true),
          isEmpty,
        );
      }
    });

    test('non-team standings tab shows Share standings only', () {
      expect(
        standingsShareActionsFor(
          mode: TournamentDetailScreenMode.standings,
          isTeamEvent: false,
        ),
        [TournamentMenuAction.shareStandings],
      );
    });

    test('team standings tab shows Share team standings only', () {
      expect(
        standingsShareActionsFor(
          mode: TournamentDetailScreenMode.standings,
          isTeamEvent: true,
        ),
        [TournamentMenuAction.shareTeamStandings],
      );
    });

    test('team players tab (individual table) shows Share standings only', () {
      expect(
        standingsShareActionsFor(
          mode: TournamentDetailScreenMode.players,
          isTeamEvent: true,
        ),
        [TournamentMenuAction.shareStandings],
      );
    });

    test('players mode on non-team events shows nothing (tab not used)', () {
      expect(
        standingsShareActionsFor(
          mode: TournamentDetailScreenMode.players,
          isTeamEvent: false,
        ),
        isEmpty,
      );
    });
  });

  group('areAllVisibleSectionsCollapsed', () {
    test('treats unvisited rounds as collapsed by default', () {
      expect(
        areAllVisibleSectionsCollapsed(
          visibleRoundIds: const ['round-1', 'round-2'],
          visibleMatchKeys: const [],
          roundExpansionState: const {},
          matchExpansionState: const {},
        ),
        isTrue,
      );
    });

    test('returns true when every visible round is collapsed', () {
      expect(
        areAllVisibleSectionsCollapsed(
          visibleRoundIds: const ['round-1', 'round-2'],
          visibleMatchKeys: const [],
          roundExpansionState: const {'round-1': false, 'round-2': false},
          matchExpansionState: const {},
        ),
        isTrue,
      );
    });

    test('collapsed parents hide remembered expanded knockout matches', () {
      expect(
        areAllVisibleSectionsCollapsed(
          visibleRoundIds: const ['round-1'],
          visibleMatchKeys: const ['match-a'],
          roundExpansionState: const {'round-1': false},
          matchExpansionState: const {},
        ),
        isTrue,
      );

      expect(
        areAllVisibleSectionsCollapsed(
          visibleRoundIds: const ['round-1'],
          visibleMatchKeys: const ['match-a'],
          roundExpansionState: const {'round-1': false},
          matchExpansionState: const {'match-a': false},
        ),
        isTrue,
      );
    });

    test('standalone match sections still use their own expansion state', () {
      expect(
        areAllVisibleSectionsCollapsed(
          visibleRoundIds: const [],
          visibleMatchKeys: const ['match-a'],
          roundExpansionState: const {},
          matchExpansionState: const {},
        ),
        isFalse,
      );
      expect(
        areAllVisibleSectionsCollapsed(
          visibleRoundIds: const [],
          visibleMatchKeys: const ['match-a'],
          roundExpansionState: const {},
          matchExpansionState: const {'match-a': false},
        ),
        isTrue,
      );
    });
  });
}
