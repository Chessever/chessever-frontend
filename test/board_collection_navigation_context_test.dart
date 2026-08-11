import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart'
    show
        BoardNavigationListPolicy,
        ChessboardView,
        ChessboardViewNavigationContext;
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Board navigation opened from a *collection* surface must keep the exact
/// list and order that surface handed over.
///
/// The board's game-switcher dropdown and previous/next both read the list
/// resolved by `_resolveNavigationGames`. That resolver expands an incomplete
/// list (a For You top-N preview, a single-round pin) to the tapped game's full
/// event. Favorites, Countrymen and Smart Events are not incomplete — they are
/// filtered and ordered on purpose — so expanding them silently refills the
/// dropdown with games the collection deliberately excluded.
///
/// These tests drive the real resolver through its `debugResolveNavigation`
/// seam with a cache that *would* satisfy an expansion, so a passing
/// passthrough assertion can only mean the context gate held.
void main() {
  // Five games across three rounds of `tour-1`. Games-tab order (round DESC,
  // board ASC) is: r3-b1, r2-b1, r2-b2, r1-b1, r1-b2.
  List<Games> tourOneRawGames() => [
    _makeGame(id: 'r2-b1', roundSlug: 'round-2', boardNr: 1),
    _makeGame(id: 'r2-b2', roundSlug: 'round-2', boardNr: 2),
    _makeGame(id: 'r1-b1', roundSlug: 'round-1', boardNr: 1),
    _makeGame(id: 'r1-b2', roundSlug: 'round-1', boardNr: 2),
    _makeGame(id: 'r3-b1', roundSlug: 'round-3', boardNr: 1),
  ];

  List<Games> tourTwoRawGames() => [
    _makeGame(
      id: 'b-r2-b1',
      roundSlug: 'round-2',
      boardNr: 1,
      tourId: 'tour-2',
    ),
    _makeGame(
      id: 'b-r1-b1',
      roundSlug: 'round-1',
      boardNr: 1,
      tourId: 'tour-2',
    ),
  ];

  GamesTourModel modelFor(String id) {
    final all = [...tourOneRawGames(), ...tourTwoRawGames()];
    return GamesTourModel.fromGame(all.firstWhere((g) => g.id == id));
  }

  /// A container whose cache holds BOTH full events, so any expansion the
  /// resolver decides to perform will succeed. Passthrough therefore proves
  /// the gate, not a starved fake.
  ProviderContainer containerWithFullCache() {
    return ProviderContainer(
      overrides: [
        gamesLocalStorage.overrideWith(
          (ref) => _FakeGamesLocalStorage(
            ref,
            byTour: {'tour-1': tourOneRawGames(), 'tour-2': tourTwoRawGames()},
          ),
        ),
      ],
    );
  }

  Future<(List<GamesTourModel>, int)> resolve(
    ProviderContainer container, {
    required List<GamesTourModel> orderedGames,
    required int gameIndex,
    required ChessboardView viewSource,
    BoardNavigationListPolicy listPolicy =
        BoardNavigationListPolicy.sourceDefault,
  }) {
    return container
        .read(gameCardWrapperProvider)
        .debugResolveNavigation(
          orderedGames: orderedGames,
          gameIndex: gameIndex,
          viewSource: viewSource,
          listPolicy: listPolicy,
        );
  }

  group('collection contexts keep their list', () {
    // Every collection/player-list surface hands over a deliberate ordered
    // feed. Background navigation hydration must never replace that feed with
    // the tapped game's whole tournament.
    for (final viewSource in [
      ChessboardView.favorites,
      ChessboardView.countryman,
      ChessboardView.favScorecard,
      ChessboardView.playerProfile,
    ]) {
      test('$viewSource keeps its mixed-event feed exactly', () async {
        final container = containerWithFullCache();
        addTearDown(container.dispose);

        final feed = [
          modelFor('r2-b1'), // tour-1
          modelFor('b-r1-b1'), // tour-2
        ];

        final (games, index) = await resolve(
          container,
          orderedGames: feed,
          gameIndex: 0,
          viewSource: viewSource,
        );

        expect(games.map((g) => g.gameId).toList(), [
          'r2-b1',
          'b-r1-b1',
        ], reason: '$viewSource must not refill the switcher with tour-1');
        expect(index, 0);
        expect(games[index].gameId, 'r2-b1');
      });
    }

    test(
      'smartEvent keeps a filtered single-round subset of one event',
      () async {
        final container = containerWithFullCache();
        addTearDown(container.dispose);

        // The strongest case: a single-tour, single-round list is exactly the
        // shape the resolver expands for every other route. A Smart Event that
        // filtered down to these two games must still see only these two.
        final filtered = [modelFor('r1-b1'), modelFor('r1-b2')];

        final (games, index) = await resolve(
          container,
          orderedGames: filtered,
          gameIndex: 1,
          viewSource: ChessboardView.smartEvent,
        );

        expect(games.map((g) => g.gameId).toList(), ['r1-b1', 'r1-b2']);
        expect(index, 1);
        expect(games[index].gameId, 'r1-b2');
      },
    );

    test(
      'smartEvent keeps a custom order the Games tab would resort',
      () async {
        final container = containerWithFullCache();
        addTearDown(container.dispose);

        // Reverse of Games-tab order. An expansion would resort to round DESC /
        // board ASC and lose the Smart Event's own ranking.
        final customOrder = [
          modelFor('r1-b2'),
          modelFor('r1-b1'),
          modelFor('r2-b1'),
          modelFor('r3-b1'),
        ];

        final (games, _) = await resolve(
          container,
          orderedGames: customOrder,
          gameIndex: 0,
          viewSource: ChessboardView.smartEvent,
        );

        expect(games.map((g) => g.gameId).toList(), [
          'r1-b2',
          'r1-b1',
          'r2-b1',
          'r3-b1',
        ]);
      },
    );

    test(
      'an out-of-range index is clamped without widening the list',
      () async {
        final container = containerWithFullCache();
        addTearDown(container.dispose);

        final feed = [modelFor('r1-b1'), modelFor('r1-b2')];

        final (games, index) = await resolve(
          container,
          orderedGames: feed,
          gameIndex: 9,
          viewSource: ChessboardView.favorites,
        );

        expect(games, hasLength(2));
        expect(index, 1);
      },
    );
  });

  test('control: the same subset from a tournament still expands', () async {
    // Guards the test above: proves the passthrough comes from the context
    // gate and not from a fake that simply cannot expand.
    final container = containerWithFullCache();
    addTearDown(container.dispose);

    final filtered = [modelFor('r1-b1'), modelFor('r1-b2')];

    final (games, index) = await resolve(
      container,
      orderedGames: filtered,
      gameIndex: 1,
      viewSource: ChessboardView.tour,
    );

    expect(games.map((g) => g.gameId).toList(), [
      'r3-b1',
      'r2-b1',
      'r2-b2',
      'r1-b1',
      'r1-b2',
    ]);
    expect(games[index].gameId, 'r1-b2');
  });

  test(
    'stale event cache cannot discard an immediate preview sibling',
    () async {
      // The cache contains the tapped game, but is missing another game that
      // was already visible in the caller's live preview. Treating this cache
      // as authoritative would remove that sibling from the open board. If the
      // user swiped to it before expansion completed, the PageView could no
      // longer remap its gameId and would jump to a different game.
      final staleCachedEvent =
          tourOneRawGames().where((game) => game.id != 'r2-b2').toList();
      final container = ProviderContainer(
        overrides: [
          gamesLocalStorage.overrideWith(
            (ref) => _FakeGamesLocalStorage(
              ref,
              byTour: {'tour-1': staleCachedEvent},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final immediatePreview = [modelFor('r2-b1'), modelFor('r2-b2')];
      final (games, index) = await container
          .read(gameCardWrapperProvider)
          .debugResolveForYouNavigation(
            orderedGames: immediatePreview,
            gameIndex: 0,
          );

      expect(
        games.map((game) => game.gameId).toList(),
        ['r2-b1', 'r2-b2'],
        reason:
            'an expansion candidate that omits any same-event immediate game '
            'must be rejected instead of deleting a caller-visible sibling',
      );
      expect(index, 0);
      expect(games[index].gameId, 'r2-b1');
    },
  );

  test(
    'event expansion keeps the freshest version of every immediate sibling',
    () async {
      final cachedEvent = tourOneRawGames();
      final container = ProviderContainer(
        overrides: [
          gamesLocalStorage.overrideWith(
            (ref) =>
                _FakeGamesLocalStorage(ref, byTour: {'tour-1': cachedEvent}),
          ),
        ],
      );
      addTearDown(container.dispose);

      const freshSiblingPgn = '''
[Event "Fresh live preview"]
[White "White r2-b2"]
[Black "Black r2-b2"]
[Result "1-0"]

1. e4 e5 2. Nf3 Nc6 1-0
''';
      const freshSiblingFen =
          'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3';
      final immediatePreview = [
        modelFor('r2-b1'),
        modelFor('r2-b2').copyWith(
          pgn: freshSiblingPgn,
          fen: freshSiblingFen,
          lastMove: 'b8c6',
          lastMoveTime: DateTime.utc(2026, 8, 12, 12),
          whiteClockSeconds: 287,
          blackClockSeconds: 281,
          gameStatus: GameStatus.whiteWins,
        ),
      ];

      final (games, _) = await container
          .read(gameCardWrapperProvider)
          .debugResolveForYouNavigation(
            orderedGames: immediatePreview,
            gameIndex: 0,
          );

      final resolvedSibling = games.singleWhere(
        (game) => game.gameId == 'r2-b2',
      );
      expect(
        resolvedSibling.pgn,
        freshSiblingPgn,
        reason:
            'cache expansion must not rewind a sibling the user can swipe to '
            'while hydration is running',
      );
      expect(resolvedSibling.fen, freshSiblingFen);
      expect(resolvedSibling.lastMove, 'b8c6');
      expect(resolvedSibling.whiteClockSeconds, 287);
      expect(resolvedSibling.blackClockSeconds, 281);
      expect(resolvedSibling.gameStatus, GameStatus.whiteWins);
    },
  );

  test(
    'an event-scoped player list preserves its tournament context',
    () async {
      final container = containerWithFullCache();
      addTearDown(container.dispose);

      final playerGames = [modelFor('r1-b1'), modelFor('r1-b2')];
      final (games, index) = await resolve(
        container,
        orderedGames: playerGames,
        gameIndex: 1,
        viewSource: ChessboardView.tour,
        listPolicy: BoardNavigationListPolicy.preserve,
      );

      expect(games.map((g) => g.gameId).toList(), ['r1-b1', 'r1-b2']);
      expect(index, 1);
      expect(games[index].gameId, 'r1-b2');
    },
  );

  test('archive lists never hydrate from a broadcast event cache', () async {
    final container = containerWithFullCache();
    addTearDown(container.dispose);

    final archiveGames = [
      modelFor('r1-b1').copyWith(source: GameSource.twic),
      modelFor('r1-b2').copyWith(source: GameSource.twic),
    ];
    final (games, index) = await resolve(
      container,
      orderedGames: archiveGames,
      gameIndex: 1,
      viewSource: ChessboardView.tour,
    );

    expect(games.map((g) => g.gameId).toList(), ['r1-b1', 'r1-b2']);
    expect(index, 1);
  });

  test('every board view declares its navigation contract', () {
    // The getters are exhaustive switches, so this also fails to COMPILE if a
    // new ChessboardView is added without choosing a side.
    expect(ChessboardView.favorites.preservesNavigationCollection, isTrue);
    expect(ChessboardView.countryman.preservesNavigationCollection, isTrue);
    expect(ChessboardView.smartEvent.preservesNavigationCollection, isTrue);
    expect(ChessboardView.favScorecard.preservesNavigationCollection, isTrue);
    expect(ChessboardView.playerProfile.preservesNavigationCollection, isTrue);
    expect(ChessboardView.forYou.preservesNavigationCollection, isFalse);
    expect(ChessboardView.tour.preservesNavigationCollection, isFalse);

    // Favorites used to travel as forYou; the score card's event-scoped
    // favourite toggle must keep working now that it has its own context.
    expect(ChessboardView.forYou.usesEventScopedScorecardContext, isTrue);
    expect(ChessboardView.favorites.usesEventScopedScorecardContext, isTrue);
    expect(ChessboardView.tour.usesEventScopedScorecardContext, isFalse);
    expect(ChessboardView.smartEvent.usesEventScopedScorecardContext, isFalse);
  });

  test('tournament search and status filters preserve their visible list', () {
    GamesScreenModel data({
      bool isSearchMode = false,
      GameDisplayMode displayMode = GameDisplayMode.all,
    }) => GamesScreenModel(
      gamesTourModels: const [],
      pinnedGamedIs: const [],
      isSearchMode: isSearchMode,
      gameDisplayMode: displayMode,
    );

    expect(
      boardNavigationListPolicyForGamesData(data()),
      BoardNavigationListPolicy.sourceDefault,
    );
    expect(
      boardNavigationListPolicyForGamesData(data(isSearchMode: true)),
      BoardNavigationListPolicy.preserve,
    );
    expect(
      boardNavigationListPolicyForGamesData(
        data(displayMode: GameDisplayMode.hideFinishedGames),
      ),
      BoardNavigationListPolicy.preserve,
    );
  });
}

class _FakeGamesLocalStorage extends GamesLocalStorage {
  _FakeGamesLocalStorage(super.ref, {required Map<String, List<Games>> byTour})
    : _byTour = byTour;

  final Map<String, List<Games>> _byTour;

  @override
  Future<List<Games>> getCachedGames(String tourId) async =>
      _byTour[tourId] ?? const [];

  @override
  Future<List<Games>> fetchAndSaveGames(
    String tourId, {
    bool forceRefresh = false,
  }) async => _byTour[tourId] ?? const [];
}

Games _makeGame({
  required String id,
  required String roundSlug,
  required int boardNr,
  String tourId = 'tour-1',
}) {
  return Games(
    id: id,
    roundId: roundSlug,
    roundSlug: roundSlug,
    tourId: tourId,
    tourSlug: tourId,
    players: [
      _player(name: 'White $id'),
      _player(name: 'Black $id', fideId: 2),
    ],
    boardNr: boardNr,
    status: '*',
    lastMove: 'e2e4',
  );
}

Player _player({required String name, int fideId = 1}) {
  return Player(
    name: name,
    title: 'GM',
    rating: 2700,
    fideId: fideId,
    fed: 'USA',
    clock: 0,
    team: '',
  );
}
