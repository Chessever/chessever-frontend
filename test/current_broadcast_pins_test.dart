import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/home_live_first_provider.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('Current ranks stars and pins within the live ordering', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sorter = container.read(tournamentSortingServiceProvider);
    final now = DateTime.utc(2026, 11, 21);
    GroupEventCardModel event(String id, int elo, {int? pinDay}) {
      final group = GroupBroadcast(
        id: id,
        name: id,
        createdAt: now,
        search: const [],
        maxAvgElo: elo,
        pinnedAt: pinDay == null ? null : DateTime.utc(2026, 11, pinDay),
      );
      final cached = GroupBroadcast.fromJson(group.toJson());
      return GroupEventCardModel.fromGroupBroadcast(cached, const []);
    }

    List<GroupEventCardModel> rank(
      List<GroupEventCardModel> events, {
      bool prioritizePins = false,
    }) => sorter.sortBasedOnFavorite(
      tours: events,
      favorites: const ['star', 'star-pin'],
      favoriteTimestamps: {'star': now, 'star-pin': DateTime.utc(2026, 11, 20)},
      eventFavoritePlayersMap: const {
        'favorite': EventFavoritePlayers(count: 2, fideIds: [1, 2]),
        'older': EventFavoritePlayers(count: 1, fideIds: [1]),
      },
      prioritizePins: prioritizePins,
    );

    final cards = [
      event('star-pin', 1800, pinDay: 21),
      event('rating', 2900),
      event('older', 1900, pinDay: 19),
      event('newer', 1600, pinDay: 20),
      event('favorite', 2000),
      event('star', 2000),
      event('live', 2800),
    ];
    final whenRated = rank(cards, prioritizePins: true);
    expect(whenRated.map((e) => e.id), [
      'star',
      'star-pin',
      'newer',
      'older',
      'favorite',
      'rating',
      'live',
    ]);
    final liveFirst = liveEventsFirst(whenRated, const {'live', 'older'});
    expect(liveFirst.map((e) => e.id), [
      'older',
      'live',
      'star',
      'star-pin',
      'newer',
      'favorite',
      'rating',
    ]);
    expect(rank(cards).map((e) => e.id), [
      'star',
      'star-pin',
      'favorite',
      'older',
      'rating',
      'live',
      'newer',
    ]);
    final oldCache = GroupBroadcast(
      id: 'legacy',
      name: 'legacy',
      createdAt: now,
      search: const [],
    ).toJson()..remove('pinned_at');
    expect(GroupBroadcast.fromJson(oldCache).pinnedAt, isNull);
  });
}
