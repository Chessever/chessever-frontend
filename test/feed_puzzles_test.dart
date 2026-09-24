import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:chessever2/config/puzzle_service_config.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_repository.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_service_client.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_session.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_store.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_widgets.dart';
import 'package:chessever2/screens/feed/race/puzzle_rating_range.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _base = 'https://race.example.dev';

/// Lichess's daily puzzle 5JAJ1 as the puzzle service sends it: the position
/// BEFORE White's setup move Nxf3, then the setup move and the solution.
const Map<String, Object?> _dailyRow = {
  'id': 4211,
  'source_id': '5JAJ1',
  'fen': '5bk1/p5pp/1p2p3/1Pp1B1P1/2P2PpP/P3rbR1/8/2K3N1 w - - 0 31',
  'moves': 'g1f3 g4f3 c1d2 f3f2 g3e3 f2f1q',
  'rating': 1939,
  'themes': ['endgame', 'advancedPawn', 'crushing', 'long', 'promotion'],
  'opening_tags': [],
  'game_url': 'https://lichess.org/jWjInszN/black#61',
};

const String _backRankFen = '6k1/6pp/8/8/8/8/8/RR4K1 b - - 0 1';

/// A back-rank mate in one as a service row, under [id].
Map<String, Object?> _row(Object id, {int rating = 1200}) => {
  'id': id,
  'source_id': 'L$id',
  'fen': _backRankFen,
  'moves': 'g8h8 a1a8',
  'rating': rating,
  'themes': ['mateIn1', 'backRankMate'],
  'opening_tags': ['Kings_Pawn_Game', 'Kings_Pawn_Game_Other'],
  'game_url': 'https://lichess.org/abcdefgh#$id',
};

String _ce(int n) => '$kPuzzleServiceIdPrefix$n';

/// Black plays Kh8; White mates on the back rank. Both Ra8# and Rb8# mate,
/// the solution only lists Ra8#.
const FeedPuzzle _backRank = FeedPuzzle(
  id: 'backrank',
  fen: _backRankFen,
  initialMoveUci: 'g8h8',
  solution: ['a1a8'],
  rating: 900,
  themes: ['mateIn1', 'mate', 'backRankMate', 'oneMove', 'endgame'],
);

/// White's answer is to castle short; the reply and recapture follow.
const FeedPuzzle _castle = FeedPuzzle(
  id: 'castle',
  fen: 'r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1',
  initialMoveUci: 'a8b8',
  solution: ['e1g1', 'b8b1', 'f1b1'],
  rating: 1200,
  openingTags: ['Sicilian_Defense', 'Sicilian_Defense_Najdorf_Variation'],
  gameUrl: 'https://lichess.org/castle00#1',
);

/// A fake puzzle service. Each feed request answers `limit` rows with ids
/// that continue where the last answer stopped (1, 2, 3, ...), unless
/// [fixedPage] pins what an unseeded request returns.
class _FakeService {
  final List<Uri> requests = [];
  bool online = true;
  Duration delay = Duration.zero;
  int _next = 0;
  List<Map<String, Object?>>? fixedPage;

  http.Client get http_ => MockClient((request) async {
    requests.add(request.url);
    if (!online) throw http.ClientException('offline');
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (request.url.path != PuzzleServiceClient.feedPath) {
      return http.Response('{"error":"not_found"}', 404);
    }
    final limit = int.parse(request.url.queryParameters['limit']!);
    final seeded = request.url.queryParameters.containsKey('seed');
    final rows = !seeded && fixedPage != null
        ? fixedPage!
        : [for (var i = 0; i < limit; i++) _row(++_next)];
    return http.Response(jsonEncode({'seed': 7, 'puzzles': rows}), 200);
  });

  PuzzleServiceClient client({DateTime Function()? clock}) =>
      PuzzleServiceClient(baseUrl: _base, httpClient: http_, clock: clock);
}

void main() {
  group('parsePuzzleRow', () {
    test('reads a row: the position before the setup move, then the line', () {
      final puzzle = parsePuzzleRow(_dailyRow);

      expect(puzzle.id, 'ce:4211');
      expect(puzzle.sourceId, '5JAJ1');
      expect(puzzle.rating, 1939);
      expect(puzzle.themes, [
        'endgame',
        'advancedPawn',
        'crushing',
        'long',
        'promotion',
      ]);
      expect(
        puzzle.fen,
        '5bk1/p5pp/1p2p3/1Pp1B1P1/2P2PpP/P3rbR1/8/2K3N1 w - - 0 31',
      );
      expect(puzzle.initialMoveUci, 'g1f3');
      expect(puzzle.solution, ['g4f3', 'c1d2', 'f3f2', 'g3e3', 'f2f1q']);
      expect(puzzle.solver, Side.black);
      expect(puzzle.gameUrl, 'https://lichess.org/jWjInszN/black#61');
      expect(puzzle.white, isNull);

      final session = PuzzleSession(puzzle);
      expect(session.setupSan, 'Nxf3');
      expect(session.startPosition.turn, Side.black);
      expect(session.solverMoveCount, 3);
    });

    test('survives a cache round trip', () {
      final puzzle = parsePuzzleRow(_row(12));
      final back = FeedPuzzle.fromJson(jsonDecode(jsonEncode(puzzle.toJson())));
      expect(back, puzzle);
      expect(back!.sourceId, 'L12');
      expect(back.openingTags, ['Kings_Pawn_Game', 'Kings_Pawn_Game_Other']);
      expect(back.gameUrl, 'https://lichess.org/abcdefgh#12');
      expect(back.rating, 1200);
    });

    test('takes string ids, move lists, space-separated themes', () {
      final puzzle = parsePuzzleRow({
        ..._row(1),
        'id': 'abc',
        'moves': ['g8h8', 'a1a8'],
        'themes': 'mateIn1 short',
        'rating': '1450',
        'source_id': 99,
      });
      expect(puzzle.id, 'ce:abc');
      expect(puzzle.solution, ['a1a8']);
      expect(puzzle.themes, ['mateIn1', 'short']);
      expect(puzzle.rating, 1450);
      expect(puzzle.sourceId, '99');
    });

    test('keeps only https Lichess links', () {
      expect(
        parsePuzzleRow({
          ..._row(1),
          'game_url': 'http://lichess.org/x',
        }).gameUrl,
        isNull,
      );
      expect(
        parsePuzzleRow({
          ..._row(1),
          'game_url': 'https://example.com/lichess.org',
        }).gameUrl,
        isNull,
      );
      expect(parsePuzzleRow({..._row(1), 'game_url': null}).gameUrl, isNull);
    });

    test('rejects rows that are not playable puzzles', () {
      for (final bad in <Map<String, Object?>>[
        {..._row(1), 'moves': 'g8h8 a1b2'}, // not legal after the setup
        {..._row(1), 'moves': 'g8h8'}, // setup move only
        {..._row(1), 'moves': 'Kh8 Ra8#'}, // not UCI
        {..._row(1), 'fen': ''},
        {..._row(1), 'fen': 'not a fen'},
        {..._row(1)}..remove('id'),
      ]) {
        expect(
          () => parsePuzzleRow(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
      expect(() => parsePuzzleRow('row'), throwsFormatException);
    });

    test('a feed body skips bad rows and needs a puzzle list', () {
      final puzzles = parsePuzzleFeed({
        'seed': 3,
        'puzzles': [
          _row(1),
          {..._row(2), 'moves': 'e2e4'},
          _row(3),
        ],
      });
      expect(puzzles.map((p) => p.id), ['ce:1', 'ce:3']);
      expect(parsePuzzleFeed([_row(4)]).single.id, 'ce:4');
      expect(
        () => parsePuzzleFeed({'error': 'x'}),
        throwsA(isA<PuzzleServiceException>()),
      );
    });

    test('puzzles cached by earlier versions still read', () {
      final legacy = FeedPuzzle.fromJson({
        'id': '5JAJ1',
        'fen': _backRankFen,
        'solution': ['a1a8'],
        'initialMove': 'g8h8',
        'rating': 1939,
        'themes': ['endgame'],
        'gameUrl': 'https://lichess.org/jWjInszN/black#61',
        'daily': true,
        'plays': 52843,
        'perf': 'Rapid',
        'white': {'name': 'bathop1', 'rating': 1906},
      });
      expect(legacy, isNotNull);
      expect(legacy!.id, '5JAJ1');
      expect(legacy.perfName, 'Rapid');
      expect(legacy.white?.name, 'bathop1');
      expect(legacy.openingTags, isEmpty);
      expect(legacy.toJson().containsKey('daily'), isFalse);
    });
  });

  group('PuzzleSession', () {
    test(
      'walks the daily line, rejecting wrong moves and wrong promotions',
      () {
        final s = PuzzleSession(parsePuzzleRow(_dailyRow));

        final wrong = s.play(Move.parse('h7h6')!)!;
        expect(wrong.verdict, PuzzleVerdict.wrong);
        expect(s.step, 0);
        expect(s.position.fen, s.startPosition.fen);

        final first = s.play(Move.parse('g4f3')!)!;
        expect(first.verdict, PuzzleVerdict.correct);
        expect(first.san, 'gxf3');
        expect(s.replyDue, isTrue);
        expect(s.play(Move.parse('f3f2')!), isNull); // not the solver's turn

        final reply = s.advance()!;
        expect(reply.san, 'Kd2');
        expect(reply.bySolver, isFalse);

        expect(s.play(Move.parse('f3f2')!)!.verdict, PuzzleVerdict.correct);
        expect(s.advance()!.san, 'Rxe3');
        expect(s.solverMovesPlayed, 2);

        // The pawn must promote, and to the right piece.
        expect(s.play(Move.parse('f2f1')!), isNull);
        expect(s.play(Move.parse('f2f1n')!)!.verdict, PuzzleVerdict.wrong);
        final last = s.play(Move.parse('f2f1q')!)!;
        expect(last.verdict, PuzzleVerdict.solved);
        expect(last.san, 'f1=Q');
        expect(s.isSolved, isTrue);
        expect(s.solverMovesPlayed, 3);
        expect(s.play(Move.parse('a7a6')!), isNull);
      },
    );

    test('any mate is accepted, as on Lichess', () {
      final s = PuzzleSession(_backRank);
      expect(s.solver, Side.white);
      expect(s.hint, NormalMove(from: Square.a1, to: Square.a8));

      expect(s.play(Move.parse('a1a7')!)!.verdict, PuzzleVerdict.wrong);
      final alt = s.play(Move.parse('b1b8')!)!;
      expect(alt.verdict, PuzzleVerdict.solved);
      expect(alt.san, 'Rb8#');
      expect(s.isSolved, isTrue);

      s.reset();
      expect(s.play(Move.parse('a1a8')!)!.verdict, PuzzleVerdict.solved);
    });

    test('castling counts in either encoding', () {
      final s = PuzzleSession(_castle);
      // King-takes-rook, as a tap on the rook sends it.
      final attempt = s.play(NormalMove(from: Square.e1, to: Square.h1))!;
      expect(attempt.verdict, PuzzleVerdict.correct);
      expect(attempt.san, 'O-O');
      expect(attempt.move, NormalMove(from: Square.e1, to: Square.g1));

      s.reset();
      expect(s.play(Move.parse('e1g1')!)!.verdict, PuzzleVerdict.correct);
    });

    test('showing the answer plays it out without counting as solved', () {
      final s = PuzzleSession(_castle)..beginReveal();
      final steps = <String>[];
      for (var step = s.advance(); step != null; step = s.advance()) {
        steps.add(step.san);
      }
      expect(steps, ['O-O', 'Rb1', 'Rfxb1']);
      expect(s.isComplete, isTrue);
      expect(s.isSolved, isFalse);
      expect(s.isRevealed, isTrue);
    });
  });

  group('puzzle names', () {
    test('themes drop length tags and lead with the idea', () {
      expect(puzzleThemeNames(_backRank.themes), [
        'Mate in 1',
        'Back rank mate',
        'Endgame',
      ]);
      expect(puzzleThemeName('xRayAttack'), 'X-ray attack');
      expect(puzzleThemeName('advancedPawn'), 'Advanced pawn');
    });

    test('the opening is the broadest tag, readable', () {
      expect(puzzleOpeningName(_castle.openingTags), 'Sicilian Defense');
      expect(
        puzzleOpeningName(['Kings_Pawn_Game', 'Kings_Pawn_Game_Other']),
        "King's Pawn Game",
      );
      expect(
        puzzleOpeningName(['Queens_Gambit_Declined']),
        "Queen's Gambit "
        'Declined',
      );
      expect(puzzleOpeningName(const []), isNull);
      expect(puzzleOpeningName(['', 'Italian_Game']), 'Italian Game');
    });
  });

  group('resolveRaceApiUrl', () {
    test('a dart-define wins and loses its trailing slash', () {
      expect(
        resolveRaceApiUrl(
          define: ' https://race.example.dev/ ',
          debugEnvValue: () => 'https://other.example.dev',
          allowDebugEnv: true,
        ),
        'https://race.example.dev',
      );
    });

    test('.env is read only where debug builds allow it', () {
      expect(
        resolveRaceApiUrl(
          define: '',
          debugEnvValue: () => 'http://127.0.0.1:8787/',
          allowDebugEnv: true,
        ),
        'http://127.0.0.1:8787',
      );
      expect(
        resolveRaceApiUrl(
          define: '',
          debugEnvValue: () => 'https://race.example.dev',
          allowDebugEnv: false,
        ),
        isEmpty,
      );
    });

    test('unset or unusable means no service', () {
      expect(
        resolveRaceApiUrl(
          define: '',
          debugEnvValue: () => '',
          allowDebugEnv: true,
        ),
        isEmpty,
      );
      expect(normalizeRaceApiUrl('race.example.dev'), isEmpty);
      expect(normalizeRaceApiUrl('ftp://race.example.dev'), isEmpty);
      expect(normalizeRaceApiUrl('   '), isEmpty);
    });

    test('every Codemagic build command passes RACE_API_URL', () {
      // Release builds have no .env: without this define every Codemagic
      // build ships a Feed with no puzzles and no Puzzle Race.
      final docs = io.File('CODEMAGIC_DART_DEFINES.txt').readAsStringSync();
      final builds = RegExp(
        r'^flutter build ',
        multiLine: true,
      ).allMatches(docs).length;
      expect(builds, greaterThan(0));
      expect(
        '--dart-define=RACE_API_URL="\$RACE_API_URL"'.allMatches(docs).length,
        builds,
      );
    });
  });

  group('PuzzleServiceClient', () {
    test('asks the feed endpoint anonymously for a rating window', () async {
      final service = _FakeService();
      final client = PuzzleServiceClient(
        baseUrl: '$_base/',
        httpClient: service.http_,
      );
      final puzzles = await client.feed(minRating: 1000, maxRating: 1400);

      expect(puzzles, hasLength(20));
      final uri = service.requests.single;
      expect(uri.host, 'race.example.dev');
      expect(uri.path, '/v1/puzzles/feed');
      expect(uri.queryParameters, {
        'min': '1000',
        'max': '1400',
        'limit': '20',
      });

      await client.feed(minRating: 1000, maxRating: 1400, limit: 5, seed: 42);
      expect(service.requests.last.queryParameters['seed'], '42');
      expect(service.requests.every((u) => u.host != 'lichess.org'), isTrue);
    });

    test('sends no credentials', () async {
      final seen = <http.BaseRequest>[];
      final client = PuzzleServiceClient(
        baseUrl: _base,
        httpClient: MockClient((request) async {
          seen.add(request);
          return http.Response(jsonEncode({'puzzles': []}), 200);
        }),
      );
      await client.feed(minRating: 1000, maxRating: 1400);
      final keys = seen.single.headers.keys.map((k) => k.toLowerCase());
      expect(keys, isNot(contains('authorization')));
      expect(keys, isNot(contains('apikey')));
    });

    test("backs off for the service's Retry-After after a 429", () async {
      var now = DateTime(2026, 9, 23, 12);
      var calls = 0;
      final client = PuzzleServiceClient(
        baseUrl: _base,
        clock: () => now,
        httpClient: MockClient((request) async {
          calls++;
          return calls == 1
              ? http.Response('', 429, headers: {'retry-after': '120'})
              : http.Response(
                  jsonEncode({
                    'puzzles': [_row(1)],
                  }),
                  200,
                );
        }),
      );

      await expectLater(
        client.feed(minRating: 1000, maxRating: 1400),
        throwsA(isA<PuzzleServiceRateLimitedException>()),
      );
      expect(client.blockedUntil, now.add(const Duration(seconds: 120)));

      // Inside the window nothing is sent.
      now = now.add(const Duration(seconds: 90));
      await expectLater(
        client.feed(minRating: 1000, maxRating: 1400),
        throwsA(isA<PuzzleServiceRateLimitedException>()),
      );
      expect(calls, 1);

      now = now.add(const Duration(seconds: 31));
      expect(
        (await client.feed(minRating: 1000, maxRating: 1400)).single.id,
        'ce:1',
      );
      expect(calls, 2);
    });

    test('a 429 without Retry-After waits a minute', () async {
      final now = DateTime(2026, 9, 23, 12);
      final client = PuzzleServiceClient(
        baseUrl: _base,
        clock: () => now,
        httpClient: MockClient((_) async => http.Response('', 429)),
      );
      await expectLater(
        client.feed(minRating: 1000, maxRating: 1400),
        throwsA(isA<PuzzleServiceRateLimitedException>()),
      );
      expect(client.blockedUntil, now.add(const Duration(seconds: 60)));
    });

    test('errors and an unset URL fail without puzzles', () async {
      final failing = PuzzleServiceClient(
        baseUrl: _base,
        httpClient: MockClient((_) async => http.Response('', 503)),
      );
      await expectLater(
        failing.feed(minRating: 1000, maxRating: 1400),
        throwsA(
          isA<PuzzleServiceException>().having(
            (e) => e.statusCode,
            'statusCode',
            503,
          ),
        ),
      );

      var sent = 0;
      final unset = PuzzleServiceClient(
        baseUrl: '',
        httpClient: MockClient((_) async {
          sent++;
          return http.Response('[]', 200);
        }),
      );
      expect(unset.isConfigured, isFalse);
      await expectLater(
        unset.feed(minRating: 1000, maxRating: 1400),
        throwsA(isA<PuzzleServiceException>()),
      );
      expect(sent, 0);
    });
  });

  group('FeedPuzzleRating', () {
    test('starts at 1200 and asks around it', () {
      const r = FeedPuzzleRating.initial;
      expect(r.value, 1200);
      expect(r.band, (min: 1000, max: 1400));
    });

    test('moves with success: solved up, helped flat, shown down', () {
      const r = FeedPuzzleRating.initial;
      expect(r.after(puzzleRating: 1200, score: 1).value, 1240);
      expect(r.after(puzzleRating: 1200, score: 0.5).value, 1200);
      expect(r.after(puzzleRating: 1200, score: 0).value, 1160);
      // Solving an easy one moves it less than solving a hard one.
      final easy = r.after(puzzleRating: 900, score: 1).value - 1200;
      final hard = r.after(puzzleRating: 1500, score: 1).value - 1200;
      expect(easy, lessThan(hard));
      // Unknown puzzle rating: judged as even.
      expect(r.after(score: 1).value, 1240);
    });

    test('settles after the first ten, clamps, and rounds the window', () {
      var r = FeedPuzzleRating.initial;
      for (var i = 0; i < 10; i++) {
        r = FeedPuzzleRating(1200, finished: r.finished + 1);
      }
      expect(r.after(puzzleRating: 1200, score: 1).value, 1220);
      expect(
        const FeedPuzzleRating(2790).after(puzzleRating: 2800, score: 1).value,
        FeedPuzzleRating.ceiling,
      );
      expect(const FeedPuzzleRating(1337).band, (min: 1150, max: 1550));
      expect(
        FeedPuzzleRating.fromJson(
          const FeedPuzzleRating(1337, finished: 4).toJson(),
        ),
        const FeedPuzzleRating(1337, finished: 4),
      );
      expect(FeedPuzzleRating.fromJson({'value': 'x'}), isNull);
    });
  });

  group('FeedPuzzleRepository', () {
    final today = DateTime.utc(2026, 9, 23, 12);

    PuzzleServiceClient offline([List<Uri>? log]) => PuzzleServiceClient(
      baseUrl: _base,
      httpClient: MockClient((request) async {
        log?.add(request.url);
        throw http.ClientException('offline');
      }),
    );

    CachedPuzzle cached(String id, DateTime at, {DateTime? servedAt}) =>
        CachedPuzzle(
          FeedPuzzle(
            id: id,
            fen: _backRankFen,
            initialMoveUci: 'g8h8',
            solution: const ['a1a8'],
            rating: 1200,
          ),
          at,
          servedAt: servedAt,
        );

    List<String> ids(Iterable<Object> items) => [
      for (final item in items)
        switch (item) {
          FeedPuzzle(:final id) => id,
          CachedPuzzle(:final puzzle) => puzzle.id,
          _ => '$item',
        },
    ];

    test('cold start: five fresh from one request, the rest cached', () async {
      final service = _FakeService();
      final store = MemoryFeedPuzzleStore();
      final repo = FeedPuzzleRepository(
        client: service.client(),
        store: store,
        clock: () => today,
      );

      final puzzles = await repo.load();
      await repo.settle();

      expect(ids(puzzles), [for (var i = 1; i <= 5; i++) _ce(i)]);
      expect(service.requests, hasLength(1));
      expect(service.requests.single.queryParameters, {
        'min': '1000',
        'max': '1400',
        'limit': '${FeedPuzzleRepository.fetchLimit}',
      });
      // The five served move behind the five the viewer has not seen.
      expect(ids(store.pool), [
        for (var i = 6; i <= 10; i++) _ce(i),
        for (var i = 1; i <= 5; i++) _ce(i),
      ]);
      expect(ids(store.pool.where((c) => c.servedAt != null)), [
        for (var i = 1; i <= 5; i++) _ce(i),
      ]);
      expect(await repo.backgroundUpdate, isFalse);

      final served = store.pool.last;
      final roundTrip = CachedPuzzle.fromJson(
        jsonDecode(jsonEncode(served.toJson())),
      )!;
      expect(roundTrip.servedAt!.isAtSameMomentAs(served.servedAt!), isTrue);
      expect(
        CachedPuzzle.fromJson(cached('x', today).toJson())!.servedAt,
        isNull,
      );
    });

    test(
      'the next launch leads with unseen puzzles and drops finished ones',
      () async {
        final store = MemoryFeedPuzzleStore();
        final service = _FakeService();
        final first = FeedPuzzleRepository(
          client: service.client(),
          store: store,
          clock: () => today,
        );
        await first.load();
        await first.settle();
        await first.markFinished(_ce(1), FeedPuzzleOutcome.solved);
        await first.markFinished(_ce(2), FeedPuzzleOutcome.revealed);
        expect(first.outcomeOf(_ce(1)), FeedPuzzleOutcome.solved);
        expect(store.done, {_ce(1), _ce(2)});

        final second = FeedPuzzleRepository(
          client: service.client(),
          store: store,
          clock: () => today.add(const Duration(minutes: 30)),
        );
        final puzzles = await second.load();
        await second.settle();

        expect(ids(puzzles), [for (var i = 6; i <= 10; i++) _ce(i)]);
        // No unseen left: one top-up in the background, for the next launch,
        // which replaces the shown ones.
        expect(service.requests, hasLength(2));
        expect(await second.backgroundUpdate, isFalse);
        expect(ids(store.pool), [for (var i = 21; i <= 30; i++) _ce(i)]);
      },
    );

    test('shown puzzles come back longest-ago first, never ahead of unseen '
        'ones', () async {
      DateTime at(int hour) => today.add(Duration(hours: hour));
      final store = MemoryFeedPuzzleStore(
        pool: [
          cached('a', today, servedAt: at(1)),
          cached('b', today, servedAt: at(3)),
          cached('c', today, servedAt: at(0)),
          cached('d', today),
          cached('e', today, servedAt: at(2)),
          cached('f', today, servedAt: at(5)),
          cached('g', today, servedAt: at(4)),
        ],
      );
      final repo = FeedPuzzleRepository(
        client: offline(),
        store: store,
        clock: () => at(6),
      );
      expect(ids(await repo.load()), ['d', 'c', 'a', 'e', 'b']);
      await repo.settle();
      // Next time the two left out lead, then the five just served.
      expect(ids(store.pool), ['g', 'f', 'd', 'c', 'a', 'e', 'b']);
    });

    test(
      'a reload in the same session keeps served puzzles in place',
      () async {
        final store = MemoryFeedPuzzleStore(
          pool: [for (var i = 1; i <= 10; i++) cached('p$i', today)],
        );
        final repo = FeedPuzzleRepository(
          client: offline(),
          store: store,
          clock: () => today,
        );
        expect(ids(await repo.load()), ['p1', 'p2', 'p3', 'p4', 'p5']);
        await repo.settle();
        await repo.markFinished('p2', FeedPuzzleOutcome.solved);
        expect(ids(await repo.load()), ['p1', 'p3', 'p4', 'p5', 'p6']);
      },
    );

    test('puzzles fetched together age out one by one', () async {
      final idsInPool = [for (var i = 0; i < 10; i++) 'q$i'];
      final ages = idsInPool.map(FeedPuzzleRepository.maxAgeOf).toList();
      const newest = FeedPuzzleRepository.poolMaxAge;
      final oldest = newest - FeedPuzzleRepository.poolAgeSpread;
      expect(ages.every((a) => a <= newest && a >= oldest), isTrue);
      expect(ages.toSet().length, greaterThan(5));

      final elapsed = newest - FeedPuzzleRepository.poolAgeSpread ~/ 2;
      final live = [
        for (final id in idsInPool)
          if (FeedPuzzleRepository.maxAgeOf(id) > elapsed) id,
      ];
      expect(live.length, inInclusiveRange(1, idsInPool.length - 1));

      final repo = FeedPuzzleRepository(
        client: offline(),
        store: MemoryFeedPuzzleStore(
          pool: [for (final id in idsInPool) cached(id, today)],
        ),
        clock: () => today.add(elapsed),
      );
      expect(ids(await repo.load()), live.take(5));
      await repo.settle();
    });

    test('puzzles cached before the service are still served', () async {
      final legacy = FeedPuzzle.fromJson({
        'id': '5JAJ1',
        'fen': _backRankFen,
        'solution': ['a1a8'],
        'initialMove': 'g8h8',
        'daily': true,
      })!;
      final repo = FeedPuzzleRepository(
        client: offline(),
        store: MemoryFeedPuzzleStore(pool: [CachedPuzzle(legacy, today)]),
        clock: () => today,
      );
      expect(ids(await repo.load()), ['5JAJ1']);
      await repo.settle();
    });

    test('with no cache and no service it resolves to an empty list', () async {
      final repo = FeedPuzzleRepository(
        client: offline(),
        store: MemoryFeedPuzzleStore(),
        clock: () => today,
      );
      expect(await repo.load(), isEmpty);
    });

    test('with no service URL it serves and sends nothing', () async {
      var sent = 0;
      final repo = FeedPuzzleRepository(
        client: PuzzleServiceClient(
          baseUrl: '',
          httpClient: MockClient((_) async {
            sent++;
            return http.Response('[]', 200);
          }),
        ),
        store: MemoryFeedPuzzleStore(
          pool: [for (var i = 1; i <= 5; i++) cached('p$i', today)],
        ),
        clock: () => today,
      );
      expect(repo.isConfigured, isFalse);
      expect(await repo.load(), isEmpty);
      expect(await repo.load(), isEmpty);
      expect(sent, 0);
    });

    test('asks around the viewer rating, which finishes move', () async {
      final service = _FakeService();
      final store = MemoryFeedPuzzleStore(
        rating: const FeedPuzzleRating(1600, finished: 20),
      );
      final repo = FeedPuzzleRepository(
        client: service.client(),
        store: store,
        clock: () => today,
      );
      await repo.load();
      await repo.settle();
      expect(service.requests.single.queryParameters['min'], '1400');
      expect(service.requests.single.queryParameters['max'], '1800');

      // A clean solve of a puzzle at the viewer's level: +20 (settled K).
      await repo.markFinished(_ce(1), FeedPuzzleOutcome.solved, rating: 1600);
      expect(store.rating?.value, 1620);
      // Finishing it again does not count twice.
      await repo.markFinished(_ce(1), FeedPuzzleOutcome.revealed, rating: 1600);
      expect(store.rating?.value, 1620);
      // The puzzle's rating is looked up when the page does not pass it.
      await repo.markFinished(_ce(2), FeedPuzzleOutcome.revealed);
      expect(store.rating!.value, lessThan(1620));
      expect(store.rating!.finished, 22);
    });

    test('a finish recorded before any load is persisted', () async {
      final store = MemoryFeedPuzzleStore();
      final repo = FeedPuzzleRepository(
        client: offline(),
        store: store,
        clock: () => today,
      );
      await repo.markFinished(
        'x',
        FeedPuzzleOutcome.solved,
        rating: 1200,
        assisted: true,
      );
      expect(store.done, {'x'});
      expect(store.rating?.value, 1200); // helped solve at level: even
      expect(store.rating?.finished, 1);
    });

    test('when the shared page holds nothing new, a page of our own is asked '
        'for', () async {
      final service = _FakeService()
        ..fixedPage = [for (var i = 1; i <= 20; i++) _row(1000 + i)];
      final repo = FeedPuzzleRepository(
        client: service.client(),
        store: MemoryFeedPuzzleStore(
          done: {for (var i = 1; i <= 20; i++) _ce(1000 + i)},
        ),
        clock: () => today,
        random: math.Random(1),
      );
      final puzzles = await repo.load();
      await repo.settle();
      expect(service.requests, hasLength(2));
      expect(service.requests.first.queryParameters, isNot(contains('seed')));
      final seed = int.parse(service.requests.last.queryParameters['seed']!);
      expect(seed, inInclusiveRange(0, FeedPuzzleRepository.seedRange - 1));
      expect(ids(puzzles), [for (var i = 1; i <= 5; i++) _ce(i)]);
    });

    test('feedPuzzlesProvider reads through the repository', () async {
      final store = MemoryFeedPuzzleStore(
        pool: [
          for (final id in ['p1', 'p2', 'p3', 'p4', 'p5']) cached(id, today),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          feedPuzzleRepositoryProvider.overrideWithValue(
            FeedPuzzleRepository(
              client: offline(),
              store: store,
              clock: () => today,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final puzzles = await container.read(feedPuzzlesProvider.future);
      expect(puzzles.map((p) => p.id), ['p1', 'p2', 'p3', 'p4', 'p5']);
    });

    test('the chosen difficulty sets the band the service is asked', () async {
      final service = _FakeService();
      final repo = FeedPuzzleRepository(
        client: service.client(),
        store: MemoryFeedPuzzleStore(
          rating: const FeedPuzzleRating(1600, finished: 20),
        ),
        clock: () => today,
        band: () => (min: 2000, max: 2500),
      );
      await repo.load();
      await repo.settle();
      // The picked band, not the adaptive rating's window around 1600.
      expect(service.requests.first.queryParameters['min'], '2000');
      expect(service.requests.first.queryParameters['max'], '2500');
    });

    test('rated puzzles outside the difficulty are not served, and a new '
        'difficulty drops them from the cache', () async {
      CachedPuzzle rated(String id, int rating) => CachedPuzzle(
        FeedPuzzle(
          id: id,
          fen: _backRankFen,
          initialMoveUci: 'g8h8',
          solution: const ['a1a8'],
          rating: rating,
        ),
        today,
      );
      final store = MemoryFeedPuzzleStore(
        pool: [
          rated('easy1', 900),
          rated('mid1', 1600),
          rated('easy2', 1000),
          rated('mid2', 1800),
          CachedPuzzle(
            const FeedPuzzle(
              id: 'unrated',
              fen: _backRankFen,
              initialMoveUci: 'g8h8',
              solution: ['a1a8'],
            ),
            today,
          ),
        ],
      );
      final repo = FeedPuzzleRepository(
        client: offline(),
        store: store,
        clock: () => today,
        band: () => (min: 1500, max: 2000),
      );
      expect(ids(await repo.load()), ['mid1', 'mid2', 'unrated']);

      await repo.retainWithin(1500, 2000);
      expect(ids(store.pool), containsAll(['mid1', 'mid2', 'unrated']));
      expect(ids(store.pool), isNot(contains('easy1')));
      expect(ids(store.pool), isNot(contains('easy2')));
    });

    test('without a difficulty the adaptive rating still steers', () async {
      final service = _FakeService();
      final repo = FeedPuzzleRepository(
        client: service.client(),
        store: MemoryFeedPuzzleStore(),
        clock: () => today,
      );
      await repo.load();
      await repo.settle();
      expect(service.requests.first.queryParameters['min'], '1000');
      expect(service.requests.first.queryParameters['max'], '1400');
    });

    test('an empty list retries with a back-off, never inside a 429', () {
      final now = DateTime.utc(2026, 9, 23, 12);
      Duration delay(int attempt, [DateTime? blockedUntil]) =>
          feedPuzzlesRetryDelay(
            attempt: attempt,
            now: now,
            blockedUntil: blockedUntil,
          );
      expect(delay(0), const Duration(seconds: 30));
      expect(delay(1), const Duration(minutes: 1));
      expect(delay(3), const Duration(minutes: 4));
      expect(delay(40), const Duration(minutes: 5));
      expect(
        delay(0, now.add(const Duration(seconds: 90))),
        const Duration(seconds: 91),
      );
      expect(delay(0, now.subtract(const Duration(seconds: 5))), delay(0));
    });

    testWidgets('an empty first load is retried, not kept for the session', (
      tester,
    ) async {
      final service = _FakeService()..online = false;
      final repo = FeedPuzzleRepository(
        client: service.client(clock: () => today),
        store: MemoryFeedPuzzleStore(),
        clock: () => today,
      );
      final container = ProviderContainer(
        overrides: [feedPuzzleRepositoryProvider.overrideWithValue(repo)],
      );
      container.listen(feedPuzzlesProvider, (_, _) {});

      await tester.pump();
      await tester.pump();
      expect(container.read(feedPuzzlesProvider).valueOrNull, isEmpty);

      service.online = true;
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
      expect(
        container.read(feedPuzzlesProvider).valueOrNull?.map((p) => p.id),
        [for (var i = 1; i <= 5; i++) _ce(i)],
      );
      container.dispose();
    });

    testWidgets('a load that fails is retried like an empty one', (
      tester,
    ) async {
      final service = _FakeService();
      final repo = _FlakyRepository(
        service.client(clock: () => today),
        MemoryFeedPuzzleStore(),
        today,
      );
      final container = ProviderContainer(
        overrides: [feedPuzzleRepositoryProvider.overrideWithValue(repo)],
      );
      container.listen(feedPuzzlesProvider, (_, _) {});

      await tester.pump();
      await tester.pump();
      expect(container.read(feedPuzzlesProvider).hasError, isFalse);
      expect(container.read(feedPuzzlesProvider).valueOrNull, isEmpty);

      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
      expect(repo.calls, 2);
      expect(
        container.read(feedPuzzlesProvider).valueOrNull,
        hasLength(FeedPuzzleRepository.freshCount),
      );
      container.dispose();
    });

    testWidgets(
      'with no service URL the list stays empty and nothing retries',
      (tester) async {
        var sent = 0;
        final repo = FeedPuzzleRepository(
          client: PuzzleServiceClient(
            baseUrl: '',
            httpClient: MockClient((_) async {
              sent++;
              return http.Response('[]', 200);
            }),
          ),
          store: MemoryFeedPuzzleStore(),
          clock: () => today,
        );
        final container = ProviderContainer(
          overrides: [feedPuzzleRepositoryProvider.overrideWithValue(repo)],
        );
        container.listen(feedPuzzlesProvider, (_, _) {});
        await tester.pump();
        expect(container.read(feedPuzzlesProvider).valueOrNull, isEmpty);
        await tester.pump(const Duration(minutes: 10));
        expect(sent, 0);
        expect(container.read(feedPuzzlesProvider).valueOrNull, isEmpty);
        container.dispose();
      },
    );

    testWidgets('a top-up for a short load joins the list when it lands', (
      tester,
    ) async {
      final service = _FakeService()..delay = const Duration(seconds: 2);
      final repo = FeedPuzzleRepository(
        client: service.client(clock: () => today),
        store: MemoryFeedPuzzleStore(
          pool: [cached('p1', today), cached('p2', today)],
        ),
        clock: () => today,
      );
      final container = ProviderContainer(
        overrides: [feedPuzzleRepositoryProvider.overrideWithValue(repo)],
      );
      container.listen(feedPuzzlesProvider, (_, _) {});

      await tester.pump();
      await tester.pump();
      expect(
        container.read(feedPuzzlesProvider).valueOrNull?.map((p) => p.id),
        ['p1', 'p2'],
      );

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(
        container.read(feedPuzzlesProvider).valueOrNull?.map((p) => p.id),
        ['p1', 'p2', _ce(1), _ce(2), _ce(3)],
      );
      container.dispose();
    });
  });

  group('FeedPuzzlePage', () {
    testWidgets('setup move, then a mating move solves it', (tester) async {
      final h = await _pumpPage(tester, _backRank);

      expect(find.text('Daily puzzle'), findsNothing);
      // One header line: what it is, its rating, and the difficulty control;
      // themes stay off the page.
      final header = find.byKey(const ValueKey('feed_puzzle_header'));
      expect(tester.getSize(header).height, 44);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('feed_header_rating')),
          matching: find.textContaining('900'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('feed_header_difficulty')), findsOne);
      expect(find.text('Mate in 1, Back rank mate, Endgame'), findsNothing);
      _expectNoLichess();
      expect(h.board(tester).fen, _backRank.fen);

      // The opponent's setup move plays by itself.
      await tester.pump(const Duration(milliseconds: 700));
      expect(h.sounds.played, [('Kh8', null)]);
      expect(
        h.board(tester).lastMove,
        NormalMove(from: Square.g8, to: Square.h8),
      );

      await h.tap(tester, Square.a1);
      await h.tap(tester, Square.a8);
      await tester.pump();

      expect(find.text('Solved'), findsOneWidget);
      expect(h.sounds.played.last, ('Ra8#', MoveClass.brilliant));
      expect(h.repo.outcomeOf('backrank'), FeedPuzzleOutcome.solved);
      // Finished: Retry and Next, nothing pointing off the app.
      _expectNoLichess();
      expect(find.text('Retry'), findsOneWidget);
      // A clean solve of an easier puzzle nudges the rating up.
      await tester.pump();
      expect(h.store.rating?.finished, 1);
      expect(h.store.rating!.value, greaterThan(1200));

      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(h.nextRequests, 1);

      await _tearDown(tester);
    });

    testWidgets('a wrong move is judged and slides back', (tester) async {
      final h = await _pumpPage(tester, _backRank);
      await tester.pump(const Duration(milliseconds: 700));
      final start = h.board(tester).fen;

      await h.tap(tester, Square.a1);
      await h.tap(tester, Square.a7);
      await tester.pump();
      expect(find.textContaining('Not quite'), findsOneWidget);
      expect(h.sounds.played.last, ('Ra7', MoveClass.mistake));
      expect(h.board(tester).fen, isNot(start));

      await tester.pump(const Duration(milliseconds: 600));
      expect(h.board(tester).fen, start);
      expect(find.textContaining('Not quite'), findsOneWidget);

      // Hint circles the piece to move.
      await tester.tap(find.text('Hint'));
      await tester.pump();
      final shapes = tester.widget<Chessboard>(find.byType(Chessboard)).shapes;
      expect(
        shapes.whereType<Circle>().map((c) => c.orig),
        contains(Square.a1),
      );

      // Solved after a wrong try and a hint: it counts for less.
      await h.tap(tester, Square.a1);
      await h.tap(tester, Square.a8);
      await tester.pump();
      expect(find.text('Solved'), findsOneWidget);
      expect(h.store.rating?.finished, 1);
      expect(h.store.rating!.value, lessThan(1200));

      await _tearDown(tester);
    });

    testWidgets('a right move is answered, the last one solves it', (
      tester,
    ) async {
      final h = await _pumpPage(tester, _castle);
      await tester.pump(const Duration(milliseconds: 700));

      await h.tap(tester, Square.e1);
      await h.tap(tester, Square.g1);
      await tester.pump();
      expect(find.textContaining('Best move'), findsOneWidget);
      expect(h.sounds.played.last, ('O-O', MoveClass.best));

      // The opponent answers on its own a beat later.
      await tester.pump(const Duration(milliseconds: 500));
      expect(h.sounds.played.last, ('Rb1', null));

      await h.tap(tester, Square.f1);
      await h.tap(tester, Square.b1);
      await tester.pump();
      expect(find.text('Solved'), findsOneWidget);
      expect(h.sounds.played.last, ('Rfxb1', MoveClass.brilliant));
      expect(h.repo.outcomeOf('castle'), FeedPuzzleOutcome.solved);

      await _tearDown(tester);
    });

    testWidgets('the difficulty opens the presets and a pick applies', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpPage(tester, _backRank);
      await tester.tap(find.byKey(const ValueKey('feed_header_difficulty')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Puzzle difficulty'), findsOneWidget);
      for (final preset in PuzzleRatingPreset.values) {
        expect(find.text(preset.label), findsOneWidget);
      }
      await tester.tap(find.text('Strong'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FeedPuzzlePage)),
      );
      expect(
        container.read(puzzleRatingRangeProvider),
        PuzzleRatingPreset.strong.range,
      );
      expect(find.text('Puzzle difficulty'), findsNothing);
      // The header now names the pick.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('feed_header_difficulty')),
          matching: find.text('Strong'),
        ),
        findsOneWidget,
      );
      await _tearDown(tester);
    });

    testWidgets('Solution plays the answer out', (tester) async {
      final h = await _pumpPage(tester, _castle);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('feed_header_rating')),
          matching: find.textContaining('1200'),
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 700));
      _expectNoLichess();

      await tester.tap(find.text('Solution'));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 800));
      }
      expect(find.text('Solution'), findsOneWidget); // the status line
      // The puzzle carries its source game's link, but the post neither
      // names Lichess nor offers to open it: just Retry and Next.
      expect(_castle.gameUrl, isNotNull);
      _expectNoLichess();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.byType(PuzzleButton), findsNWidgets(2));
      expect(h.repo.outcomeOf('castle'), FeedPuzzleOutcome.revealed);
      expect(h.store.rating!.value, lessThan(1200));
      expect(h.sounds.played.map((p) => p.$1), ['Rb8', 'O-O', 'Rb1', 'Rfxb1']);
      expect(h.sounds.played.every((p) => p.$2 == null), isTrue);

      await _tearDown(tester);
    });

    testWidgets('nothing plays while the page is not seen', (tester) async {
      final h = await _pumpPage(tester, _backRank, visible: false);
      await tester.pump(const Duration(seconds: 2));
      expect(h.sounds.played, isEmpty);
      expect(h.board(tester).fen, _backRank.fen);
      await _tearDown(tester);
    });
  });
}

class _Harness {
  _Harness(this.repo, this.store, this.sounds);

  final FeedPuzzleRepository repo;
  final MemoryFeedPuzzleStore store;
  final _RecordingSounds sounds;
  int nextRequests = 0;

  ChessboardController board(WidgetTester tester) =>
      tester.widget<Chessboard>(find.byType(Chessboard)).controller;

  /// Taps [square] on the (white-at-the-bottom or flipped) puzzle board.
  Future<void> tap(WidgetTester tester, Square square) async {
    final rect = tester.getRect(
      find.byKey(const ValueKey('feed_puzzle_board')),
    );
    final orientation = tester
        .widget<Chessboard>(find.byType(Chessboard))
        .orientation;
    final sq = rect.width / 8;
    final col = orientation == Side.white ? square.file : 7 - square.file;
    final row = orientation == Side.white ? 7 - square.rank : square.rank;
    await tester.tapAt(
      Offset(rect.left + (col + 0.5) * sq, rect.top + (row + 0.5) * sq),
    );
    await tester.pump();
  }
}

Future<_Harness> _pumpPage(
  WidgetTester tester,
  FeedPuzzle puzzle, {
  bool visible = true,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final store = MemoryFeedPuzzleStore();
  final repo = FeedPuzzleRepository(
    client: PuzzleServiceClient(
      baseUrl: '',
      httpClient: MockClient((_) async => http.Response('', 404)),
    ),
    store: store,
  );
  final sounds = _RecordingSounds();
  final harness = _Harness(repo, store, sounds);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        feedPuzzleRepositoryProvider.overrideWithValue(repo),
        feedPuzzleSoundsProvider.overrideWithValue(sounds),
        boardSettingsProviderNew.overrideWith(_TestBoardSettings.new),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: FeedPuzzlePage(
                puzzle: puzzle,
                isCurrent: true,
                isVisible: visible,
                onRequestNext: () => harness.nextRequests++,
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return harness;
}

/// Unmount inside the fake clock so no page timer outlives the test.
Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// A puzzle post never mentions Lichess: no credit line, no "View on
/// Lichess" action, no label or link naming it, in any state.
void _expectNoLichess() {
  final lichess = RegExp('lichess', caseSensitive: false);
  expect(find.textContaining(lichess), findsNothing);
  expect(find.bySemanticsLabel(lichess), findsNothing);
}

class _RecordingSounds extends FeedPuzzleSounds {
  final List<(String, MoveClass?)> played = [];

  @override
  void move({required String san, MoveClass? moveClass}) =>
      played.add((san, moveClass));
}

class _TestBoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

/// Fails its first load, then loads normally.
class _FlakyRepository extends FeedPuzzleRepository {
  _FlakyRepository(
    PuzzleServiceClient client,
    FeedPuzzleStore store,
    DateTime now,
  ) : super(client: client, store: store, clock: () => now);

  int calls = 0;

  @override
  Future<List<FeedPuzzle>> load() async {
    calls++;
    if (calls == 1) throw StateError('store blew up');
    return super.load();
  }
}
