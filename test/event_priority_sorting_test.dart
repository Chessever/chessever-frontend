import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

GroupEventCardModel _event({required String id, required int maxAvgElo}) {
  return GroupEventCardModel(
    id: id,
    title: 'Event $id',
    dates: 'Jun 1, 2026',
    maxAvgElo: maxAvgElo,
    timeUntilStart: '',
    tourEventCategory: TourEventCategory.ongoing,
    timeControl: 'Blitz',
    endDate: DateTime(2026, 6),
    startDate: DateTime(2026, 6),
  );
}

void main() {
  test(
    'event sorting prioritizes starred, then hearted by count, then regular',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final events = [
        _event(id: 'regular-high-elo', maxAvgElo: 2900),
        _event(id: 'hearted-one', maxAvgElo: 3000),
        _event(id: 'starred', maxAvgElo: 2400),
        _event(id: 'hearted-three', maxAvgElo: 2500),
        _event(id: 'regular-low-elo', maxAvgElo: 2300),
      ];

      final sorted = container
          .read(tournamentSortingServiceProvider)
          .sortBasedOnFavorite(
            tours: events,
            favorites: const ['starred'],
            eventFavoritePlayersMap: const {
              'hearted-one': EventFavoritePlayers(count: 1, fideIds: [1]),
              'hearted-three': EventFavoritePlayers(
                count: 3,
                fideIds: [2, 3, 4],
              ),
            },
          );

      expect(sorted.map((event) => event.id), [
        'starred',
        'hearted-three',
        'hearted-one',
        'regular-high-elo',
        'regular-low-elo',
      ]);
    },
  );

  test('starring a mid-list event bubbles it above non-starred peers', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final events = [
      _event(id: 'regular-high-elo', maxAvgElo: 2900),
      _event(id: 'regular-mid-elo', maxAvgElo: 2700),
      _event(id: 'to-star', maxAvgElo: 2400),
      _event(id: 'regular-low-elo', maxAvgElo: 2300),
    ];

    final before = container
        .read(tournamentSortingServiceProvider)
        .sortBasedOnFavorite(tours: events, favorites: const []);
    expect(before.map((event) => event.id).first, 'regular-high-elo');
    expect(
      before.map((event) => event.id).toList().indexOf('to-star'),
      greaterThan(0),
    );

    final after = container
        .read(tournamentSortingServiceProvider)
        .sortBasedOnFavorite(tours: events, favorites: const ['to-star']);

    expect(after.map((event) => event.id), [
      'to-star',
      'regular-high-elo',
      'regular-mid-elo',
      'regular-low-elo',
    ]);
  });

  test('unstarring drops an event out of starred priority', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final events = [
      _event(id: 'regular-high-elo', maxAvgElo: 2900),
      _event(id: 'was-starred', maxAvgElo: 2400),
      _event(id: 'regular-low-elo', maxAvgElo: 2300),
    ];

    final starred = container
        .read(tournamentSortingServiceProvider)
        .sortBasedOnFavorite(tours: events, favorites: const ['was-starred']);
    expect(starred.map((event) => event.id).first, 'was-starred');

    final unstarred = container
        .read(tournamentSortingServiceProvider)
        .sortBasedOnFavorite(tours: events, favorites: const []);
    expect(unstarred.map((event) => event.id), [
      'regular-high-elo',
      'was-starred',
      'regular-low-elo',
    ]);
  });
}
