import 'dart:async';

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The event Games list's own search, on the real screen model: the list it
/// shows stays until a query's hits land, a quiet "still looking" flag runs
/// meanwhile, closing puts the list back in the same frame, and a refresh
/// pulled while searching keeps the search.
///
/// A gamebase-only event searches the games already loaded (no disk cache),
/// so the catalog below is the whole world.

const _tourId = 'gamebase::Test Open';

const _about = AboutTourModel(
  id: _tourId,
  slug: 'test-open',
  name: 'Test Open',
  description: '',
  imageUrl: '',
  players: [],
  timeControl: '90+30',
  date: '1 Jan 2026',
  location: '',
  websiteUrl: '',
  standingsUrl: '',
  tourUrl: '',
  groupBroadcastId: 'gb-1',
);

TourDetailViewModel _viewModel() => TourDetailViewModel(
  aboutTourModel: _about,
  liveTourIds: const [],
  tours: [
    TourModel(
      tour: Tour.virtual(
        id: _tourId,
        name: 'Test Open',
        slug: 'test-open',
        dates: [DateTime.utc(2026, 1, 1), DateTime.utc(2026, 1, 9)],
        players: const [],
      ),
      roundStatus: RoundStatus.ongoing,
    ),
  ],
);

Player _player(String name) => Player(
  name: name,
  title: 'GM',
  rating: 2750,
  fideId: name.hashCode,
  fed: 'NOR',
  clock: 0,
  team: '',
);

Games _game(String id, String white, String black, {int board = 1}) => Games(
  id: id,
  roundId: 'round-1',
  roundSlug: 'round-1',
  tourId: _tourId,
  tourSlug: 'test-open',
  players: [_player(white), _player(black)],
  status: '1-0',
  boardNr: board,
  search: [white.toLowerCase(), black.toLowerCase()],
);

final _carlsenDing = _game('g1', 'Carlsen', 'Ding', board: 1);
final _nepoGiri = _game('g2', 'Nepomniachtchi', 'Giri', board: 2);
final _caruanaSo = _game('g3', 'Caruana', 'So', board: 3);
final _carlsenGukesh = _game('g4', 'Carlsen', 'Gukesh', board: 4);

/// The event's games. A refresh swaps in [next], and waits on [hold] first
/// when one is set, as a slow network does.
class _Catalog extends GamesTourNotifier {
  _Catalog({required super.ref, required super.tourId});

  int refreshes = 0;
  List<Games>? next;
  Completer<void>? hold;

  void seed(List<Games> games) => state = AsyncValue.data(games);

  @override
  Future<void> refreshGames() async {
    refreshes++;
    await hold?.future;
    final games = next;
    if (games != null && mounted) state = AsyncValue.data(games);
  }
}

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      tourDetailScreenProviderOverride(_viewModel()),
      gamesTourProvider.overrideWith(
        (ref, tourId) => _Catalog(ref: ref, tourId: tourId),
      ),
      gamesPinProviderOverride(),
      gamebaseEventViewProvider.overrideWith((ref, request) async => null),
      combinedLiveTourIdsProvider.overrideWithValue(const <String>{}),
      gamesAppBarTourIdProvider.overrideWith((ref) => null),
      liveRoundsIdProvider.overrideWith(
        (ref) => Stream<List<String>>.value(const <String>[]),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Real time passes here: the screen model sorts its games on an isolate.
Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// The event loaded with [games], every game listed.
Future<(GamesTourScreenProvider, _Catalog)> _loaded(
  ProviderContainer container,
  List<Games> games,
) async {
  container.listen(gamesTourScreenProvider, (_, __) {});
  final catalog =
      container.read(gamesTourProvider(_tourId).notifier) as _Catalog;
  // The first (empty) gamebase read lands, then the games.
  await catalog.waitForCompleteCatalog();
  catalog.seed(games);
  final screen = container.read(gamesTourScreenProvider.notifier);
  await _until(
    () =>
        container
            .read(gamesTourScreenProvider)
            .valueOrNull
            ?.gamesTourModels
            .length ==
        games.length,
  );
  return (screen, catalog);
}

GamesScreenModel _model(ProviderContainer container) =>
    container.read(gamesTourScreenProvider).requireValue;

Set<String> _ids(GamesScreenModel model) => {
  for (final game in model.gamesTourModels) game.gameId,
};

void main() {
  test(
    'the list stays until the hits land, with the search said to run',
    () async {
      final container = _container();
      final (screen, _) = await _loaded(container, [
        _carlsenDing,
        _nepoGiri,
        _caruanaSo,
      ]);
      final everyGame = _model(container);
      expect(container.read(gamesTourSearchPendingProvider), isFalse);

      final search = screen.searchGamesEnhanced('carlsen');
      // Running: every game is still on screen, nothing wiped to a spinner.
      expect(container.read(gamesTourSearchPendingProvider), isTrue);
      expect(_model(container), same(everyGame));

      await search;
      expect(container.read(gamesTourSearchPendingProvider), isFalse);
      final hits = _model(container);
      expect(hits.isSearchMode, isTrue);
      expect(hits.searchQuery, 'carlsen');
      expect(_ids(hits), {'g1'});
    },
  );

  test(
    'closing puts back the list the hits replaced, in the same frame',
    () async {
      final container = _container();
      final (screen, _) = await _loaded(container, [
        _carlsenDing,
        _nepoGiri,
        _caruanaSo,
      ]);
      final everyGame = _model(container).gamesTourModels;
      await screen.searchGamesEnhanced('carlsen');
      expect(_model(container).isSearchMode, isTrue);

      screen.clearSearch();
      // No await: the reader never waits on a fetch to see every game again.
      final restored = _model(container);
      expect(restored.isSearchMode, isFalse);
      expect(restored.searchQuery, isNull);
      expect(restored.gamesTourModels, same(everyGame));
      expect(container.read(gamesTourSearchPendingProvider), isFalse);

      // Then it is brought up to date from every game, still out of search.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await _until(() => _ids(_model(container)).length == 3);
      expect(_model(container).isSearchMode, isFalse);
    },
  );

  test('a search closed before its hits land never lands', () async {
    final container = _container();
    final (screen, _) = await _loaded(container, [
      _carlsenDing,
      _nepoGiri,
      _caruanaSo,
    ]);

    final search = screen.searchGamesEnhanced('carlsen');
    expect(container.read(gamesTourSearchPendingProvider), isTrue);
    screen.clearSearch();
    expect(container.read(gamesTourSearchPendingProvider), isFalse);
    await search;

    expect(container.read(gamesTourSearchPendingProvider), isFalse);
    expect(_model(container).isSearchMode, isFalse);
    expect(_ids(_model(container)), {'g1', 'g2', 'g3'});
  });

  test('a refresh pulled while searching keeps the search, run again over the '
      'new games', () async {
    final container = _container();
    final (screen, catalog) = await _loaded(container, [
      _carlsenDing,
      _nepoGiri,
      _caruanaSo,
    ]);
    await screen.searchGamesEnhanced('carlsen');
    final hits = _model(container);

    catalog
      ..next = [_carlsenDing, _nepoGiri, _caruanaSo, _carlsenGukesh]
      ..hold = Completer<void>();
    final refresh = screen.refreshGames();
    await Future<void>.delayed(Duration.zero);
    // While the games refresh, the hits stay up.
    expect(catalog.refreshes, 1);
    expect(_model(container), same(hits));

    catalog.hold!.complete();
    await refresh;
    final again = _model(container);
    expect(again.isSearchMode, isTrue);
    expect(again.searchQuery, 'carlsen');
    expect(_ids(again), {'g1', 'g4'});
    expect(container.read(gamesTourSearchPendingProvider), isFalse);
  });

  test('a refresh does not run a search the reader closed meanwhile', () async {
    final container = _container();
    final (screen, catalog) = await _loaded(container, [
      _carlsenDing,
      _nepoGiri,
      _caruanaSo,
    ]);
    await screen.searchGamesEnhanced('carlsen');

    catalog
      ..next = [_carlsenDing, _nepoGiri, _caruanaSo, _carlsenGukesh]
      ..hold = Completer<void>();
    final refresh = screen.refreshGames();
    await Future<void>.delayed(Duration.zero);
    screen.clearSearch();
    catalog.hold!.complete();
    await refresh;

    expect(_model(container).isSearchMode, isFalse);
    expect(container.read(gamesTourSearchPendingProvider), isFalse);
    // Every game, the new one included.
    await _until(() => _ids(_model(container)).length == 4);
    expect(_model(container).isSearchMode, isFalse);
  });
}
