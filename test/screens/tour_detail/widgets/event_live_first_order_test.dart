import 'package:chessever2/providers/live_game_ids_provider.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_games_provider.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_round_sections.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_display_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_games_quick_actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../support/fake_live_game_ids.dart';

/// What an event's Live first lifts, through the real list providers (the
/// single category's `gamesTourGroupedProvider`, Combined's
/// `combinedGamesPresentationProvider`): the server's games in play
/// (`get_live_game_ids`), the set its capsule counts, never the rows' own
/// status. A row can read in play and not be (a leftover `*` from an
/// earlier day, a finish the list has not seen); only while the server has
/// not answered do the rows decide.

/// A board after 1. e4.
const _afterE4 = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKB1R b KQkq - 0 1';

/// One player per name, with an id of their own.
Player _player(String name) => Player(
  name: name,
  title: 'GM',
  rating: 2700,
  fideId: 1000000 + (name.hashCode & 0xFFFFF),
  fed: 'NOR',
  clock: 600,
  team: '',
);

/// Board [board] of `round-1` in [tourId]: in play by its row (`*`, a move
/// made) or [finished].
Games _row(
  String id, {
  required int board,
  bool finished = false,
  String tourId = 'tour-1',
}) => Games(
  id: id,
  roundId: 'round-1-$tourId',
  roundSlug: 'round-1',
  tourId: tourId,
  tourSlug: tourId,
  name: '$id White - $id Black',
  players: [_player('$id White'), _player('$id Black')],
  status: finished ? '1-0' : '*',
  fen: _afterE4,
  lastMove: 'e2e4',
  boardNr: board,
  lastMoveTime: DateTime.now().toUtc(),
  dateStart: DateTime.now().toUtc(),
);

List<String> _ids(Iterable<GamesTourModel> games) => [
  for (final game in games) game.gameId,
];

/// The rows a leftover `*` (`a`, board 1), a board in play (`b`, board 2)
/// and a finished one (`c`, board 3): the server has only `b` in play.
List<Games> _rows({String tourId = 'tour-1'}) => [
  _row('$tourId-a', board: 1, tourId: tourId),
  _row('$tourId-b', board: 2, tourId: tourId),
  _row('$tourId-c', board: 3, finished: true, tourId: tourId),
];

// ---------------------------------------------------------------------------
// One category

TourDetailViewModel _event() => TourDetailViewModel(
  aboutTourModel: const AboutTourModel(
    id: 'tour-1',
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
  ),
  liveTourIds: const [],
  tours: [
    TourModel(
      tour: Tour.virtual(
        id: 'tour-1',
        name: 'Test Open',
        slug: 'test-open',
        dates: [DateTime.utc(2026, 1, 1), DateTime.utc(2026, 1, 9)],
        players: const [],
      ),
      roundStatus: RoundStatus.ongoing,
    ),
  ],
);

/// The tour's rows, as loaded: no network behind them.
class _LoadedRows extends StateNotifier<AsyncValue<List<Games>>>
    implements GamesTourNotifier {
  _LoadedRows(List<Games> rows) : super(AsyncValue.data(rows));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The screen model with Live first on or off.
class _Screen extends GamesTourScreenProvider {
  _Screen({
    required super.ref,
    required List<GamesTourModel> games,
    required bool liveFirst,
  }) : super.loading() {
    state = AsyncValue.data(
      GamesScreenModel(
        gamesTourModels: games,
        pinnedGamedIs: const [],
        gameDisplayMode: liveFirst
            ? GameDisplayMode.hideFinishedGames
            : GameDisplayMode.all,
      ),
    );
  }
}

ProviderContainer _singleCategory({
  required bool liveFirst,
  Set<String>? server,
}) {
  final rows = _rows();
  final container = ProviderContainer(
    overrides: [
      combinedCategorySelectedProvider.overrideWithValue(false),
      tourDetailScreenProviderOverride(_event()),
      // No round metadata: the rounds come from the rows.
      gamesAppBarTourIdProvider.overrideWith((ref) => null),
      liveRoundsIdProvider.overrideWith(
        (ref) => const Stream<List<String>>.empty(),
      ),
      gamesTourProvider.overrideWith((ref, tourId) => _LoadedRows(rows)),
      knockoutTournamentStateProvider.overrideWith(
        (ref, tourId) => const KnockoutTournamentState.empty(),
      ),
      gamesPinProviderOverride(const GamesPinState(hasResolvedAutoPins: true)),
      gamesTourScreenProvider.overrideWith(
        (ref) => _Screen(
          ref: ref,
          games: [for (final row in rows) GamesTourModel.fromGame(row)],
          liveFirst: liveFirst,
        ),
      ),
      eventLiveGameIdsProvider.overrideWith(
        (ref, scope) => FakeLiveGameIds(server),
      ),
    ],
  );
  addTearDown(container.dispose);
  // Kept alive as the Games list keeps it.
  final subscription = container.listen(gamesTourGroupedProvider, (_, _) {});
  addTearDown(subscription.close);
  return container;
}

List<String> _singleOrder(ProviderContainer container) {
  final grouped = container.read(gamesTourGroupedProvider);
  return _ids(grouped.gamesByRound.values.expand((games) => games));
}

// ---------------------------------------------------------------------------
// Combined

const _categories = [
  CombinedCategory(tourId: 'open', label: 'Open', avgElo: 2700, order: 0),
  CombinedCategory(tourId: 'women', label: 'Women', avgElo: 2500, order: 1),
];

ProviderContainer _combined({required bool liveFirst, Set<String>? server}) {
  final sections = buildCombinedRoundSections(
    categories: _categories,
    gamesByTourId: {
      for (final category in _categories)
        category.tourId: [
          for (final row in _rows(tourId: category.tourId))
            GamesTourModel.fromGame(row),
        ],
    },
    roundsByTourId: const {},
    liveRoundIds: const [],
  );
  final container = ProviderContainer(
    overrides: [
      combinedCategorySelectedProvider.overrideWithValue(true),
      combinedCategoriesProvider.overrideWithValue(
        const CombinedCategories(_categories),
      ),
      combinedRoundSectionsProvider.overrideWithValue(
        CombinedRoundSections(
          isLoading: false,
          error: null,
          sections: sections,
          pinnedGameIds: const [],
          searchQuery: '',
          hasUnscheduledRounds: false,
        ),
      ),
      gamesListViewModeProvider.overrideWithValue(
        GamesListViewMode.values.first,
      ),
      eventLiveGameIdsProvider.overrideWith(
        (ref, scope) => FakeLiveGameIds(server),
      ),
    ],
  );
  addTearDown(container.dispose);
  if (liveFirst) {
    for (final category in _categories) {
      container.read(gameDisplayModeProvider(category.tourId).notifier).state =
          GameDisplayMode.hideFinishedGames;
    }
  }
  final subscription = container.listen(
    combinedGamesPresentationProvider,
    (_, _) {},
  );
  addTearDown(subscription.close);
  return container;
}

/// Each category's boards, in the order Combined lists them.
Map<String, List<String>> _combinedOrder(ProviderContainer container) {
  final games = container
      .read(combinedGamesPresentationProvider)
      .gamesByRound
      .values
      .expand((games) => games);
  return {
    for (final category in _categories)
      category.tourId: _ids(
        games.where((game) => game.tourId == category.tourId),
      ),
  };
}

void main() {
  group('One category: Live first lifts the server\'s games in play', () {
    test('the board the server has in play leads, a leftover `*` stays '
        'in its place', () {
      final container = _singleCategory(
        liveFirst: true,
        server: const {'tour-1-b'},
      );
      expect(_singleOrder(container), ['tour-1-b', 'tour-1-a', 'tour-1-c']);
      // What the capsule counts is what was lifted.
      expect(container.read(eventGamesLiveIdsProvider), {'tour-1-b'});
      expect(container.read(eventGamesLiveCountProvider), 1);
    });

    test('a new answer moves the boards with it', () {
      final container = _singleCategory(
        liveFirst: true,
        server: const {'tour-1-b'},
      );
      final poll =
          container.read(
                eventLiveGameIdsProvider(
                  EventLiveGamesScope(const ['tour-1']),
                ).notifier,
              )
              as FakeLiveGameIds;

      poll.answer(const {'tour-1-a'});
      expect(_singleOrder(container), ['tour-1-a', 'tour-1-b', 'tour-1-c']);

      // A finish the list already shows is never lifted.
      poll.answer(const {'tour-1-c'});
      expect(_singleOrder(container), ['tour-1-a', 'tour-1-b', 'tour-1-c']);
      expect(container.read(eventGamesLiveCountProvider), 0);
    });

    test('until the server answers, the rows decide', () {
      final container = _singleCategory(liveFirst: true);
      // Both `*` rows lead, in board order.
      expect(_singleOrder(container), ['tour-1-a', 'tour-1-b', 'tour-1-c']);
      expect(container.read(eventGamesLiveCountProvider), isNull);
    });

    test('off, the server\'s set changes nothing', () {
      final container = _singleCategory(
        liveFirst: false,
        server: const {'tour-1-c'},
      );
      expect(_singleOrder(container), ['tour-1-a', 'tour-1-b', 'tour-1-c']);
    });
  });

  group('Combined: Live first lifts every category\'s games in play', () {
    test('each category\'s board in play leads its section', () {
      final container = _combined(
        liveFirst: true,
        server: const {'open-b', 'women-b'},
      );
      expect(_combinedOrder(container), {
        'open': ['open-b', 'open-a', 'open-c'],
        'women': ['women-b', 'women-a', 'women-c'],
      });
      expect(container.read(eventGamesLiveCountProvider), 2);
    });

    test('until the server answers, the rows decide', () {
      final container = _combined(liveFirst: true);
      expect(_combinedOrder(container), {
        'open': ['open-a', 'open-b', 'open-c'],
        'women': ['women-a', 'women-b', 'women-c'],
      });
    });

    test('off, the server\'s set changes nothing', () {
      final container = _combined(
        liveFirst: false,
        server: const {'open-c', 'women-c'},
      );
      expect(_combinedOrder(container), {
        'open': ['open-a', 'open-b', 'open-c'],
        'women': ['women-a', 'women-b', 'women-c'],
      });
    });
  });
}
