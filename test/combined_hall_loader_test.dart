import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_hall_loader.dart';

const r1 = (id: 'a1', source: 'a');
const r2 = (id: 'a2', source: 'a');
const r3 = (id: 'a3', source: 'a');
typedef R = ({String id, String source});
CombinedHallLoader<R, int> hall({
  List<String> sources = const ['a'],
  Future<List<R>> Function(String)? source,
  Future<List<int>> Function(R, int, int)? page,
  void Function()? change,
  bool Function(int)? finished,
  bool Function(R, int)? valid,
}) => CombinedHallLoader<R, int>(
  sourceIds: sources,
  readSource: source ?? (_) async => [r1],
  readPage: page ?? (_, __, ___) async => [1],
  roundId: (r) => r.id,
  sourceId: (r) => r.source,
  validGame: valid ?? (_, __) => true,
  finished: finished ?? (_) => false,
  orderRounds: (rounds) => rounds,
  onChange: change ?? () {},
);
void main() {
  test('removed metadata cannot be revived by a late round response', () {
    fakeAsync((clock) {
      var catalogs = 0;
      final pending = Completer<List<int>>();
      final loader = hall(
        source: (_) async => ++catalogs == 1 ? [r1, r2] : [r1],
        page: (r, __, ___) async => r.id == 'a2' ? pending.future : [],
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(milliseconds: 120));
      loader.refresh();
      clock.flushMicrotasks();
      pending.complete([2]);
      clock.flushMicrotasks();
      expect(loader.catalogs['a'], [r1]);
      expect(loader.games.containsKey('a2'), isFalse);
      loader.dispose();
    });
  });
  test(
    'anchor preview appears before a stalled sibling; remaining boards page without truncation',
    () {
      fakeAsync((clock) {
        final sibling = Completer<List<R>>();
        final calls = <(String, int, int)>[];
        final loader = hall(
          sources: ['a', 'b'],
          source: (id) async => id == 'a' ? [r1] : sibling.future,
          page: (r, offset, limit) async {
            calls.add((r.id, offset, limit));
            return List.generate(
              (1117 - offset).clamp(0, limit),
              (i) => offset + i,
            );
          },
        );
        clock.flushMicrotasks();
        expect(loader.games['a1'], hasLength(16));
        expect(calls, [('a1', 0, 16)]);
        clock.elapse(const Duration(milliseconds: 120));
        expect(loader.games['a1'], hasLength(1117));
        expect(calls, [('a1', 0, 16), ('a1', 16, 1000), ('a1', 1016, 1000)]);
        expect(loader.loaded, contains('a1'));
        expect(loader.catalogs.keys, ['a']);
        loader.dispose();
      });
    },
  );
  test('two background jobs leave a third lane for an expanded round', () {
    fakeAsync((clock) {
      final pending = <String, Completer<List<int>>>{};
      final loader = hall(
        source: (_) async => [r1, r2, r3, (id: 'a4', source: 'a')],
        page: (r, offset, limit) async =>
            limit == 16 ? [] : (pending[r.id] = Completer<List<int>>()).future,
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(milliseconds: 120));
      expect(pending.keys, ['a2', 'a3']);
      loader.demand(['a4']);
      clock.flushMicrotasks();
      expect(pending.keys, ['a2', 'a3', 'a4']);
      loader.dispose();
    });
  });
  test('background publications coalesce; demand publishes immediately', () {
    fakeAsync((clock) {
      var changes = 0;
      final pending = Completer<List<int>>();
      final loader = hall(
        source: (_) async => [r1, r2, r3],
        change: () => changes++,
        page: (r, _, __) async => r.id == 'a3' ? pending.future : [1],
      );
      clock.flushMicrotasks();
      final initial = changes;
      clock.elapse(const Duration(milliseconds: 120));
      expect(changes, initial);
      loader.demand(['a3']);
      pending.complete([3]);
      clock.flushMicrotasks();
      expect(changes, initial + 1);
      clock.elapse(const Duration(milliseconds: 200));
      expect(changes, initial + 1);
      loader.dispose();
    });
  });
  test('metadata owns all round headers before their games load', () {
    fakeAsync((clock) {
      final loader = hall(source: (_) async => [r1, r2, r3]);
      clock.flushMicrotasks();
      expect(loader.catalogs['a'], [r1, r2, r3]);
      expect(loader.games.keys, ['a1']);
      loader.dispose();
    });
  });
  test(
    'pause rejects late completions and stops background and refresh work; resume recovers',
    () {
      fakeAsync((clock) {
        final first = Completer<List<int>>();
        var requests = 0;
        final loader = hall(
          page: (_, __, ___) async => ++requests == 1 ? first.future : [2],
        );
        clock.flushMicrotasks();
        loader.setActive(false);
        first.complete([1]);
        clock.flushMicrotasks();
        clock.elapse(const Duration(minutes: 1));
        expect(loader.games, isEmpty);
        expect(requests, 1);
        loader.setActive(true);
        clock.flushMicrotasks();
        expect(loader.games['a1'], [2]);
        loader.dispose();
      });
    },
  );
  test('disposing ignores late completions and publishes nothing', () {
    fakeAsync((clock) {
      final page = Completer<List<int>>();
      var changes = 0;
      final loader = hall(
        page: (_, __, ___) => page.future,
        change: () => changes++,
      );
      clock.flushMicrotasks();
      final before = changes;
      loader.dispose();
      page.complete([1]);
      clock.elapse(const Duration(minutes: 1));
      expect(loader.games, isEmpty);
      expect(changes, before);
    });
  });
  test(
    'empty rounds cache, finished rounds stay cached, only watched unfinished rounds refresh',
    () {
      fakeAsync((clock) {
        final calls = <String, int>{};
        final loader = hall(
          source: (_) async => [r1, r2, r3],
          finished: (g) => g == 2,
          page: (r, __, ___) async {
            calls.update(r.id, (n) => n + 1, ifAbsent: () => 1);
            return r.id == 'a1'
                ? []
                : r.id == 'a2'
                ? [2]
                : [3];
          },
        );
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 1));
        loader.watch(['a2', 'a3']);
        clock.elapse(const Duration(seconds: 20));
        expect(calls, {'a1': 1, 'a2': 1, 'a3': 2});
        loader.dispose();
      });
    },
  );
  test(
    'refresh discovers appended rounds without refetching completed snapshots',
    () {
      fakeAsync((clock) {
        var reads = 0;
        final calls = <String>[];
        final loader = hall(
          source: (_) async => ++reads == 1 ? [r1] : [r1, r2],
          page: (r, __, ___) async {
            calls.add(r.id);
            return [];
          },
        );
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 21));
        expect(loader.catalogs['a'], [r1, r2]);
        expect(calls, ['a1', 'a2']);
        loader.dispose();
      });
    },
  );
  test(
    'wrong round identity is rejected; failed reads retry only on explicit retry',
    () {
      fakeAsync((clock) {
        var calls = 0;
        var valid = false;
        final loader = hall(
          valid: (_, __) => valid,
          page: (_, __, ___) async {
            calls++;
            return [1];
          },
        );
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 41));
        expect(loader.games, isEmpty);
        expect(calls, 1);
        expect(loader.failures, contains('round:a1'));
        valid = true;
        loader.refresh(retry: true);
        clock.flushMicrotasks();
        expect(loader.games['a1'], [1]);
        expect(calls, 2);
        loader.dispose();
      });
    },
  );
  test('failed anchor does not strand the remaining source catalogs', () {
    fakeAsync((clock) {
      final loader = hall(
        sources: ['a', 'b'],
        source: (id) async {
          if (id == 'a') throw StateError('offline');
          return [(id: 'b1', source: 'b')];
        },
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      expect(loader.games['b1'], [1]);
      loader.dispose();
    });
  });
  test('wrong source catalog is rejected before any game request', () {
    fakeAsync((clock) {
      var calls = 0;
      final loader = hall(
        source: (_) async => [(id: 'foreign', source: 'b')],
        page: (_, __, ___) async {
          calls++;
          return [];
        },
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      expect(loader.catalogs, isEmpty);
      expect(calls, 0);
      expect(loader.failures, contains('source:a'));
      loader.dispose();
    });
  });
}
