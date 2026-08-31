import 'dart:convert';

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _MemoryRecentSearchStorage implements RecentSearchStorage {
  _MemoryRecentSearchStorage([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

GroupEventCardModel _event(String id) {
  return GroupEventCardModel(
    id: id,
    title: 'Event $id',
    dates: 'Aug 20–22',
    maxAvgElo: 2600,
    timeUntilStart: '',
    tourEventCategory: TourEventCategory.upcoming,
    timeControl: 'Standard',
    endDate: null,
    startDate: null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recent destinations deduplicate, move to front, and persist', () async {
    final storage = _MemoryRecentSearchStorage();
    final notifier = RecentSearchesNotifier(storage);
    addTearDown(notifier.dispose);

    await notifier.record(RecentSearchEntry.tournament(_event('one')));
    await notifier.record(
      RecentSearchEntry.opening(GameEcoFilter.forFamily('B9')),
    );
    await notifier.record(RecentSearchEntry.tournament(_event('one')));

    final entries = notifier.state.asData!.value;
    expect(entries, hasLength(2));
    expect(entries.first.targetId, 'one');
    expect(entries.last.targetId, 'B9');
    expect(storage.value, contains('B9'));
  });

  test('recent destinations are capped at six', () async {
    final notifier = RecentSearchesNotifier(_MemoryRecentSearchStorage());
    addTearDown(notifier.dispose);

    for (var index = 0; index < 7; index++) {
      await notifier.record(
        RecentSearchEntry.tournament(_event('event-$index')),
      );
    }

    expect(notifier.state.asData!.value, hasLength(6));
    expect(notifier.state.asData!.value.first.targetId, 'event-6');
    expect(
      notifier.state.asData!.value.map((entry) => entry.targetId),
      isNot(contains('event-0')),
    );
  });

  test(
    'stored player and opening destinations reconstruct navigation data',
    () {
      const player = SearchPlayer(
        id: 'p-1',
        name: 'Judit Polgar',
        title: 'GM',
        rating: 2735,
        fideId: 700070,
        fed: 'HUN',
        tournamentId: 'event',
        tournamentName: 'Event',
      );

      final restoredPlayer = RecentSearchEntry.player(player).toPlayer();
      final restoredOpening =
          RecentSearchEntry.opening(GameEcoFilter.forFamily('B9')).toOpening();

      expect(restoredPlayer?.name, 'Judit Polgar');
      expect(restoredPlayer?.fideId, 700070);
      expect(restoredOpening?.code, 'B9');
      expect(restoredOpening?.isFamily, isTrue);
    },
  );

  test('recent tournament preserves the complete live navigation payload', () {
    final live = GroupEventCardModel(
      id: 'cal_event_mikhail_tal_memorial',
      title: 'Mikhail Tal Memorial',
      dates: 'Nov 5–12',
      maxAvgElo: 2765,
      timeUntilStart: 'Starts in 2 days',
      tourEventCategory: TourEventCategory.upcoming,
      timeControl: 'Rapid',
      startDate: DateTime.utc(2026, 11, 5, 12, 30),
      endDate: DateTime.utc(2026, 11, 12, 18, 45),
      location: 'Riga, Latvia',
      searchTerms: const ['mikhail tal memorial', 'riga', 'rapid'],
      eventSource: EventSource.communityEvent,
      isMajorUpcoming: true,
    );

    final encoded = jsonEncode(RecentSearchEntry.tournament(live).toJson());
    final restored =
        RecentSearchEntry.fromJson(
          (jsonDecode(encoded) as Map).cast<String, dynamic>(),
        ).toTournament()!;

    expect(restored.id, live.id);
    expect(restored.title, live.title);
    expect(restored.dates, live.dates);
    expect(restored.maxAvgElo, live.maxAvgElo);
    expect(restored.timeUntilStart, live.timeUntilStart);
    expect(restored.tourEventCategory, live.tourEventCategory);
    expect(restored.timeControl, live.timeControl);
    expect(restored.startDate, live.startDate);
    expect(restored.endDate, live.endDate);
    expect(restored.location, live.location);
    expect(restored.searchTerms, live.searchTerms);
    expect(restored.eventSource, live.eventSource);
    expect(restored.isMajorUpcoming, live.isMajorUpcoming);
  });

  test('recent player preserves the complete live navigation payload', () {
    const live = SearchPlayer(
      id: 'event-42_700070_game-8',
      name: 'Judit Polgar',
      title: 'GM',
      rating: 2735,
      fideId: 700070,
      fed: 'HUN',
      tournamentId: 'event-42',
      tournamentName: 'Legends Match',
      gameId: 'game-8',
      roundId: 'round-3',
      isWhitePlayer: false,
      gamebasePlayerId: 'gamebase-judit-polgar',
    );

    final encoded = jsonEncode(RecentSearchEntry.player(live).toJson());
    final restored =
        RecentSearchEntry.fromJson(
          (jsonDecode(encoded) as Map).cast<String, dynamic>(),
        ).toPlayer()!;

    expect(restored.id, live.id);
    expect(restored.name, live.name);
    expect(restored.title, live.title);
    expect(restored.rating, live.rating);
    expect(restored.fideId, live.fideId);
    expect(restored.fed, live.fed);
    expect(restored.tournamentId, live.tournamentId);
    expect(restored.tournamentName, live.tournamentName);
    expect(restored.gameId, live.gameId);
    expect(restored.roundId, live.roundId);
    expect(restored.isWhitePlayer, live.isWhitePlayer);
    expect(restored.gamebasePlayerId, live.gamebasePlayerId);
    expect(restored.memorialSourceIdentity, live.memorialSourceIdentity);
    expect(restored.memorialRouteId, live.memorialRouteId);
  });

  test('stored Memorial player keeps its exact immutable identity', () {
    const player = SearchPlayer(
      id: 'memorial:memorial-e03cdf6af47b368c',
      name: 'Tal, Mikhail',
      title: 'GM',
      rating: 2705,
      fed: 'LAT',
      tournamentId: 'memorial',
      tournamentName: 'Chess Memorial',
      memorialSourceIdentity: 'memorial:memorial-e03cdf6af47b368c',
      memorialRouteId: 'memorial-e03cdf6af47b368c',
    );

    final restored =
        RecentSearchEntry.fromJson(
          RecentSearchEntry.player(player).toJson(),
        ).toPlayer();

    expect(restored?.memorialSourceIdentity, player.memorialSourceIdentity);
    expect(restored?.memorialRouteId, player.memorialRouteId);
    expect(restored?.id, player.id);
  });

  test('legacy stored Memorial player is upgraded before navigation', () async {
    final legacy = RecentSearchEntry.fromJson({
      'kind': 'player',
      'targetId': 'name:tal, mikhail',
      'title': 'Tal, Mikhail',
      'subtitle': 'GM · 2705 · LAT',
      'data': {
        'id': 'memorial:memorial-e03cdf6af47b368c',
        'title': 'GM',
        'rating': 2705,
        'fed': 'LAT',
        'tournamentId': 'historical-event',
        'tournamentName': 'Candidates Reunion',
        'gameId': 'historical-game',
        'roundId': 'round-7',
        'isWhitePlayer': false,
      },
    });

    final restored = await resolveRecentSearchPlayer(legacy);

    expect(
      restored?.memorialSourceIdentity,
      'memorial:memorial-e03cdf6af47b368c',
    );
    expect(restored?.memorialRouteId, 'memorial-e03cdf6af47b368c');
    expect(restored?.name, 'Tal, Mikhail');
    expect(restored?.tournamentId, 'historical-event');
    expect(restored?.tournamentName, 'Candidates Reunion');
    expect(restored?.gameId, 'historical-game');
    expect(restored?.roundId, 'round-7');
    expect(restored?.isWhitePlayer, isFalse);
  });

  test(
    'unknown legacy Memorial route never falls back to live search',
    () async {
      final legacy = RecentSearchEntry.fromJson({
        'kind': 'player',
        'targetId': 'name:historical player',
        'title': 'Historical Player',
        'subtitle': 'Chess Memorial',
        'data': {'id': 'memorial:memorial-reviewed-player'},
      });

      final restored = await resolveRecentSearchPlayer(legacy);

      expect(restored?.memorialRouteId, 'memorial-reviewed-player');
      expect(
        restored?.memorialSourceIdentity,
        'memorial:memorial-reviewed-player',
      );
    },
  );

  test(
    'legacy and current Memorial entries deduplicate to one destination',
    () async {
      final storage = _MemoryRecentSearchStorage(
        '[{"kind":"player","targetId":"name:tal, mikhail",'
        '"title":"Tal, Mikhail","subtitle":"GM · 2705 · LAT",'
        '"data":{"id":"memorial:memorial-e03cdf6af47b368c",'
        '"title":"GM","rating":2705,"fed":"LAT"}}]',
      );
      final notifier = RecentSearchesNotifier(storage);
      addTearDown(notifier.dispose);

      await notifier.record(
        RecentSearchEntry.player(
          const SearchPlayer(
            id: 'memorial:memorial-e03cdf6af47b368c',
            name: 'Tal, Mikhail',
            title: 'GM',
            rating: 2705,
            fed: 'LAT',
            tournamentId: 'memorial',
            tournamentName: 'Chess Memorial',
            memorialSourceIdentity: 'memorial:memorial-e03cdf6af47b368c',
            memorialRouteId: 'memorial-e03cdf6af47b368c',
          ),
        ),
      );

      expect(notifier.state.asData!.value, hasLength(1));
      expect(
        notifier.state.asData!.value.single.targetId,
        'memorial:memorial-e03cdf6af47b368c',
      );
    },
  );

  test('numeric Memorial identity wins over a recyclable FIDE id', () {
    final entry = RecentSearchEntry.player(
      const SearchPlayer(
        id: 'memorial:2000016',
        name: 'Fischer, Robert James',
        fideId: 2000016,
        tournamentId: 'memorial',
        tournamentName: 'Chess Memorial',
        memorialSourceIdentity: '2000016',
        memorialRouteId: '2000016',
      ),
    );

    expect(entry.targetId, 'memorial:2000016');
    expect(entry.toPlayer()?.memorialSourceIdentity, '2000016');
  });

  test("complete King's Indian family persists without exposing its id", () {
    final entry = RecentSearchEntry.opening(
      GameEcoFilter.forFamily('E6+E7+E8+E9'),
    );
    final restored = RecentSearchEntry.fromJson(entry.toJson()).toOpening();

    expect(entry.targetId, 'E6+E7+E8+E9');
    expect(entry.title, "King's Indian");
    expect(entry.subtitle, 'E60-E99');
    expect(restored?.code, 'E6+E7+E8+E9');
    expect(restored?.ecoPrefixes, ['E6', 'E7', 'E8', 'E9']);
  });

  test('a recent named line keeps its hierarchy and move context', () {
    final entry = RecentSearchEntry.openingSelection(
      OpeningSearchSelection(
        filter: GameEcoFilter.forCode('B06'),
        hierarchyLabel: 'Robatsch defence › Gurgenidze variation',
        movePath: const ['e4', 'g6', 'd4', 'Bg7'],
        isAggregate: false,
      ),
    );

    final restored =
        RecentSearchEntry.fromJson(entry.toJson()).toOpeningSelection();

    expect(restored?.filter.code, 'B06');
    expect(restored?.hierarchyLabel, 'Robatsch defence › Gurgenidze variation');
    expect(restored?.movePath, ['e4', 'g6', 'd4', 'Bg7']);
    expect(restored?.isAggregate, isFalse);
  });

  test('corrupt stored history does not prevent new entries', () async {
    final notifier = RecentSearchesNotifier(
      _MemoryRecentSearchStorage('{broken json'),
    );
    addTearDown(notifier.dispose);

    await notifier.record(RecentSearchEntry.tournament(_event('healthy')));

    expect(notifier.state.asData!.value.single.targetId, 'healthy');
  });

  test('individual removal and clear update durable history', () async {
    final storage = _MemoryRecentSearchStorage();
    final notifier = RecentSearchesNotifier(storage);
    addTearDown(notifier.dispose);
    final first = RecentSearchEntry.tournament(_event('first'));
    final second = RecentSearchEntry.tournament(_event('second'));

    await notifier.record(first);
    await notifier.record(second);
    await notifier.remove(first);

    expect(notifier.state.asData!.value.single.targetId, 'second');
    expect(storage.value, isNot(contains('first')));

    await notifier.clear();

    expect(notifier.state.asData!.value, isEmpty);
    expect(storage.value, '[]');
  });
}
