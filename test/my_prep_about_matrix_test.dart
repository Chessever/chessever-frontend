import 'dart:math' as math;

import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_identity.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Every source a profile can read, two of one kind among them.
const _sources = [
  (PrepSource.lichess, '/prep/lichess_a.pgn'),
  (PrepSource.chesscom, '/prep/chesscom_a.pgn'),
  (PrepSource.chesscom, '/prep/chesscom_b.pgn'),
  (PrepSource.chessever, '/prep/chessever_a.pgn'),
  (PrepSource.manual, '/prep/manual_a.pgn'),
];

/// Written as sources write them: in either case, padded, or missing.
const _ecos = ['C50', 'c50', ' B90 ', 'B90', 'D37', 'E60', 'A00', null];
const _openings = [
  'Italian Game: Giuoco Piano',
  'Sicilian Defense, Najdorf',
  'Queen\'s Gambit Declined',
  null,
];

/// Two spellings of one opponent, and the names no opponent is listed by.
const _opponents = [
  'Anna',
  'anna ',
  'Boris',
  'Clara',
  'Dmitri',
  'Eve',
  'Farid',
  'Gita',
  'Hugo',
  'Ines',
  'Jon',
  'Kira',
  'Lev',
  '?',
  '',
];

const _speeds = [
  PrepTimeControl.bullet,
  PrepTimeControl.blitz,
  PrepTimeControl.rapid,
  PrepTimeControl.classical,
  PrepTimeControl.correspondence,
  null,
];

/// A career in every state a game arrives in: either side or neither,
/// finished or not, with and without a clock, a date, a code, ratings.
List<PrepGame> _career(math.Random random, int count) {
  T pick<T>(List<T> from) => from[random.nextInt(from.length)];
  final games = <PrepGame>[];
  for (var i = 0; i < count; i++) {
    final (source, path) = pick(_sources);
    final side = pick(const [true, false, true, false, null]);
    final opponent = pick(_opponents);
    final day = random.nextInt(2400);
    final date = random.nextInt(12) == 0
        ? null
        : DateTime.utc(2019, 1, 1).add(Duration(days: day));
    int? elo() => random.nextInt(6) == 0 ? null : 1200 + random.nextInt(1600);
    games.add(
      PrepGame(
        index: i,
        source: source,
        sourcePath: path,
        white: side == false ? opponent : 'Hero',
        black: side == false ? 'Hero' : opponent,
        result: pick(const ['1-0', '0-1', '1/2-1/2', '*']),
        plies: pick(const [0, 12, 40, 41, 60, 61, 80, 81, 100, 101, 150]),
        playerIsWhite: side,
        whiteElo: elo(),
        blackElo: elo(),
        speed: pick(_speeds),
        date: date,
        eco: pick(_ecos),
        opening: pick(_openings),
      ),
    );
  }
  // Newest first, as a profile's analysis holds them.
  games.sort(
    (a, b) =>
        (b.date ?? DateTime.utc(1900)).compareTo(a.date ?? DateTime.utc(1900)),
  );
  return games;
}

PrepTally _tally(Iterable<PrepGame> games) {
  var tally = const PrepTally();
  for (final g in games) {
    if (g.playerIsWhite != null) tally += g.outcome;
  }
  return tally;
}

String _code(PrepGame g) => g.eco?.trim().toUpperCase() ?? '';

String _opponentKey(PrepGame g) => g.opponent.trim().toLowerCase();

bool _named(PrepGame g) {
  final name = g.opponent.trim();
  return g.playerIsWhite != null && name.isNotEmpty && name != '?';
}

/// A filter as About's choices and the Games filters make them.
PrepFilter _randomFilter(math.Random random, List<PrepGame> games) {
  T? maybe<T>(List<T> from, {int odds = 3}) =>
      random.nextInt(odds) == 0 ? from[random.nextInt(from.length)] : null;
  final scope = random.nextInt(4);
  final (source, path) = _sources[random.nextInt(_sources.length)];
  final years = {for (final g in games) ?g.date?.year}.toList();
  return PrepFilter(
    // Every source together, one kind of source, or one source alone.
    source: scope == 0 ? null : source,
    accountKey: scope >= 2 ? path : null,
    accountFile: scope >= 2 ? path.split('/').last : null,
    window: random.nextInt(4) == 0
        ? PrepStatsWindow.values[random.nextInt(PrepStatsWindow.values.length)]
        : PrepStatsWindow.all,
    speed: maybe(PrepTimeControl.values),
    side: PrepSide.values[random.nextInt(PrepSide.values.length)],
    outcome: maybe(PrepOutcome.values.take(3).toList()),
    // A year these games were played in, now and then one they were not.
    year: maybe([...years, 1999]),
    eco: maybe(const ['C50', 'B90', 'D37', 'E60', 'A00', 'Z99']),
    opponent: maybe(const ['Anna', 'Boris', 'Clara', 'Nobody'], odds: 4),
    length: maybe(const [0, 1, 2, 3, 4]),
    opening: maybe(const ['Italian Game', 'Sicilian Defense'], odds: 8),
    base: random.nextInt(8) == 0
        ? GameFilter().copyWith(minYear: 2021 + random.nextInt(3))
        : null,
  );
}

void main() {
  test('About agrees with the games Games lists, for every combination of '
      'source and choices', () {
    for (final seed in [1, 2, 3, 4]) {
      final random = math.Random(seed);
      final games = _career(random, 700);
      final facets = PrepFacets(games);
      for (var round = 0; round < 400; round++) {
        final filter = _randomFilter(random, games);
        final rating = random.nextBool()
            ? _sources[random.nextInt(_sources.length)].$2.split('/').last
            : null;
        final s = filter.stats(facets, ratingAccount: rating);
        final why =
            'seed $seed round $round: ${filter.summary} '
            '${filter.accountFile ?? ''}';

        // What Games lists, and the results counted out of it.
        final listed = filter.apply(games);
        expect(s.matching, listed.length, reason: why);
        final ofResults = filter.copyWith(outcome: null).apply(games);
        expect(s.games, ofResults.length, reason: why);
        final overall = _tally(ofResults);
        expect(
          (s.overall.wins, s.overall.draws, s.overall.losses),
          (overall.wins, overall.draws, overall.losses),
          reason: why,
        );

        // Colours keep both, whichever is chosen.
        final ofColours = filter.copyWith(side: PrepSide.both).apply(games);
        final white = ofColours.where((g) => g.playerIsWhite == true);
        final black = ofColours.where((g) => g.playerIsWhite == false);
        expect(s.whiteGames, white.length, reason: why);
        expect(s.blackGames, black.length, reason: why);
        expect(s.asWhite.total, _tally(white).total, reason: why);
        expect(s.asWhite.wins, _tally(white).wins, reason: why);
        expect(s.asBlack.total, _tally(black).total, reason: why);
        expect(s.asBlack.losses, _tally(black).losses, reason: why);

        // Clocks keep every clock beside the chosen one.
        final ofClocks = filter.copyWith(speed: null).apply(games);
        final clocks = <PrepTimeControl?, int>{};
        for (final g in ofClocks) {
          clocks[g.speed] = (clocks[g.speed] ?? 0) + 1;
        }
        expect(
          {
            for (final (speed, count) in s.clocks)
              if (count > 0) speed: count,
          },
          clocks,
          reason: why,
        );
        if (filter.speed case final speed?) {
          expect(s.clocks.map((c) => c.$1), contains(speed), reason: why);
        }
        expect(
          s.clocks.map((c) => c.$2).toList(),
          [...s.clocks.map((c) => c.$2)]..sort((a, b) => b.compareTo(a)),
          reason: '$why: clocks most played first',
        );

        // Years.
        final ofYears = filter.copyWith(year: null).apply(games);
        final years = <int, List<PrepGame>>{};
        for (final g in ofYears) {
          if (g.date case final date?) {
            (years[date.year] ??= []).add(g);
          }
        }
        for (final line in s.byYear) {
          final played = years[line.year] ?? const [];
          expect(line.total, played.length, reason: '$why: ${line.year}');
          expect(
            line.tally.total,
            _tally(played).total,
            reason: '$why: ${line.year}',
          );
        }
        expect(
          s.byYear.where((y) => y.total > 0).map((y) => y.year).toSet(),
          years.keys.toSet(),
          reason: why,
        );

        // Lengths.
        final ofLengths = filter.copyWith(length: null).apply(games);
        final lengths = List.filled(PrepStats.lengthLabels.length, 0);
        for (final g in ofLengths) {
          if (PrepStats.lengthOf(g.plies) case final at?) lengths[at]++;
        }
        expect(s.lengths, lengths, reason: why);

        // Opponents: the ten most met, counted however they are spelled.
        final ofOpponents = filter.copyWith(opponent: null).apply(games);
        final met = <String, List<PrepGame>>{};
        for (final g in ofOpponents.where(_named)) {
          (met[_opponentKey(g)] ??= []).add(g);
        }
        for (final line in s.opponents) {
          final played = met[line.name.trim().toLowerCase()] ?? const [];
          expect(line.games, played.length, reason: '$why: ${line.name}');
          expect(
            line.tally.total,
            _tally(played).total,
            reason: '$why: ${line.name}',
          );
          final rated = [
            for (final g in played)
              if ((g.opponentElo ?? 0) > 0) g.opponentElo!,
          ];
          expect(
            line.rating,
            rated.isEmpty
                ? null
                : (rated.reduce((a, b) => a + b) / rated.length).round(),
            reason: '$why: ${line.name}',
          );
        }
        final listedNames = {
          for (final o in s.opponents) o.name.trim().toLowerCase(),
        };
        // A chosen opponent outside the ten follows them as an eleventh.
        final ten = s.opponents.take(10).toList();
        for (final MapEntry(:key, :value) in met.entries) {
          final finished = _tally(value).total;
          if (finished == 0 || listedNames.contains(key)) continue;
          // Left out only below ten others that were met more.
          expect(ten, hasLength(10), reason: '$why: $key');
          expect(
            finished,
            lessThanOrEqualTo(ten.map((o) => o.tally.total).reduce(math.min)),
            reason: '$why: $key',
          );
        }

        // Openings: a colour's ten most played, whatever colour is chosen.
        final ofLines = filter
            .copyWith(eco: null, side: PrepSide.both)
            .apply(games);
        for (final (colour, lines) in [
          (true, s.whiteOpenings),
          (false, s.blackOpenings),
        ]) {
          final played = <String, List<PrepGame>>{};
          for (final g in ofLines) {
            if (g.playerIsWhite != colour || _code(g).isEmpty) continue;
            (played[_code(g)] ??= []).add(g);
          }
          for (final line in lines) {
            final own = played[line.eco] ?? const [];
            expect(line.games, own.length, reason: '$why: ${line.eco}');
            expect(
              line.tally.total,
              _tally(own).total,
              reason: '$why: ${line.eco}',
            );
          }
          final shown = {for (final l in lines) l.eco};
          final ten = lines.take(10).toList();
          for (final MapEntry(:key, :value) in played.entries) {
            final finished = _tally(value).total;
            if (finished == 0 || shown.contains(key)) continue;
            expect(ten, hasLength(10), reason: '$why: $key');
            expect(
              finished,
              lessThanOrEqualTo(ten.map((l) => l.tally.total).reduce(math.min)),
              reason: '$why: $key',
            );
          }
        }

        // Rating figures: one source's scale, never two averaged.
        final read = <String>{for (final g in listed) g.sourcePath};
        expect(s.accounts, read.length, reason: why);
        if (s.ratingPath case final path?) {
          final own = [
            for (final g in listed)
              if (g.sourcePath == path && g.playerIsWhite != null) g,
          ];
          final theirs = [
            for (final g in own)
              if ((g.opponentElo ?? 0) > 0) g.opponentElo!,
          ];
          expect(
            s.averageOpponent,
            theirs.isEmpty
                ? null
                : (theirs.reduce((a, b) => a + b) / theirs.length).round(),
            reason: why,
          );
          final history = s.ratingHistory.map((p) => p.$2).toSet();
          final mine = {
            for (final g in own)
              if ((g.playerElo ?? 0) > 0 && g.date != null) g.playerElo!,
          };
          expect(mine.containsAll(history), isTrue, reason: why);
          final asked = rating == null
              ? null
              : own.any(
                  (g) =>
                      g.sourcePath.endsWith(rating) &&
                      (g.playerElo ?? 0) > 0 &&
                      g.date != null,
                );
          // The source asked for leads wherever it has rated games.
          if (asked == true && s.ratingHistory.isNotEmpty) {
            expect(path.endsWith(rating!), isTrue, reason: why);
          }
        }
        if (s.ratingHistory.isNotEmpty) {
          final points = s.ratingHistory.map((p) => p.$2);
          expect(s.peakRating, points.reduce(math.max), reason: why);
          expect(s.currentRating, s.ratingHistory.last.$2, reason: why);
        }
      }
    }
  });

  test('a choice given up is the statistics it was taken from', () {
    final random = math.Random(9);
    final games = _career(random, 400);
    final facets = PrepFacets(games);
    for (var round = 0; round < 200; round++) {
      final base = _randomFilter(random, games);
      // One choice a group: each is taken where its group has none.
      for (final (before, take)
          in <(PrepFilter, PrepFilter Function(PrepFilter))>[
            (base.withSpeed(null), (f) => f.toggleSpeed(PrepTimeControl.blitz)),
            (
              base.copyWith(outcome: null),
              (f) => f.toggleOutcome(PrepOutcome.draw),
            ),
            (base.copyWith(year: null), (f) => f.toggleYear(2022)),
            (base.copyWith(length: null), (f) => f.toggleLength(2)),
            (base.copyWith(opponent: null), (f) => f.toggleOpponent('Boris')),
          ]) {
        final plain = before.stats(facets);
        final taken = take(before);
        expect(taken.narrows, isTrue);
        final again = take(taken).stats(facets);
        expect(again.matching, plain.matching, reason: 'round $round');
        expect(again.overall.total, plain.overall.total);
        expect(again.clocks, plain.clocks);
        expect(again.lengths, plain.lengths);
        expect(again.byYear.map((y) => (y.year, y.total)), [
          for (final y in plain.byYear) (y.year, y.total),
        ]);
      }
    }
  });

  group('the ratings games carry', () {
    PrepGame game(
      String path, {
      required PrepTimeControl? speed,
      bool? white = true,
      int? mine,
      int? theirs,
      DateTime? date,
    }) => PrepGame(
      index: 0,
      source: PrepSource.lichess,
      sourcePath: path,
      white: 'Hero',
      black: 'Rival',
      result: '1-0',
      plies: 40,
      speed: speed,
      playerIsWhite: white,
      whiteElo: white == false ? theirs : mine,
      blackElo: white == false ? mine : theirs,
      date: date,
    );

    test('are the newest rated game of each clock, by source file', () {
      final ratings = prepGameRatings([
        // Newest first.
        game(
          '/prep/a.pgn',
          speed: PrepTimeControl.blitz,
          mine: 2500,
          date: DateTime.utc(2025, 3, 2),
        ),
        game(
          '/prep/a.pgn',
          speed: PrepTimeControl.blitz,
          mine: 2400,
          date: DateTime.utc(2025, 3, 1),
        ),
        // As Black, the player's rating is Black's.
        game(
          '/prep/a.pgn',
          speed: PrepTimeControl.rapid,
          white: false,
          mine: 2300,
          theirs: 1500,
          date: DateTime.utc(2024, 1, 1),
        ),
        // Played, but with no rating to read.
        game('/prep/a.pgn', speed: PrepTimeControl.bullet),
        // Whose side is not known says nothing of the player.
        game(
          '/prep/b.pgn',
          speed: PrepTimeControl.blitz,
          white: null,
          mine: 2900,
          theirs: 2900,
        ),
        game('b.pgn', speed: PrepTimeControl.classical, mine: 2100),
        game('/prep/a.pgn', speed: null, mine: 2800),
      ]);
      expect(ratings['a.pgn'], {
        PrepTimeControl.blitz: 2500,
        PrepTimeControl.rapid: 2300,
        PrepTimeControl.bullet: 0,
      });
      expect(ratings['b.pgn'], {
        PrepTimeControl.blitz: 0,
        PrepTimeControl.classical: 2100,
      });
    });

    test('follow the date, not the order, and prefer a dated game', () {
      final ratings = prepGameRatings([
        game('x.pgn', speed: PrepTimeControl.rapid, mine: 1000),
        game(
          'x.pgn',
          speed: PrepTimeControl.rapid,
          mine: 1700,
          date: DateTime.utc(2023, 1, 1),
        ),
        game(
          'x.pgn',
          speed: PrepTimeControl.rapid,
          mine: 1800,
          date: DateTime.utc(2024, 1, 1),
        ),
        game(
          'x.pgn',
          speed: PrepTimeControl.rapid,
          mine: 1750,
          date: DateTime.utc(2024, 1, 1),
        ),
      ]);
      expect(ratings['x.pgn']![PrepTimeControl.rapid], 1800);
    });
  });

  test('a history of fast and slow games alone keeps to one clock', () {
    PrepGame rated(int day, PrepTimeControl speed, int rating) => PrepGame(
      index: day,
      source: PrepSource.chesscom,
      sourcePath: 'c.pgn',
      white: 'Hero',
      black: 'Rival',
      result: '1-0',
      plies: 40,
      speed: speed,
      playerIsWhite: true,
      whiteElo: rating,
      blackElo: 1500,
      date: DateTime.utc(2025, 1, 1).add(Duration(days: day)),
    );
    final s = PrepStats.of([
      for (var day = 9; day >= 0; day--) ...[
        rated(day, PrepTimeControl.bullet, 2900 + day),
        if (day.isEven) rated(day, PrepTimeControl.correspondence, 1100),
      ],
    ]);
    expect(s.ratingSpeed, PrepTimeControl.bullet);
    expect(s.ratingHistory.map((p) => p.$2), [
      for (var day = 0; day < 10; day++) 2900 + day,
    ]);
    expect(s.currentRating, 2909);
  });

  group('the identity\'s ratings', () {
    const database = PrepAccount(
      source: PrepSource.chessever,
      username: 'Hero, Ada',
      externalId: '7',
      ratings: {'classical': 2611},
    );
    const lichess = PrepAccount(
      source: PrepSource.lichess,
      username: 'AdaHero',
      ratings: {'blitz': 2805},
    );
    // Added from a known handle: no ratings of its own yet.
    const chesscom = PrepAccount(
      source: PrepSource.chesscom,
      username: 'adahero',
    );
    final fromGames = {
      PrepRepository.gamesFileName(chesscom): {
        PrepTimeControl.rapid: 2302,
        PrepTimeControl.bullet: 0,
      },
    };

    Future<List<PrepTimeControl>> pump(
      WidgetTester tester,
      List<PrepAccount> accounts, {
      String? accountKey,
    }) async {
      final taken = <PrepTimeControl>[];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            builder: (context, child) {
              ResponsiveHelper.init(context);
              return child!;
            },
            home: Scaffold(
              body: PrepIdentity(
                profile: PrepProfile(
                  id: 'p',
                  kind: PrepKind.opponent,
                  name: 'Ada Hero',
                  createdAtMs: 1,
                  accounts: accounts,
                ),
                accountKey: accountKey,
                gameRatings: fromGames,
                onRating: taken.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return taken;
    }

    String label(WidgetTester tester, String clock) => tester
        .widget<Semantics>(
          find
              .ancestor(
                of: find.text(clock),
                matching: find.byWidgetPredicate(
                  (w) => w is Semantics && w.properties.label != null,
                ),
              )
              .first,
        )
        .properties
        .label!;

    testWidgets('a source with no ratings of its own reads them from its '
        'games, and its clocks narrow About', (tester) async {
      final taken = await pump(tester, [chesscom]);
      expect(find.text('Bullet'), findsOneWidget);
      expect(find.text('2302'), findsOneWidget);
      // Played, without a rating anywhere: nothing to read, still a choice.
      expect(label(tester, 'Bullet'), 'Bullet rating not recorded');
      await tester.tap(find.text('Bullet'));
      await tester.tap(find.text('Rapid'));
      // Never played: nothing to narrow to.
      await tester.tap(find.text('Blitz'));
      expect(taken, [PrepTimeControl.bullet, PrepTimeControl.rapid]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('read together, a clock the main source lacks takes '
        'another source\'s rating, named', (tester) async {
      final taken = await pump(tester, [chesscom, lichess, database]);
      // The database player leads: the three FIDE clocks.
      expect(find.text('Classical'), findsOneWidget);
      expect(find.text('2611'), findsOneWidget);
      expect(find.text('2302'), findsOneWidget);
      expect(find.text('2805'), findsOneWidget);
      expect(label(tester, 'Classical'), 'Classical rating 2611 on ChessEver');
      expect(label(tester, 'Rapid'), 'Rapid rating 2302 on Chess.com');
      expect(label(tester, 'Blitz'), 'Blitz rating 2805 on Lichess');
      await tester.tap(find.text('2805'));
      expect(taken, [PrepTimeControl.blitz]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one source read alone shows its own ratings only', (
      tester,
    ) async {
      final taken = await pump(tester, [
        chesscom,
        lichess,
        database,
      ], accountKey: lichess.key);
      expect(find.text('Bullet'), findsOneWidget);
      expect(find.text('2805'), findsOneWidget);
      // Chess.com's rapid is another source's, and not this one's to show.
      expect(find.text('2302'), findsNothing);
      expect(find.text('2611'), findsNothing);
      expect(label(tester, 'Blitz'), 'Blitz rating 2805 on Lichess');
      expect(label(tester, 'Rapid'), 'Rapid rating not recorded');
      await tester.tap(find.text('Rapid'));
      expect(taken, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
