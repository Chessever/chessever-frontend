import 'dart:convert';

import 'package:chessever2/screens/feed/race/race_chess.dart';
import 'package:chessever2/screens/feed/race/race_client.dart';
import 'package:chessever2/screens/feed/race/race_controller.dart';
import 'package:chessever2/screens/feed/race/race_copy.dart';
import 'package:chessever2/screens/feed/race/race_stats_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'puzzle_race_fakes.dart';

Map<String, Object?> _decode(String frame) =>
    (jsonDecode(frame) as Map).cast<String, Object?>();

void main() {
  group('client messages match protocol.ts', () {
    test('heartbeat is exactly the auto-answered frame', () {
      // The runtime only auto-answers these exact bytes (no spaces).
      expect(RaceClientMessage.heartbeat, '{"type":"ping"}');
    });

    test('join trims and caps the name at 24 characters', () {
      expect(_decode(RaceClientMessage.join('  Magnus  ')), {
        'type': 'join',
        'name': 'Magnus',
      });
      expect(_decode(RaceClientMessage.join(null)), {
        'type': 'join',
        'name': null,
      });
      expect(_decode(RaceClientMessage.join('   ')), {
        'type': 'join',
        'name': null,
      });
      final long = _decode(RaceClientMessage.join('x' * 40))['name']! as String;
      expect(long.length, kRaceMaxNameLength);
    });

    test('move, ready, start, stop and the clock ping', () {
      expect(
        _decode(RaceClientMessage.move(puzzleIndex: 4, uci: 'e2e4', ply: 1)),
        {'type': 'move', 'puzzleIndex': 4, 'uci': 'e2e4', 'ply': 1},
      );
      expect(_decode(RaceClientMessage.ready(true)), {
        'type': 'ready',
        'ready': true,
      });
      expect(_decode(RaceClientMessage.start()), {'type': 'start'});
      expect(_decode(RaceClientMessage.stop()), {'type': 'stop'});
      expect(_decode(RaceClientMessage.clockPing(1234)), {
        'type': 'ping',
        't': 1234,
      });
    });

    test('every frame stays under the room limit of 512', () {
      final frames = [
        RaceClientMessage.join('名' * 40),
        RaceClientMessage.move(puzzleIndex: 999999, uci: 'a7a8q', ply: 99),
        RaceClientMessage.clockPing(1790000000000),
      ];
      for (final f in frames) {
        expect(f.length, lessThan(512));
      }
    });
  });

  group('server messages', () {
    test('snapshot (README example)', () {
      final m = RaceServerMessage.decode(
        jsonEncode(
          snapshot(
            state: 'running',
            multiplayer: true,
            startedAt: 1790000000000,
            players: [player(score: 4, mistakes: 1, level: 4, ready: true)],
          ),
        ),
      );
      expect(m, isA<RaceSnapshot>());
      final s = m! as RaceSnapshot;
      expect(s.state, RaceRoomState.running);
      expect(s.mode, RaceMode.survival);
      expect(s.multiplayer, isTrue);
      expect(s.you, kYou);
      expect(s.hostId, kYou);
      expect(s.lives, 3);
      expect(s.startedAt, 1790000000000);
      expect(s.countdownEndsAt, isNull);
      expect(s.players.single.score, 4);
      expect(s.players.single.mistakes, 1);
      expect(s.players.single.ready, isTrue);
    });

    test('infinite snapshot has no lives', () {
      final s =
          RaceServerMessage.decode(jsonEncode(snapshot(mode: 'infinite')))!
              as RaceSnapshot;
      expect(s.mode, RaceMode.infinite);
      expect(s.lives, isNull);
    });

    test('puzzle carries no solution', () {
      final m =
          RaceServerMessage.decode(
                jsonEncode(
                  puzzle(index: 5, ply: 3, progress: ['a1a7', 'h8g8']),
                ),
              )!
              as RacePuzzleMessage;
      expect(m.index, 5);
      expect(m.fen, kBackRankFen);
      expect(m.sideToMove, 'white');
      expect(m.setupMove, 'g8h8');
      expect(m.ply, 3);
      expect(m.progress, ['a1a7', 'h8g8']);
    });

    test('continuing and completing verdicts', () {
      final going =
          RaceServerMessage.decode(
                jsonEncode(
                  verdict(
                    complete: false,
                    expectedReply: 'f3g5',
                    nextPly: 3,
                    score: 4,
                    mistakes: 1,
                    level: 4,
                    elapsedMs: 81234,
                  ),
                ),
              )!
              as RaceVerdict;
      expect(going.correct, isTrue);
      expect(going.complete, isFalse);
      expect(going.expectedReply, 'f3g5');
      expect(going.nextPly, 3);
      expect(going.solutionRevealed, isEmpty);
      expect(going.elapsedMs, 81234);

      final done =
          RaceServerMessage.decode(
                jsonEncode(verdict(correct: false, solutionRevealed: ['a1a8'])),
              )!
              as RaceVerdict;
      expect(done.complete, isTrue);
      expect(done.correct, isFalse);
      expect(done.solutionRevealed, ['a1a8']);
      expect(done.puzzleId, 4211);
      expect(done.themes, contains('backRankMate'));
    });

    test('finished with results and reasons', () {
      final f =
          RaceServerMessage.decode(
                jsonEncode(
                  finished(
                    playerId: kYou,
                    reason: 'lives',
                    roomFinished: false,
                    results: [
                      result(score: 12, mistakes: 3, finishReason: 'lives'),
                      result(
                        rank: 2,
                        id: kRival,
                        finished: false,
                        finishReason: null,
                      ),
                    ],
                  ),
                ),
              )!
              as RaceFinished;
      expect(f.playerId, kYou);
      expect(f.reason, RaceFinishReason.lives);
      expect(f.roomFinished, isFalse);
      expect(f.results.first.score, 12);
      expect(f.results.first.finishReason, RaceFinishReason.lives);
      expect(f.results.last.finishReason, isNull);
      expect(
        RaceFinishReason.fromWire('time_limit'),
        RaceFinishReason.timeLimit,
      );
      expect(
        RaceFinishReason.fromWire('puzzle_limit'),
        RaceFinishReason.puzzleLimit,
      );
      expect(RaceFinishReason.fromWire('new_one'), RaceFinishReason.unknown);
    });

    test('pong, errors, unknown types and junk', () {
      final pong =
          RaceServerMessage.decode('{"type":"pong","serverNow":10,"t":4}')!
              as RacePong;
      expect(pong.serverNow, 10);
      expect(pong.t, 4);
      final bare = RaceServerMessage.decode('{"type":"pong"}')! as RacePong;
      expect(bare.serverNow, isNull);

      final stale =
          RaceServerMessage.decode(
                '{"type":"error","code":"stale","expectedIndex":3,'
                '"expectedPly":1}',
              )!
              as RaceError;
      expect(stale.code, 'stale');
      expect(stale.expectedIndex, 3);
      expect(stale.expectedPly, 1);

      expect(
        RaceServerMessage.decode('{"type":"hello"}'),
        isA<RaceUnknownMessage>(),
      );
      expect(RaceServerMessage.decode('not json'), isNull);
      expect(RaceServerMessage.decode('[1,2]'), isNull);
    });
  });

  group('room codes', () {
    test('read the way the Worker reads them', () {
      expect(normalizeRaceCode('7kq2mx'), '7KQ2MX');
      expect(normalizeRaceCode('7KQ-2MX'), '7KQ2MX');
      expect(normalizeRaceCode(' 7kq 2mx '), '7KQ2MX');
      // O reads as 0, I and L as 1.
      expect(normalizeRaceCode('O1ILAB'), '0111AB');
      expect(normalizeRaceCode('OOIILL'), '001111');
      expect(normalizeRaceCode('7KQ2M'), isNull);
      expect(normalizeRaceCode('7KQ2MXX'), isNull);
      // U is not a Crockford character.
      expect(normalizeRaceCode('UUUUUU'), isNull);
    });
  });

  group('service', () {
    test('POST /v1/races sends mode, multiplayer and the token', () async {
      late http.Request seen;
      final api = RaceHttpApi(
        baseUrl: 'https://race.example.dev/',
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'code': '7KQ2MX',
              'mode': 'survival',
              'multiplayer': false,
              'wsUrl': 'wss://race.example.dev/v1/races/7KQ2MX/ws',
              'seat': 'AAAAAAAAAAAAAAAAAAAAAA',
            }),
            201,
          );
        }),
      );
      final created = await api.create(
        mode: RaceMode.survival,
        multiplayer: false,
        token: 'jwt',
      );
      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'https://race.example.dev/v1/races');
      expect(seen.headers['authorization'], 'Bearer jwt');
      expect(jsonDecode(seen.body), {'mode': 'survival', 'multiplayer': false});
      expect(created.code, '7KQ2MX');
      expect(created.seat, 'AAAAAAAAAAAAAAAAAAAAAA');
      expect(
        created.wsUrl.toString(),
        'wss://race.example.dev/v1/races/7KQ2MX/ws',
      );
    });

    test('errors carry the Worker code and status', () async {
      final api = RaceHttpApi(
        baseUrl: 'https://race.example.dev',
        client: MockClient(
          (_) async => http.Response(
            '{"error":"authentication_required","message":"x"}',
            401,
          ),
        ),
      );
      await expectLater(
        api.create(mode: RaceMode.infinite, multiplayer: true),
        throwsA(
          isA<RaceApiException>()
              .having((e) => e.code, 'code', 'authentication_required')
              .having((e) => e.statusCode, 'status', 401),
        ),
      );
    });

    test('offline is a network error, and no URL sends nothing', () async {
      var calls = 0;
      final offline = RaceHttpApi(
        baseUrl: 'https://race.example.dev',
        client: MockClient((_) async {
          calls++;
          throw http.ClientException('offline');
        }),
      );
      await expectLater(
        offline.create(mode: RaceMode.survival, multiplayer: false),
        throwsA(
          isA<RaceApiException>().having((e) => e.code, 'code', 'network'),
        ),
      );
      final off = RaceHttpApi(
        baseUrl: '',
        client: MockClient((_) async {
          calls++;
          return http.Response('', 500);
        }),
      );
      expect(off.isConfigured, isFalse);
      await expectLater(
        off.create(mode: RaceMode.survival, multiplayer: false),
        throwsA(
          isA<RaceApiException>().having(
            (e) => e.code,
            'code',
            'not_configured',
          ),
        ),
      );
      expect(calls, 1);
    });

    test('GET results reads the room\'s standings, no credential', () async {
      late http.Request seen;
      final api = RaceHttpApi(
        baseUrl: 'https://race.example.dev/',
        client: MockClient((request) async {
          seen = request;
          if (request.url.path.endsWith('/NOPE00/results')) {
            return http.Response(
              '{"error":"room_not_found","message":"x"}',
              404,
            );
          }
          return http.Response(
            jsonEncode(
              roomSummary(
                multiplayer: true,
                finishedAt: 1790000060000,
                results: [
                  result(score: 4, mistakes: 3, finishReason: 'lives'),
                  result(rank: 2, id: kRival, name: 'Hikaru', score: 2),
                ],
              ),
            ),
            200,
          );
        }),
      );
      final summary = await api.results('7KQ2MX');
      expect(seen.method, 'GET');
      expect(
        seen.url.toString(),
        'https://race.example.dev/v1/races/7KQ2MX/results',
      );
      expect(seen.headers.containsKey('authorization'), isFalse);
      expect(summary.state, RaceRoomState.finished);
      expect(summary.multiplayer, isTrue);
      expect(summary.finishedAt, 1790000060000);
      expect(summary.results, hasLength(2));
      expect(summary.resultFor(kYou)!.finishReason, RaceFinishReason.lives);
      expect(summary.resultFor(null), isNull);
      await expectLater(
        api.results('NOPE00'),
        throwsA(
          isA<RaceApiException>()
              .having((e) => e.code, 'code', 'room_not_found')
              .having((e) => e.statusCode, 'status', 404),
        ),
      );
    });

    test('socket address follows the base scheme', () {
      expect(
        RaceHttpApi(baseUrl: 'https://race.example.dev').socketUri('7KQ2MX'),
        Uri.parse('wss://race.example.dev/v1/races/7KQ2MX/ws'),
      );
      expect(
        RaceHttpApi(baseUrl: 'http://localhost:8787').socketUri('7KQ2MX'),
        Uri.parse('ws://localhost:8787/v1/races/7KQ2MX/ws'),
      );
    });

    test('upgrade refusals map to calm codes', () {
      expect(raceUpgradeRefusalCode(404), 'room_not_found');
      expect(raceUpgradeRefusalCode(409), 'room_closed');
      expect(raceUpgradeRefusalCode(410), 'race_finished');
      expect(raceUpgradeRefusalCode(401), 'authentication_required');
      expect(raceUpgradeRefusalCode(null), 'network');
      for (final code in [
        'room_not_found',
        'room_closed',
        'race_finished',
        'network',
        'puzzle_source_unavailable',
      ]) {
        expect(raceErrorMessage(code), isNot(contains('_')));
      }
    });
  });

  group('formatting', () {
    test('the race clock is mm:ss.t', () {
      expect(formatRaceClock(0), '00:00.0');
      expect(formatRaceClock(81234), '01:21.2');
      expect(formatRaceClock(3723400), '1:02:03.4');
      expect(formatRaceClock(-5), '00:00.0');
    });

    test('puzzle times', () {
      expect(formatPuzzleTime(7400), '7.4s');
      expect(formatPuzzleTime(65000), '1:05');
    });

    test('levels and tension', () {
      expect(raceDisplayLevel(0), 1);
      expect(raceDisplayLevel(2), 1);
      expect(raceDisplayLevel(3), 2);
      expect(raceDisplayLevel(18), 7);
      expect(raceTension(solves: 0, mode: RaceMode.survival, livesLeft: 3), 0);
      expect(
        raceTension(solves: 0, mode: RaceMode.survival, livesLeft: 1),
        closeTo(0.3, 0.001),
      );
      expect(
        raceTension(solves: 60, mode: RaceMode.infinite, livesLeft: null),
        closeTo(0.7, 0.001),
      );
    });

    test('solutions read as SAN with move numbers', () {
      expect(raceSanLine(kBackRankFen, 'g8h8', ['a1a8']), '2. Ra8#');
      // Unplayable input falls back to UCI.
      expect(raceSanLine('bad fen', 'g8h8', ['a1a8']), 'a1a8');
    });

    test('share text names the mode, score and time', () {
      final text = raceShareText(
        mode: RaceMode.survival,
        multiplayer: true,
        score: 24,
        elapsedMs: 192400,
        displayLevel: 9,
        bestStreak: 7,
        rank: 2,
        players: 5,
      );
      expect(text, contains('Survival'));
      expect(text, contains('24 puzzles in 03:12.4'));
      expect(text, contains('Finished 2 of 5.'));
      expect(text, isNot(contains('—')));
      expect(raceInviteText('7KQ2MX'), 'Join my ChessEver Puzzle Race: 7KQ2MX');
    });
  });

  group('personal bests (race_stats_v1)', () {
    test('writes the documented JSON and keeps unknown keys', () async {
      SharedPreferences.setMockInitialValues({
        kRaceStatsKey: jsonEncode({
          'survivalBest': 10,
          'infiniteBest': 40,
          'racesPlayed': 3,
          'bestStreak': 5,
          'future': 'kept',
        }),
      });
      final store = PrefsRaceStatsStore(
        clock: () => DateTime.utc(2026, 9, 23, 10),
      );
      final outcome = await store.record(
        mode: RaceMode.survival,
        score: 12,
        bestStreak: 4,
      );
      expect(outcome.newBest, isTrue);
      expect(outcome.before.survivalBest, 10);
      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString(kRaceStatsKey)!) as Map;
      expect(stored['survivalBest'], 12);
      expect(stored['infiniteBest'], 40);
      expect(stored['racesPlayed'], 4);
      expect(stored['bestStreak'], 5);
      expect(stored['updatedAt'], '2026-09-23T10:00:00.000Z');
      expect(stored['future'], 'kept');
    });

    test('a lower score is not a new best; bad JSON starts over', () async {
      SharedPreferences.setMockInitialValues({kRaceStatsKey: '{not json'});
      final store = PrefsRaceStatsStore();
      final first = await store.record(
        mode: RaceMode.infinite,
        score: 0,
        bestStreak: 0,
      );
      expect(first.newBest, isFalse);
      expect(first.after.racesPlayed, 1);
      final second = await store.record(
        mode: RaceMode.infinite,
        score: 7,
        bestStreak: 7,
      );
      expect(second.newBest, isTrue);
      final third = await store.record(
        mode: RaceMode.infinite,
        score: 5,
        bestStreak: 2,
      );
      expect(third.newBest, isFalse);
      expect(third.after.infiniteBest, 7);
      expect(third.after.bestStreak, 7);
      expect((await store.read()).racesPlayed, 3);
    });

    test('reads the profile reader\'s snake_case too', () {
      final bests = RaceBests.decode(
        '{"survival_best": 9, "races_played": "2", "best_streak": -1}',
      );
      expect(bests.survivalBest, 9);
      expect(bests.racesPlayed, 2);
      expect(bests.bestStreak, 0);
    });
  });
}
