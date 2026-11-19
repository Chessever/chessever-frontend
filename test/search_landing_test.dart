import 'dart:async';

import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/search/search_landing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Search tab's landing: which events count as live now and how the
/// real Live now source fills in, how a ranking row becomes a player result
/// and how the ranking is read, and which openings it offers.
void main() {
  group('Live now', () {
    test('the live set picks the events, by id or by configured name, each '
        'once, strongest first', () {
      final events = searchLiveNowEvents(
        liveIds: {'a', 'Named Open', 'c'},
        feedEvents: [
          _event('a', 'Alpha Open', elo: 2500),
          _event('b', 'Not Live', elo: 2800),
          _event('n', 'Named Open', elo: 2400),
        ],
        fetchedEvents: [
          _event('c', 'Charlie Cup', elo: 2700),
          // The feed's copy stays; a fetched duplicate is dropped.
          _event('a', 'Alpha Open (fetched)', elo: 2900),
        ],
      );
      expect(events.map((e) => e.title), [
        'Charlie Cup',
        'Alpha Open',
        'Named Open',
      ]);
    });

    test('equal ratings read by name; the list stops at its limit', () {
      final events = searchLiveNowEvents(
        liveIds: {for (var i = 0; i < 12; i++) 'e$i'},
        feedEvents: [
          for (var i = 0; i < 12; i++) _event('e$i', 'Event ${11 - i}'),
        ],
        fetchedEvents: const [],
      );
      expect(events, hasLength(searchLandingLiveLimit));
      expect(events.first.title, 'Event 0');
      expect(events[1].title, 'Event 1');
    });
  });

  group('Live now, as the tab reads it', () {
    test('nothing live: nothing listed, nothing asked for', () async {
      final repo = _Broadcasts();
      final live = _LiveNow(live: const [], feed: [_event('a', 'Alpha')]);
      final container = live.start(repo);
      expect(container.read(searchLiveNowProvider).isEmpty, isTrue);
      expect(repo.calls, isEmpty);
    });

    test('the feed already holds them all: listed at once, no lookup', () {
      final repo = _Broadcasts();
      final container = _LiveNow(
        live: const ['a', 'b'],
        feed: [
          _event('a', 'Alpha', elo: 2500),
          _event('b', 'Bravo', elo: 2700),
          _event('x', 'Not live', elo: 2800),
        ],
      ).start(repo);
      final state = container.read(searchLiveNowProvider);
      expect(state.events.map((e) => e.id), ['b', 'a']);
      expect(state.pending, 0);
      expect(repo.calls, isEmpty);
    });

    test('the feed\'s events list at once; only the rest are looked up, and '
        'they land in held room under the listed rows', () async {
      final repo = _Broadcasts();
      final container = _LiveNow(
        live: const ['a', 'b', 'c'],
        feed: [_event('a', 'Alpha', elo: 2500)],
      ).start(repo);

      final before = container.read(searchLiveNowProvider);
      expect(before.events.map((e) => e.id), ['a']);
      expect(before.pending, 2);
      expect(repo.calls, [
        ['b', 'c'],
      ]);

      repo.answer([
        _broadcast('c', 'Charlie', elo: 2600),
        _broadcast('b', 'Bravo', elo: 2800),
        // The feed's own copy stays; the lookup's is dropped.
        _broadcast('a', 'Alpha (lookup)', elo: 2900),
      ]);
      await _settle();

      final after = container.read(searchLiveNowProvider);
      // The listed row keeps its place, even below a stronger arrival.
      expect(after.events.map((e) => e.title), ['Alpha', 'Bravo', 'Charlie']);
      expect(after.pending, 0);
      expect(after.events.length, before.events.length + before.pending);
    });

    test('a failed lookup keeps the listed rows, gives the room back and '
        'says so, quietly', () async {
      final repo = _Broadcasts();
      final container = _LiveNow(
        live: const ['a', 'b'],
        feed: [_event('a', 'Alpha', elo: 2500)],
      ).start(repo);
      expect(container.read(searchLiveNowProvider).pending, 1);

      repo.fail(Exception('offline'));
      await _settle();

      final state = container.read(searchLiveNowProvider);
      expect(state.events.map((e) => e.id), ['a']);
      expect(state.pending, 0);
      expect(container.read(searchLiveNowProvider.notifier).lookupFailed, true);
    });

    test('an event found once lists at once after a live change, and an id '
        'that named nothing is not asked for again', () async {
      final repo = _Broadcasts();
      final live = _LiveNow(
        live: const ['a', 'b', 'z'],
        feed: [_event('a', 'Alpha', elo: 2500)],
      );
      final container = live.start(repo);
      repo.answer([_broadcast('b', 'Bravo', elo: 2800)]);
      await _settle();
      expect(container.read(searchLiveNowProvider).events.map((e) => e.id), [
        'a',
        'b',
      ]);

      container.read(liveBroadcastIdsProvider.notifier).state = [
        'a',
        'b',
        'z',
        'd',
      ];
      final state = container.read(searchLiveNowProvider);
      // Everything known reads strongest first; only the new id is asked.
      expect(state.events.map((e) => e.id), ['b', 'a']);
      expect(state.pending, 1);
      expect(repo.calls.last, ['d']);
      repo.answer(const []);
      await _settle();
      expect(container.read(searchLiveNowProvider).pending, 0);
    });

    test('a lookup outrun by a live change is dropped', () async {
      final repo = _Broadcasts();
      final container = _LiveNow(live: const ['b'], feed: const []).start(repo);
      final first = repo.pending!;
      container.read(liveBroadcastIdsProvider.notifier).state = ['c'];
      container.read(searchLiveNowProvider);
      first.complete([_broadcast('b', 'Bravo', elo: 2800)]);
      await _settle();
      final state = container.read(searchLiveNowProvider);
      expect(state.events, isEmpty);
      expect(state.pending, 1);
      expect(repo.calls, [
        ['b'],
        ['c'],
      ]);
      repo.answer([_broadcast('c', 'Charlie', elo: 2600)]);
      await _settle();
      expect(container.read(searchLiveNowProvider).events.map((e) => e.id), [
        'c',
      ]);
    });

    test('five at the most, without asking for more', () {
      final repo = _Broadcasts();
      final container = _LiveNow(
        live: [for (var i = 0; i < 12; i++) 'e$i'],
        feed: [for (var i = 0; i < 10; i++) _event('e$i', 'Event $i')],
      ).start(repo);
      final state = container.read(searchLiveNowProvider);
      expect(state.events, hasLength(searchLandingLiveLimit));
      expect(state.pending, 0);
      expect(repo.calls, isEmpty);
    });
  });

  test('a ranking row reads as a player search result', () {
    final player = searchPlayerFromRanking(
      const ChessPlayer(
        fideid: 1503014,
        name: ' Carlsen, Magnus ',
        title: 'GM',
        rating: 2833,
        country: 'NOR',
      ),
    );
    expect(player.fideId, 1503014);
    expect(player.name, 'Carlsen, Magnus');
    expect(player.title, 'GM');
    expect(player.rating, 2833);
    expect(player.fed, 'NOR');

    final untitled = searchPlayerFromRanking(
      const ChessPlayer(fideid: 0, name: 'Doe, Jane', title: '', rating: 0),
    );
    expect(untitled.fideId, isNull);
    expect(untitled.title, isNull);
    expect(untitled.rating, isNull);
  });

  group('Top players, as the tab reads them', () {
    test('the head of the default ranking, one grid of player cards, '
        'nameless rows skipped', () async {
      final ranking = _Ranking(
        rows: const [
          ChessPlayer(fideid: 1503014, name: 'Carlsen, Magnus', rating: 2833),
          ChessPlayer(fideid: 9, name: '  ', rating: 2800),
          ChessPlayer(fideid: 2016192, name: 'Nakamura, Hikaru', rating: 2802),
        ],
      );
      final container = ProviderContainer(
        overrides: [chessPlayerRepositoryProvider.overrideWithValue(ranking)],
      );
      addTearDown(container.dispose);
      container.listen(searchTopPlayersProvider, (_, __) {});

      final players = await container.read(searchTopPlayersProvider.future);
      expect(players.map((p) => p.name), [
        'Carlsen, Magnus',
        'Nakamura, Hikaru',
      ]);
      expect(ranking.limits, [searchLandingPlayerCount]);
      expect(ranking.filters.single, RankingFilters.defaults);
    });

    test('a dropped connection is asked again', () async {
      final ranking = _Ranking(
        rows: const [ChessPlayer(fideid: 1, name: 'Player, One', rating: 2700)],
        failFirst: TimeoutException('slow'),
      );
      final container = ProviderContainer(
        overrides: [chessPlayerRepositoryProvider.overrideWithValue(ranking)],
      );
      addTearDown(container.dispose);
      container.listen(searchTopPlayersProvider, (_, __) {});

      final players = await container.read(searchTopPlayersProvider.future);
      expect(players.single.name, 'Player, One');
      expect(ranking.limits, hasLength(2));
    });
  });

  group('Openings', () {
    test('each is the opening search\'s own first result, a whole family '
        'counted in codes', () {
      final openings = resolveSearchLandingOpenings(
        searchLandingOpeningQueries,
      );
      expect(openings.map((o) => o.codeLabel), [
        'B20-B99', // Sicilian defence
        'C60-C99', // Ruy Lopez
        'D30-D42', // Queen's gambit declined
        'C00-C19', // French defence
        'B10-B19', // Caro-Kann defence
        'E60-E99', // King's Indian
        'E20-E59', // Nimzo-Indian defence
        'A10-A39', // English opening
      ]);
      expect(openings.map((o) => o.id).toSet(), hasLength(openings.length));
      for (final opening in openings) {
        // Every card reads "★ All … / N ECO codes", none a single line's
        // moves, so the row is even.
        expect(opening.isAggregate, isTrue, reason: opening.title);
        expect(opening.isFamily, isTrue, reason: opening.title);
        expect(opening.subtitle, matches(RegExp(r'^\d+ ECO codes$')));
      }
    });

    test('the tab resolves them off the UI isolate, the same', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.listen(searchLandingOpeningsProvider, (_, __) {});

      final openings = await container.read(
        searchLandingOpeningsProvider.future,
      );
      expect(
        openings.map((o) => o.id),
        resolveSearchLandingOpenings(
          searchLandingOpeningQueries,
        ).map((o) => o.id),
      );
    });
  });

  group('Coming up', () {
    final now = DateTime.utc(2026, 11, 19, 12);
    GroupEventCardModel up(String id, DateTime? start) => GroupEventCardModel(
      id: id,
      title: 'Event $id',
      dates: '',
      maxAvgElo: 2700,
      timeUntilStart: '',
      tourEventCategory: TourEventCategory.upcoming,
      timeControl: 'Standard',
      startDate: start,
      endDate: null,
    );

    test('soonest first, undated last, each once, five at the most', () {
      final events = searchUpcomingEvents([
        up('late', DateTime.utc(2027, 6)),
        up('undated', null),
        up('soon', DateTime.utc(2027, 1)),
        up('soon', DateTime.utc(2027, 1)),
        up('mid', DateTime.utc(2027, 3)),
        up('', DateTime.utc(2027, 2)),
      ], now: now);
      expect(events.map((e) => e.id), ['soon', 'mid', 'late', 'undated']);
    });

    test('the strongest five of the read (its order), then soonest first', () {
      // The read is strongest first; e0 is the strongest and starts last.
      final many = searchUpcomingEvents([
        for (var i = 0; i < 9; i++) up('e$i', DateTime.utc(2027, 1, 9 - i)),
      ], now: now);
      expect(many.map((e) => e.id), ['e4', 'e3', 'e2', 'e1', 'e0']);
    });

    test('an event that has started or gone live leaves, and the next '
        'strongest takes its place', () {
      final read = [
        for (var i = 0; i < 7; i++) up('e$i', DateTime.utc(2026, 11, 20 + i)),
      ];
      // e0 went live early (by id), e1 by its configured name, and e2's
      // start has passed.
      final events = searchUpcomingEvents(
        read,
        liveIds: const ['e0', 'Event e1'],
        now: DateTime.utc(2026, 11, 22, 1),
      );
      expect(events.map((e) => e.id), ['e3', 'e4', 'e5', 'e6']);
      expect(events.map((e) => e.tourEventCategory).toSet(), {
        TourEventCategory.upcoming,
      });
    });

    test('one read of the upcoming view, twice what it lists, strongest '
        'first', () async {
      final repo = _Broadcasts();
      final container = ProviderContainer(
        overrides: [
          groupBroadcastRepositoryProvider.overrideWith((ref) => repo),
        ],
      );
      addTearDown(container.dispose);
      container.listen(searchUpcomingProvider, (_, __) {});
      final events = await container.read(searchUpcomingProvider.future);
      expect(repo.upcomingLimits, [searchUpcomingReadLimit]);
      expect(searchUpcomingReadLimit, searchLandingUpcomingLimit * 2);
      expect(events.map((e) => e.title), ['Later Cup', 'Soon Open']);
    });

    test('Coming up follows the live set: an event that goes live leaves it '
        'at once, with no new read', () async {
      final repo = _Broadcasts();
      final container = ProviderContainer(
        overrides: [
          groupBroadcastRepositoryProvider.overrideWith((ref) => repo),
          // The strict stream has not answered, so its mirror is the set.
          liveGroupBroadcastIdsProvider.overrideWith(
            (ref) => const Stream<List<String>>.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(searchComingUpProvider, (_, __) {});
      await container.read(searchUpcomingProvider.future);
      expect(container.read(searchComingUpProvider)!.map((e) => e.title), [
        'Soon Open',
        'Later Cup',
      ]);

      container.read(liveBroadcastIdsProvider.notifier).state = const ['soon'];
      expect(container.read(searchComingUpProvider)!.map((e) => e.title), [
        'Later Cup',
      ]);
      expect(repo.upcomingLimits, hasLength(1));
    });
  });

  group('a recent event', () {
    final saved = GroupEventCardModel(
      id: 'ev',
      title: 'Old Live',
      dates: '',
      maxAvgElo: 2700,
      timeUntilStart: '',
      tourEventCategory: TourEventCategory.live,
      timeControl: 'Standard',
      startDate: DateTime.utc(2020, 1, 1),
      endDate: DateTime.utc(2020, 1, 9),
    );

    test('saved while live, it no longer reads LIVE once it ends', () {
      final now = searchRecentEvent(saved, const []);
      expect(now.tourEventCategory, TourEventCategory.completed);
      expect(now.id, saved.id);
      expect(now.title, saved.title);
    });

    test('live again by the live set, it reads LIVE', () {
      expect(
        searchRecentEvent(saved, const ['ev']).tourEventCategory,
        TourEventCategory.live,
      );
    });
  });
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// The real Live now over a fixed live set and Today feed.
class _LiveNow {
  _LiveNow({required this.live, required this.feed});

  final List<String> live;
  final List<GroupEventCardModel> feed;

  ProviderContainer start(_Broadcasts repo) {
    final container = ProviderContainer(
      overrides: [
        // The strict stream has not answered, so its mirror is the live set.
        liveGroupBroadcastIdsProvider.overrideWith(
          (ref) => const Stream<List<String>>.empty(),
        ),
        liveBroadcastIdsProvider.overrideWith((ref) => live),
        searchLandingFeedEventsProvider.overrideWith((ref) => feed),
        groupBroadcastRepositoryProvider.overrideWith((ref) => repo),
      ],
    );
    addTearDown(container.dispose);
    container.listen(searchLiveNowProvider, (_, __) {});
    return container;
  }
}

/// A by-id lookup the test answers.
class _Broadcasts implements GroupBroadcastRepository {
  final calls = <List<String>>[];
  Completer<List<GroupBroadcast>>? pending;

  void answer(List<GroupBroadcast> broadcasts) => pending!.complete(broadcasts);

  void fail(Object error) => pending!.completeError(error);

  @override
  Future<List<GroupBroadcast>> getGroupBroadcastsByIdsOrNames(
    List<String> identifiers,
  ) {
    calls.add(List.of(identifiers));
    return (pending = Completer<List<GroupBroadcast>>()).future;
  }

  final upcomingLimits = <int?>[];

  @override
  Future<List<GroupBroadcast>> getUpcomingGroupBroadcasts({
    int? limit,
    int? offset,
    String orderBy = 'max_avg_elo',
    bool ascending = false,
  }) async {
    upcomingLimits.add(limit);
    return [
      _dated('later', 'Later Cup', DateTime.utc(2099, 6)),
      _dated('soon', 'Soon Open', DateTime.utc(2099, 1)),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GroupBroadcast _dated(String id, String name, DateTime start) => GroupBroadcast(
  id: id,
  createdAt: DateTime.utc(2027),
  name: name,
  search: const [],
  maxAvgElo: 2700,
  timeControl: 'standard',
  dateStart: start,
  dateEnd: start.add(const Duration(days: 9)),
);

class _Ranking implements ChessPlayerRepository {
  _Ranking({required this.rows, this.failFirst});

  final List<ChessPlayer> rows;
  Object? failFirst;
  final limits = <int>[];
  final filters = <RankingFilters>[];

  @override
  Future<List<ChessPlayer>> getRankedPlayers({
    required RankingFilters filters,
    String? countryCode,
    String searchQuery = '',
    int limit = 30,
    int offset = 0,
    DateTime? now,
  }) async {
    limits.add(limit);
    this.filters.add(filters);
    final error = failFirst;
    if (error != null) {
      failFirst = null;
      throw error;
    }
    return rows;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GroupBroadcast _broadcast(String id, String name, {int? elo}) => GroupBroadcast(
  id: id,
  createdAt: DateTime.utc(2027),
  name: name,
  search: const [],
  maxAvgElo: elo,
  timeControl: 'standard',
);

GroupEventCardModel _event(String id, String title, {int elo = 0}) =>
    GroupEventCardModel(
      id: id,
      title: title,
      dates: '',
      maxAvgElo: elo,
      timeUntilStart: '',
      tourEventCategory: TourEventCategory.live,
      timeControl: 'Standard',
      startDate: null,
      endDate: null,
    );
