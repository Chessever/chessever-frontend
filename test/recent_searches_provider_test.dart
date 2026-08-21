import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
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
