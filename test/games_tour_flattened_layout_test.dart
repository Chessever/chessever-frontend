import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_display_rounds.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_flattened_layout.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('selectGamesTourDisplayRounds', () {
    test('keeps every populated upcoming synthetic stage', () {
      final quarterfinals = _round(
        'knockout-stage-quarterfinals',
        RoundStatus.completed,
      );
      final semifinals = _round(
        'knockout-stage-semifinals',
        RoundStatus.upcoming,
      );

      final visible = selectGamesTourDisplayRounds(
        rounds: [semifinals, quarterfinals],
        effectiveRounds: [semifinals, quarterfinals],
        gamesByRound: {
          quarterfinals.id: [_game('qf-1')],
          semifinals.id: [_game('sf-1')],
        },
        upcomingPairingRoundIds: const {},
        isSearchMode: false,
        isMultiStageKnockout: true,
      );

      expect(visible.map((round) => round.id), [
        semifinals.id,
        quarterfinals.id,
      ]);
    });
  });

  group('buildGamesTourFlattenedLayout', () {
    test('reversed-color legs produce one canonical match header', () {
      final round = _round('knockout-stage-quarterfinals', RoundStatus.live);
      final games = [
        _game('leg-1', slug: 'game-1'),
        _game('leg-2', reverseColors: true, slug: 'game-2'),
      ];

      final layout = _layout(rounds: [round], gamesByRound: {round.id: games});

      expect(
        layout.entries.whereType<GamesTourMatchHeaderEntry>(),
        hasLength(1),
      );
      expect(layout.itemIndexForGameId('leg-1'), 2);
      expect(layout.itemIndexForGameId('leg-2'), 3);
    });

    test('collapsed round and match shift the next header exactly', () {
      final first = _round(
        'knockout-stage-quarterfinals',
        RoundStatus.completed,
      );
      final second = _round('knockout-stage-semifinals', RoundStatus.live);
      final gamesByRound = {
        first.id: [
          _game('qf-1', slug: 'game-1'),
          _game('qf-2', reverseColors: true, slug: 'game-2'),
        ],
        second.id: [
          _game('sf-1', slug: 'game-1', identityOffset: 100),
          _game(
            'sf-2',
            reverseColors: true,
            slug: 'game-2',
            identityOffset: 100,
          ),
        ],
      };

      final collapsedRound = _layout(
        rounds: [first, second],
        gamesByRound: gamesByRound,
        roundExpansionState: {first.id: false},
      );
      expect(collapsedRound.roundHeaderIndex(first.id), 0);
      expect(collapsedRound.roundHeaderIndex(second.id), 1);
      expect(collapsedRound.itemIndexForGameId('qf-1'), isNull);

      final firstMatchKey =
          _layout(
            rounds: [first],
            gamesByRound: {first.id: gamesByRound[first.id]!},
          ).matchGroupsByRound[first.id]!.keys.single;
      final collapsedMatch = _layout(
        rounds: [first, second],
        gamesByRound: gamesByRound,
        matchExpansionState: {firstMatchKey: false},
      );
      expect(collapsedMatch.roundHeaderIndex(second.id), 2);
      expect(collapsedMatch.itemIndexForGameId('qf-1'), isNull);
      expect(collapsedMatch.itemIndexForGameId('sf-1'), isNotNull);
    });

    test('grid filtering maps both visible games to their actual row', () {
      final round = _round('knockout-stage-finals', RoundStatus.live);
      final games = [
        _game('live-1', slug: 'game-1'),
        _game('live-2', reverseColors: true, slug: 'game-2'),
        _game('finished', slug: 'tiebreak-1-rapid-1', status: GameStatus.draw),
      ];

      final layout = _layout(
        rounds: [round],
        gamesByRound: {round.id: games},
        mode: GamesListViewMode.chessBoardGrid,
        displayMode: GameDisplayMode.hideFinishedGames,
      );

      expect(layout.itemIndexForGameId('live-1'), 2);
      expect(layout.itemIndexForGameId('live-2'), 2);
      expect(layout.firstGameIdAt(2), 'live-1');
      expect(layout.itemIndexForGameId('finished'), isNull);
      expect(layout.itemCount, 3);
    });
  });

  test('group-event spans omit cards when the round is collapsed', () {
    expect(
      groupEventRoundListItemCount(isExpanded: true, matchupCardCount: 3),
      4,
    );
    expect(
      groupEventRoundListItemCount(isExpanded: false, matchupCardCount: 3),
      1,
    );
  });

  test('empty sibling loading never covers an already loaded stage', () {
    expect(
      shouldKeepGroupedGamesLoading(
        representedSiblingIsLoading: true,
        hasGroupedGames: false,
      ),
      isTrue,
    );
    expect(
      shouldKeepGroupedGamesLoading(
        representedSiblingIsLoading: true,
        hasGroupedGames: true,
      ),
      isFalse,
    );
  });
}

GamesTourFlattenedLayout _layout({
  required List<GamesAppBarModel> rounds,
  required Map<String, List<GamesTourModel>> gamesByRound,
  GamesListViewMode mode = GamesListViewMode.gamesCard,
  Map<String, bool> matchExpansionState = const {},
  Map<String, bool> roundExpansionState = const {},
  GameDisplayMode displayMode = GameDisplayMode.all,
}) => buildGamesTourFlattenedLayout(
  rounds: rounds,
  gamesByRound: gamesByRound,
  mode: mode,
  matchExpansionState: matchExpansionState,
  roundExpansionState: roundExpansionState,
  isKnockoutTournament: true,
  displayMode: displayMode,
);

GamesAppBarModel _round(String id, RoundStatus status) =>
    GamesAppBarModel(id: id, name: id, startsAt: null, roundStatus: status);

GamesTourModel _game(
  String id, {
  bool reverseColors = false,
  String slug = 'game-1',
  GameStatus status = GameStatus.ongoing,
  int identityOffset = 0,
}) {
  final alpha = _player(
    'GM Alpha Player $identityOffset',
    11 + identityOffset,
    2700,
  );
  final beta = _player(
    'Beta Player $identityOffset',
    22 + identityOffset,
    2600,
  );
  return GamesTourModel(
    gameId: id,
    whitePlayer: reverseColors ? beta : alpha,
    blackPlayer: reverseColors ? alpha : beta,
    whiteTimeDisplay: '',
    blackTimeDisplay: '',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: status,
    roundId: slug,
    roundSlug: slug,
    tourId: 'tour',
  );
}

PlayerCard _player(String name, int fideId, int rating) => PlayerCard(
  name: name,
  federation: 'FIDE',
  title: '',
  rating: rating,
  countryCode: 'FIDE',
  team: null,
  fideId: fideId,
);
