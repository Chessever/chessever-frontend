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
        quarterfinals.id,
        semifinals.id,
      ]);
    });

    test('promotes the next ready pairing at the two-hour boundary', () {
      final now = DateTime(2026, 7, 13, 12);
      final round1 = _round(
        'r1',
        RoundStatus.completed,
        startsAt: now.subtract(const Duration(hours: 4)),
      );
      final round2 = _round(
        'r2',
        RoundStatus.completed,
        startsAt: now.subtract(const Duration(hours: 2)),
      );
      final round3 = _round(
        'r3',
        RoundStatus.upcoming,
        startsAt: now.add(const Duration(hours: 2)),
      );
      final round4 = _round(
        'r4',
        RoundStatus.upcoming,
        startsAt: now.add(const Duration(hours: 3)),
      );

      final visible = selectGamesTourDisplayRounds(
        rounds: [round4, round2, round3, round1],
        effectiveRounds: [round4, round2, round3, round1],
        gamesByRound: {
          round1.id: [_game('finished-1', status: GameStatus.draw)],
          round2.id: [_game('finished-2', status: GameStatus.draw)],
          round3.id: [_game('pairing-3')],
          round4.id: [_game('pairing-4')],
        },
        upcomingPairingRoundIds: {round3.id, round4.id},
        isSearchMode: false,
        isMultiStageKnockout: false,
        now: now,
      );

      expect(visible.map((round) => round.id), ['r3', 'r2', 'r1', 'r4']);
    });

    test('does not promote an upcoming round before its boards are ready', () {
      final now = DateTime(2026, 7, 13, 12);
      final completed = _round(
        'r1',
        RoundStatus.completed,
        startsAt: now.subtract(const Duration(hours: 2)),
      );
      final awaitingBoards = _round(
        'r2',
        RoundStatus.upcoming,
        startsAt: now.add(const Duration(minutes: 90)),
      );

      final visible = selectGamesTourDisplayRounds(
        rounds: [awaitingBoards, completed],
        effectiveRounds: [awaitingBoards, completed],
        gamesByRound: {
          completed.id: [_game('finished', status: GameStatus.draw)],
          awaitingBoards.id: const <GamesTourModel>[],
        },
        upcomingPairingRoundIds: {awaitingBoards.id},
        isSearchMode: false,
        isMultiStageKnockout: false,
        now: now,
      );

      expect(visible.map((round) => round.id), ['r1', 'r2']);
    });

    test('keeps future pairings last while a played round is unfinished', () {
      final now = DateTime(2026, 7, 13, 12);
      final completed = _round(
        'r1',
        RoundStatus.completed,
        startsAt: now.subtract(const Duration(hours: 4)),
      );
      final ongoing = _round(
        'r2',
        RoundStatus.ongoing,
        startsAt: now.subtract(const Duration(hours: 2)),
      );
      final next = _round(
        'r3',
        RoundStatus.upcoming,
        startsAt: now.add(const Duration(minutes: 30)),
      );
      final later = _round(
        'r4',
        RoundStatus.upcoming,
        startsAt: now.add(const Duration(hours: 2)),
      );

      final visible = selectGamesTourDisplayRounds(
        rounds: [next, completed, later, ongoing],
        effectiveRounds: [next, completed, later, ongoing],
        gamesByRound: {
          completed.id: [_game('finished', status: GameStatus.draw)],
          ongoing.id: [_game('ongoing')],
          next.id: [_game('pairing-next')],
          later.id: [_game('pairing-later')],
        },
        upcomingPairingRoundIds: {next.id, later.id},
        isSearchMode: false,
        isMultiStageKnockout: false,
        now: now,
      );

      expect(visible.map((round) => round.id), ['r2', 'r1', 'r3', 'r4']);
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
      // Boards render latest-first inside the matchup: leg 2 above leg 1.
      expect(layout.itemIndexForGameId('leg-2'), 2);
      expect(layout.itemIndexForGameId('leg-1'), 3);
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

    test('collapsed knockout matchups render latest-first by round start', () {
      final stage = _round('knockout-stage-round-of-16', RoundStatus.completed);
      // Eight-matchup RO16 collapsed into one stage. Two matchups share each
      // calendar day, so ordering must fall back to the round start TIME, which
      // the date-granular game rows cannot supply.
      final games = [
        _game('ju', identityOffset: 0, roundId: 'r-ju'), // 07-06 14:00
        _game('vaishali', identityOffset: 100, roundId: 'r-vaishali'), // 07-06 16:30
        _game('hou', identityOffset: 200, roundId: 'r-hou'), // 07-13 12:00
        _game('polina', identityOffset: 300, roundId: 'r-polina'), // 07-13 14:30
      ];

      final layout = _layout(
        rounds: [stage],
        gamesByRound: {stage.id: games},
        roundStartTimesById: {
          'r-ju': DateTime.utc(2026, 7, 6, 14, 0),
          'r-vaishali': DateTime.utc(2026, 7, 6, 16, 30),
          'r-hou': DateTime.utc(2026, 7, 13, 12, 0),
          'r-polina': DateTime.utc(2026, 7, 13, 14, 30),
        },
      );

      final matchupOrder =
          layout.entries
              .whereType<GamesTourGameRowEntry>()
              .map((entry) => entry.game1.gameId)
              .toList();

      // Descending datetime: latest day first, same-day tie broken by time.
      expect(matchupOrder, ['polina', 'hou', 'vaishali', 'ju']);

      // Every matchup card carries the exact datetime the sort used, so the
      // rendered order is verifiable at a glance.
      final playedAts =
          layout.entries
              .whereType<GamesTourMatchHeaderEntry>()
              .map((entry) => entry.matchHeader.playedAt)
              .toList();
      expect(playedAts, [
        DateTime.utc(2026, 7, 13, 14, 30),
        DateTime.utc(2026, 7, 13, 12, 0),
        DateTime.utc(2026, 7, 6, 16, 30),
        DateTime.utc(2026, 7, 6, 14, 0),
      ]);
    });

    test('actual play time outranks a stale scheduled start', () {
      final stage = _round('knockout-stage-round-of-16', RoundStatus.completed);
      // The "postponed matchup" shape: scheduled for the earlier slot but
      // actually streamed a day later, while the broadcast's starts_at was
      // never corrected. The live-streamed lastMoveTime must win.
      final games = [
        _game(
          'postponed',
          identityOffset: 0,
          roundId: 'r-postponed',
          lastMoveTime: DateTime.utc(2026, 7, 11, 20, 14),
        ),
        _game('on-schedule', identityOffset: 100, roundId: 'r-on-schedule'),
      ];

      final layout = _layout(
        rounds: [stage],
        gamesByRound: {stage.id: games},
        roundStartTimesById: {
          'r-postponed': DateTime.utc(2026, 7, 10, 14, 0),
          'r-on-schedule': DateTime.utc(2026, 7, 10, 16, 30),
        },
      );

      final matchupOrder =
          layout.entries
              .whereType<GamesTourGameRowEntry>()
              .map((entry) => entry.game1.gameId)
              .toList();

      expect(matchupOrder, ['postponed', 'on-schedule']);
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
      // Latest-first inside the matchup: game 2 leads the row.
      expect(layout.firstGameIdAt(2), 'live-2');
      expect(layout.itemIndexForGameId('finished'), isNull);
      expect(layout.itemCount, 3);
    });

    test('live board floats above boards that finished after its last move', () {
      final stage = _round('knockout-stage-semifinals', RoundStatus.live);
      // Matchup-labeled feed (speed-championship shape): every game of the
      // matchup shares one round slug, so slug order ties everywhere and only
      // status plus actual play time can rank the boards. The live board must
      // hold the top even while other boards finish after its last move.
      final games = [
        _game(
          'finished-late',
          slug: 'semifinals',
          status: GameStatus.whiteWins,
          lastMoveTime: DateTime.utc(2026, 7, 15, 20, 0),
        ),
        _game(
          'live',
          slug: 'semifinals',
          lastMoveTime: DateTime.utc(2026, 7, 15, 19, 30),
        ),
        _game(
          'finished-early',
          slug: 'semifinals',
          status: GameStatus.draw,
          lastMoveTime: DateTime.utc(2026, 7, 15, 18, 0),
        ),
      ];

      final layout = _layout(rounds: [stage], gamesByRound: {stage.id: games});

      final boardOrder =
          layout.entries
              .whereType<GamesTourGameRowEntry>()
              .map((entry) => entry.game1.gameId)
              .toList();
      expect(boardOrder, ['live', 'finished-late', 'finished-early']);
    });

    test('matchup with a live board outranks matchups that finished later', () {
      final stage = _round('knockout-stage-semifinals', RoundStatus.live);
      final games = [
        _game(
          'finished',
          identityOffset: 0,
          roundId: 'r-finished',
          status: GameStatus.blackWins,
          lastMoveTime: DateTime.utc(2026, 7, 15, 20, 0),
        ),
        _game(
          'live',
          identityOffset: 100,
          roundId: 'r-live',
          lastMoveTime: DateTime.utc(2026, 7, 15, 19, 30),
        ),
      ];

      final layout = _layout(rounds: [stage], gamesByRound: {stage.id: games});

      final matchupOrder =
          layout.entries
              .whereType<GamesTourGameRowEntry>()
              .map((entry) => entry.game1.gameId)
              .toList();
      expect(matchupOrder, ['live', 'finished']);
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

  test('priority refresh keeps loading when only new boards are visible', () {
    expect(
      shouldKeepPrioritySnapshotLoading(
        isSearchMode: false,
        hadGroupedGamesBeforeOrdering: true,
        hasGroupedGamesAfterOrdering: false,
        hasResolvedAutoPins: true,
        isRefreshingAutoPins: true,
      ),
      isTrue,
    );
    expect(
      shouldKeepPrioritySnapshotLoading(
        isSearchMode: false,
        hadGroupedGamesBeforeOrdering: true,
        hasGroupedGamesAfterOrdering: true,
        hasResolvedAutoPins: true,
        isRefreshingAutoPins: true,
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
  Map<String, DateTime?> roundStartTimesById = const {},
}) => buildGamesTourFlattenedLayout(
  rounds: rounds,
  gamesByRound: gamesByRound,
  mode: mode,
  matchExpansionState: matchExpansionState,
  roundExpansionState: roundExpansionState,
  isKnockoutTournament: true,
  displayMode: displayMode,
  roundStartTimesById: roundStartTimesById,
);

GamesAppBarModel _round(String id, RoundStatus status, {DateTime? startsAt}) =>
    GamesAppBarModel(id: id, name: id, startsAt: startsAt, roundStatus: status);

GamesTourModel _game(
  String id, {
  bool reverseColors = false,
  String slug = 'game-1',
  GameStatus status = GameStatus.ongoing,
  int identityOffset = 0,
  String? roundId,
  DateTime? lastMoveTime,
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
    roundId: roundId ?? slug,
    roundSlug: slug,
    tourId: 'tour',
    lastMoveTime: lastMoveTime,
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
