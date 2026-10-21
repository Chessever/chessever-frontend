import 'package:chessever2/screens/feed/logic/feed_ranker.dart';
import 'package:chessever2/screens/feed/logic/feed_taste.dart';
import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:flutter_test/flutter_test.dart';

FeedSignals _game(
  String id, {
  FeedPool pool = FeedPool.top,
  int white = 2600,
  int black = 2600,
  String result = '1-0',
  Duration age = const Duration(hours: 6),
  int likes = 0,
  String? event,
  Set<String> players = const {},
  bool seen = false,
  double interest = 0,
  ReportGameType? type,
  String? opening,
  bool freestyle = false,
  bool online = false,
  Set<String> countries = const {},
}) => FeedSignals(
  id: id,
  pool: pool,
  whiteElo: white,
  blackElo: black,
  result: result,
  age: age,
  likes: likes,
  eventKey: event ?? 'event-$id',
  playerKeys: players.isEmpty ? {'w-$id', 'b-$id'} : players,
  seenBefore: seen,
  reportInterest: interest,
  reportType: type,
  openingKey: opening,
  freestyle: freestyle,
  online: online,
  countries: countries,
);

List<FeedSignals> _drain(FeedRanker ranker, List<FeedSignals> pool, int n) => [
  for (var i = 0; i < n; i++) ranker.next(pool)!,
];

void main() {
  group('feedInterest', () {
    test('a decisive elite game beats a quiet draw', () {
      expect(
        feedInterest(_game('a', white: 2750, black: 2740)),
        greaterThan(
          feedInterest(_game('b', white: 2300, black: 2300, result: '½-½')),
        ),
      );
    });

    test('report action beats an otherwise identical quiet game', () {
      final quiet = _game('quiet');
      final exciting = _game(
        'exciting',
      ).withSeenBefore(false, reportInterest: 2.7);
      expect(FeedRanker(1).next([quiet, exciting])!.id, 'exciting');
      expect(exciting.withSeenBefore(true).reportInterest, 2.7);
    });

    test('a rating-gap result earns no invented quality bonus', () {
      final upset = _game('u', white: 2550, black: 2750);
      final expected = _game('e', white: 2750, black: 2550);
      expect(feedInterest(upset), feedInterest(expected));
    });

    test('recent report highlights beat an older quiet elite game', () {
      expect(
        FeedRanker(1).next([
          _game(
            'quiet',
            white: 2800,
            black: 2800,
            age: const Duration(days: 6),
          ),
          _game('highlight', white: 2500, black: 2500, interest: 2.5),
        ])!.id,
        'highlight',
      );
    });

    test('freshness has weight when report quality is equal', () {
      expect(
        FeedRanker(2).next([
          _game('old', age: const Duration(days: 6), interest: 2),
          _game('recent', interest: 2),
        ])!.id,
        'recent',
      );
    });

    test('a followed player lifts a game; being seen sinks it', () {
      final base = _game('x');
      expect(
        feedInterest(_game('x', pool: FeedPool.favorite)),
        greaterThan(feedInterest(base)),
      );
      expect(
        feedInterest(_game('x', seen: true)),
        lessThan(feedInterest(base)),
      );
    });
  });

  group('FeedRanker', () {
    test('opens on the single best game', () {
      final pool = [
        _game('club', white: 2200, black: 2210, result: '½-½'),
        _game('star', white: 2780, black: 2760, pool: FeedPool.favorite),
        _game('mid', white: 2500, black: 2480),
      ];
      expect(FeedRanker(1).next(pool)!.id, 'star');
      expect(pool.map((s) => s.id), isNot(contains('star')));
    });

    test('the same seed replays the same order', () {
      List<String> order(int seed) {
        final pool = [
          for (var i = 0; i < 30; i++) _game('g$i', white: 2400 + i * 10),
        ];
        final ranker = FeedRanker(seed);
        return [for (var i = 0; i < 30; i++) ranker.next(pool)!.id];
      }

      expect(order(7), order(7));
      expect(order(7), isNot(order(8)));
    });

    test('draws empty the pool exactly once each and honour eligibility', () {
      final pool = [for (var i = 0; i < 12; i++) _game('g$i')];
      final ranker = FeedRanker(3);
      final ids = <String>{};
      FeedSignals? next;
      while ((next = ranker.next(pool, eligible: (s) => s.id != 'g5')) !=
          null) {
        expect(ids.add(next!.id), isTrue);
      }
      expect(ids, hasLength(11));
      expect(pool.single.id, 'g5');
    });

    test('what was just shown tires: a story or an opening steps back', () {
      final ranker = FeedRanker(7);
      final repeat = _game(
        'repeat',
        type: ReportGameType.comeback,
        opening: 'C20',
      );
      final fresh = _game(
        'fresh',
        type: ReportGameType.greatEscape,
        opening: 'D30',
      );
      expect(ranker.appeal(repeat), ranker.appeal(fresh));
      ranker.next([
        _game('first', type: ReportGameType.comeback, opening: 'C2'),
      ]);
      expect(ranker.appeal(repeat), lessThan(ranker.appeal(fresh)));
    });

    test('weak games are never drawn while strong ones are on offer', () {
      for (var seed = 0; seed < 25; seed++) {
        final pool = [
          for (var i = 0; i < 4; i++)
            _game('strong$i', white: 2750, black: 2740, interest: 3),
          for (var i = 0; i < 300; i++)
            _game(
              'weak$i',
              white: 2300,
              black: 2300,
              result: '½-½',
              age: const Duration(days: 6),
            ),
        ];
        final picks = _drain(FeedRanker(seed), pool, 4);
        expect(
          picks.map((p) => p.id),
          everyElement(startsWith('strong')),
          reason: 'seed $seed',
        );
      }
    });

    test('a shortlist starts as tired as the feed it follows', () {
      final feed = FeedRanker(1);
      feed.next([_game('ff', event: 'ff', freestyle: true)]);
      final shortlist = FeedRanker.following(feed, 2);
      final again = _game('ff2', event: 'ff', freestyle: true);
      expect(shortlist.appeal(again), feed.appeal(again));
      expect(shortlist.appeal(again), lessThan(FeedRanker(3).appeal(again)));
    });
  });

  group('Taste: the feed learns the viewer (Trello: limit Freestyle)', () {
    // A Freestyle Friday evening: most of the pool is Freestyle, fresh and
    // strong, scoring well above everything else.
    List<FeedSignals> freestyleEvening() => [
      for (var i = 0; i < 60; i++)
        _game(
          'fs$i',
          white: 2700,
          black: 2690,
          age: const Duration(hours: 1),
          interest: 2.5,
          event: 'freestyle-friday',
          freestyle: true,
          online: true,
          players: {'fp${i % 12}', 'fq${i % 7}'},
        ),
      for (var i = 0; i < 160; i++)
        _game(
          'otb$i',
          white: 2560 + (i % 7) * 20,
          black: 2540,
          interest: 1 + (i % 5) / 2,
          event: 'classical-${i % 14}',
          age: Duration(hours: 4 + i),
        ),
    ];

    /// Freestyle share of 30-post sessions, posts 11 to 30, for a viewer
    /// whose visits earn [reward].
    double freestyleShare(double Function(FeedSignals) reward) {
      var freestyle = 0, total = 0;
      for (var seed = 0; seed < 60; seed++) {
        final taste = FeedTaste();
        final ranker = FeedRanker(seed, taste: taste);
        final pool = freestyleEvening();
        for (var k = 0; k < 30; k++) {
          final pick = ranker.next(pool)!;
          final r = reward(pick);
          taste.learn(
            pick,
            FeedVisit(
              dwell: Duration(seconds: r == 0 ? 1 : 10),
              progress: r,
            ),
          );
          if (k < 10) continue;
          total++;
          if (pick.freestyle) freestyle++;
        }
      }
      return freestyle / total;
    }

    test('a viewer with no say sees about one Freestyle game in ten', () {
      expect(freestyleShare((_) => 0.6), inInclusiveRange(0.06, 0.16));
    });

    test('a Freestyle fan is shown more; a viewer who skips it, less', () {
      final neutral = freestyleShare((_) => 0.6);
      final fan = freestyleShare((s) => s.freestyle ? 1.0 : 0.3);
      final skipper = freestyleShare((s) => s.freestyle ? 0.0 : 0.6);
      expect(fan, greaterThan(neutral * 1.4));
      expect(skipper, lessThan(neutral * 0.7));
    });

    test('one running event never takes over the feed', () {
      for (var seed = 0; seed < 25; seed++) {
        final pool = [
          for (var i = 0; i < 80; i++)
            _game(
              'blitz$i',
              white: 2720,
              black: 2700,
              interest: 2,
              event: 'russian-blitz',
            ),
          for (var i = 0; i < 60; i++)
            _game('other$i', white: 2560, black: 2550, event: 'event-$i'),
        ];
        final picks = _drain(FeedRanker(seed), pool, 30);
        for (var start = 0; start + 10 <= picks.length; start++) {
          expect(
            picks
                .sublist(start, start + 10)
                .where((p) => p.eventKey == 'russian-blitz')
                .length,
            lessThanOrEqualTo(4),
            reason: 'seed $seed at $start',
          );
        }
      }
    });

    test('followed players and countrymen come up more', () {
      int share(FeedTaste taste, bool Function(FeedSignals) mine) {
        var n = 0;
        for (var seed = 0; seed < 40; seed++) {
          final pool = [
            for (var i = 0; i < 20; i++)
              _game('m$i', players: {'carlsen', 'o$i'}, countries: {'NO'}),
            for (var i = 0; i < 80; i++) _game('g$i'),
          ];
          final ranker = FeedRanker(seed, taste: taste);
          n += _drain(ranker, pool, 10).where(mine).length;
        }
        return n;
      }

      bool magnus(FeedSignals s) => s.playerKeys.contains('carlsen');
      final plain = share(FeedTaste(), magnus);
      expect(
        share(FeedTaste()..seed(players: ['carlsen']), magnus),
        greaterThan(plain),
      );
      expect(
        share(FeedTaste()..seed(country: 'no'), magnus),
        greaterThan(plain),
      );
    });

    test('a quick swipe says no, watching says yes, a like says more', () {
      const skip = FeedVisit(dwell: Duration(milliseconds: 600));
      const watched = FeedVisit(dwell: Duration(seconds: 12), progress: 0.8);
      const liked = FeedVisit(
        dwell: Duration(seconds: 12),
        progress: 0.8,
        actions: {FeedAction.like},
      );
      expect(skip.reward, 0);
      expect(watched.reward, greaterThan(0.4));
      expect(liked.reward, greaterThan(watched.reward));
    });

    test('taste survives a restart and fades with age', () {
      final taste = FeedTaste();
      final game = _game('x', event: 'olympiad');
      for (var i = 0; i < 6; i++) {
        taste.learn(
          game,
          const FeedVisit(dwell: Duration(seconds: 20), progress: 1),
        );
      }
      final now = DateTime(2026, 10, 17);
      final raw = taste.encode(now);
      final same = FeedTaste()..restore(raw, now);
      final later = FeedTaste()..restore(raw, now.add(FeedTaste.halfLife * 3));
      expect(
        same.affinity('e:olympiad'),
        closeTo(taste.affinity('e:olympiad'), 1e-9),
      );
      expect(
        later.affinity('e:olympiad'),
        lessThan(same.affinity('e:olympiad')),
      );
      expect(later.affinity('e:olympiad'), greaterThan(0.5));
    });

    test('Freestyle and online start as a minority taste, not a ban', () {
      final taste = FeedTaste();
      expect(
        taste.score(_game('x', freestyle: true)),
        lessThan(taste.score(_game('x'))),
      );
      expect(
        taste.score(_game('x', online: true)),
        lessThan(taste.score(_game('x'))),
      );
      expect(taste.affinity('k:freestyle'), greaterThan(0.2));
    });
  });

  group('game kind and quality floor', () {
    test('event names', () {
      expect(feedIsFreestyleEvent('freestyle-friday-october-16-2026'), isTrue);
      expect(feedIsFreestyleEvent('freestyle-chess-grand-slam-paris'), isTrue);
      expect(feedIsFreestyleEvent(null, 'Chess960 Championship'), isTrue);
      expect(feedIsFreestyleEvent('2026-us-chess-championship'), isFalse);
      expect(feedIsOnlineEvent('freestyle-friday-october-16-2026'), isTrue);
      expect(feedIsOnlineEvent('3-0-thursday-october-15-2026-first'), isTrue);
      expect(feedIsOnlineEvent('2026-titled-tuesday-blitz-october-13'), isTrue);
      expect(
        feedIsOnlineEvent('2026-collegiate-chess-league-fall-division-7'),
        isTrue,
      );
      expect(feedIsOnlineEvent('russian-blitz-championship-2026'), isFalse);
      expect(feedIsOnlineEvent('2026-us-chess-championship'), isFalse);
    });

    test('PGN tells Freestyle from a set-up position', () {
      const freestyle =
          '[Event "2026 Freestyle Friday"]\n[Site "Chess.com"]\n'
          '[FEN "rnkrqbbn/pppppppp/8/8/8/8/PPPPPPPP/RNKRQBBN w DAda - 0 1"]\n'
          '[SetUp "1"]\n\n1. e4 e5 *';
      const midgame =
          '[Event "Study"]\n'
          '[FEN "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"]\n'
          '\n3. Bb5 *';
      const standard = '[Event "Olympiad"]\n[Site "Budapest"]\n\n1. e4 *';
      const variant = '[Variant "Chess960"]\n\n1. e4 *';
      expect(feedPgnIsFreestyle(freestyle), isTrue);
      expect(feedPgnIsFreestyle(variant), isTrue);
      expect(feedPgnIsFreestyle(midgame), isFalse);
      expect(feedPgnIsFreestyle(standard), isFalse);
      expect(feedPgnIsOnline(freestyle), isTrue);
      expect(feedPgnIsOnline(standard), isFalse);
    });

    test('a strong player alone does not carry a weak pairing in', () {
      expect(
        feedMeetsQualityFloor(_game('a', white: 1965, black: 2492)),
        isFalse,
      );
      expect(feedMeetsQualityFloor(_game('b', white: 0, black: 2700)), isFalse);
      expect(
        feedMeetsQualityFloor(_game('c', white: 2400, black: 2450)),
        isTrue,
      );
      expect(
        feedMeetsQualityFloor(
          _game('d', white: 1965, black: 2492, pool: FeedPool.favorite),
        ),
        isTrue,
      );
    });
  });
}
