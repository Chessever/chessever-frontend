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

/// The Search tab's landing: how a ranking row becomes a player result and
/// how the ranking is read, which openings it offers, and what Coming up
/// lists as the live set moves.
void main() {
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

/// The upcoming view, two events strongest first.
class _Broadcasts implements GroupBroadcastRepository {
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
