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

    test('the second line is the time control and the average rating', () {
      expect(
        searchLiveEventSubtitle(_event('a', 'A', elo: 2712)),
        'Standard · Ø 2712',
      );
      expect(searchLiveEventSubtitle(_event('a', 'A')), 'Standard');
      expect(
        searchLiveEventSemantics(_event('a', 'A', elo: 2712)),
        'A, live, Standard, average rating 2712',
      );
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

    test('eight at the most, without asking for more', () {
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
    expect(searchPlayerSubtitle(player), 'GM · 2833 · NOR');
    expect(
      searchTopPlayerSemantics(player, 1),
      'Carlsen, Magnus, number 1, GM, rating 2833, NOR',
    );

    final untitled = searchPlayerFromRanking(
      const ChessPlayer(fideid: 0, name: 'Doe, Jane', title: '', rating: 0),
    );
    expect(untitled.fideId, isNull);
    expect(untitled.title, isNull);
    expect(untitled.rating, isNull);
    expect(searchPlayerSubtitle(untitled), isEmpty);
  });

  group('Top players, as the tab reads them', () {
    test('the head of the default ranking, five rows, nameless rows '
        'skipped', () async {
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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
