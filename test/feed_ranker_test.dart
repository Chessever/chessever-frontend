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
);

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
}
