import 'package:chessever2/screens/feed/feed_visibility.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/feed/news/news_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// How often the Feed's news list goes to the network: only while the Feed can
// be seen, and without re-downloading every body when nothing changed.

Map<String, dynamic> _row({
  int id = 7,
  String title = 'Carlsen wins Norway Chess 2026',
  String content = 'Magnus Carlsen won again.',
  String updatedAt = '2026-09-17T08:00:00Z',
}) => {
  'id': id,
  'title': title,
  'summary': 'A clean sweep in Stavanger.',
  'content': content,
  'source_url': null,
  'image_url': null,
  'status': 'published',
  'published_at': '2026-09-16T12:00:00Z',
  'created_at': '2026-09-16T11:00:00Z',
  'updated_at': updatedAt,
};

class _Fetcher {
  _Fetcher(this.rows);

  List<Map<String, dynamic>> rows;
  int calls = 0;

  Future<List<Map<String, dynamic>>> call(int limit) async {
    calls++;
    return rows;
  }
}

class _MemoryCache implements NewsCacheStore {
  NewsCacheEntry? entry;
  int writes = 0;

  @override
  Future<NewsCacheEntry?> read(String key) async => entry;

  @override
  Future<void> write(String key, String value) async {
    writes++;
    entry = (value: value, storedAt: DateTime.now());
  }
}

void main() {
  group('FeedNewsRepository change check', () {
    test('an unchanged list costs a stamp read, not the bodies', () async {
      var clock = DateTime(2026, 9, 23, 12);
      final full = _Fetcher([_row(), _row(id: 8, title: 'Second')]);
      final stamps = _Fetcher(const []);
      void syncStamps() => stamps.rows = [
        for (final row in full.rows) Map.of(row)..remove('content'),
      ];
      syncStamps();
      final repo = FeedNewsRepository(
        fetchRows: full.call,
        fetchStamps: stamps.call,
        cache: _MemoryCache(),
        clock: () => clock,
      );

      final first = (await repo.refresh())!;
      expect(full.calls, 1);
      expect(stamps.calls, 0, reason: 'nothing to compare with yet');

      clock = clock.add(const Duration(minutes: 31));
      final same = (await repo.refresh())!;
      expect(stamps.calls, 1);
      expect(full.calls, 1);
      expect(identical(same.items, first.items), isTrue);
      expect(same.fetchedAt, clock, reason: 'checked, so fresh again');

      // An edit moves the stamps: the bodies are fetched.
      full.rows = [
        _row(content: 'Edited.', updatedAt: '2026-09-23T12:10:00Z'),
        _row(id: 8, title: 'Second'),
      ];
      syncStamps();
      clock = clock.add(const Duration(minutes: 31));
      final edited = (await repo.refresh())!;
      expect(full.calls, 2);
      expect(edited.items.first.content, 'Edited.');
      expect(identical(edited.items[1], first.items[1]), isTrue);

      // Stamps alone never vouch for a list past fullRefreshEvery.
      clock = clock.add(FeedNewsRepository.fullRefreshEvery);
      await repo.refresh();
      expect(full.calls, 3);
    });

    test(
      'a custom row fetcher without stamps always fetches in full',
      () async {
        final full = _Fetcher([_row()]);
        final repo = FeedNewsRepository(
          fetchRows: full.call,
          cache: _MemoryCache(),
        );
        await repo.refresh();
        await repo.refresh();
        expect(full.calls, 2);
      },
    );
  });

  group('feedNewsProvider refresh', () {
    testWidgets('runs only while the Feed tab is selected and the app is up', (
      tester,
    ) async {
      var clock = DateTime(2026, 9, 23, 12);
      final cache = _MemoryCache()
        ..entry = (
          value: encodeFeedNewsCache([normalizeNewsRow(_row())!]),
          storedAt: clock,
        );
      final fetch = _Fetcher([_row(id: 9, title: 'Fresh story')]);
      final container = ProviderContainer(
        overrides: [
          feedNewsRepositoryProvider.overrideWithValue(
            FeedNewsRepository(
              fetchRows: fetch.call,
              cache: cache,
              clock: () => clock,
            ),
          ),
        ],
      );
      final sub = container.listen(feedNewsProvider, (_, _) {});
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );

      Future<void> settle() async {
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 1));
        }
      }

      Future<void> elapse(Duration duration) async {
        clock = clock.add(duration);
        await tester.pump(duration);
        await settle();
      }

      void feedOpen(bool open) =>
          container.read(feedScreenOpenProvider.notifier).state = open;

      expect((await container.read(feedNewsProvider.future)).single.id, 7);

      // Feed closed: the list goes stale and nobody fetches it.
      await elapse(const Duration(minutes: 45));
      expect(fetch.calls, 0);

      // Feed opened: the overdue refresh runs at once.
      feedOpen(true);
      await settle();
      expect(fetch.calls, 1);
      expect((await container.read(feedNewsProvider.future)).single.id, 9);

      // In the background: nothing ticks, however long.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await elapse(const Duration(hours: 2));
      expect(fetch.calls, 1);

      // Resumed on the Feed: refreshed once, then on the half hour.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle();
      expect(fetch.calls, 2);
      await elapse(const Duration(minutes: 31));
      expect(fetch.calls, 3);

      // Feed closed again: quiet.
      feedOpen(false);
      await elapse(const Duration(hours: 3));
      expect(fetch.calls, 3);

      sub.close();
      container.dispose();
    });
  });
}
