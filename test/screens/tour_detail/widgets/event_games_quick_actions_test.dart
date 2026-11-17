import 'package:chessever2/providers/game_list_live_first_provider.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_games_provider.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_round_sections.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_display_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_flattened_layout.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/match_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_games_quick_actions.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/live_first_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The event Games tab's Live first and Collapse all, moved out of the ⋮
/// menu into the search row (Trello #1420). Same rules as the menu rows,
/// for one category and for Combined.

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
  lastMoveTime: DateTime.now().toUtc(),
);

GroupedGamesData _grouped(List<GamesTourModel> games) => GroupedGamesData(
  filteredRounds: const [],
  gamesByRound: {'round-1': games},
  isKnockoutTournament: false,
  isMultiStageKnockout: false,
  isLoading: false,
  rounds: const [],
  allGames: games,
  providerGameCount: games.length,
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
  bool isSearchMode = false,
  String? searchQuery,
  EventGamesSections? sections,
}) => [
  combinedCategorySelectedProvider.overrideWithValue(false),
  gamesTourScreenProvider.overrideWith(
    (ref) => _GamesScreen(
      ref: ref,
      games: games,
      isSearchMode: isSearchMode,
      searchQuery: searchQuery,
    ),
  ),
  gamesTourGroupedProvider.overrideWithValue(_grouped(games)),
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
}) => [
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

    test('a game that went quiet yesterday is not in play', () async {
      final stale = _game('a', live: true).copyWith(
        lastMoveTime: DateTime.now().toUtc().subtract(const Duration(days: 2)),
      );
      final container = ProviderContainer(
        overrides: _singleCategory(games: [stale]),
      );
      addTearDown(container.dispose);

      expect(
        pressEventGamesLiveFirst(container.read),
        EventLiveFirstPress.nothingLive,
      );
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

  group('EventGamesQuickActions', () {
    Future<void> pumpActions(
      WidgetTester tester,
      List<Override> overrides,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return const Scaffold(
                  body: Center(child: EventGamesQuickActions()),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('Live first wears the web mark and follows the state', (
      tester,
    ) async {
      await pumpActions(
        tester,
        _singleCategory(games: [_game('b', live: true)]),
      );
      expect(find.byType(LiveFirstMark), findsOneWidget);
      expect(find.bySemanticsLabel('Show live games first'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Show live games first'));
      await tester.pump();
      expect(
        find.bySemanticsLabel('Live games are shown first'),
        findsOneWidget,
      );
      expect(find.text(kNoLiveGamesRightNowMessage), findsNothing);

      await tester.tap(find.bySemanticsLabel('Live games are shown first'));
      await tester.pump();
      expect(find.bySemanticsLabel('Show live games first'), findsOneWidget);
    });

    testWidgets('Live first with nothing in play says so and stays off', (
      tester,
    ) async {
      await pumpActions(
        tester,
        _singleCategory(games: [_game('a', live: false)]),
      );

      await tester.tap(find.bySemanticsLabel('Show live games first'));
      await tester.pump();
      expect(find.text('No live games right now'), findsOneWidget);
      expect(find.bySemanticsLabel('Show live games first'), findsOneWidget);
    });

    testWidgets('Collapse all flips its glyph and name as it folds', (
      tester,
    ) async {
      await pumpActions(
        tester,
        _singleCategory(
          games: const [],
          sections: const EventGamesSections(
            roundIds: ['r1', 'r2'],
            foldRoundIds: ['r1', 'r2'],
          ),
        ),
      );
      expect(find.byIcon(Icons.unfold_less), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(kCollapseAllRoundsLabel));
      await tester.pump();
      expect(find.bySemanticsLabel(kExpandAllRoundsLabel), findsOneWidget);
      expect(find.byIcon(Icons.unfold_more), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(kExpandAllRoundsLabel));
      await tester.pump();
      expect(find.bySemanticsLabel(kCollapseAllRoundsLabel), findsOneWidget);
    });

    testWidgets('Collapse all rests disabled with nothing to fold', (
      tester,
    ) async {
      await pumpActions(
        tester,
        _singleCategory(
          games: const [],
          sections: const EventGamesSections(roundIds: [], foldRoundIds: []),
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel(kCollapseAllRoundsLabel)),
        containsSemantics(hasEnabledState: true, isEnabled: false),
      );

      await tester.tap(
        find.bySemanticsLabel(kCollapseAllRoundsLabel),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(find.bySemanticsLabel(kCollapseAllRoundsLabel), findsOneWidget);
    });

    testWidgets('Collapse all rests disabled during a search', (tester) async {
      await pumpActions(
        tester,
        _combined([
          _game('o1', live: false, tourId: 'open'),
        ], searchQuery: 'o1'),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel(kCollapseAllRoundsLabel)),
        containsSemantics(hasEnabledState: true, isEnabled: false),
      );
    });

    testWidgets('both targets are at least 44pt and carry no tile', (
      tester,
    ) async {
      await pumpActions(
        tester,
        _singleCategory(games: [_game('b', live: true)]),
      );
      for (final label in ['Show live games first', kCollapseAllRoundsLabel]) {
        final size = tester.getSize(find.bySemanticsLabel(label));
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
      final boxes = find.descendant(
        of: find.byType(EventGamesQuickActions),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox ||
              (widget is Container && widget.decoration != null) ||
              widget is Material,
        ),
      );
      expect(boxes, findsNothing);
    });
  });
}
