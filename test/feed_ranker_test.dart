import 'package:chessever2/screens/feed/logic/feed_ranker.dart';
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
);

/// Every run of [FeedRanker.window] consecutive picks in [picks] has at most
/// [max] that pass [test].
void _expectWindowCap(
  List<FeedSignals> picks,
  bool Function(FeedSignals) test,
  int max, {
  String reason = '',
}) {
  for (var start = 0; start + FeedRanker.window <= picks.length; start++) {
    final count = picks
        .sublist(start, start + FeedRanker.window)
        .where(test)
        .length;
    expect(
      count,
      lessThanOrEqualTo(max),
      reason: '$reason window at $start: ${picks.map((p) => p.id).toList()}',
    );
  }
}

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
    test('stories and openings do not repeat by default', () {
      final ranker = FeedRanker(7);
      ranker.next([
        _game('first', type: ReportGameType.comeback, opening: 'C20'),
      ]);
      expect(
        ranker.varietyFactor(
          _game('repeat', type: ReportGameType.comeback, opening: 'C20'),
        ),
        lessThan(
          ranker.varietyFactor(
            _game(
              'different',
              type: ReportGameType.greatEscape,
              opening: 'D30',
            ),
          ),
        ),
      );
      ranker.next([_game('second', type: ReportGameType.comeback)]);
      final pool = [
        _game(
          'third',
          white: 2800,
          black: 2800,
          interest: 3,
          type: ReportGameType.comeback,
        ),
        _game('escape', type: ReportGameType.greatEscape),
      ];
      expect(ranker.next(pool)!.id, 'escape');
    });
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

    test('never serves one event three times in a row when others exist', () {
      final pool = [
        for (var i = 0; i < 20; i++)
          _game('ol$i', white: 2750, black: 2740, event: 'olympiad'),
        for (var i = 0; i < 20; i++)
          _game('op$i', white: 2450, black: 2440, event: 'open-$i'),
      ];
      for (var seed = 0; seed < 20; seed++) {
        final copy = [...pool];
        final ranker = FeedRanker(seed);
        final events = [
          for (var i = 0; i < 15; i++) ranker.next(copy)!.eventKey,
        ];
        var run = 1;
        for (var i = 1; i < events.length; i++) {
          run = events[i] == 'olympiad' && events[i - 1] == 'olympiad'
              ? run + 1
              : 1;
          expect(run, lessThan(3), reason: 'seed $seed: $events');
        }
      }
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
  });

  group('Feed quotas (Trello: limit Freestyle chess in Feed)', () {
    // A Freestyle Friday evening: most of the pool is Freestyle, fresh and
    // strong, scoring above everything else.
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
        ),
      for (var i = 0; i < 30; i++)
        _game(
          'otb$i',
          white: 2550,
          black: 2540,
          age: const Duration(days: 2),
          event: 'classical-$i',
        ),
    ];

    test('at most one Freestyle game in any ten, whatever the pool', () {
      for (var seed = 0; seed < 25; seed++) {
        final picks = _drain(FeedRanker(seed), freestyleEvening(), 30);
        _expectWindowCap(
          picks,
          (p) => p.freestyle,
          FeedRanker.freestylePerWindow,
          reason: 'seed $seed',
        );
        // It still has its share: a Freestyle game turns up.
        expect(picks.where((p) => p.freestyle), isNotEmpty);
      }
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
          for (var i = 0; i < 25; i++)
            _game('other$i', white: 2560, black: 2550, event: 'event-$i'),
        ];
        _expectWindowCap(
          _drain(FeedRanker(seed), pool, 30),
          (p) => p.eventKey == 'russian-blitz',
          FeedRanker.eventPerWindow,
          reason: 'seed $seed',
        );
      }
    });

    test('online dumps leave room for over-the-board games', () {
      for (var seed = 0; seed < 25; seed++) {
        final pool = [
          for (var i = 0; i < 80; i++)
            _game('on$i', interest: 2, event: 'thursday-$i', online: true),
          for (var i = 0; i < 25; i++)
            _game('otb$i', white: 2500, black: 2500, event: 'otb-$i'),
        ];
        _expectWindowCap(
          _drain(FeedRanker(seed), pool, 30),
          (p) => p.online,
          FeedRanker.onlinePerWindow,
          reason: 'seed $seed',
        );
      }
    });

    test('one player is not on every other post', () {
      for (var seed = 0; seed < 25; seed++) {
        final pool = [
          for (var i = 0; i < 30; i++)
            _game(
              'magnus$i',
              white: 2830,
              black: 2700,
              interest: 2,
              players: {'magnus', 'opp$i'},
            ),
          for (var i = 0; i < 30; i++) _game('g$i'),
        ];
        _expectWindowCap(
          _drain(FeedRanker(seed), pool, 30),
          (p) => p.playerKeys.contains('magnus'),
          FeedRanker.playerPerWindow,
          reason: 'seed $seed',
        );
      }
    });

    test('quotas give way rather than leave the feed empty', () {
      final pool = [
        for (var i = 0; i < 12; i++)
          _game('fs$i', event: 'freestyle', freestyle: true, online: true),
      ];
      final ranker = FeedRanker(4);
      expect(_drain(ranker, pool, 12), hasLength(12));
    });

    test('a shortlist follows the quota the feed already used', () {
      final feed = FeedRanker(1);
      feed.next([_game('fs', freestyle: true)]);
      final shortlist = FeedRanker.following(feed, 2);
      expect(shortlist.breaksQuota(_game('fs2', freestyle: true)), isTrue);
      expect(shortlist.breaksQuota(_game('plain')), isFalse);
      final pool = [
        _game('fs3', interest: 3, freestyle: true),
        _game('plain2'),
      ];
      expect(shortlist.next(pool)!.id, 'plain2');
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

    test('Freestyle and online games rank a little below their twin', () {
      final base = feedInterest(_game('x'));
      expect(feedInterest(_game('x', freestyle: true)), lessThan(base));
      expect(feedInterest(_game('x', online: true)), lessThan(base));
    });
  });
}
