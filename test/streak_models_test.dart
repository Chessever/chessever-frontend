// Parity with chessever_cloudflare/apps/streaks-site/src/lib/model.test.ts:
// the app must read, rank and filter streaks exactly like the site.
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:flutter_test/flutter_test.dart';

const Map<String, dynamic> _ang = {
  'fide_id': 4303636,
  'time_class': 'standard',
  'name': 'Ang, Alphaeus Wei Ern',
  'title': 'fm',
  'fed': 'nzl',
  'rating': 2362,
  'age': 24,
  'current_streak': 42,
  'best_streak': 42,
  'streak_start_game_day': '2026-05-30',
  'last_game_day': '2026-09-05',
  'last_result': 'win',
  'run_opp_avg': 2011,
  'run_opp_best': 2390,
  'run_opp_best_name': 'Smith, John',
  'run_opp_best_title': 'im',
  'tracked_current': true,
  'tracked_top500': false,
  'updated_at': '2026-09-22T10:00:00Z',
};

StreakRow _row({
  int fideId = 4303636,
  StreakTimeClass timeClass = StreakTimeClass.standard,
  String name = 'Ang, Alphaeus Wei Ern',
  String? title,
  String? fed = 'NZL',
  String? sex,
  int? rating = 2362,
  int? age = 24,
  int currentStreak = 42,
  bool trackedCurrent = false,
}) {
  return StreakRow(
    fideId: fideId,
    timeClass: timeClass,
    name: name,
    title: title,
    fed: fed,
    sex: sex,
    rating: rating,
    age: age,
    currentStreak: currentStreak,
    bestStreak: currentStreak,
    trackedCurrent: trackedCurrent,
  );
}

StreakGame _game(String id, String result, int after) =>
    StreakGame.fromJson({
      'game_id': id,
      'result': result,
      'streak_after': after,
    })!;

StreakClassRun _run(
  StreakTimeClass tc, {
  int current = 0,
  int best = 0,
  List<StreakGame> games = const [],
}) {
  return StreakClassRun(
    timeClass: tc,
    currentStreak: current,
    bestStreak: best,
    games: games,
  );
}

void main() {
  group('StreakRow.fromJson', () {
    test('reads the leaderboard row and upper-cases codes', () {
      final r = StreakRow.fromJson(_ang)!;
      expect(r.fideId, 4303636);
      expect(r.timeClass, StreakTimeClass.standard);
      expect(r.currentStreak, 42);
      expect(r.trackedCurrent, isTrue);
      expect(r.trackedTop500, isFalse);
      expect(r.lastResult, 'win');
      expect(r.fed, 'NZL');
      expect(r.title, 'FM');
      expect(r.runOppAvg, 2011);
      expect(r.runOppBest, 2390);
      expect(r.runOppBestTitle, 'IM');
      expect(r.updatedAt, DateTime.utc(2026, 9, 22, 10));
      expect(r.level, StreakLevel.inferno);
    });

    test('needs an id and a name', () {
      expect(StreakRow.fromJson({'fide_id': 1}), isNull);
      expect(StreakRow.fromJson({'name': 'x'}), isNull);
      expect(StreakRow.fromJson({..._ang, 'fide_id': 0}), isNull);
      expect(StreakRow.fromJson({..._ang, 'fide_id': -3}), isNull);
      expect(StreakRow.fromJson({..._ang, 'fide_id': 'abc'}), isNull);
      expect(StreakRow.fromJson({..._ang, 'name': '   '}), isNull);
    });

    test('needs a known time control', () {
      expect(StreakRow.fromJson({..._ang, 'time_class': 'bullet'}), isNull);
      expect(StreakRow.fromJson({..._ang, 'time_class': null}), isNull);
      expect(
        StreakRow.fromJson({..._ang, 'time_class': 'rapid'})!.timeClass,
        StreakTimeClass.rapid,
      );
      expect(
        StreakRow.fromJson({..._ang, 'time_class': 'blitz'})!.timeClass,
        StreakTimeClass.blitz,
      );
    });

    test('a bad field becomes null, never a throw', () {
      final r = StreakRow.fromJson({
        ..._ang,
        'rating': 'strong',
        'current_streak': null,
        'best_streak': -4,
        'tracked_current': 'yes',
        'updated_at': 'yesterday',
        'fide_id': '4303636',
      })!;
      expect(r.fideId, 4303636);
      expect(r.rating, isNull);
      expect(r.currentStreak, 0);
      expect(r.bestStreak, 0);
      expect(r.trackedCurrent, isFalse);
      expect(r.updatedAt, isNull);
    });

    test('age is derived from birth year when the view gives none', () {
      final year = DateTime.now().toUtc().year;
      final derived = StreakRow.fromJson({
        ..._ang,
        'age': null,
        'birth_year': 2002,
      })!;
      expect(derived.age, year - 2002);
      expect(
        StreakRow.fromJson({..._ang, 'age': 24, 'birth_year': 2002})!.age,
        24,
      );
      expect(
        StreakRow.fromJson({..._ang, 'age': null, 'birth_year': 1800})!.age,
        isNull,
      );
    });
  });

  group('names', () {
    test('Surname, First reads as First Surname', () {
      expect(streakDisplayName('Carlsen, Magnus'), 'Magnus Carlsen');
      expect(
        streakDisplayName('Ang, Alphaeus Wei Ern'),
        'Alphaeus Wei Ern Ang',
      );
      expect(streakDisplayName('Hou Yifan'), 'Hou Yifan');
      expect(streakDisplayName('Carlsen,'), 'Carlsen');
      expect(streakDisplayName('  Carlsen , Magnus  '), 'Magnus Carlsen');
      final r = _row(name: 'Carlsen, Magnus');
      expect(r.displayName, 'Magnus Carlsen');
      expect(r.shortName, 'Carlsen');
    });
  });

  group('levels', () {
    test('ember 3-4, flame 5-9, blaze 10-19, inferno 20+', () {
      expect(streakLevel(3), StreakLevel.ember);
      expect(streakLevel(4), StreakLevel.ember);
      expect(streakLevel(5), StreakLevel.flame);
      expect(streakLevel(9), StreakLevel.flame);
      expect(streakLevel(10), StreakLevel.blaze);
      expect(streakLevel(19), StreakLevel.blaze);
      expect(streakLevel(20), StreakLevel.inferno);
    });
  });

  group('time classes', () {
    test('wire values and labels', () {
      expect(StreakTimeClass.standard.wire, 'standard');
      expect(StreakTimeClass.standard.label, 'Classical');
      expect(StreakTimeClassX.tryParse('classical'), StreakTimeClass.standard);
      expect(StreakTimeClassX.tryParse('blitz'), StreakTimeClass.blitz);
      expect(StreakTimeClassX.tryParse('bullet'), isNull);
    });
  });

  group('FIDE age groups count by birth year, both edges included', () {
    test('under groups', () {
      expect(StreakAgeGroup.u12.contains(12), isTrue);
      expect(StreakAgeGroup.u12.contains(13), isFalse);
      expect(StreakAgeGroup.u10.contains(10), isTrue);
      expect(StreakAgeGroup.u10.contains(11), isFalse);
      expect(StreakAgeGroup.u20.contains(20), isTrue);
      expect(StreakAgeGroup.u20.contains(21), isFalse);
    });

    test('senior groups', () {
      expect(StreakAgeGroup.s50.contains(50), isTrue);
      expect(StreakAgeGroup.s50.contains(49), isFalse);
      expect(StreakAgeGroup.s65.contains(65), isTrue);
      expect(StreakAgeGroup.s65.contains(64), isFalse);
    });

    test('an unknown age only belongs to all ages', () {
      expect(StreakAgeGroup.all.contains(null), isTrue);
      for (final g in StreakAgeGroup.values) {
        if (g == StreakAgeGroup.all) continue;
        expect(g.contains(null), isFalse, reason: g.name);
      }
    });
  });

  group('StreakWallFilter.matches', () {
    final rows = [
      _row(fideId: 1, currentStreak: 55, trackedCurrent: true, age: 24),
      _row(
        fideId: 2,
        name: 'Nunn, John',
        currentStreak: 35,
        trackedCurrent: true,
        age: 71,
        rating: 2512,
        fed: 'ENG',
        title: 'GM',
      ),
      _row(
        fideId: 3,
        name: 'Vaz, Ethan',
        currentStreak: 21,
        age: 15,
        rating: 2525,
        fed: 'IND',
        title: 'IM',
      ),
      _row(
        fideId: 4,
        name: 'Doe, Jane',
        currentStreak: 4,
        age: 30,
        rating: 2610,
        fed: 'ENG',
        title: 'GM',
        sex: 'F',
      ),
    ];
    List<int> ids(StreakWallFilter f) =>
        rows.where(f.matches).map((r) => r.fideId).toList();

    test('the default filter keeps everyone', () {
      const f = StreakWallFilter();
      expect(f.isDefault, isTrue);
      expect(ids(f), [1, 2, 3, 4]);
    });

    test('age groups', () {
      expect(ids(const StreakWallFilter(age: StreakAgeGroup.u16)), [3]);
      expect(ids(const StreakWallFilter(age: StreakAgeGroup.u14)), isEmpty);
      expect(ids(const StreakWallFilter(age: StreakAgeGroup.s50)), [2]);
      expect(ids(const StreakWallFilter(age: StreakAgeGroup.s65)), [2]);
    });

    test('women, federation, title, playing now', () {
      expect(ids(const StreakWallFilter(womenOnly: true)), [4]);
      expect(ids(const StreakWallFilter(fed: 'ENG')), [2, 4]);
      expect(ids(const StreakWallFilter(title: 'IM')), [3]);
      expect(ids(const StreakWallFilter(playingNow: true)), [1, 2]);
      expect(
        ids(const StreakWallFilter(fed: 'ENG', womenOnly: true)),
        [4],
      );
    });

    test('search matches name either way round, id, federation and title', () {
      expect(ids(const StreakWallFilter(query: 'ethan')), [3]);
      expect(ids(const StreakWallFilter(query: 'Ethan Vaz')), [3]);
      expect(ids(const StreakWallFilter(query: 'vaz, e')), [3]);
      expect(ids(const StreakWallFilter(query: '  NUNN ')), [2]);
      expect(ids(const StreakWallFilter(query: 'ind')), [3]);
      expect(ids(const StreakWallFilter(query: '4')), [4]);
      expect(ids(const StreakWallFilter(query: 'nobody')), isEmpty);
      expect(const StreakWallFilter(query: '   ').isDefault, isTrue);
    });

    test('copyWith sets and clears', () {
      const f = StreakWallFilter(fed: 'ENG', title: 'GM');
      expect(f.copyWith(clearFed: true).fed, isNull);
      expect(f.copyWith(clearFed: true).title, 'GM');
      expect(f.copyWith(clearTitle: true).title, isNull);
      expect(f.copyWith(age: StreakAgeGroup.u12).age, StreakAgeGroup.u12);
      expect(f.copyWith().fed, 'ENG');
      expect(f.isDefault, isFalse);
    });
  });

  group('games and runs', () {
    test('game rows need an id and a decisive result', () {
      expect(_game('a', 'loss', 0).result, 'loss');
      expect(
        StreakGame.fromJson({'game_id': 'a', 'result': '*'}),
        isNull,
      );
      expect(StreakGame.fromJson({'result': 'win'}), isNull);
      final g = StreakGame.fromJson({
        'game_id': 'a',
        'result': 'WIN',
        'color': 'White',
        'opponent_title': 'gm',
        'streak_after': '3',
      })!;
      expect(g.isWin, isTrue);
      expect(g.color, 'white');
      expect(g.opponentTitle, 'GM');
      expect(g.streakAfter, 3);
      expect(
        StreakGame.fromJson({'game_id': 'b', 'result': 'win', 'color': 'x'})!
            .color,
        isNull,
      );
    });

    test('class run drops junk games and unknown classes', () {
      final run = StreakClassRun.fromJson({
        'time_class': 'blitz',
        'current_streak': 2,
        'games': [
          {'game_id': 'a', 'result': 'win', 'streak_after': 1},
          null,
          {'result': 'win'},
          'x',
        ],
      })!;
      expect(run.games.map((g) => g.gameId), ['a']);
      expect(
        StreakClassRun.fromJson({'time_class': 'correspondence'}),
        isNull,
      );
      expect(
        StreakClassRun.fromJson({'time_class': 'rapid', 'games': 'nope'})!
            .games,
        isEmpty,
      );
    });

    test('the run starts at the last loss in its own class, loss included', () {
      final run = _run(
        StreakTimeClass.standard,
        current: 2,
        games: [
          _game('a', 'win', 5),
          _game('b', 'loss', 0),
          _game('c', 'win', 1),
          _game('d', 'win', 2),
        ],
      );
      expect(run.currentRunGames.map((g) => g.gameId), ['b', 'c', 'd']);
      expect(run.latestWin?.gameId, 'd');
    });

    test('a run that just lost is only that loss', () {
      final run = _run(
        StreakTimeClass.rapid,
        games: [_game('a', 'win', 1), _game('b', 'loss', 0)],
      );
      expect(run.currentRunGames.map((g) => g.gameId), ['b']);
      expect(run.latestWin, isNull);
    });

    test('an anchor outside the retained window still shows the wins', () {
      final games = [_game('a', 'win', 399), _game('b', 'win', 400)];
      expect(
        _run(StreakTimeClass.standard, current: 2, games: games)
            .currentRunGames
            .map((g) => g.gameId),
        ['a', 'b'],
      );
      expect(
        _run(StreakTimeClass.standard, current: 1, games: games)
            .currentRunGames
            .map((g) => g.gameId),
        ['b'],
      );
      expect(
        _run(StreakTimeClass.standard, current: 9, games: games)
            .currentRunGames
            .map((g) => g.gameId),
        ['a', 'b'],
      );
      expect(
        _run(StreakTimeClass.standard, games: games).currentRunGames,
        isEmpty,
      );
    });
  });

  group('PlayerStreaks', () {
    test('profile carries all three ratings and every class', () {
      final p = PlayerStreaks.fromJson(
        {
          'fide_id': 1503014,
          'name': 'Carlsen, Magnus',
          'title': 'gm',
          'fed': 'nor',
          'rating': 2839,
          'rapid_rating': 2824,
          'blitz_rating': 2886,
          'birth_year': 1990,
          'tracked_current': true,
        },
        [
          {'time_class': 'blitz', 'current_streak': 11, 'best_streak': 11},
          {'time_class': 'standard', 'current_streak': 0, 'best_streak': 15},
          {'time_class': 'bullet', 'current_streak': 99},
        ],
      )!;
      expect(p.displayName, 'Magnus Carlsen');
      expect(p.title, 'GM');
      expect(p.fed, 'NOR');
      expect(p.ratings, {
        StreakTimeClass.standard: 2839,
        StreakTimeClass.rapid: 2824,
        StreakTimeClass.blitz: 2886,
      });
      expect(p.age, DateTime.now().toUtc().year - 1990);
      expect(p.trackedCurrent, isTrue);
      expect(p.runs.keys.toSet(), {
        StreakTimeClass.blitz,
        StreakTimeClass.standard,
      });
      expect(p.run(StreakTimeClass.blitz)!.currentStreak, 11);
      expect(p.run(StreakTimeClass.rapid), isNull);
      expect(PlayerStreaks.fromJson({'fide_id': 0, 'name': 'x'}, []), isNull);
      expect(PlayerStreaks.fromJson({'fide_id': 1}, []), isNull);
    });

    PlayerStreaks player(List<StreakClassRun> runs) => PlayerStreaks(
      fideId: 1,
      name: 'X, Y',
      runs: {for (final r in runs) r.timeClass: r},
    );

    test('opens on the asked class, else the hottest run', () {
      final p = player([
        _run(StreakTimeClass.standard, current: 1, best: 15),
        _run(StreakTimeClass.blitz, current: 11, best: 11),
      ]);
      expect(p.pickClass(), StreakTimeClass.blitz);
      expect(p.pickClass(StreakTimeClass.standard), StreakTimeClass.standard);
      expect(p.pickClass(StreakTimeClass.rapid), StreakTimeClass.blitz);
      expect(player([]).pickClass(StreakTimeClass.rapid), StreakTimeClass.rapid);
      expect(player([]).pickClass(), StreakTimeClass.standard);
    });

    test('ties go to the best-ever run, then classical, rapid, blitz', () {
      expect(
        player([
          _run(StreakTimeClass.blitz, current: 4, best: 9),
          _run(StreakTimeClass.rapid, current: 4, best: 12),
        ]).pickClass(),
        StreakTimeClass.rapid,
      );
      expect(
        player([
          _run(StreakTimeClass.blitz, current: 0, best: 7),
          _run(StreakTimeClass.rapid, current: 0, best: 7),
          _run(StreakTimeClass.standard, current: 0, best: 7),
        ]).pickClass(),
        StreakTimeClass.standard,
      );
    });
  });
}
