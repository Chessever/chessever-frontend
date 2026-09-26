import 'dart:convert';

import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/standings_builder.dart';
import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/screens/standings/utils/fide_rating_change.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

PlayerCard _player(int id, {int rating = 2400, String? team, double? points}) =>
    PlayerCard(
      name: 'Player $id',
      fideId: id,
      federation: '',
      title: 'GM',
      rating: rating,
      countryCode: '',
      team: team,
      customPoints: points,
    );

GamesTourModel _game(
  String id,
  int white,
  int black, {
  GameStatus result = GameStatus.ongoing,
  String? round,
  String tc = 'standard',
  String? pgn,
  int blackRating = 2400,
  String? whiteTeam,
  String? blackTeam,
  double? whitePoints,
  double? blackPoints,
}) => GamesTourModel(
  gameId: id,
  whitePlayer: _player(white, team: whiteTeam, points: whitePoints),
  blackPlayer: _player(
    black,
    rating: blackRating,
    team: blackTeam,
    points: blackPoints,
  ),
  whiteTimeDisplay: '',
  blackTimeDisplay: '',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: result,
  roundId: round ?? id,
  roundSlug: round ?? id,
  tourId: 'tour',
  timeControl: tc,
  pgn: pgn,
);

void main() {
  late SupabaseClient client;
  setUp(() {
    client = SupabaseClient(
      'https://example.test',
      'placeholder',
      httpClient: MockClient(
        (request) async => http.Response(
          '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
  });
  tearDown(() => client.dispose());

  Future<PlayerStandingModel> standing(
    List<GamesTourModel> games, {
    List<TournamentPlayer> source = const [],
  }) async => (await buildStandingsFromData(
    supabase: client,
    tournamentPlayers: source,
    gamesTourModels: games,
  )).singleWhere((p) => p.fideId == 1);

  test('Swiss results and corrections change both score and Elo', () async {
    final first = _game('r1', 1, 2, result: GameStatus.draw);
    final next = _game('r2', 1, 3);
    expect((await standing([first, next])).matchScore, '0.5 / 1');
    final won = await standing([
      first,
      next.copyWith(gameStatus: GameStatus.whiteWins),
    ]);
    expect(won.matchScore, '1.5 / 2');
    expect(won.scoreChange, 5);
    final corrected = await standing([
      first,
      next.copyWith(gameStatus: GameStatus.blackWins),
    ]);
    expect(corrected.matchScore, '0.5 / 2');
    expect(corrected.scoreChange, -5);
    expect((await standing([first, next])).scoreChange, 0);
  });

  test(
    'double round robin counts repeated opponents with reversed colours once per game',
    () async {
      final rounds = [
        _game('r1', 1, 2, result: GameStatus.whiteWins),
        _game('r2', 3, 1, result: GameStatus.draw),
        _game('r3', 2, 1, result: GameStatus.blackWins),
        _game('r4', 1, 3),
      ];
      expect((await standing(rounds)).matchScore, '2.5 / 3');
      final row = await standing([
        ...rounds.take(3),
        rounds.last.copyWith(gameStatus: GameStatus.whiteWins),
      ]);
      expect(row.matchScore, '3.5 / 4');
      expect(row.scoreChange, 15);
    },
  );

  test('knockout tiebreaks never combine standard and rapid Elo', () async {
    final row = await standing([
      _game(
        'final-1',
        1,
        2,
        result: GameStatus.draw,
        pgn: '[TimeControl "5400+30"]',
      ),
      _game(
        'final-2',
        2,
        1,
        result: GameStatus.draw,
        pgn: '[TimeControl "5400+30"]',
      ),
      // The group still says standard, but this game is a rapid tiebreak.
      _game(
        'final-tb',
        1,
        2,
        result: GameStatus.whiteWins,
        pgn: '[TimeControl "900+10"]',
      ),
    ]);
    expect(row.matchScore, '2 / 3');
    expect(row.hasRatingDiff, isFalse);
  });

  test(
    'team round robin waits for the last board and retracts match points on correction',
    () {
      final first = _game(
        'board1',
        1,
        2,
        round: 'r1',
        result: GameStatus.whiteWins,
        whiteTeam: 'A',
        blackTeam: 'B',
      );
      final last = _game(
        'board2',
        3,
        4,
        round: 'r1',
        whiteTeam: 'B',
        blackTeam: 'A',
      );
      final played = _game(
        'r2-board1',
        1,
        5,
        round: 'r2',
        result: GameStatus.draw,
        whiteTeam: 'A',
        blackTeam: 'C',
      );
      final boards = [first, played];
      final initial = buildTeamStandings(
        games: [...boards, last],
        playerStandings: [],
      );
      expect(initial.singleWhere((t) => t.teamName == 'A').matchPoints, 1);
      final completed = buildTeamStandings(
        games: [
          ...boards,
          last.copyWith(gameStatus: GameStatus.draw),
        ],
        playerStandings: [],
      );
      final a = completed.singleWhere((t) => t.teamName == 'A');
      expect(a.matchPoints, 3);
      expect(a.gamePoints, 2);
      final retracted = buildTeamStandings(
        games: [...boards, last],
        playerStandings: [],
      );
      expect(retracted.singleWhere((t) => t.teamName == 'A').matchPoints, 1);
    },
  );

  test(
    'custom scoring and Armageddon count points without inventing rated games',
    () async {
      final row = await standing([
        _game(
          'classical',
          1,
          2,
          result: GameStatus.whiteWins,
          whitePoints: 3,
          blackPoints: 0,
        ),
        _game(
          'bonus',
          1,
          2,
          round: 'r1-armageddon',
          result: GameStatus.whiteWins,
          whitePoints: 0.5,
          blackPoints: 0,
        ),
      ]);
      expect(row.matchScore, '3.5 / 2');
      expect(row.hasRatingDiff, isFalse);
    },
  );

  test(
    'source score, awarded points and zero Elo stay authoritative',
    () async {
      final row = await standing(
        [_game('r1', 1, 2, result: GameStatus.whiteWins)],
        source: [
          TournamentPlayer(
            name: 'Player 1',
            fideId: 1,
            played: 2,
            score: 4.5,
            ratingDiff: 0,
            rank: 1,
          ),
        ],
      );
      expect(row.matchScore, '4.5 / 2');
      expect(row.scoreChange, 0);
      expect(row.hasRatingDiff, isTrue);
      expect(PlayerStandingModel.fromJson(row.toJson()).hasRatingDiff, isTrue);
    },
  );

  test(
    'missing opponent rating makes the event Elo unavailable, not a partial sum',
    () async {
      final row = await standing([
        _game('r1', 1, 2, result: GameStatus.whiteWins),
        _game('r2', 1, 3, result: GameStatus.whiteWins, blackRating: 0),
      ]);
      expect(row.matchScore, '2 / 2');
      expect(row.hasRatingDiff, isFalse);
      expect(PlayerStandingModel.fromJson(row.toJson()).hasRatingDiff, isFalse);
    },
  );

  test(
    'rapid and blitz fallbacks use the same selected-rating K as the report',
    () async {
      for (final tc in ['rapid', 'blitz']) {
        final row = await standing([
          _game('r1', 1, 2, tc: tc, result: GameStatus.whiteWins),
        ]);
        expect(
          row.scoreChange,
          calculateFideRatingChange(
            playerRating: 2400,
            opponentRating: 2400,
            actualScore: 1,
            kFactor: scoreCardFallbackKFactorForSelectedRating(
              2400,
              timeControl: tc,
            ),
          ).round(),
        );
      }
    },
  );

  test(
    'a partial catalog cannot supply the missing source Elo total',
    () async {
      final row = await standing(
        [_game('r1', 1, 2, result: GameStatus.whiteWins)],
        source: [
          TournamentPlayer(name: 'Player 1', fideId: 1, played: 9, score: 6.5),
        ],
      );
      expect(row.matchScore, '6.5 / 9');
      expect(row.hasRatingDiff, isFalse);
    },
  );

  test('published event ratings survive a newer monthly FIDE list', () async {
    final differentList = SupabaseClient(
      'https://example.test',
      'placeholder',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode([
            {'fideid': 1, 'rating': 2250, 'k': 40},
            {'fideid': 2, 'rating': 2150, 'k': 20},
          ]),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    final rows = await buildStandingsFromData(
      supabase: differentList,
      tournamentPlayers: [],
      gamesTourModels: [_game('r1', 1, 2, result: GameStatus.whiteWins)],
    );
    expect(rows.singleWhere((p) => p.fideId == 1).scoreChange, 20);
    await differentList.dispose();
  });

  test(
    'standings snapshots ignore clocks but include rating, team, and custom-point corrections',
    () {
      Map<String, dynamic> row({
        int clock = 100,
        int rating = 2400,
        String team = 'A',
        double points = 1,
      }) => {
        'id': 'g',
        'round_id': 'r',
        'round_slug': 'r',
        'tour_id': 'tour',
        'tour_slug': 'tour',
        'status': '1-0',
        'players': [
          {
            'name': 'Player 1',
            'rating': rating,
            'team': team,
            'clock': clock,
            'customPoints': points,
          },
          {'name': 'Player 2', 'rating': 2400, 'team': 'B', 'clock': 100},
        ],
      };
      final original = Games.fromJson(row());
      final clockOnly = TourGameSafetyNetSnapshot.fromJson(row(clock: 99));
      expect(clockOnly.differsFrom(original), isFalse);
      final before = standingsGamesSignature(AsyncValue.data([original]));
      for (final corrected in [
        row(rating: 2300),
        row(team: 'C'),
        row(points: 3),
      ]) {
        final snapshot = TourGameSafetyNetSnapshot.fromJson(corrected);
        expect(snapshot.differsFrom(original), isTrue);
        expect(
          standingsGamesSignature(
            AsyncValue.data([snapshot.mergeInto(original)]),
          ),
          isNot(before),
        );
      }
    },
  );
}
