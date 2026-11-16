import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_standings.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_standings_screen.dart';
import 'package:chessever2/screens/tour_detail/combined/standings_category_scope.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_header_widget.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_tour_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Paints whatever state the test hands it, and lets the test swap it.
class _FixedStandings extends CombinedStandingsNotifier {
  _FixedStandings(this.initial);

  final CombinedStandingsState initial;

  @override
  CombinedStandingsState build(CombinedStandingsView arg) => initial;

  void show(CombinedStandingsState next) => state = next;
}

class _NoFavorites extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => const [];
}

CombinedCategory _category(String tourId, String label, int order) =>
    CombinedCategory(tourId: tourId, label: label, avgElo: 2700, order: order);

PlayerStandingModel _player(String name, int rank) => PlayerStandingModel(
  countryCode: 'NOR',
  title: 'GM',
  name: name,
  score: 2700,
  scoreChange: 0,
  matchScore: '3 / 5',
  overallRank: rank,
);

TeamStandingModel _team(String name, int rank) => TeamStandingModel(
  teamName: name,
  rank: rank,
  matchPoints: 10,
  gamePoints: 20,
  matchesWon: 5,
  matchesDrawn: 0,
  matchesLost: 0,
  boardsPlayed: 20,
  players: const [],
);

CombinedStandingsSection _section(
  String tourId,
  String label, {
  int players = 0,
  int teams = 0,
  bool selected = false,
  bool hasError = false,
}) => CombinedStandingsSection(
  group: CombinedStandingsGroup(
    tourIds: [tourId],
    label: label,
    isTeam: teams > 0,
  ),
  tourId: tourId,
  isSelectedCategory: selected,
  showsTeams: teams > 0,
  players: [
    for (var i = 0; i < players; i++) _player('$label Player ${i + 1}', i + 1),
  ],
  teams: [for (var i = 0; i < teams; i++) _team('$label Team ${i + 1}', i + 1)],
  total: teams > 0 ? teams : players,
  officialRound: null,
  officialSections: const [],
  hasError: hasError,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  CombinedStandingsState state, {
  CombinedStandingsView view = CombinedStandingsView.standings,
}) async {
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      combinedStandingsProvider.overrideWith(() => _FixedStandings(state)),
      favoritePlayersProviderNew.overrideWith(_NoFavorites.new),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(body: CombinedStandingsScreen(view: view));
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

CombinedStandingsState _state(
  List<CombinedStandingsSection> sections, {
  String query = '',
  int? tableCount,
}) => CombinedStandingsState(
  isLoading: false,
  sections: sections,
  tableCount: tableCount ?? sections.length,
  query: query,
);

Finder _header(String label) => find.ancestor(
  of: find.textContaining(label, findRichText: true),
  matching: find.byType(TournamentRoundHeader),
);

double _listTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(CustomScrollView)).dy;

/// Shimmer tickers outlive the assertions; let them drain.
Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 30));
}

void main() {
  group('buildCombinedStandingsGroups', () {
    test('one section per category, in picker order', () {
      final groups = buildCombinedStandingsGroups(
        categories: [
          _category('a', 'Group Stage | A', 0),
          _category('b', 'Group Stage | B', 1),
          _category('blitz', 'Blitz Tiebreak', 2),
        ],
        tourNamesById: const {
          'a': 'Total Chess | Group Stage | A',
          'b': 'Total Chess | Group Stage | B',
          'blitz': 'Total Chess | Blitz Tiebreak',
        },
      );

      expect(
        [for (final group in groups) group.label],
        ['Group Stage | A', 'Group Stage | B', 'Blitz Tiebreak'],
      );
      expect(groups.every((group) => group.tourIds.length == 1), isTrue);
    });

    test('pages of one board-paginated tournament are one table', () {
      final groups = buildCombinedStandingsGroups(
        categories: [
          _category('open-1', 'Open | Boards 1-50', 0),
          _category('open-2', 'Open | Boards 51-100', 1),
          _category('women', 'Women', 2),
        ],
        tourNamesById: const {
          'open-1': 'European Championship | Open | Boards 1-50',
          'open-2': 'European Championship | Open | Boards 51-100',
          'women': 'European Championship | Women',
        },
      );

      expect(groups, hasLength(2));
      expect(groups.first.tourIds, ['open-1', 'open-2']);
      expect(groups.first.label, 'Open');
      expect(groups.last.label, 'Women');
    });

    test('a tournament that is only pages keeps a name to show', () {
      final groups = buildCombinedStandingsGroups(
        categories: [
          _category('p1', 'Boards 1-100', 0),
          _category('p2', 'Boards 101-200', 1),
        ],
        tourNamesById: const {
          'p1': 'Titled Tuesday - Boards 1-100',
          'p2': 'Titled Tuesday - Boards 101-200',
        },
      );

      expect(groups, hasLength(1));
      expect(groups.single.tourIds, ['p1', 'p2']);
      expect(groups.single.label, 'All boards');
    });

    test('pages of different tournaments stay apart', () {
      final groups = buildCombinedStandingsGroups(
        categories: [
          _category('open', 'Open | Boards 1-50', 0),
          _category('women', 'Women | Boards 1-50', 1),
        ],
        tourNamesById: const {
          'open': 'Championship | Open | Boards 1-50',
          'women': 'Championship | Women | Boards 1-50',
        },
      );

      expect([for (final group in groups) group.label], ['Open', 'Women']);
    });

    test('an organizer copy of the other categories is left out', () {
      final groups = buildCombinedStandingsGroups(
        categories: [
          _category('a', 'Group A', 0),
          _category('all', 'Everyone', 1),
          _category('b', 'Group B', 2),
        ],
        tourNamesById: const {
          'a': 'E | Group A',
          'all': 'E',
          'b': 'E | Group B',
        },
        mirrorTourIds: const {'all'},
      );

      expect([for (final group in groups) group.id], ['a', 'b']);
    });

    test('a team category is marked, the others are not', () {
      final groups = buildCombinedStandingsGroups(
        categories: [_category('open', 'Open', 0), _category('u8', 'U8', 1)],
        tourNamesById: const {'open': 'Olympiad | Open', 'u8': 'Olympiad | U8'},
        teamTourIds: const {'open'},
      );

      expect(groups.first.isTeam, isTrue);
      expect(groups.last.isTeam, isFalse);
    });

    test('the selected page leads its table', () {
      const group = CombinedStandingsGroup(
        tourIds: ['p1', 'p2'],
        label: 'Open',
        isTeam: false,
      );

      expect(group.tourIdFor('p2'), 'p2');
      expect(group.tourIdFor('other'), 'p1');
      expect(group.tourIdFor(null), 'p1');
    });
  });

  group('standingsToursFor', () {
    TourModel tour(String id, String name) => TourModel(
      tour: Tour.virtual(
        id: id,
        name: name,
        slug: id,
        dates: const [],
        players: const [],
      ),
      roundStatus: RoundStatus.ongoing,
    );
    final tours = [
      tour('open-1', 'Championship | Open | Boards 1-50'),
      tour('open-2', 'Championship | Open | Boards 51-100'),
      tour('women-1', 'Championship | Women | Boards 1-50'),
      tour('blitz', 'Championship | Blitz'),
    ];

    test('a page resolves to every page of its own tournament', () {
      final related = standingsToursFor(
        tours,
        tourId: 'open-2',
        tourName: 'Championship | Open | Boards 51-100',
      );
      expect([for (final t in related) t.tour.id], ['open-1', 'open-2']);
    });

    test('a category of its own resolves to itself', () {
      final related = standingsToursFor(
        tours,
        tourId: 'blitz',
        tourName: 'Championship | Blitz',
      );
      expect([for (final t in related) t.tour.id], ['blitz']);
    });

    test('what counts as a page', () {
      expect(isBoardPaginationCategory('Open | Boards 1-50'), isTrue);
      expect(isBoardPaginationCategory('Open | Boards 252+'), isTrue);
      expect(isBoardPaginationCategory('Group Stage | A'), isFalse);
      expect(boardPaginationBaseName('Open | Boards 1-50'), 'Open |');
    });
  });

  group('CombinedStandingsScreen', () {
    testWidgets('every category gets its own table under its own header', (
      tester,
    ) async {
      await _pump(
        tester,
        _state([
          _section('a', 'Group A', players: 3, selected: true),
          _section('b', 'Group B', players: 3),
        ]),
      );

      expect(_header('Group A'), findsOneWidget);
      expect(_header('Group B'), findsOneWidget);
      // Each table is ranked on its own: both start at 1.
      expect(find.text('Group A Player 1', findRichText: true), findsOneWidget);
      expect(find.text('Group B Player 1', findRichText: true), findsOneWidget);
      expect(
        find.textContaining('3 players', findRichText: true),
        findsNWidgets(2),
      );
      await _drain(tester);
    });

    testWidgets('a team category shows teams, another one players', (
      tester,
    ) async {
      await _pump(
        tester,
        _state([
          _section('open', 'Open', teams: 2),
          _section('u8', 'U8', players: 2),
        ]),
      );

      expect(find.byType(TeamStandingRow), findsNWidgets(2));
      expect(find.byType(StandingsPlayerRow), findsNWidgets(2));
      expect(
        find.textContaining('2 teams', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('2 players', findRichText: true),
        findsOneWidget,
      );
      await _drain(tester);
    });

    testWidgets('a row of another category names it, the selected one not', (
      tester,
    ) async {
      await _pump(
        tester,
        _state([
          _section('a', 'Group A', players: 1, selected: true),
          _section('b', 'Group B', players: 1),
        ]),
      );

      String? scopeOf(String player) => StandingsCategoryScope.tourIdOf(
        tester.element(find.text(player, findRichText: true)),
      );
      expect(scopeOf('Group A Player 1'), isNull);
      expect(scopeOf('Group B Player 1'), 'b');
      await _drain(tester);
    });

    testWidgets('the header of the table being read stays on top, then '
        'hands over to the next category', (tester) async {
      await _pump(
        tester,
        _state([
          _section('a', 'Group A', players: 30, selected: true),
          _section('b', 'Group B', players: 30),
        ]),
      );
      final top = _listTop(tester);

      // Deep inside Group A's table its header is still at the top.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pump();
      expect(tester.getTopLeft(_header('Group A')).dy, closeTo(top, 8));
      expect(find.text('Group A Player 1', findRichText: true), findsNothing);

      // Past the end of Group A, Group B's header holds the top instead.
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ),
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
      expect(tester.getTopLeft(_header('Group B')).dy, closeTo(top, 8));
      expect(_header('Group A').hitTestable(), findsNothing);
      await _drain(tester);
    });

    testWidgets('folding the table being read brings the next category up', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        _state([
          _section('a', 'Group A', players: 30, selected: true),
          _section('b', 'Group B', players: 30),
        ]),
      );
      final top = _listTop(tester);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pump();
      await tester.tap(_header('Group A'));
      await tester.pump();

      expect(container.read(combinedStandingsCollapsedProvider), {'a'});
      // Group A's rows are gone, its header stays, and Group B follows it
      // directly instead of the list landing somewhere inside Group B.
      expect(
        find.textContaining('Group A Player', findRichText: true),
        findsNothing,
      );
      expect(tester.getTopLeft(_header('Group A')).dy, closeTo(top, 8));
      expect(
        find.text('Group B Player 1', findRichText: true).hitTestable(),
        findsOneWidget,
      );

      // Tapping again opens it.
      await tester.tap(_header('Group A'));
      await tester.pump();
      expect(container.read(combinedStandingsCollapsedProvider), isEmpty);
      expect(find.text('Group A Player 1', findRichText: true), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('a single table has no header', (tester) async {
      await _pump(
        tester,
        _state([_section('p1', 'All boards', players: 4, selected: true)]),
      );

      expect(find.byType(TournamentRoundHeader), findsNothing);
      expect(find.byType(StandingsPlayerRow), findsNWidgets(4));
      await _drain(tester);
    });

    testWidgets('a search opens folded tables, counts its hits, and leaves '
        'the folds as they were', (tester) async {
      final unfiltered = _state([
        _section('a', 'Group A', players: 6, selected: true),
        _section('b', 'Group B', players: 6),
      ]);
      final container = await _pump(tester, unfiltered);
      final standings =
          container.read(
                combinedStandingsProvider(
                  CombinedStandingsView.standings,
                ).notifier,
              )
              as _FixedStandings;

      await tester.tap(_header('Group A'));
      await tester.pump();
      expect(
        find.textContaining('Group A Player', findRichText: true),
        findsNothing,
      );

      // The reader searches: the folded table opens on its hit.
      standings.show(
        CombinedStandingsState(
          isLoading: false,
          query: 'player 1',
          // Group B has no hit, but it is still a table of this event.
          tableCount: 2,
          sections: [
            CombinedStandingsSection(
              group: const CombinedStandingsGroup(
                tourIds: ['a'],
                label: 'Group A',
                isTeam: false,
              ),
              tourId: 'a',
              isSelectedCategory: true,
              showsTeams: false,
              players: [_player('Group A Player 1', 1)],
              teams: const [],
              total: 6,
              officialRound: null,
              officialSections: const [],
              hasError: false,
            ),
          ],
        ),
      );
      await tester.pump();
      expect(find.text('Group A Player 1', findRichText: true), findsOneWidget);
      expect(find.textContaining('1 of 6', findRichText: true), findsOneWidget);
      // Nothing to fold while every hit is shown: the header takes no tap.
      await tester.tap(_header('Group A'));
      await tester.pump();
      expect(find.text('Group A Player 1', findRichText: true), findsOneWidget);

      // Search cleared: Group A is folded again, as the reader left it.
      standings.show(unfiltered);
      await tester.pump();
      expect(container.read(combinedStandingsCollapsedProvider), {'a'});
      expect(
        find.textContaining('Group A Player', findRichText: true),
        findsNothing,
      );
      expect(find.text('Group B Player 1', findRichText: true), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('a table that failed says so under its header', (tester) async {
      await _pump(
        tester,
        _state([
          _section('a', 'Group A', players: 2, selected: true),
          _section('b', 'Group B', hasError: true),
        ]),
      );

      expect(_header('Group B'), findsOneWidget);
      expect(
        find.textContaining("Couldn't load these standings"),
        findsOneWidget,
      );
      await _drain(tester);
    });

    testWidgets('nothing to rank reads as empty, not as loading', (
      tester,
    ) async {
      await _pump(tester, _state(const []));
      expect(find.text('No data available'), findsOneWidget);

      await _pump(tester, _state(const [], query: 'zzz'));
      expect(
        find.text('No players or teams found matching your search'),
        findsOneWidget,
      );
      await _drain(tester);
    });
  });
}
