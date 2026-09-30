import 'dart:convert';
import 'dart:math' as math;

import 'package:chessever2/screens/feed/race/race_client.dart';
import 'package:chessever2/screens/feed/race/race_controller.dart';
import 'package:chessever2/screens/feed/race/race_flames.dart';
import 'package:chessever2/screens/feed/race/race_stats_store.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_flame.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'puzzle_race_fakes.dart';

/// Flames, the race's lasting score: the rule (the Worker's
/// `apps/race/test/flames.test.ts` pins exactly these rows), the device's
/// own count, the kept record, and how a count reads on screen.

/// Rating, flames. Change it together with the Worker's `FLAME_TABLE`.
const List<(int, int)> _flameTable = [
  (399, 1),
  (999, 1),
  (1000, 2),
  (1499, 2),
  (1500, 3),
  (1999, 3),
  (2000, 4),
  (2499, 4),
  (2500, 5),
  (3200, 5),
];

RacePuzzleRecord _record(int rating, {required bool solved}) =>
    RacePuzzleRecord(
      puzzle: RacePuzzle(
        index: 0,
        fen: kBackRankFen,
        solver: Side.white,
        setupMove: 'g8h8',
        rating: rating,
        level: 0,
        ply: 1,
        progress: const [],
        revision: 0,
      ),
      solved: solved,
      solution: const ['a1a8'],
      finalLine: const ['a1a8'],
      timeMs: 3000,
    );

double _contrast(Color fg, Color bg) {
  final top = Color.alphaBlend(fg, bg);
  final a = top.computeLuminance();
  final b = bg.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

void main() {
  group('the rule', () {
    test('each solve earns by its rating tier, as the Worker counts', () {
      for (final (rating, flames) in _flameTable) {
        expect(
          (rating, raceFlamesForRating(rating)),
          (rating, flames),
          reason: 'rating $rating',
        );
      }
    });

    test('a run is the sum of its solves; a miss earns nothing', () {
      expect(raceLocalFlames(const []), 0);
      expect(
        raceLocalFlames([
          _record(812, solved: true),
          _record(1620, solved: true),
          _record(2600, solved: false),
          _record(2100, solved: true),
        ]),
        1 + 3 + 4,
      );
    });

    test('the flame burns hotter as the count grows', () {
      expect(raceFlameHeat(0), 0);
      expect(raceFlameHeat(-3), 0);
      // Any flames at all burn at the streak flame's first heat.
      expect(raceFlameHeat(1), 5);
      expect(raceFlameHeat(99), 5);
      expect(raceFlameHeat(100), 10);
      expect(raceFlameHeat(499), 10);
      expect(raceFlameHeat(500), 20);
    });

    test('the kept count wins when the service answered', () {
      const kept = RaceServerStats(flames: 40);
      expect(raceFlameTotal(server: kept, local: 12), 40);
      expect(raceFlameTotal(server: null, local: 12), 12);
    });
  });

  group('the kept record', () {
    test('GET /v1/me/stats with the bearer, read tolerantly', () async {
      late http.Request seen;
      final api = RaceHttpApi(
        baseUrl: 'https://race.example.dev/',
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'flames': 42,
              'racesPlayed': 3,
              'solved': 19.0,
              'survivalBest': -4,
              'infiniteBest': 'junk',
              'bestStreak': 9,
              'updatedAt': 1790000000000,
              'future': true,
            }),
            200,
          );
        }),
      );
      final stats = await api.myStats('jwt');
      expect(seen.method, 'GET');
      expect(seen.url.toString(), 'https://race.example.dev/v1/me/stats');
      expect(seen.headers['authorization'], 'Bearer jwt');
      expect(
        stats,
        const RaceServerStats(
          flames: 42,
          racesPlayed: 3,
          solved: 19,
          bestStreak: 9,
        ),
      );
    });

    test('an older service, a guest or a refusal keeps nothing', () async {
      for (final status in [401, 403, 404, 503]) {
        final api = RaceHttpApi(
          baseUrl: 'https://race.example.dev',
          client: MockClient(
            (_) async => http.Response('{"error":"x"}', status),
          ),
        );
        expect(await api.myStats('jwt'), isNull, reason: 'HTTP $status');
      }
    });

    test('offline is a network error; no URL sends nothing', () async {
      final offline = RaceHttpApi(
        baseUrl: 'https://race.example.dev',
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(
        offline.myStats('jwt'),
        throwsA(
          isA<RaceApiException>().having((e) => e.code, 'code', 'network'),
        ),
      );
      final none = RaceHttpApi(baseUrl: '');
      await expectLater(
        none.myStats('jwt'),
        throwsA(
          isA<RaceApiException>().having(
            (e) => e.code,
            'code',
            'not_configured',
          ),
        ),
      );
    });

    test('POST /v1/races carries the chosen range only when given', () async {
      final bodies = <Object?>[];
      final api = RaceHttpApi(
        baseUrl: 'https://race.example.dev',
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body));
          return http.Response(
            jsonEncode({
              'code': '7KQ2MX',
              'mode': 'infinite',
              'multiplayer': true,
              'wsUrl': 'wss://race.example.dev/v1/races/7KQ2MX/ws',
            }),
            201,
          );
        }),
      );
      await api.create(
        mode: RaceMode.infinite,
        multiplayer: true,
        token: 'jwt',
        minRating: 1500,
        maxRating: 2000,
      );
      await api.create(mode: RaceMode.infinite, multiplayer: true);
      // What the app sends: a start alone, so the ladder has no ceiling.
      await api.create(
        mode: RaceMode.survival,
        multiplayer: false,
        minRating: 1500,
      );
      expect(bodies, [
        {
          'mode': 'infinite',
          'multiplayer': true,
          'minRating': 1500,
          'maxRating': 2000,
        },
        {'mode': 'infinite', 'multiplayer': true},
        {'mode': 'survival', 'multiplayer': false, 'minRating': 1500},
      ]);
    });

    test('the source asks only for a signed-in account, and never '
        'throws', () async {
      final api = FakeRaceApi()..stats = const RaceServerStats(flames: 5);
      final guest = RaceHttpServerStatsSource(api: api, auth: FakeRaceAuth());
      expect(await guest.read(), isNull);
      expect(api.statsTokens, isEmpty);

      final signedIn = RaceHttpServerStatsSource(
        api: api,
        auth: FakeRefreshingRaceAuth(accessToken: 'old', fresh: ['fresh']),
      );
      expect(await signedIn.read(), const RaceServerStats(flames: 5));
      // A token about to expire is refreshed first.
      expect(api.statsTokens, ['fresh']);

      final unconfigured = RaceHttpServerStatsSource(
        api: FakeRaceApi(isConfigured: false),
        auth: FakeRaceAuth(accessToken: 'jwt'),
      );
      expect(await unconfigured.read(), isNull);

      final failing = RaceHttpServerStatsSource(
        api: _ThrowingStatsApi(),
        auth: FakeRaceAuth(accessToken: 'jwt'),
      );
      expect(await failing.read(), isNull);
    });
  });

  group('the room says', () {
    test("where its ladder runs, and each run's flames", () {
      final s =
          RaceServerMessage.decode(
                jsonEncode(snapshot(startRating: 1000, maxRating: 1500)),
              )!
              as RaceSnapshot;
      expect(s.startRating, 1000);
      expect(s.maxRating, 1500);
      final f =
          RaceServerMessage.decode(
                jsonEncode(finished(results: [result(score: 4, flames: 9)])),
              )!
              as RaceFinished;
      expect(f.results.single.flames, 9);
    });

    test('an older room says neither, and nothing is made up', () {
      final s =
          RaceServerMessage.decode(jsonEncode(snapshot()))! as RaceSnapshot;
      expect(s.startRating, isNull);
      expect(s.maxRating, isNull);
      final f =
          RaceServerMessage.decode(jsonEncode(finished()))! as RaceFinished;
      expect(f.results.single.flames, isNull);
    });
  });

  group('this device', () {
    test('bests keep flames beside every key they had', () async {
      SharedPreferences.setMockInitialValues({
        kRaceStatsKey: jsonEncode({
          'survivalBest': 10,
          'racesPlayed': 3,
          'future': 'kept',
        }),
      });
      final store = PrefsRaceStatsStore();
      // A copy written before flames reads none.
      expect((await store.read()).flames, 0);
      await store.record(
        mode: RaceMode.survival,
        score: 4,
        bestStreak: 2,
        flames: 7,
      );
      final after = await store.record(
        mode: RaceMode.infinite,
        score: 2,
        bestStreak: 2,
        flames: 3,
      );
      expect(after.after.flames, 10);
      expect(after.after.survivalBest, 10);
      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString(kRaceStatsKey)!) as Map;
      expect(stored['flames'], 10);
      expect(stored['racesPlayed'], 5);
      expect(stored['future'], 'kept');
    });

    test('a count never goes down on a bad figure', () {
      final bests = RaceBests.decode('{"flames": -7}');
      expect(bests.flames, 0);
      expect(
        bests
            .withRace(mode: RaceMode.survival, score: 1, streak: 1, flames: -2)
            .flames,
        0,
      );
    });
  });

  group('the mark', () {
    for (final entry in {
      'dark': AppTheme.darkTheme,
      'light': AppTheme.lightTheme,
    }.entries) {
      testWidgets('${entry.key}: the streak flame and a count that reads', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: entry.value,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return const Scaffold(
                  body: Column(
                    children: [
                      RaceFlameMark(flames: 1),
                      RaceFlameMark(flames: 12, earned: true),
                      RaceFlameMark(flames: 0),
                    ],
                  ),
                );
              },
            ),
          ),
        );
        expect(find.text('1 flame'), findsOneWidget);
        expect(find.text('+12 flames'), findsOneWidget);
        expect(find.text('0 flames'), findsOneWidget);
        expect(find.bySemanticsLabel('12 flames earned'), findsOneWidget);
        // The same pixel flame the Streaks wall burns.
        final flames = tester.widgetList<PixelFlame>(find.byType(PixelFlame));
        expect(flames.map((f) => f.streak), [5, 5, 0]);

        final colors = entry.value.extension<AppColors>()!;
        final ink = tester.widget<Text>(find.text('+12 flames')).style!.color!;
        expect(_contrast(ink, colors.background), greaterThanOrEqualTo(4.5));
      });
    }
  });
}

class _ThrowingStatsApi extends FakeRaceApi {
  @override
  Future<RaceServerStats?> myStats(String token) async =>
      throw const RaceApiException('network');
}
