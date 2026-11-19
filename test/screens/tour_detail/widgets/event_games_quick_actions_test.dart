import 'dart:async';

import 'package:chessever2/providers/live_game_ids_provider.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_games_provider.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_round_sections.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_live_game_ids.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_display_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_flattened_layout.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/match_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_games_quick_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../support/fake_live_game_ids.dart';

/// The event Games tab's Live first and Collapse all, moved out of the ⋮
/// menu into the search row (Trello #1420). Same rules as the menu rows,
/// for one category and for Combined. What is in play is the server's
/// answer (`get_live_game_ids`), faked here per scope.

PlayerCard _player(String name) => PlayerCard(
  name: name,
  federation: 'NOR',
  title: 'GM',
  rating: 2800,
  countryCode: 'NOR',
  team: null,
);

GamesTourModel _game(
  String id, {
  required bool live,
  String tourId = 'tour-1',
  String roundId = 'round-1',
}) => GamesTourModel(
  gameId: id,
  whitePlayer: _player('$id white'),
  blackPlayer: _player('$id black'),
  whiteTimeDisplay: '--:--',
  blackTimeDisplay: '--:--',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: live ? GameStatus.ongoing : GameStatus.whiteWins,
  roundId: roundId,
  tourId: tourId,
  lastMove: 'e2e4',
  lastMoveTime: DateTime.now().toUtc(),
);

GroupedGamesData _grouped(
  List<GamesTourModel> games, {
  Map<String, List<GamesTourModel>>? byRound,
}) => GroupedGamesData(
  filteredRounds: const [],
  gamesByRound: byRound ?? {'round-1': games},
  isKnockoutTournament: false,
  isMultiStageKnockout: false,
  isLoading: false,
  rounds: const [],
  allGames: games,
  providerGameCount: games.length,
  liveScopes: eventGamesLiveScopes('tour-1'),
);

/// The boards a fixture marks in play: what the server says by default.
Set<String> _inPlay(Iterable<GamesTourModel> games) => {
  for (final game in games)
    if (game.gameStatus == GameStatus.ongoing) game.gameId,
};

/// The server's answer for every scope: [server] (by default the boards the
/// fixture marks in play), or none yet when [answered] is false.
Override _serverLive(
  Iterable<GamesTourModel> games, {
  Set<String>? server,
  bool answered = true,
}) => eventLiveGameIdsProvider.overrideWith(
  (ref, scope) => FakeLiveGameIds(answered ? server ?? _inPlay(games) : null),
);

/// The single-category screen model, with the two order switches recorded.
class _GamesScreen extends GamesTourScreenProvider {
  _GamesScreen({
    required super.ref,
    required List<GamesTourModel> games,
    bool isSearchMode = false,
    String? searchQuery,
  }) : super.loading() {
    state = AsyncValue.data(
      GamesScreenModel(
        gamesTourModels: games,
        pinnedGamedIs: const [],
        isSearchMode: isSearchMode,
        searchQuery: searchQuery,
      ),
    );
  }

  final calls = <String>[];

  void _setMode(GameDisplayMode mode) {
    final current = state.value!;
    // As the real switches do: rebuilt from every game, search ended.
    state = AsyncValue.data(
      GamesScreenModel(
        gamesTourModels: current.gamesTourModels,
        pinnedGamedIs: current.pinnedGamedIs,
        gameDisplayMode: mode,
      ),
    );
  }

  @override
  Future<void> hideFinishedGames() async {
    calls.add('hideFinishedGames');
    _setMode(GameDisplayMode.hideFinishedGames);
  }

  @override
  Future<void> showAllGames() async {
    calls.add('showAllGames');
    _setMode(GameDisplayMode.all);
  }

  @override
  Future<void> searchGamesEnhanced(String query) async {
    calls.add('search:$query');
    state = AsyncValue.data(
      state.value!.copyWith(isSearchMode: true, searchQuery: query),
    );
  }
}

List<Override> _singleCategory({
  required List<GamesTourModel> games,
  Map<String, List<GamesTourModel>>? byRound,
  bool isSearchMode = false,
  String? searchQuery,
  EventGamesSections? sections,
  Set<String>? server,
  bool answered = true,
}) => [
  _serverLive(games, server: server, answered: answered),
  combinedCategorySelectedProvider.overrideWithValue(false),
  gamesTourScreenProvider.overrideWith(
    (ref) => _GamesScreen(
      ref: ref,
      games: games,
      isSearchMode: isSearchMode,
      searchQuery: searchQuery,
    ),
  ),
  gamesTourGroupedProvider.overrideWithValue(_grouped(games, byRound: byRound)),
  eventGamesSectionsProvider.overrideWithValue(
    sections ??
        const EventGamesSections(
          roundIds: ['round-1'],
          foldRoundIds: ['round-1'],
        ),
  ),
];

const _categories = [
  CombinedCategory(tourId: 'open', label: 'Open', avgElo: 2700, order: 0),
  CombinedCategory(tourId: 'women', label: 'Women', avgElo: 2500, order: 1),
];

CombinedGamesPresentation _combinedPresentation(
  List<GamesTourModel> games, {
  String searchQuery = '',
}) {
  final byTour = <String, List<GamesTourModel>>{};
  for (final game in games) {
    (byTour[game.tourId] ??= []).add(game);
  }
  final sections = buildCombinedRoundSections(
    categories: _categories,
    gamesByTourId: byTour,
    roundsByTourId: const {},
    liveRoundIds: const [],
  );
  return CombinedGamesPresentation(
    source: CombinedRoundSections(
      isLoading: false,
      error: null,
      sections: sections,
      pinnedGameIds: const [],
      searchQuery: searchQuery,
      hasUnscheduledRounds: false,
    ),
    gamesByRound: {'combined:round': games},
    layout: GamesTourFlattenedLayout.empty,
  );
}

List<Override> _combined(
  List<GamesTourModel> games, {
  String searchQuery = '',
  Set<String>? server,
  bool answered = true,
}) => [
  _serverLive(games, server: server, answered: answered),
  combinedCategorySelectedProvider.overrideWithValue(true),
  combinedCategoriesProvider.overrideWithValue(
    const CombinedCategories(_categories),
  ),
  combinedGamesPresentationProvider.overrideWithValue(
    _combinedPresentation(games, searchQuery: searchQuery),
  ),
];

void main() {
  group('Live first, one category', () {
    test('turns on with a game in play and off again', () async {
      final container = ProviderContainer(
        overrides: _singleCategory(
          games: [_game('a', live: false), _game('b', live: true)],
        ),
      );
      addTearDown(container.dispose);
      final screen =
          container.read(gamesTourScreenProvider.notifier) as _GamesScreen;
      expect(container.read(eventGamesLiveFirstProvider), isFalse);

      expect(
        pressEventGamesLiveFirst(container.read),
        EventLiveFirstPress.turnedOn,
      );
      await pumpEventQueue();
      expect(screen.calls, ['hideFinishedGames']);
      expect(container.read(eventGamesLiveFirstProvider), isTrue);

      expect(
        pressEventGamesLiveFirst(container.read),
        EventLiveFirstPress.turnedOff,
      );
      await pumpEventQueue();
      expect(screen.calls, ['hideFinishedGames', 'showAllGames']);
      expect(container.read(eventGamesLiveFirstProvider), isFalse);
    });

    test('stays off when nothing is in play', () async {
      final container = ProviderContainer(
        overrides: _singleCategory(
          games: [_game('a', live: false), _game('b', live: false)],
        ),
      );
      addTearDown(container.dispose);
      final screen =
          container.read(gamesTourScreenProvider.notifier) as _GamesScreen;

      expect(
        pressEventGamesLiveFirst(container.read),
        EventLiveFirstPress.nothingLive,
      );
      await pumpEventQueue();
      expect(screen.calls, isEmpty);
      expect(container.read(eventGamesLiveFirstProvider), isFalse);
    });

    test('a board whose row still reads in play is not, when the server '
        'says no game is', () async {
      // A 0-move shell, or a game whose finish the list has not seen yet.
      final container = ProviderContainer(
        overrides: _singleCategory(
          games: [_game('a', live: true)],
          server: const {},
        ),
      );
      addTearDown(container.dispose);

      expect(
        pressEventGamesLiveFirst(container.read),
        EventLiveFirstPress.nothingLive,
      );
    });

    test('until the server answers, the boards\' own status decides', () {
      final stale = _game('a', live: true).copyWith(
        lastMoveTime: DateTime.now().toUtc().subtract(const Duration(days: 2)),
      );
      final quiet = ProviderContainer(
        overrides: _singleCategory(games: [stale], answered: false),
      );
      addTearDown(quiet.dispose);
      expect(
        pressEventGamesLiveFirst(quiet.read),
        EventLiveFirstPress.nothingLive,
      );

      final live = ProviderContainer(
        overrides: _singleCategory(
          games: [_game('b', live: true)],
          answered: false,
        ),
      );
      addTearDown(live.dispose);
      expect(pressEventGamesLiveFirst(live.read), EventLiveFirstPress.turnedOn);
    });

    test('turning off works after the last live game ends', () async {
      final container = ProviderContainer(
        overrides: _singleCategory(games: [_game('a', live: false)]),
      );
      addTearDown(container.dispose);
      final screen =
          container.read(gamesTourScreenProvider.notifier) as _GamesScreen;
      await screen.hideFinishedGames();
      screen.calls.clear();

      expect(
        pressEventGamesLiveFirst(container.read),
        EventLiveFirstPress.turnedOff,
      );
      await pumpEventQueue();
      expect(screen.calls, ['showAllGames']);
    });

    test('keeps a search running in the new order', () async {
      final container = ProviderContainer(
        overrides: _singleCategory(
          games: [_game('b', live: true)],
          isSearchMode: true,
          searchQuery: ' Carlsen ',
        ),
      );
      addTearDown(container.dispose);
      final screen =
          container.read(gamesTourScreenProvider.notifier) as _GamesScreen;

      pressEventGamesLiveFirst(container.read);
      await pumpEventQueue();
      expect(screen.calls, ['hideFinishedGames', 'search:Carlsen']);
      final model = container.read(gamesTourScreenProvider).value!;
      expect(model.isSearchMode, isTrue);
      expect(model.gameDisplayMode, GameDisplayMode.hideFinishedGames);
    });
  });

  group('Live first, Combined', () {
    test('switches every merged category together', () {
      final container = ProviderContainer(
        overrides: _combined([
          _game('o1', live: true, tourId: 'open'),
          _game('w1', live: false, tourId: 'women'),
        ]),
      );
      addTearDown(container.dispose);

      expect(
        pressEventGamesLiveFirst(container.read),
        EventLiveFirstPress.turnedOn,
      );
      for (final tourId in ['open', 'women']) {
        expect(
          container.read(gameDisplayModeProvider(tourId)),
          GameDisplayMode.hideFinishedGames,
        );
      }
      expect(container.read(eventGamesLiveFirstProvider), isTrue);

      expect(
        pressEventGamesLiveFirst(container.read),
        EventLiveFirstPress.turnedOff,
      );
      for (final tourId in ['open', 'women']) {
        expect(
          container.read(gameDisplayModeProvider(tourId)),
          GameDisplayMode.all,
        );
      }
      expect(container.read(eventGamesLiveFirstProvider), isFalse);
    });

    test('stays off when no category has a game in play', () {
      final container = ProviderContainer(
        overrides: _combined([
          _game('o1', live: false, tourId: 'open'),
          _game('w1', live: false, tourId: 'women'),
        ]),
      );
      addTearDown(container.dispose);

      expect(
        pressEventGamesLiveFirst(container.read),
        EventLiveFirstPress.nothingLive,
      );
      expect(
        container.read(gameDisplayModeProvider('open')),
        GameDisplayMode.all,
      );
    });

    test('reads off while only some categories have it on', () {
      final container = ProviderContainer(overrides: _combined(const []));
      addTearDown(container.dispose);
      container.read(gameDisplayModeProvider('open').notifier).state =
          GameDisplayMode.hideFinishedGames;
      expect(container.read(eventGamesLiveFirstProvider), isFalse);
    });
  });

  group('Collapse all', () {
    test('one category folds every round and match, then opens them', () {
      final container = ProviderContainer(
        overrides: _singleCategory(
          games: const [],
          sections: const EventGamesSections(
            roundIds: ['r1', 'r2'],
            matchKeys: ['m1'],
            foldRoundIds: ['r1', 'r2', 'r3'],
            foldMatchKeys: ['m1', 'm2'],
          ),
        ),
      );
      addTearDown(container.dispose);
      final sections = container.read(eventGamesSectionsProvider);
      expect(eventGamesSectionsCollapsed(container.read, sections), isFalse);

      toggleEventGamesSections(container.read);
      final rounds = container.read(roundExpansionProvider);
      expect(rounds, {'r1': false, 'r2': false, 'r3': false});
      final matches = container.read(matchExpansionProvider);
      expect(resolveMatchExpansionState(matches, 'm1'), isFalse);
      expect(resolveMatchExpansionState(matches, 'm2'), isFalse);
      // Matches that appear later stay folded too.
      expect(resolveMatchExpansionState(matches, 'm-new'), isFalse);
      expect(eventGamesSectionsCollapsed(container.read, sections), isTrue);

      toggleEventGamesSections(container.read);
      expect(container.read(roundExpansionProvider), {
        'r1': true,
        'r2': true,
        'r3': true,
      });
      expect(
        resolveMatchExpansionState(
          container.read(matchExpansionProvider),
          'm1',
        ),
        isTrue,
      );
      expect(eventGamesSectionsCollapsed(container.read, sections), isFalse);
    });

    test('a round opened by hand makes it fold again first', () {
      final container = ProviderContainer(
        overrides: _singleCategory(
          games: const [],
          sections: const EventGamesSections(
            roundIds: ['r1', 'r2'],
            foldRoundIds: ['r1', 'r2'],
          ),
        ),
      );
      addTearDown(container.dispose);
      toggleEventGamesSections(container.read);
      container.read(roundExpansionProvider.notifier).toggleRound('r2');

      toggleEventGamesSections(container.read);
      expect(container.read(roundExpansionProvider), {
        'r1': false,
        'r2': false,
      });
    });

    test('Combined folds its round cards and leaves matches alone', () {
      final container = ProviderContainer(
        overrides: _combined([
          _game('o1', live: false, tourId: 'open'),
          _game('w1', live: false, tourId: 'women', roundId: 'round-2'),
        ]),
      );
      addTearDown(container.dispose);
      final sections = container.read(eventGamesSectionsProvider);
      expect(sections.roundIds, isNotEmpty);
      expect(sections.roundIds, everyElement(startsWith('combined:')));
      expect(sections.foldRoundIds, sections.roundIds);
      expect(sections.matchKeys, isEmpty);

      toggleEventGamesSections(container.read);
      expect(container.read(roundExpansionProvider), {
        for (final id in sections.roundIds) id: false,
      });
      expect(container.read(matchExpansionProvider), isEmpty);

      toggleEventGamesSections(container.read);
      expect(container.read(roundExpansionProvider), {
        for (final id in sections.roundIds) id: true,
      });
    });

    test('Combined has nothing to fold during a search', () {
      // A search shows every hit open under inert headers.
      final container = ProviderContainer(
        overrides: _combined([
          _game('o1', live: false, tourId: 'open'),
        ], searchQuery: 'o1'),
      );
      addTearDown(container.dispose);
      expect(
        container.read(combinedGamesPresentationProvider).roundIds,
        isNotEmpty,
      );
      expect(
        container.read(eventGamesSectionsProvider),
        EventGamesSections.none,
      );

      toggleEventGamesSections(container.read);
      expect(container.read(roundExpansionProvider), isEmpty);
    });
  });

  group('areAllVisibleSectionsCollapsed', () {
    test('treats missing round state as expanded by default', () {
      expect(
        areAllVisibleSectionsCollapsed(
          visibleRoundIds: const ['round-1', 'round-2'],
          visibleMatchKeys: const [],
          roundExpansionState: const {},
          matchExpansionState: const {},
        ),
        isFalse,
      );
    });

    test('returns true when every visible round is collapsed', () {
      expect(
        areAllVisibleSectionsCollapsed(
          visibleRoundIds: const ['round-1', 'round-2'],
          visibleMatchKeys: const [],
          roundExpansionState: const {'round-1': false, 'round-2': false},
          matchExpansionState: const {},
        ),
        isTrue,
      );
    });

    test('requires visible knockout matches to be collapsed as well', () {
      expect(
        areAllVisibleSectionsCollapsed(
          visibleRoundIds: const ['round-1'],
          visibleMatchKeys: const ['match-a'],
          roundExpansionState: const {'round-1': false},
          matchExpansionState: const {},
        ),
        isFalse,
      );

      expect(
        areAllVisibleSectionsCollapsed(
          visibleRoundIds: const ['round-1'],
          visibleMatchKeys: const ['match-a'],
          roundExpansionState: const {'round-1': false},
          matchExpansionState: const {'match-a': false},
        ),
        isTrue,
      );
    });

    test('an empty list is not folded', () {
      expect(
        areAllVisibleSectionsCollapsed(
          visibleRoundIds: const [],
          visibleMatchKeys: const [],
          roundExpansionState: const {},
          matchExpansionState: const {},
        ),
        isFalse,
      );
    });
  });

  group('eventGamesAnyLiveProvider', () {
    // Live first floats over Games only while this holds (Trello #1420).
    test('one category: true while a game is in play', () {
      final container = ProviderContainer(
        overrides: _singleCategory(
          games: [_game('a', live: false), _game('b', live: true)],
        ),
      );
      addTearDown(container.dispose);
      expect(container.read(eventGamesAnyLiveProvider), isTrue);
    });

    test('one category: false with nothing in play', () {
      final container = ProviderContainer(
        overrides: _singleCategory(
          games: [_game('a', live: false), _game('b', live: false)],
        ),
      );
      addTearDown(container.dispose);
      expect(container.read(eventGamesAnyLiveProvider), isFalse);
    });

    test('Combined: reads every merged category', () {
      final live = ProviderContainer(
        overrides: _combined([
          _game('a', tourId: 'tour-a', live: false),
          _game('b', tourId: 'tour-b', live: true),
        ]),
      );
      addTearDown(live.dispose);
      expect(live.read(eventGamesAnyLiveProvider), isTrue);

      final quiet = ProviderContainer(
        overrides: _combined([
          _game('a', tourId: 'tour-a', live: false),
          _game('b', tourId: 'tour-b', live: false),
        ]),
      );
      addTearDown(quiet.dispose);
      expect(quiet.read(eventGamesAnyLiveProvider), isFalse);
    });
  });

  group('eventGamesLiveCountProvider', () {
    // What Live first reads out ("3 live").
    test('one category: each board in play once, however many sections '
        'list it', () {
      final live = _game('a', live: true);
      final container = ProviderContainer(
        overrides: _singleCategory(
          games: [live, _game('b', live: true), _game('c', live: false)],
          byRound: {
            'round-1': [live, _game('b', live: true), _game('c', live: false)],
            // A knockout match lists its board again under its stage.
            'round-2': [live],
          },
        ),
      );
      addTearDown(container.dispose);
      expect(container.read(eventGamesLiveCountProvider), 2);
    });

    test('one category: the server decides, not the rows', () {
      // 'a' reads in play but the server has it finished (or never
      // started); 'c' is in play by the server though its row is behind.
      final container = ProviderContainer(
        overrides: _singleCategory(
          games: [
            _game('a', live: true),
            _game('b', live: true),
            _game('c', live: false).copyWith(gameStatus: GameStatus.unknown),
          ],
          server: const {'b', 'c'},
        ),
      );
      addTearDown(container.dispose);
      expect(container.read(eventGamesLiveCountProvider), 2);
      expect(container.read(eventGamesLiveIdsProvider), {'b', 'c'});
    });

    test('one category: only boards the list shows, and none it already '
        'shows as finished', () {
      final container = ProviderContainer(
        overrides: _singleCategory(
          games: [_game('a', live: true), _game('b', live: false)],
          // 'elsewhere' is another tour's board; 'b' finished since.
          server: const {'a', 'b', 'elsewhere'},
        ),
      );
      addTearDown(container.dispose);
      expect(container.read(eventGamesLiveIdsProvider), {'a'});
      expect(container.read(eventGamesLiveCountProvider), 1);
    });

    test('unknown until the server answers: no number ("See live"), and the '
        'boards\' own status floats the capsule', () {
      final container = ProviderContainer(
        overrides: _singleCategory(
          games: [_game('a', live: true)],
          answered: false,
        ),
      );
      addTearDown(container.dispose);
      expect(container.read(eventGamesLiveCountProvider), isNull);
      expect(container.read(eventGamesAnyLiveProvider), isTrue);
    });

    test('Combined: every merged category\'s boards in play', () {
      final container = ProviderContainer(
        overrides: _combined([
          _game('a', tourId: 'open', live: true),
          _game('b', tourId: 'women', live: true),
          _game('c', tourId: 'women', live: false),
        ]),
      );
      addTearDown(container.dispose);
      expect(container.read(eventGamesLiveCountProvider), 2);
    });

    test('Combined asks about every category at once, at its own pace', () {
      final container = ProviderContainer(overrides: _combined(const []));
      addTearDown(container.dispose);
      expect(
        container.read(combinedGamesLiveScopeProvider),
        EventLiveGamesScope(const ['women', 'open']),
      );
      expect(
        container.read(combinedGamesLiveScopeProvider)!.poll,
        EventLiveGamesScope.combinedPoll,
      );
    });
  });

  group('event live scopes', () {
    test('the tour at the event pace, sibling stages at their own', () {
      expect(eventGamesLiveScopes(null), isEmpty);
      expect(eventGamesLiveScopes('t1'), [
        EventLiveGamesScope(const ['t1']),
      ]);
      final scopes = eventGamesLiveScopes(
        't1',
        siblingTourIds: const ['t3', 't1', 't2', ' '],
      );
      expect(scopes, [
        EventLiveGamesScope(const ['t1']),
        EventLiveGamesScope(const ['t2', 't3'], poll: kSiblingStageLivePoll),
      ]);
      expect(scopes.first.poll, EventLiveGamesScope.eventPoll);
    });
  });

  group('eventLiveFocusOrder', () {
    final games = [
      _game('a', live: false),
      _game('b', live: true),
      _game('c', live: true),
      _game('d', live: false).copyWith(gameStatus: GameStatus.unknown),
    ];
    List<String> ids(List<GamesTourModel> games) => [
      for (final game in games) game.gameId,
    ];

    test('lifts what the server has in play, less boards shown finished', () {
      expect(ids(eventLiveFocusOrder(games, const {'c', 'a', 'd'})), [
        'c',
        'd',
        'a',
        'b',
      ]);
    });

    test('nothing in play keeps the usual order', () {
      expect(ids(eventLiveFocusOrder(games, const {})), ['a', 'b', 'c', 'd']);
    });

    test('until the server answers, the boards in play by their own rows '
        'lead (ongoing, with a move)', () {
      expect(ids(eventLiveFocusOrder(games, null)), ['b', 'c', 'a', 'd']);
      // A 0-move shell is never lifted, whatever its day.
      final shell = _game('s', live: true).copyWith(lastMove: '');
      expect(ids(eventLiveFocusOrder([games.first, shell], null)), ['a', 's']);
    });
  });

  group('the event list\'s live-game polls wait while it is out of view', () {
    // Live first keeps the polls running from the kept-alive Games tab: they
    // wait while another tab is in front or a board covers the event,
    // whichever tab the board was opened from.
    final scope = EventLiveGamesScope(const ['tour-1']);

    /// Polls started, newest last; [gamesInView] is the event's tab.
    Future<(List<FakeLiveGameIds>, StateProvider<bool>, StateProvider<bool>)>
    pumpEvent(WidgetTester tester) async {
      final polls = <FakeLiveGameIds>[];
      final gamesInView = StateProvider<bool>((ref) => true);
      // Live first is on: the list watches the poll.
      final listWatches = StateProvider<bool>((ref) => true);
      final container = ProviderContainer(
        overrides: [
          combinedCategorySelectedProvider.overrideWithValue(false),
          gamesTourGroupedProvider.overrideWithValue(_grouped(const [])),
          eventLiveGameIdsProvider.overrideWith((ref, scope) {
            final poll = FakeLiveGameIds(const <String>{});
            polls.add(poll);
            return poll;
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              // The floating buttons, above the list in the tree. They
              // rebuild with the page (a category picked rebuilds both).
              builder: (context, ref, _) {
                ref.watch(listWatches);
                syncEventGamesLiveIdsVisibility(
                  context,
                  ref,
                  gamesInView: ref.watch(gamesInView),
                );
                return Consumer(
                  // The kept-alive Games list.
                  builder: (context, ref, _) {
                    ref.watch(gamesTourGroupedProvider);
                    if (ref.watch(listWatches)) {
                      ref.watch(eventLiveGameIdsProvider(scope));
                    }
                    return const SizedBox.shrink();
                  },
                );
              },
            ),
          ),
        ),
      );
      return (polls, gamesInView, listWatches);
    }

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

    testWidgets('another tab in front, then a board opened from it', (
      tester,
    ) async {
      final (polls, gamesInView, _) = await pumpEvent(tester);
      final poll = polls.single;
      expect(poll.visible, isTrue);

      containerOf(tester).read(gamesInView.notifier).state = false;
      await tester.pump();
      expect(poll.visible, isFalse);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold()),
        ),
      );
      await tester.pumpAndSettle();
      expect(poll.visible, isFalse);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(poll.visible, isFalse);

      containerOf(tester).read(gamesInView.notifier).state = true;
      await tester.pump();
      expect(poll.visible, isTrue);
    });

    testWidgets('a board over the Games tab', (tester) async {
      final (polls, _, _) = await pumpEvent(tester);
      final poll = polls.single;
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));

      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold()),
        ),
      );
      await tester.pumpAndSettle();
      expect(poll.visible, isFalse);

      navigator.pop();
      await tester.pumpAndSettle();
      expect(poll.visible, isTrue);
    });

    testWidgets('a poll the list starts while another tab is in front waits '
        'too', (tester) async {
      final (polls, gamesInView, listWatches) = await pumpEvent(tester);
      final container = containerOf(tester);
      container.read(listWatches.notifier).state = false;
      container.read(gamesInView.notifier).state = false;
      await tester.pump();
      // Nothing watches the first poll any more.
      await tester.pump();

      // Live first starts a poll again (a category picked from Standings),
      // in the same frame as the buttons' build, after it.
      container.read(listWatches.notifier).state = true;
      await tester.pump();
      expect(polls, hasLength(2));
      expect(polls.last.visible, isFalse);
    });
  });
}
