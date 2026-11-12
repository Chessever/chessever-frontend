import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_provider.dart';
import 'package:chessever2/screens/chessboard/game_review/server_game_report.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The wire contract with the `chessever-analysis` Worker.
///
/// `test/fixtures/server_game_report.json` is a real response captured from the
/// service, not a hand-written approximation — a fixture someone wrote from the
/// docs would keep passing after the server changed shape, which is the one
/// failure this test exists to catch.
void main() {
  late Map<String, dynamic> payload;
  late ChessGame game;

  const pgn = '1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0';

  setUp(() {
    payload =
        jsonDecode(
              File('test/fixtures/server_game_report.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    game = ChessGame.fromPgn('test', pgn);
  });

  test('a real server response rebuilds into a report', () {
    final report = gameAnalysisReportFromServerJson(payload, game: game);

    expect(report.fingerprint, gameReportFingerprint(game));
    expect(report.moves, hasLength(game.mainline.length));
    // One evaluation per position, starting position included.
    expect(report.positions, hasLength(game.mainline.length + 1));
    expect(report.whiteAccuracy, closeTo(88.27, 0.01));
    expect(report.blackAccuracy, closeTo(21.81, 0.01));
    expect(report.whiteEstimatedRating, 1920);
    expect(report.blackEstimatedRating, 362);
  });

  test('classifications survive the round trip by name', () {
    final report = gameAnalysisReportFromServerJson(payload, game: game);
    final byPly = {for (final move in report.moves) move.ply: move};

    // The opening is theory, Qh5 is punished, and Nf6 walks into mate.
    expect(byPly[1]!.classification, GameMoveClassification.bookMove);
    expect(byPly[4]!.classification, GameMoveClassification.bookMove);
    expect(byPly[5]!.classification, GameMoveClassification.inaccuracy);
    expect(byPly[6]!.classification, GameMoveClassification.blunder);
    // Null is a real value: the mating move itself earns no named category.
    expect(byPly[7]!.classification, isNull);
  });

  test(
    'optional game-story metadata does not change the existing report parser',
    () {
      final original = gameAnalysisReportFromServerJson(payload, game: game);
      for (final metadata in [
        null,
        {
          'version': 1,
          'result': '1-0',
          'primary': 'one_blunder',
          'tags': ['one_blunder', 'miniature'],
          'moves': 4,
        },
      ]) {
        final enriched = gameAnalysisReportFromServerJson({
          ...payload,
          'gameClassification': metadata,
        }, game: game);
        expect(enriched.fingerprint, original.fingerprint);
        expect(enriched.whiteAccuracy, original.whiteAccuracy);
        expect(enriched.blackAccuracy, original.blackAccuracy);
        expect(
          enriched.moves.map((m) => m.classification),
          original.moves.map((m) => m.classification),
        );
        expect(
          enriched.positions.map((p) => p.fen),
          original.positions.map((p) => p.fen),
        );
      }
    },
  );

  test('mate scores and centipawns are kept apart', () {
    final report = gameAnalysisReportFromServerJson(payload, game: game);
    final byPly = {for (final move in report.moves) move.ply: move};

    expect(byPly[1]!.evaluation.centipawns, 32);
    expect(byPly[1]!.evaluation.mate, isNull);
    expect(byPly[1]!.evaluation.depth, 14);

    // A forced mate has no centipawn value, and reading one as the other would
    // put a mate on the evaluation graph as a ~0.01 pawn edge.
    expect(byPly[6]!.evaluation.mate, 1);
    expect(byPly[6]!.evaluation.centipawns, isNull);
  });

  test('a report for a different game is refused, not adapted', () {
    // Everything downstream — badges, graph, PGN export — is keyed on the
    // fingerprint, so accepting a mismatch would paint one game's verdicts onto
    // another rather than fail.
    final otherGame = ChessGame.fromPgn('other', '1. d4 d5 2. c4 e6 *');

    expect(
      () => gameAnalysisReportFromServerJson(payload, game: otherGame),
      throwsA(isA<ServerGameReportException>()),
    );
  });

  test('a truncated report is refused', () {
    final short = Map<String, dynamic>.from(payload);
    short['moves'] = (payload['moves'] as List).sublist(0, 3);

    expect(
      () => gameAnalysisReportFromServerJson(short, game: game),
      throwsA(isA<ServerGameReportException>()),
    );
  });

  test('the response carries the report back in the PGN', () {
    // How a report already travels between ChessEver clients: the ChessEver
    // `$240`-`$247` NAG beside the standard glyph.
    final returnedPgn = payload['pgn'] as String;
    expect(returnedPgn, contains(r'$247')); // book
    expect(returnedPgn, contains(r'$246')); // blunder
  });

  test('a report backed by official Lichess analysis still rebuilds', () {
    // Such a report has no engine or search block, no evaluation for the
    // starting position, no search depth or line anywhere, and extra keys on
    // every position and move. Reshaped here from the captured response
    // rather than stored: the real ones are other people's games.
    Map<String, dynamic> sourceEvaluation(Object? evaluation) => {
      ...evaluation as Map<String, dynamic>,
      'depth': null,
      'moves': <String>[],
    };
    final positions = (payload['positions'] as List)
        .cast<Map<String, dynamic>>();
    final lichess = <String, dynamic>{
      ...payload,
      'source': 'lichess',
      'engine': null,
      'search': null,
      'provenance': {'provider': 'lichess', 'coverage': 'complete'},
      'positions': [
        {
          'fen': positions.first['fen'],
          'evaluation': null,
          'winPercentage': null,
          'provenance': 'lichess_initial_policy',
        },
        for (final raw in positions.skip(1))
          {
            ...raw,
            'evaluation': sourceEvaluation(raw['evaluation']),
            'provenance': 'lichess',
          },
      ],
      'moves': [
        for (final raw
            in (payload['moves'] as List).cast<Map<String, dynamic>>())
          {
            ...raw,
            'evaluation': sourceEvaluation(raw['evaluation']),
            'evidence': {'evaluation': 'lichess', 'book': 'gamebase'},
          },
      ],
    };

    final original = gameAnalysisReportFromServerJson(payload, game: game);
    final report = gameAnalysisReportFromServerJson(lichess, game: game);

    expect(report.moves, hasLength(game.mainline.length));
    expect(report.positions, hasLength(game.mainline.length + 1));
    expect(
      report.moves.map((move) => move.classification),
      original.moves.map((move) => move.classification),
    );
    expect(
      report.moves.map((move) => move.evaluation.centipawns),
      original.moves.map((move) => move.evaluation.centipawns),
    );
    expect(
      report.moves.map((move) => move.evaluation.mate),
      original.moves.map((move) => move.evaluation.mate),
    );
    // No score for the starting position reads as "no information", and an
    // unknown depth as zero, never as a failure.
    expect(report.positions.first.bestLine.centipawns, isNull);
    expect(report.positions.first.bestLine.mate, isNull);
    expect(report.moves.map((move) => move.evaluation.depth), everyElement(0));
    expect(report.whiteAccuracy, original.whiteAccuracy);
    expect(report.blackAccuracy, original.blackAccuracy);
  });

  group('the game id in the report request', () {
    /// Runs one report through the controller-facing runner against a stub
    /// Worker and returns the body it posted. The stub answers the create call
    /// with a finished job, so nothing waits on a poll.
    Future<Map<String, dynamic>> postedBody({String? gameId}) async {
      Map<String, dynamic>? body;
      final runner = serverGameReportRunner(
        gameId: gameId,
        clientFactory: () => ServerGameReportClient(
          baseUrl: 'https://analysis.test',
          accessToken: () => 'token',
          httpClient: MockClient((request) async {
            if (request.method == 'POST') {
              expect(request.url.path, '/v1/reports');
              body = jsonDecode(request.body) as Map<String, dynamic>;
              return http.Response(
                '{"id":"job-1","status":"succeeded","progress":1}',
                200,
              );
            }
            expect(request.url.path, '/v1/reports/job-1/result');
            return http.Response.bytes(utf8.encode(jsonEncode(payload)), 200);
          }),
        ),
      )!;
      final report = await runner(
        game,
        onProgress: (_, _) {},
        isCancelled: () => false,
      );
      expect(report.moves, hasLength(game.mainline.length));
      return body!;
    }

    test('is sent for every id shape the games table holds', () async {
      for (final id in const [
        'GLT6Si5W',
        'chess.com:181569501439',
        '0kWCULYV-13etm2g',
        'gb_0000c846-df42-4105-bb7a-c01a82e4b80f',
      ]) {
        final body = await postedBody(gameId: id);
        expect(body['gameId'], id, reason: id);
        expect(body['pgn'], contains('Qxf7#'), reason: id);
      }
    });

    test('is left out when the game has none', () async {
      expect(await postedBody(), isNot(contains('gameId')));
    });

    test('is left out when it cannot be a games id', () async {
      // The Worker would only drop these, and an id with a space or a slash is
      // one of the app's own (a virtual gamebase event, an import), never a
      // row.
      for (final id in [
        '',
        ' ',
        'GLT6Si5W ',
        'GLT6Si5W\n',
        'gamebase::Tata Steel 2026',
        'games/GLT6Si5W',
        'a' * 65,
      ]) {
        expect(
          await postedBody(gameId: id),
          isNot(contains('gameId')),
          reason: '"$id"',
        );
      }
    });

    test('comes only from a board opened on a broadcast game', () {
      GamesTourModel board(String id, GameSource source) {
        PlayerCard player(String name) => PlayerCard(
          name: name,
          federation: '',
          title: '',
          rating: 0,
          countryCode: '',
          team: null,
        );
        return GamesTourModel(
          gameId: id,
          source: source,
          whitePlayer: player('White'),
          blackPlayer: player('Black'),
          whiteTimeDisplay: '--:--',
          blackTimeDisplay: '--:--',
          whiteClockCentiseconds: 0,
          blackClockCentiseconds: 0,
          gameStatus: GameStatus.whiteWins,
          roundId: 'round',
          tourId: 'tour',
        );
      }

      expect(
        reportDatabaseGameId(board('GLT6Si5W', GameSource.supabase)),
        'GLT6Si5W',
      );
      // Every other source carries an id of the app's own making, which names
      // no row even when it happens to look like one.
      for (final source in GameSource.values) {
        if (source == GameSource.supabase) continue;
        expect(
          reportDatabaseGameId(board('GLT6Si5W', source)),
          isNull,
          reason: source.name,
        );
      }
    });
  });

  group('the poll delay', () {
    test('is short while the job is young, then the usual two seconds', () {
      const fast = Duration(milliseconds: 750);
      const slow = Duration(seconds: 2);

      expect(ServerGameReportClient.pollDelay(Duration.zero), fast);
      expect(
        ServerGameReportClient.pollDelay(const Duration(seconds: 5)),
        fast,
      );
      expect(
        ServerGameReportClient.pollDelay(
          const Duration(seconds: 19, milliseconds: 999),
        ),
        fast,
      );
      expect(
        ServerGameReportClient.pollDelay(const Duration(seconds: 20)),
        slow,
      );
      expect(
        ServerGameReportClient.pollDelay(const Duration(minutes: 5)),
        slow,
      );
      expect(ServerGameReportClient.pollInterval, slow);
    });

    testWidgets('a young job is asked again after the short delay', (
      tester,
    ) async {
      // On the test clock, so the wait costs nothing and the moment of the
      // first poll is exact.
      var polls = 0;
      final client = ServerGameReportClient(
        baseUrl: 'https://analysis.test',
        accessToken: () => 'token',
        httpClient: MockClient((request) async {
          if (request.method == 'POST') {
            return http.Response(
              '{"id":"job-1","status":"queued","progress":0}',
              202,
            );
          }
          if (request.url.path.endsWith('/result')) {
            return http.Response.bytes(utf8.encode(jsonEncode(payload)), 200);
          }
          polls++;
          return http.Response(
            '{"id":"job-1","status":"succeeded","progress":1}',
            200,
          );
        }),
      );
      addTearDown(client.close);
      GameAnalysisReport? report;
      unawaited(client.analyze(game).then((value) => report = value));

      await tester.pump(const Duration(milliseconds: 749));
      expect(polls, 0);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(polls, 1);
      expect(report, isNotNull);
    });
  });

  group('ANALYSIS_API_BASE', () {
    test('a build that defines nothing still reaches the service', () {
      // The whole point of the default: a build that forgets the define gets
      // server reports, not a silent demotion to the phone's own engine.
      expect(
        resolveAnalysisApiBase(define: '', allowDebugEnv: false),
        kDefaultAnalysisApiBase,
      );
      expect(kAnalysisApiBase, isNotEmpty);
    });

    test('the define wins, whitespace and all', () {
      expect(
        resolveAnalysisApiBase(
          define: '  http://127.0.0.1:8787 ',
          allowDebugEnv: false,
        ),
        'http://127.0.0.1:8787',
      );
    });

    test('a .env value is read only when the define is absent', () {
      expect(
        resolveAnalysisApiBase(
          define: '',
          allowDebugEnv: true,
          debugEnvValue: () => 'https://preview.example.workers.dev',
        ),
        'https://preview.example.workers.dev',
      );
      expect(
        resolveAnalysisApiBase(
          define: 'https://defined.example.workers.dev',
          allowDebugEnv: true,
          debugEnvValue: () => 'https://preview.example.workers.dev',
        ),
        'https://defined.example.workers.dev',
      );
    });

    test('a release build never reads .env', () {
      // Release has no dotenv asset, and reading one would be a way for a
      // developer machine's file to change what a shipped build talks to.
      expect(
        resolveAnalysisApiBase(
          define: '',
          allowDebugEnv: false,
          debugEnvValue: () => 'https://preview.example.workers.dev',
        ),
        kDefaultAnalysisApiBase,
      );
    });

    test('an unusable value yields to the default instead of failing', () {
      // A typo would 404 every report and fall the review back to the engine
      // with nothing on screen to explain it.
      expect(
        resolveAnalysisApiBase(
          define: 'chessever-analysis.workers.dev',
          allowDebugEnv: false,
        ),
        kDefaultAnalysisApiBase,
      );
    });

    test('the service can be turned off by name', () {
      // An empty define is indistinguishable from an absent one, so the word is
      // the switch — and an empty base is what keeps the runner null.
      for (final off in const ['off', 'none', 'DISABLED', 'local']) {
        expect(
          resolveAnalysisApiBase(define: off, allowDebugEnv: false),
          isEmpty,
          reason: off,
        );
      }
    });
  });
}
