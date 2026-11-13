import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_repo_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A board opened on a game of an event the viewer watches in Combined pages
/// through every category, wherever it was opened from. Before this, only
/// the Combined Games tab handed the board that list: the same game opened
/// from For You listed its own category alone (three boards a round in Total
/// Chess, not twelve).
void main() {
  const eventId = 'total_chess';

  setUp(debugResetCombinedBoardNavigation);

  // Two groups of two boards over two rounds, and the organizer's own
  // Combined section repeating all of them.
  List<Games> group(String tourId) => [
    for (final round in [1, 2])
      for (final board in [1, 2])
        _game(
          id: '$tourId-r$round-b$board',
          tourId: tourId,
          round: round,
          board: board,
        ),
  ];
  final groupA = group('group-a');
  final groupB = group('group-b');
  final mirror = [
    for (final game in [...groupA, ...groupB])
      _game(
        id: 'mirror-${game.id}',
        tourId: 'mirror',
        round: int.parse(game.roundSlug.split('-').last),
        board: game.boardNr!,
        white: game.players!.first.name,
        black: game.players!.last.name,
      ),
  ];

  final tours = [
    _tour('group-a', 'Total Chess | Group Stage | A', avgElo: 2718),
    _tour('group-b', 'Total Chess | Group Stage | B', avgElo: 2735),
    _tour(
      'mirror',
      'Total Chess | Group Stage | Combined',
      avgElo: 2735,
      isMirror: true,
    ),
  ];

  ProviderContainer container({
    bool combined = true,
    bool entitled = true,
  }) {
    final store = _MemoryStore();
    if (combined) {
      store.values[CombinedCategoryPrefsNotifier.selectedKey(eventId)] = '1';
    }
    final container = ProviderContainer(
      overrides: [
        gamesLocalStorage.overrideWith(
          (ref) => _GamesByTour(ref, {
            'group-a': groupA,
            'group-b': groupB,
            'mirror': mirror,
          }),
        ),
        groupBroadcastRepositoryProvider.overrideWithValue(
          _Events({
            'group-a': eventId,
            'group-b': eventId,
            'mirror': eventId,
          }),
        ),
        tourRepositoryProvider.overrideWithValue(_Tours({eventId: tours})),
        roundRepositoryProvider.overrideWithValue(
          _Rounds({
            for (final tourId in ['group-a', 'group-b', 'mirror'])
              tourId: [
                _round(tourId, 1, DateTime.utc(2026, 11, 11, 14)),
                _round(tourId, 2, DateTime.utc(2026, 11, 11, 17, 30)),
              ],
          }),
        ),
        tourSelectionStoreProvider.overrideWithValue(store),
        combinedCategoryEntitledProvider.overrideWithValue(entitled),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  // For You hands over a preview: one Group A game.
  final tapped = GamesTourModel.fromGame(groupA.first);

  test('lists every category, in the Combined order', () async {
    final scope = container();
    final (games, index) = await scope
        .read(gameCardWrapperProvider)
        .debugResolveForYouNavigation(orderedGames: [tapped], gameIndex: 0);

    expect([for (final game in games) game.gameId], [
      // The stronger group first; inside it the latest round first.
      'group-b-r2-b1',
      'group-b-r2-b2',
      'group-a-r2-b1',
      'group-a-r2-b2',
      'group-b-r1-b1',
      'group-b-r1-b2',
      'group-a-r1-b1',
      'group-a-r1-b2',
    ]);
    expect(games[index].gameId, tapped.gameId);
    // The organizer's own Combined section adds nothing: no board twice.
    expect(games.any((game) => game.tourId == 'mirror'), isFalse);

    // The board learns the event's categories for its round rail and stream.
    final event = combinedEventForTour(
      scope.read(combinedBoardEventsProvider),
      'group-b',
    );
    expect(event?.tourIds, ['group-b', 'group-a']);
    expect([for (final item in event!.items) item.label], ['B', 'A']);
  });

  test('an event not watched in Combined keeps to the game\'s category', () async {
    final (games, index) = await container(combined: false)
        .read(gameCardWrapperProvider)
        .debugResolveForYouNavigation(orderedGames: [tapped], gameIndex: 0);

    expect(games, hasLength(4));
    expect(games.every((game) => game.tourId == 'group-a'), isTrue);
    expect(games[index].gameId, tapped.gameId);
  });

  test('without Premium the list keeps to the game\'s category', () async {
    final scope = container(entitled: false);
    final (games, _) = await scope
        .read(gameCardWrapperProvider)
        .debugResolveForYouNavigation(orderedGames: [tapped], gameIndex: 0);

    expect(games, hasLength(4));
    expect(games.every((game) => game.tourId == 'group-a'), isTrue);
    expect(scope.read(combinedBoardEventsProvider), isEmpty);
  });
}

class _MemoryStore implements TourSelectionStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> setString(String key, String value) async => values[key] = value;
}

class _GamesByTour extends GamesLocalStorage {
  _GamesByTour(super.ref, this.byTour);

  final Map<String, List<Games>> byTour;

  @override
  Future<List<Games>> getCachedGames(String tourId) async =>
      byTour[tourId] ?? const [];

  @override
  Future<List<Games>> fetchAndSaveGames(
    String tourId, {
    bool forceRefresh = false,
    String? priorityRoundId,
    void Function(List<Games>)? onPriorityRound,
    Future<void> Function()? afterPriorityRound,
    bool rethrowErrors = false,
  }) async => byTour[tourId] ?? const [];
}

class _Events implements GroupBroadcastRepository {
  _Events(this.eventByTour);

  final Map<String, String> eventByTour;

  @override
  Future<Map<String, String>> getTourToGroupBroadcastMapping(
    List<String> tourIds,
  ) async => {
    for (final id in tourIds)
      if (eventByTour[id] != null) id: eventByTour[id]!,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Tours implements TourRepository {
  _Tours(this.byEvent);

  final Map<String, List<Tour>> byEvent;

  @override
  Future<List<Tour>> getTourByGroupId(String groupId) async =>
      byEvent[groupId] ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Rounds implements RoundRepository {
  _Rounds(this.byTour);

  final Map<String, List<Round>> byTour;

  @override
  Future<Map<String, List<Round>>> getRoundsByTourIds(
    List<String> tourIds,
  ) async => {
    for (final id in tourIds)
      if (byTour[id] != null) id: byTour[id]!,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Tour _tour(String id, String name, {int? avgElo, bool isMirror = false}) =>
    Tour(
      id: id,
      name: name,
      slug: id,
      info: const TourInfo(),
      createdAt: DateTime.utc(2026, 11, 1),
      url: 'https://example.test/$id',
      tier: 0,
      dates: [DateTime.utc(2026, 11, 11), DateTime.utc(2026, 11, 15)],
      players: const <TournamentPlayer>[],
      groupBroadcastId: 'total_chess',
      avgElo: avgElo,
      isMirror: isMirror,
    );

Round _round(String tourId, int number, DateTime startsAt) => Round(
  id: '$tourId-round-$number',
  slug: 'round-$number',
  tourId: tourId,
  tourSlug: tourId,
  name: 'Round $number',
  createdAt: DateTime.utc(2026, 11, 1),
  startsAt: startsAt,
  url: 'https://example.test/$tourId/$number',
);

Games _game({
  required String id,
  required String tourId,
  required int round,
  required int board,
  String? white,
  String? black,
}) => Games(
  id: id,
  roundId: '$tourId-round-$round',
  roundSlug: 'round-$round',
  tourId: tourId,
  tourSlug: tourId,
  players: [
    _player(white ?? 'White $id', 1),
    _player(black ?? 'Black $id', 2),
  ],
  boardNr: board,
  status: '1-0',
  lastMove: 'e2e4',
);

Player _player(String name, int fideId) => Player(
  name: name,
  title: 'GM',
  rating: 2700,
  fideId: fideId,
  fed: 'USA',
  clock: 0,
  team: '',
);
