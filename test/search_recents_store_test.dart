import 'dart:convert';

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/collections/collections_data.dart'
    show Collection, CollectionKind;
import 'package:chessever2/screens/feed/news/news_models.dart' show FeedNews;
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart'
    show kGmSmartPreset, kSuperGmSmartPreset;
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/search/search_feeds.dart'
    show searchSmartEventRequests;
import 'package:chessever2/screens/search/search_recents_store.dart';
import 'package:chessever2/screens/search/search_recents_view.dart'
    show SearchRecentTile;
import 'package:chessever2/screens/search/search_section_matches.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Search tab's own recent searches (what was opened, what was
/// searched), kept on the device, and what a typed search finds in the
/// landing's sections beyond the app-wide search.
void main() {
  group('the recent searches store', () {
    test(
      'things opened: newest first, each once, twelve at the most',
      () async {
        final store = _Store();
        final notifier = store.container.read(searchRecentsProvider.notifier);
        for (var i = 0; i < 14; i++) {
          await notifier.recordPick(SearchRecentPick.event(_event('e$i')));
        }
        // Opened again: to the front, not twice.
        await notifier.recordPick(SearchRecentPick.event(_event('e5')));
        final picks = store.container.read(searchRecentsProvider).picks;
        expect(picks, hasLength(searchRecentPickLimit));
        expect(picks.first.id, contains('e5'));
        expect(picks.where((p) => p.id.contains('e5')), hasLength(1));
        expect(picks.map((p) => p.name), isNot(contains('Event e0')));
      },
    );

    test('queries: trimmed, inner space folded, once whatever the case, ten '
        'at the most', () async {
      final store = _Store();
      final notifier = store.container.read(searchRecentsProvider.notifier);
      for (var i = 0; i < 12; i++) {
        await notifier.recordQuery('query $i');
      }
      await notifier.recordQuery('  Query   3 ');
      await notifier.recordQuery('   ');
      final queries = store.container.read(searchRecentsProvider).queries;
      expect(queries, hasLength(searchRecentQueryLimit));
      expect(queries.first, 'Query 3');
      expect(queries.where((q) => q.toLowerCase() == 'query 3'), hasLength(1));
    });

    test(
      'kept on the device: every kind reads back, and opens as it was',
      () async {
        final storage = _MemoryStorage();
        final najdorf = searchOpeningSuggestions('Najdorf', limit: 1).single;
        final picks = [
          SearchRecentPick.player(_player),
          SearchRecentPick.event(_event('tour-1')),
          SearchRecentPick.opening(najdorf.selection),
          SearchRecentPick.smartEvent(kSuperGmSmartPreset),
          SearchRecentPick.collection(_collection),
          SearchRecentPick.news(_story),
        ];
        final first = _Store(storage: storage);
        final notifier = first.container.read(searchRecentsProvider.notifier);
        for (final pick in picks.reversed) {
          await notifier.recordPick(pick);
        }
        await notifier.recordQuery('carlsen');
        expect(jsonDecode(storage.stored!), isA<Map>());

        final second = _Store(storage: storage);
        second.container.read(searchRecentsProvider);
        await pumpEventQueue();
        final read = second.container.read(searchRecentsProvider);
        expect(read.loaded, isTrue);
        expect(read.queries, ['carlsen']);
        expect(read.picks.map((p) => p.identity), picks.map((p) => p.identity));
        expect(read.picks[0].player?.fideId, _player.fideId);
        expect(read.picks[1].event?.id, 'tour-1');
        expect(read.picks[2].opening?.filter.code, najdorf.filter.code);
        expect(
          read.picks[3].smartEvent?.criteriaKey,
          kSuperGmSmartPreset.criteriaKey,
        );
        final collection = read.picks[4].collection!;
        expect(collection.slug, _collection.slug);
        expect(collection.kind, CollectionKind.book);
        expect(collection.coverUrl, _collection.coverUrl);
        expect(read.picks[5].news?.key, _story.key);
        expect(read.picks[5].news?.content, _story.content);
      },
    );

    test('a damaged row is skipped, never the history', () async {
      final storage = _MemoryStorage()
        ..stored = jsonEncode({
          'v': 1,
          'picks': [
            {'kind': 'nonsense', 'id': 'x', 'name': 'x'},
            {'kind': 'smartEvent', 'id': 'no-such-criteria', 'name': 'Gone'},
            SearchRecentPick.smartEvent(kGmSmartPreset).toJson(),
            42,
          ],
          'queries': ['nakamura', '', null],
        });
      final store = _Store(storage: storage);
      store.container.read(searchRecentsProvider);
      await pumpEventQueue();
      final read = store.container.read(searchRecentsProvider);
      expect(read.picks.single.smartEvent, kGmSmartPreset);
      expect(read.queries, ['nakamura']);
    });

    test('the first read brings the recent searches the tab showed before it '
        'had its own history', () async {
      final legacy = _LegacyStorage(
        jsonEncode([
          RecentSearchEntry.player(_player).toJson(),
          RecentSearchEntry.tournament(_event('tour-9')).toJson(),
        ]),
      );
      final storage = _MemoryStorage();
      final store = _Store(storage: storage, legacy: legacy);
      store.container.read(searchRecentsProvider);
      await pumpEventQueue();
      final read = store.container.read(searchRecentsProvider);
      expect(read.picks.map((p) => p.kind), [
        SearchRecentKind.player,
        SearchRecentKind.event,
      ]);
      expect(read.picks.last.event?.id, 'tour-9');
      // Imported once: the tab's own copy is written, so the next launch
      // reads it instead of the shared history.
      expect(storage.stored, isNotNull);
      final next = _Store(storage: storage, legacy: _LegacyStorage(null));
      next.container.read(searchRecentsProvider);
      await pumpEventQueue();
      expect(next.container.read(searchRecentsProvider).picks, hasLength(2));
    });

    test(
      'Clear all pressed before the device\'s copy is read stays clear',
      () async {
        final storage = _MemoryStorage()
          ..stored = jsonEncode(
            const SearchRecents(queries: ['older']).toJson(),
          );
        final store = _Store(storage: storage);
        final notifier = store.container.read(searchRecentsProvider.notifier);
        await notifier.clear();
        await pumpEventQueue();
        expect(store.container.read(searchRecentsProvider).isEmpty, isTrue);
        expect(storage.stored, isNot(contains('older')));
      },
    );

    test('a pick made before the device\'s copy is read goes in front of it, '
        'and the copy is not written over', () async {
      final storage = _MemoryStorage()
        ..stored = jsonEncode(const SearchRecents(queries: ['older']).toJson());
      final store = _Store(storage: storage);
      await store.container
          .read(searchRecentsProvider.notifier)
          .recordQuery('newer');
      final read = store.container.read(searchRecentsProvider);
      expect(read.queries, ['newer', 'older']);
      expect(storage.stored, contains('older'));
    });

    test('clear empties it and hands back what was there; restore brings it '
        'back', () async {
      final store = _Store();
      final notifier = store.container.read(searchRecentsProvider.notifier);
      await notifier.recordPick(SearchRecentPick.player(_player));
      await notifier.recordQuery('carlsen');
      final before = await notifier.clear();
      expect(store.container.read(searchRecentsProvider).isEmpty, isTrue);
      await notifier.restore(before);
      final back = store.container.read(searchRecentsProvider);
      expect(back.picks.single.name, _player.name);
      expect(back.queries, ['carlsen']);
    });

    test(
      'a device that cannot keep it still keeps it for the session',
      () async {
        final store = _Store(storage: _BrokenStorage());
        final notifier = store.container.read(searchRecentsProvider.notifier);
        await notifier.recordQuery('carlsen');
        expect(store.container.read(searchRecentsProvider).queries, [
          'carlsen',
        ]);
      },
    );
  });

  group('a recent thing\'s short name', () {
    test('a surname, an event before its section, an opening\'s own line, a '
        'level', () {
      expect(
        SearchRecentTile.shortName(SearchRecentPick.player(_player)),
        'Carlsen',
      );
      expect(
        SearchRecentTile.shortName(
          SearchRecentPick.event(
            _event('t', title: 'Norway Chess 2027 | Women'),
          ),
        ),
        'Norway Chess 2027',
      );
      expect(
        SearchRecentTile.shortName(
          SearchRecentPick.smartEvent(kSuperGmSmartPreset),
        ),
        kSuperGmSmartPreset.tierLabel,
      );
    });
  });

  group('what a search finds in the landing\'s sections', () {
    test('every word starts a word of the text; three letters or more may '
        'sit inside one; accents fold', () {
      expect(searchTextMatches('tata steel', ['Tata Steel Masters']), isTrue);
      expect(searchTextMatches('ste', ['Tata Steel Masters']), isTrue);
      expect(searchTextMatches('dorf', ['Najdorf Memorial']), isTrue);
      expect(searchTextMatches('or', ['Najdorf Memorial']), isFalse);
      expect(searchTextMatches('reti', ['Réti Opening']), isTrue);
      expect(searchTextMatches('tata open', ['Tata Steel Masters']), isFalse);
      expect(searchTextMatches('  ', ['anything']), isFalse);
    });

    test('a level or a time control finds the built-in smart events', () {
      List<String> tiers(String query) => [
        for (final request in searchSmartEventMatches(query)) request.tierLabel,
      ];
      expect(tiers('super'), ['Super GM']);
      expect(tiers('grandmaster'), containsAll(['Super GM', 'GM']));
      expect(tiers('blitz'), ['Blitz']);
      expect(tiers('2700'), contains('Super GM'));
      expect(searchSmartEventMatches('carlsen'), isEmpty);
      expect(
        searchSmartEventMatches('games'),
        hasLength(searchSmartEventRequests.length),
      );
    });

    test('events: found and listed ones once each, in play under Live now, '
        'not started under Coming up, the rest under Events', () {
      final now = DateTime.utc(2026, 11, 20);
      final found = [
        _event('past', title: 'Tata Steel 2026'),
        _event(
          'live',
          title: 'Tata Steel Masters 2027',
          category: TourEventCategory.ongoing,
        ),
      ];
      final groups = searchEventGroups(
        'tata',
        found: found,
        liveNow: [
          _event(
            'live',
            title: 'Tata Steel Masters 2027',
            category: TourEventCategory.ongoing,
          ),
        ],
        comingUp: [
          _event(
            'next',
            title: 'Tata Steel Chess 2027',
            start: DateTime.utc(2027, 1, 15),
            category: TourEventCategory.upcoming,
          ),
          _event('other', title: 'Norway Chess 2027'),
        ],
        liveIds: const ['live'],
        now: now,
      );
      expect(groups.live.map((e) => e.id), ['live']);
      expect(groups.live.single.tourEventCategory, TourEventCategory.live);
      expect(groups.upcoming.map((e) => e.id), ['next']);
      expect(groups.other.map((e) => e.id), ['past']);
    });

    test('news: a title that names the words first, then a summary, eight at '
        'the most', () {
      final stories = [
        _news(1, title: 'Round five report', summary: 'Gukesh leads.'),
        _news(2, title: 'Gukesh wins', summary: ''),
        for (var i = 3; i < 15; i++) _news(i, title: 'Gukesh $i', summary: ''),
      ];
      final found = searchNewsMatches('gukesh', stories);
      expect(found, hasLength(searchNewsResultLimit));
      expect(found.first.id, 2);
      expect(searchNewsMatches('round five', stories).single.id, 1);
      expect(searchNewsMatches('leads', stories).single.id, 1);
    });
  });
}

class _Store {
  _Store({SearchRecentsStorage? storage, RecentSearchStorage? legacy})
    : container = ProviderContainer(
        overrides: [
          searchRecentsStorageProvider.overrideWithValue(
            storage ?? _MemoryStorage(),
          ),
          recentSearchStorageProvider.overrideWithValue(
            legacy ?? _LegacyStorage(null),
          ),
        ],
      ) {
    addTearDown(container.dispose);
  }

  final ProviderContainer container;
}

class _MemoryStorage implements SearchRecentsStorage {
  String? stored;

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> write(String value) async => stored = value;
}

class _BrokenStorage implements SearchRecentsStorage {
  @override
  Future<String?> read() async => throw StateError('no disk');

  @override
  Future<void> write(String value) async => throw StateError('no disk');
}

class _LegacyStorage implements RecentSearchStorage {
  _LegacyStorage(this.value);

  final String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {}
}

const _player = SearchPlayer(
  id: 'search_1503014',
  name: 'Carlsen, Magnus',
  title: 'GM',
  rating: 2833,
  fideId: 1503014,
  fed: 'NOR',
  tournamentId: 'player_search',
  tournamentName: 'Player Search',
);

GroupEventCardModel _event(
  String id, {
  String? title,
  DateTime? start,
  TourEventCategory category = TourEventCategory.completed,
}) => GroupEventCardModel(
  id: id,
  title: title ?? 'Event $id',
  dates: '',
  maxAvgElo: 2700,
  timeUntilStart: '',
  tourEventCategory: category,
  timeControl: 'Classical',
  startDate: start ?? DateTime.utc(2026, 8, 20),
  endDate: start?.add(const Duration(days: 10)) ?? DateTime.utc(2026, 8, 30),
);

final _collection = Collection(
  id: 'book-1',
  slug: 'my-sixty-memorable-games',
  kind: CollectionKind.book,
  title: 'My 60 Memorable Games',
  author: 'Bobby Fischer',
  coverUrl: 'https://example.com/cover.webp',
  gameCount: 60,
);

final _story = FeedNews(
  id: 7,
  title: 'Carlsen wins the Champions Showdown',
  summary: 'A clean sweep in the final round.',
  content: 'A clean sweep in the final round.',
  publishedAt: DateTime.utc(2026, 11, 18, 9),
);

FeedNews _news(int id, {required String title, required String summary}) =>
    FeedNews(
      id: id,
      title: title,
      summary: summary,
      content: 'Body $id',
      publishedAt: DateTime.utc(2026, 11, 18, 9),
    );
