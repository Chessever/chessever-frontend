import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/countrymen/provider/countrymen_combined_games_provider.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/favorites/player_games/provider/favorites_combined_games_provider.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_games_tab.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  group('Favorites Games public lifecycle', () {
    testWidgets(
      'filter Apply survives its modal route and immediately shows the badge',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repository = _RecordingGameRepository(favoriteDates: const []);
        final createdNotifiers = <FavoritesCombinedGamesNotifier>[];
        final container = ProviderContainer(
          overrides: [
            gameRepositoryProvider.overrideWithValue(repository),
            favoritePlayersNotifierProvider.overrideWith(
              _TestFavoritePlayersNotifier.new,
            ),
            gamesListViewModeProvider.overrideWithValue(
              GamesListViewMode.gamesCard,
            ),
            favoritesCombinedGamesProvider.overrideWith((ref) {
              final notifier = FavoritesCombinedGamesNotifier(ref);
              createdNotifiers.add(notifier);
              return notifier;
            }),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              navigatorObservers: [routeObserver],
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  // The Filters control ends the Games toolbar (title row and
                  // search header alike).
                  return const Scaffold(
                    body: Column(
                      children: [
                        FavoritesGamesToolbar(),
                        Expanded(child: FavoritesGamesTab()),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(createdNotifiers, hasLength(1));
        const filterButtonKey = ValueKey<String>(
          E2eIds.favoritesGamesFilterButton,
        );
        await tester.tap(find.byKey(filterButtonKey));
        await tester.pumpAndSettle();

        final whiteWins = find.text('1-0');
        await tester.ensureVisible(whiteWins);
        await tester.tap(whiteWins);

        final pendingFilteredDates = Completer<List<DateTime>>();
        addTearDown(() {
          if (!pendingFilteredDates.isCompleted) {
            pendingFilteredDates.complete(const []);
          }
        });
        repository.nextFavoriteDates = pendingFilteredDates;
        await tester.tap(find.text('Apply Filters'));
        await tester.pump();
        await tester.pump();

        expect(createdNotifiers, hasLength(1));
        expect(
          container.read(favoritesCombinedGamesProvider).filter.result,
          GameResultFilter.whiteWins,
        );
        expect(
          container.read(favoritesCombinedGamesProvider).isLoading,
          isTrue,
        );
        expect(
          repository.favoriteDateFilters.last.result,
          GameResultFilter.whiteWins,
        );
        expect(
          find.descendant(
            of: find.byKey(filterButtonKey),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );

        pendingFilteredDates.complete(const []);
        await tester.pumpAndSettle();
      },
    );

    test('player chips compose with an active text search', () async {
      final repository = _RecordingGameRepository();
      final harness = await _favoritesHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        favoritesCombinedGamesProvider.notifier,
      );

      await notifier.searchGames('Sicilian');
      await notifier.togglePlayerFilter('1503014');

      expect(
        harness.container.read(favoritesCombinedGamesProvider).searchQuery,
        'Sicilian',
      );
      expect(repository.favoriteSearchCalls.last.fideIds, ['1503014']);
      expect(repository.favoriteSearchCalls.last.query, 'Sicilian');
    });

    test('Clear Filters refetches the active search with defaults', () async {
      final repository = _RecordingGameRepository();
      final harness = await _favoritesHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        favoritesCombinedGamesProvider.notifier,
      );

      await notifier.searchGames('Carlsen');
      notifier.applyFilter(
        GameFilter(
          result: GameResultFilter.whiteWins,
          color: GameColorFilter.white,
        ),
      );
      await _waitUntil(() => repository.favoriteSearchCalls.length >= 2);

      notifier.clearFilter();
      await _waitUntil(() => repository.favoriteSearchCalls.length >= 3);

      expect(repository.favoriteSearchCalls.last.filter, GameFilter());
      expect(
        harness.container.read(favoritesCombinedGamesProvider).filter,
        GameFilter(),
      );
    });

    test('refresh preserves the visible search and filter', () async {
      final repository = _RecordingGameRepository();
      final harness = await _favoritesHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        favoritesCombinedGamesProvider.notifier,
      );
      final filter = GameFilter(
        timeControl: GameTimeControlFilter.rapid,
        minRating: 2400,
      );

      await notifier.searchGames('Nakamura');
      notifier.applyFilter(filter);
      await _waitUntil(() => repository.favoriteSearchCalls.length >= 2);
      await notifier.refreshGames();

      final state = harness.container.read(favoritesCombinedGamesProvider);
      expect(state.searchQuery, 'Nakamura');
      expect(state.filter, filter);
      expect(repository.favoriteSearchCalls.last.query, 'Nakamura');
      expect(repository.favoriteSearchCalls.last.filter, filter);
    });

    test('a search keeps the list on screen until its hits land, and its '
        'close puts the list back as it was, with no fetch', () async {
      final repository = _RecordingGameRepository();
      final pending = Completer<List<Games>>();
      repository.controlledFavoriteSearches['Najdorf'] = pending;
      final harness = await _favoritesHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        favoritesCombinedGamesProvider.notifier,
      );
      FavoritesCombinedGamesState read() =>
          harness.container.read(favoritesCombinedGamesProvider);
      final plain = read();
      expect(plain.games.map((game) => game.gameId), ['favorite-day']);

      final search = notifier.searchGames('Najdorf');
      await _waitUntil(() => repository.favoriteSearchCalls.isNotEmpty);
      // On its way: the plain list stays, marked as being replaced.
      expect(read().games.map((game) => game.gameId), ['favorite-day']);
      expect(read().isLoading, isTrue);
      expect(read().isReplacing, isTrue);
      expect(read().searchQuery, isEmpty);

      pending.complete([_game('najdorf-game')]);
      await search;
      expect(read().games.map((game) => game.gameId), ['najdorf-game']);
      expect(read().searchQuery, 'Najdorf');
      expect(read().isReplacing, isFalse);

      final dateFetches = repository.favoriteDateFilters.length;
      final clear = notifier.clearSearch();
      // Back in the same tick, exactly as it was left.
      expect(read().games.map((game) => game.gameId), ['favorite-day']);
      expect(read().searchQuery, isEmpty);
      expect(read().isLoading, isFalse);
      await clear;
      expect(repository.favoriteDateFilters, hasLength(dateFetches));
      expect(read().hasMore, plain.hasMore);
      expect(read().dateOffset, plain.dateOffset);
    });

    test('a search or a filter from an empty list keeps that answer on '
        'screen as a replacement, never a first load', () async {
      final repository = _RecordingGameRepository(favoriteDates: const []);
      final pending = Completer<List<Games>>();
      repository.controlledFavoriteSearches['Najdorf'] = pending;
      final harness = await _favoritesHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        favoritesCombinedGamesProvider.notifier,
      );
      FavoritesCombinedGamesState read() =>
          harness.container.read(favoritesCombinedGamesProvider);
      expect(read().games, isEmpty);
      expect(read().isLoading, isFalse);

      final search = notifier.searchGames('Najdorf');
      expect(read().isLoading, isTrue);
      expect(read().isReplacing, isTrue);
      expect(read().searchQuery, isEmpty);
      pending.complete(const []);
      await search;
      expect(read().searchQuery, 'Najdorf');
      expect(read().isReplacing, isFalse);

      // From the search's empty answer, a filter replaces it the same way.
      final filtered = notifier.applyFilter(
        GameFilter().copyWith(timeControl: GameTimeControlFilter.classical),
      );
      expect(read().isLoading, isTrue);
      expect(read().isReplacing, isTrue);
      await filtered;
      expect(read().isReplacing, isFalse);
    });

    test('a fetch while the first load is still on its way stays a first '
        'load', () async {
      final repository = _RecordingGameRepository();
      final pendingDates = Completer<List<DateTime>>();
      repository.nextFavoriteDates = pendingDates;
      final container = ProviderContainer(
        overrides: [
          gameRepositoryProvider.overrideWithValue(repository),
          favoritePlayersNotifierProvider.overrideWith(
            _TestFavoritePlayersNotifier.new,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(favoritePlayersNotifierProvider.future);
      final subscription = container.listen(
        favoritesCombinedGamesProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      FavoritesCombinedGamesState read() =>
          container.read(favoritesCombinedGamesProvider);
      expect(read().isLoading, isTrue);
      expect(read().games, isEmpty);

      final refresh = container
          .read(favoritesCombinedGamesProvider.notifier)
          .refreshGames();
      expect(read().isLoading, isTrue);
      expect(read().isReplacing, isFalse);
      pendingDates.complete(const []);
      await refresh;
    });

    test('a search that fails shows the error instead of the list it '
        'replaced', () async {
      final repository = _RecordingGameRepository();
      final failing = Completer<List<Games>>();
      repository.controlledFavoriteSearches['Najdorf'] = failing;
      final harness = await _favoritesHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        favoritesCombinedGamesProvider.notifier,
      );

      final search = notifier.searchGames('Najdorf');
      await _waitUntil(() => repository.favoriteSearchCalls.isNotEmpty);
      failing.completeError(StateError('offline'));
      await search;

      final state = harness.container.read(favoritesCombinedGamesProvider);
      expect(state.games, isEmpty);
      expect(state.error, isNotNull);
      expect(state.isLoading, isFalse);
      expect(state.isReplacing, isFalse);
    });

    test('a filter changed during the search is kept: its close fetches the '
        'list again, the hits staying until it lands', () async {
      final repository = _RecordingGameRepository();
      final harness = await _favoritesHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        favoritesCombinedGamesProvider.notifier,
      );
      FavoritesCombinedGamesState read() =>
          harness.container.read(favoritesCombinedGamesProvider);
      final filter = GameFilter(result: GameResultFilter.draw);

      await notifier.searchGames('Carlsen');
      await notifier.applyFilter(filter);
      expect(read().games.map((game) => game.gameId), [
        'favorite-search-Carlsen',
      ]);

      final pendingDates = Completer<List<DateTime>>();
      repository.nextFavoriteDates = pendingDates;
      final asked = repository.favoriteDateFilters.length;
      final clear = notifier.clearSearch();
      expect(read().games.map((game) => game.gameId), [
        'favorite-search-Carlsen',
      ]);
      expect(read().isReplacing, isTrue);
      await _waitUntil(
        () => repository.favoriteDateFilters.length == asked + 1,
      );
      // A second word to close while the list is on its way back: no second
      // fetch, and the first one still lands.
      await notifier.clearSearch();
      await Future<void>.delayed(Duration.zero);
      expect(repository.favoriteDateFilters, hasLength(asked + 1));
      expect(read().isReplacing, isTrue);
      pendingDates.complete([DateTime.utc(2026, 8, 26)]);
      await clear;

      expect(read().games.map((game) => game.gameId), ['favorite-day']);
      expect(read().searchQuery, isEmpty);
      expect(read().filter, filter);
      expect(repository.favoriteDateFilters.last, filter);
    });

    test('a slower old search cannot overwrite the latest query', () async {
      final repository = _RecordingGameRepository();
      final first = Completer<List<Games>>();
      final second = Completer<List<Games>>();
      repository.controlledFavoriteSearches['first'] = first;
      repository.controlledFavoriteSearches['second'] = second;
      final harness = await _favoritesHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        favoritesCombinedGamesProvider.notifier,
      );

      final firstRequest = notifier.searchGames('first');
      await _waitUntil(() => repository.favoriteSearchCalls.isNotEmpty);
      final secondRequest = notifier.searchGames('second');
      await _waitUntil(() => repository.favoriteSearchCalls.length == 2);
      second.complete([_game('second-game')]);
      await secondRequest;
      first.complete([_game('first-game')]);
      await firstRequest;

      final state = harness.container.read(favoritesCombinedGamesProvider);
      expect(state.searchQuery, 'second');
      expect(state.games.map((game) => game.gameId), ['second-game']);
    });
  });

  group('Countrymen Games public lifecycle', () {
    test(
      'keeps distinct games with the same players, day, and result',
      () async {
        final repository = _RecordingGameRepository(
          countryDayGames: [
            _game('game-a', withLastMoveTime: false),
            _game('game-b', withLastMoveTime: false),
          ],
        );
        final harness = await _countryHarness(repository);
        addTearDown(harness.dispose);

        final state = harness.container.read(countrymenCombinedGamesProvider);
        expect(state.games.map((game) => game.gameId), ['game-a', 'game-b']);
      },
    );

    test('Clear Filters refetches the active search with defaults', () async {
      final repository = _RecordingGameRepository();
      final harness = await _countryHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        countrymenCombinedGamesProvider.notifier,
      );

      await notifier.searchGames('Sicilian');
      notifier.applyFilter(GameFilter(color: GameColorFilter.white));
      await _waitUntil(() => repository.countrySearchCalls.length >= 2);
      notifier.clearFilter();
      await _waitUntil(() => repository.countrySearchCalls.length >= 3);

      expect(repository.countrySearchCalls.last.filter, GameFilter());
    });

    test('refresh preserves the visible search and filter', () async {
      final repository = _RecordingGameRepository();
      final harness = await _countryHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        countrymenCombinedGamesProvider.notifier,
      );
      final filter = GameFilter(
        result: GameResultFilter.draw,
        minYear: DateTime.now().year - 1,
      );

      await notifier.searchGames('Carlsen');
      notifier.applyFilter(filter);
      await _waitUntil(() => repository.countrySearchCalls.length >= 2);
      await notifier.refreshGames();

      final state = harness.container.read(countrymenCombinedGamesProvider);
      expect(state.searchQuery, 'Carlsen');
      expect(state.filter, filter);
      expect(repository.countrySearchCalls.last.query, 'Carlsen');
      expect(repository.countrySearchCalls.last.filter, filter);
    });

    test('a search keeps the list on screen until its hits land, and its '
        'close puts the list back as it was, with no fetch', () async {
      final repository = _RecordingGameRepository();
      final pending = Completer<List<Games>>();
      repository.controlledCountrySearches['Najdorf'] = pending;
      final harness = await _countryHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        countrymenCombinedGamesProvider.notifier,
      );
      CountrymenCombinedGamesState read() =>
          harness.container.read(countrymenCombinedGamesProvider);
      expect(read().games.map((game) => game.gameId), ['country-day']);

      final search = notifier.searchGames('Najdorf');
      await _waitUntil(() => repository.countrySearchCalls.isNotEmpty);
      expect(read().games.map((game) => game.gameId), ['country-day']);
      expect(read().isReplacing, isTrue);
      expect(read().searchQuery, isEmpty);

      pending.complete([_game('najdorf-game')]);
      await search;
      expect(read().games.map((game) => game.gameId), ['najdorf-game']);
      expect(read().searchQuery, 'Najdorf');

      final dayFetches = repository.countryDayFetches;
      final clear = notifier.clearSearch();
      expect(read().games.map((game) => game.gameId), ['country-day']);
      expect(read().searchQuery, isEmpty);
      expect(read().isLoading, isFalse);
      await clear;
      expect(repository.countryDayFetches, dayFetches);
    });

    test('another country never shows the last one\'s games while it '
        'loads', () async {
      final repository = _RecordingGameRepository();
      final harness = await _countryHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        countrymenCombinedGamesProvider.notifier,
      );

      final refresh = notifier.refreshGames(keepList: false);
      final state = harness.container.read(countrymenCombinedGamesProvider);
      expect(state.games, isEmpty);
      expect(state.isLoading, isTrue);
      // Nothing of the last country is kept, so it is a first load (its
      // spinner), not a list being replaced.
      expect(state.isReplacing, isFalse);
      await refresh;
      expect(
        harness.container
            .read(countrymenCombinedGamesProvider)
            .games
            .map((game) => game.gameId),
        ['country-day'],
      );
    });

    test('a slower old search cannot overwrite the latest query', () async {
      final repository = _RecordingGameRepository();
      final first = Completer<List<Games>>();
      final second = Completer<List<Games>>();
      repository.controlledCountrySearches['first'] = first;
      repository.controlledCountrySearches['second'] = second;
      final harness = await _countryHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        countrymenCombinedGamesProvider.notifier,
      );

      final firstRequest = notifier.searchGames('first');
      await _waitUntil(() => repository.countrySearchCalls.isNotEmpty);
      final secondRequest = notifier.searchGames('second');
      await _waitUntil(() => repository.countrySearchCalls.length == 2);
      second.complete([_game('second-game')]);
      await secondRequest;
      first.complete([_game('first-game')]);
      await firstRequest;

      final state = harness.container.read(countrymenCombinedGamesProvider);
      expect(state.searchQuery, 'second');
      expect(state.games.map((game) => game.gameId), ['second-game']);
    });
  });

  _ensureListedTests();
}

/// Live first lists the live games the loaded days miss
/// (`ensureListed`), so what it lifts is what its capsule counted.
void _ensureListedTests() {
  group('Favorites Live first lists the live games the pages miss', () {
    test('fetches only the missing ones and merges them in the list\'s '
        'order, today on top', () async {
      final repository = _RecordingGameRepository();
      repository.rowsById['started-later'] = _game(
        'started-later',
        lastMoveTime: DateTime.utc(2026, 8, 27, 9),
      ).copyWith(dateStart: DateTime.utc(2026, 8, 27), status: '*');
      final harness = await _favoritesHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        favoritesCombinedGamesProvider.notifier,
      );

      await notifier.ensureListed({'favorite-day', 'started-later', 'gone'});

      expect(
        repository.byIdCalls.single,
        unorderedEquals(['started-later', 'gone']),
      );
      final state = harness.container.read(favoritesCombinedGamesProvider);
      expect(state.games.map((game) => game.gameId), [
        'started-later',
        'favorite-day',
      ]);
      expect(state.seenGameIds, containsAll(['started-later', 'favorite-day']));

      // Listed once: asking again fetches nothing.
      await notifier.ensureListed({'started-later'});
      expect(repository.byIdCalls, hasLength(1));
    });

    test('never into a search\'s hits', () async {
      final repository = _RecordingGameRepository();
      repository.rowsById['live'] = _game('live');
      final harness = await _favoritesHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        favoritesCombinedGamesProvider.notifier,
      );

      await notifier.searchGames('Carlsen');
      await notifier.ensureListed({'live'});

      expect(repository.byIdCalls, isEmpty);
      expect(
        harness.container
            .read(favoritesCombinedGamesProvider)
            .games
            .map((game) => game.gameId),
        ['favorite-search-Carlsen'],
      );
    });

    test('an answer that lands after a search began is dropped', () async {
      final repository = _RecordingGameRepository();
      repository.rowsById['live'] = _game('live');
      final gate = Completer<void>();
      repository.nextByIdGate = gate;
      final harness = await _favoritesHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        favoritesCombinedGamesProvider.notifier,
      );

      final listing = notifier.ensureListed({'live'});
      await notifier.searchGames('Carlsen');
      gate.complete();
      await listing;

      expect(
        harness.container
            .read(favoritesCombinedGamesProvider)
            .games
            .map((game) => game.gameId),
        ['favorite-search-Carlsen'],
      );
    });

    test('into a list that loaded with nothing in it', () async {
      // The only game under the filter started after the list loaded: the
      // capsule over the empty state counts it, so Live first lists it.
      final repository = _RecordingGameRepository(favoriteDates: const []);
      repository.rowsById['live'] = _game(
        'live',
        lastMoveTime: DateTime.utc(2026, 8, 27, 9),
      ).copyWith(status: '*');
      final harness = await _favoritesHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        favoritesCombinedGamesProvider.notifier,
      );
      expect(harness.container.read(favoritesCombinedGamesProvider).games, []);

      await notifier.ensureListed({'live'});

      expect(repository.byIdCalls.single, ['live']);
      expect(
        harness.container
            .read(favoritesCombinedGamesProvider)
            .games
            .map((game) => game.gameId),
        ['live'],
      );
    });

    test('waits while the first load is on its way', () async {
      final repository = _RecordingGameRepository();
      repository.rowsById['live'] = _game('live');
      final pendingDates = Completer<List<DateTime>>();
      repository.nextFavoriteDates = pendingDates;
      final container = ProviderContainer(
        overrides: [
          gameRepositoryProvider.overrideWithValue(repository),
          favoritePlayersNotifierProvider.overrideWith(
            _TestFavoritePlayersNotifier.new,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(favoritePlayersNotifierProvider.future);
      final subscription = container.listen(
        favoritesCombinedGamesProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      expect(container.read(favoritesCombinedGamesProvider).isLoading, isTrue);

      await container
          .read(favoritesCombinedGamesProvider.notifier)
          .ensureListed({'live'});

      // The page lists it again once the list lands.
      expect(repository.byIdCalls, isEmpty);
      pendingDates.complete(const []);
      await _waitUntil(
        () => !container.read(favoritesCombinedGamesProvider).isLoading,
      );
    });

    test('a later page that holds a listed game lists it once', () async {
      final days = [
        DateTime.utc(2026, 8, 26),
        DateTime.utc(2026, 8, 25),
        DateTime.utc(2026, 8, 24),
        DateTime.utc(2026, 8, 23),
      ];
      final repository = _RecordingGameRepository(
        favoriteDates: days,
        favoriteDayGames: (date) => [
          _game(
            date.day == 23 ? 'old-live' : 'day-${date.day}',
            lastMoveTime: date.add(const Duration(hours: 12)),
          ).copyWith(dateStart: date),
        ],
      );
      repository.rowsById['old-live'] = _game(
        'old-live',
        lastMoveTime: DateTime.utc(2026, 8, 23, 12),
      ).copyWith(dateStart: DateTime.utc(2026, 8, 23));
      final harness = await _favoritesHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        favoritesCombinedGamesProvider.notifier,
      );

      await notifier.ensureListed({'old-live'});
      await notifier.loadMoreGames();

      final ids = harness.container
          .read(favoritesCombinedGamesProvider)
          .games
          .map((game) => game.gameId)
          .toList();
      expect(ids.where((id) => id == 'old-live'), hasLength(1));
      expect(ids, containsAll(['day-26', 'day-25', 'day-24', 'old-live']));
    });
  });

  group('Countrymen Live first lists the live games the pages miss', () {
    test('fetches only the missing ones, and never into a search', () async {
      final repository = _RecordingGameRepository();
      repository.rowsById['live'] = _game(
        'live',
        lastMoveTime: DateTime.utc(2026, 8, 27, 9),
      );
      final harness = await _countryHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        countrymenCombinedGamesProvider.notifier,
      );

      await notifier.ensureListed({'country-day', 'live'});
      expect(repository.byIdCalls.single, ['live']);
      expect(
        harness.container
            .read(countrymenCombinedGamesProvider)
            .games
            .map((game) => game.gameId),
        ['live', 'country-day'],
      );

      await notifier.searchGames('Carlsen');
      repository.rowsById['other'] = _game('other');
      await notifier.ensureListed({'other'});
      expect(repository.byIdCalls, hasLength(1));
    });

    test('into a list that loaded with nothing in it', () async {
      final repository = _RecordingGameRepository(countryDayGames: const []);
      repository.rowsById['live'] = _game(
        'live',
        lastMoveTime: DateTime.utc(2026, 8, 27, 9),
      ).copyWith(status: '*');
      final harness = await _countryHarness(repository);
      addTearDown(harness.dispose);
      final notifier = harness.container.read(
        countrymenCombinedGamesProvider.notifier,
      );
      expect(
        harness.container.read(countrymenCombinedGamesProvider).games,
        isEmpty,
      );

      await notifier.ensureListed({'live'});

      expect(repository.byIdCalls.single, ['live']);
      expect(
        harness.container
            .read(countrymenCombinedGamesProvider)
            .games
            .map((game) => game.gameId),
        ['live'],
      );
    });
  });
}

Future<_ProviderHarness> _favoritesHarness(
  _RecordingGameRepository repository,
) async {
  final container = ProviderContainer(
    overrides: [
      gameRepositoryProvider.overrideWithValue(repository),
      favoritePlayersNotifierProvider.overrideWith(
        _TestFavoritePlayersNotifier.new,
      ),
    ],
  );
  await container.read(favoritePlayersNotifierProvider.future);
  final favoritesSubscription = container.listen(
    favoritePlayersNotifierProvider,
    (_, __) {},
    fireImmediately: true,
  );
  final subscription = container.listen(
    favoritesCombinedGamesProvider,
    (_, __) {},
    fireImmediately: true,
  );
  await _waitUntil(
    () => !container.read(favoritesCombinedGamesProvider).isLoading,
  );
  return _ProviderHarness(container, [
    favoritesSubscription.close,
    subscription.close,
  ]);
}

Future<_ProviderHarness> _countryHarness(
  _RecordingGameRepository repository,
) async {
  final norway = CountryService().findByCode('NO')!;
  final container = ProviderContainer(
    overrides: [
      gameRepositoryProvider.overrideWithValue(repository),
      effectiveCountryProvider.overrideWithValue(AsyncValue.data(norway)),
    ],
  );
  final subscription = container.listen(
    countrymenCombinedGamesProvider,
    (_, __) {},
    fireImmediately: true,
  );
  await _waitUntil(
    () => !container.read(countrymenCombinedGamesProvider).isLoading,
  );
  return _ProviderHarness(container, [subscription.close]);
}

class _ProviderHarness {
  _ProviderHarness(this.container, this._closeSubscriptions);

  final ProviderContainer container;
  final List<void Function()> _closeSubscriptions;

  void dispose() {
    for (final close in _closeSubscriptions) {
      close();
    }
    container.dispose();
  }
}

class _TestFavoritePlayersNotifier extends FavoritePlayersNotifier {
  @override
  Future<FavoritePlayersState> build() async => const FavoritePlayersState(
    players: [
      PlayerStandingModel(
        countryCode: 'NOR',
        title: 'GM',
        name: 'Carlsen, Magnus',
        score: 2800,
        scoreChange: 0,
        matchScore: null,
        fideId: 1503014,
      ),
      PlayerStandingModel(
        countryCode: 'USA',
        title: 'GM',
        name: 'Nakamura, Hikaru',
        score: 2800,
        scoreChange: 0,
        matchScore: null,
        fideId: 2016192,
      ),
    ],
  );
}

class _FavoriteSearchCall {
  const _FavoriteSearchCall({
    required this.fideIds,
    required this.query,
    required this.filter,
  });

  final List<String> fideIds;
  final String? query;
  final GameFilter? filter;
}

class _CountrySearchCall {
  const _CountrySearchCall({required this.query, required this.filter});

  final String? query;
  final GameFilter? filter;
}

class _RecordingGameRepository implements GameRepository {
  _RecordingGameRepository({
    List<DateTime>? favoriteDates,
    List<Games>? countryDayGames,
    this.favoriteDayGames,
  }) : favoriteDates = favoriteDates ?? [DateTime.utc(2026, 8, 26)],
       countryDayGames = countryDayGames ?? [_game('country-day')];

  final List<DateTime> favoriteDates;
  final List<Games> countryDayGames;

  /// A favorites day's games; one 'favorite-day' game when null.
  final List<Games> Function(DateTime date)? favoriteDayGames;

  /// Rows [getGamesByIds] can return, by id.
  final Map<String, Games> rowsById = {};

  /// Every batch of ids asked for by id.
  final List<List<String>> byIdCalls = [];

  /// Holds the next by-id answer until completed.
  Completer<void>? nextByIdGate;

  @override
  Future<List<Games>> getGamesByIds(List<String> ids) async {
    byIdCalls.add(List<String>.of(ids));
    final gate = nextByIdGate;
    nextByIdGate = null;
    if (gate != null) await gate.future;
    return [
      for (final id in ids)
        if (rowsById[id] case final row?) row,
    ];
  }

  final List<GameFilter> favoriteDateFilters = [];
  final List<_FavoriteSearchCall> favoriteSearchCalls = [];
  final List<_CountrySearchCall> countrySearchCalls = [];
  final Map<String, Completer<List<Games>>> controlledFavoriteSearches = {};
  final Map<String, Completer<List<Games>>> controlledCountrySearches = {};
  Completer<List<DateTime>>? nextFavoriteDates;

  @override
  Future<List<DateTime>> getDistinctDatesForFavorites({
    required List<String> fideIds,
    GameFilter? filter,
    int limit = 30,
    int offset = 0,
  }) {
    favoriteDateFilters.add(filter ?? GameFilter());
    final controlled = nextFavoriteDates;
    nextFavoriteDates = null;
    return controlled?.future ?? Future.value(favoriteDates);
  }

  @override
  Future<List<Games>> getGamesByFideIdsAndDate({
    required List<String> fideIds,
    required DateTime date,
    GameFilter? filter,
  }) async => favoriteDayGames?.call(date) ?? [_game('favorite-day')];

  @override
  Future<List<Games>> searchFavoritesGames({
    required List<String> fideIds,
    required List<String> playerNames,
    String? query,
    GameFilter? filter,
    int limit = 30,
    int offset = 0,
  }) async {
    favoriteSearchCalls.add(
      _FavoriteSearchCall(
        fideIds: List<String>.of(fideIds),
        query: query,
        filter: filter,
      ),
    );
    final controlled = controlledFavoriteSearches[query];
    return controlled?.future ?? [_game('favorite-search-${query ?? ''}')];
  }

  @override
  Future<List<DateTime>> getDistinctDatesForCountry({
    required String countryCode,
    int minElo = 0,
    GameFilter? filter,
    int limit = 30,
    int offset = 0,
  }) async => [DateTime.utc(2026, 8, 26)];

  /// How many days of the plain list were fetched.
  int countryDayFetches = 0;

  @override
  Future<List<Games>> getGamesByCountryAndDate({
    required String countryCode,
    required DateTime date,
    int minElo = 0,
    GameFilter? filter,
  }) async {
    countryDayFetches++;
    return countryDayGames;
  }

  @override
  Future<List<Games>> searchCountrymenGames({
    required String countryCode,
    String? query,
    GameFilter? filter,
    int limit = 30,
    int offset = 0,
  }) async {
    countrySearchCalls.add(_CountrySearchCall(query: query, filter: filter));
    final controlled = controlledCountrySearches[query];
    return controlled?.future ?? [_game('country-search-${query ?? ''}')];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Games _game(String id, {DateTime? lastMoveTime, bool withLastMoveTime = true}) {
  return Games(
    id: id,
    roundId: 'round-$id',
    roundSlug: 'round-$id',
    tourId: 'tour-$id',
    tourSlug: 'tour-$id',
    name: 'Carlsen, Magnus - Nakamura, Hikaru',
    players: [
      Player(
        name: 'Carlsen, Magnus',
        title: 'GM',
        rating: 2800,
        fideId: 1503014,
        fed: 'NOR',
        clock: 600,
        team: '',
      ),
      Player(
        name: 'Nakamura, Hikaru',
        title: 'GM',
        rating: 2800,
        fideId: 2016192,
        fed: 'USA',
        clock: 600,
        team: '',
      ),
    ],
    status: '1-0',
    lastMoveTime: withLastMoveTime ? (lastMoveTime ?? _defaultMoveTime) : null,
    dateStart: DateTime.utc(2026, 8, 26),
    boardNr: 1,
    avgElo: 2800,
  );
}

final DateTime _defaultMoveTime = DateTime.utc(2026, 8, 26, 12);

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for provider state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
