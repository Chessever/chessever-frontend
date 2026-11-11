// Duo audit for the Events area: knockout bracket + match sheet, standings
// rows (scorecard, team table, official section picker), the players list
// row, Starred Smart Events, and the countrymen ranking tab. Event cards, the
// events list and event search are already covered by
// duo_event_card_layout_test.dart and duo_content_matrix_test.dart.
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_players_tab.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/group_event/smart_event/starred_smart_events_screen.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/players/widgets/player_card.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/player_standing_section_select.dart';
import 'package:chessever2/screens/standings/player_standing_sections_provider.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/standings/widget/scoreboard_card_widget.dart';
import 'package:chessever2/screens/tour_detail/bracket/models/knockout_bracket.dart';
import 'package:chessever2/screens/tour_detail/bracket/providers/knockout_bracket_provider.dart';
import 'package:chessever2/screens/tour_detail/bracket/views/knockout_bracket_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/adaptive_window.dart';
import 'package:chessever2/widgets/event_card/smart_event_star.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/widgets/figma_team_card.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'fixtures/duo_window_matrix.dart';
import 'helpers/saved_smart_event_fakes.dart';

const _scales = [1.0, 1.3];

/// Folded <-> unfolded only: the transitions a hinge actually produces.
Iterable<DuoWindowTransition> get _hingeTransitions =>
    duoWindowTransitions.where((t) => t.from.unfolded != t.to.unfolded);

Future<void> _host(
  WidgetTester tester,
  DuoWindowCase window,
  double scale,
  Widget home, {
  List<Override> overrides = const [],
}) async {
  tester.view.devicePixelRatio = 3;
  applyDuoWindow(tester, window);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (_, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
          child: AdaptiveWindowScope(child: child!),
        ),
        home: home,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _resize(WidgetTester tester, DuoWindowCase to) async {
  applyDuoWindow(tester, to, mirrorInsets: true);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  expect(finder.hitTestable(), findsWidgets);
  await tester.tap(finder.hitTestable().first);
  await tester.pump();
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

// ---------------------------------------------------------------------------
// Knockout bracket
// ---------------------------------------------------------------------------

Player _player(String name) => Player(
  name: name,
  title: 'GM',
  rating: 2700,
  fideId: 0,
  fed: 'NOR',
  clock: 0,
  team: '',
);

KnockoutBracket _bracket() {
  const alpha = BracketParticipant(
    id: 'alpha',
    name: 'Vachier-Lagrave, Maxime',
    title: 'GM',
    federation: 'FRA',
    rating: 2731,
  );
  const beta = BracketParticipant(
    id: 'beta',
    name: 'Nepomniachtchi, Ian',
    title: 'GM',
    federation: 'FID',
    rating: 2758,
  );
  final games = [
    for (var i = 1; i <= 4; i++)
      Games(
        id: 'game-$i',
        roundId: 'final-round',
        roundSlug: 'game-$i',
        tourId: 'final-tour',
        tourSlug: 'final-tour',
        players: [
          _player('Vachier-Lagrave, Maxime'),
          _player('Nepomniachtchi, Ian'),
        ],
        status: i.isOdd ? '1-0' : '1/2-1/2',
        lastMove: 'e2e4',
      ),
  ];
  final match = KnockoutMatch(
    key: 'final-match',
    stageKey: 'finals',
    participant1: alpha,
    participant2: beta,
    games: games,
    participant1Score: 3,
    participant2Score: 1,
    leader: alpha,
    winner: alpha,
    minimumBoardOrder: 1,
    isComplete: true,
    isLive: false,
  );
  return KnockoutBracket(
    stages: [
      KnockoutStage(
        key: 'finals',
        label: 'Finals',
        sourceTourIds: const ['final-tour'],
        sourceRoundIds: const ['final-round'],
        order: 0,
        state: KnockoutStageState.completed,
        isLive: false,
        matches: [match],
      ),
    ],
    edges: const [],
    selectedStageKey: 'finals',
    currentStageKey: 'finals',
    isPartial: false,
  );
}

Future<void> _pumpBracket(
  WidgetTester tester,
  DuoWindowCase window,
  double scale,
) => _host(
  tester,
  window,
  scale,
  const Scaffold(body: SafeArea(child: KnockoutBracketScreen())),
  overrides: [knockoutBracketProvider.overrideWithValue(AsyncData(_bracket()))],
);

Future<void> _openMatchSheet(WidgetTester tester) async {
  await _tapVisible(
    tester,
    find.byKey(const ValueKey('bracket-match-final-match')),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('knockout-match-sheet')), findsOneWidget);
}

// ---------------------------------------------------------------------------
// Standings rows
// ---------------------------------------------------------------------------

const _longNames = [
  'Vachier-Lagrave, Maxime',
  'Nepomniachtchi, Ian',
  'Abdusattorov, Nodirbek',
  'Praggnanandhaa, Rameshbabu',
  'Mamedyarov, Shakhriyar',
  'Gukesh, Dommaraju',
  'Wojtaszek, Radoslaw',
  'Aronian, Levon',
  'Firouzja, Alireza',
  'Karjakin, Sergey',
  'Grischuk, Alexander',
  'Duda, Jan-Krzysztof',
];

class _ScoreboardHost extends StatelessWidget {
  const _ScoreboardHost({required this.onPlayer, required this.onGame});

  final ValueChanged<int> onPlayer;
  final ValueChanged<int> onGame;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (i, name) in _longNames.indexed)
            ScoreboardCardWidget(
              countryCode: 'NOR',
              title: 'GM',
              name: name,
              score: 2700 + i,
              scoreChange: i.isEven ? -12 : 8,
              matchScore: i.isEven ? '1' : '½',
              isWhite: i.isEven,
              roundLabel: 'Round ${i + 1}',
              index: i,
              isFirst: i == 0,
              isLast: i == _longNames.length - 1,
              onPlayerTap: () => onPlayer(i),
              onTap: () => onGame(i),
            ),
        ],
      ),
    ),
  );
}

class _PlayersListHost extends StatelessWidget {
  const _PlayersListHost({required this.onFavorite});

  final ValueChanged<int> onFavorite;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        children: [
          for (final (i, name) in _longNames.indexed)
            PlayerCard(
              key: ValueKey('player-row-$i'),
              rank: i + 1,
              playerId: '$i',
              playerName: 'GM $name',
              countryCode: 'NOR',
              elo: 2790 - i,
              age: 0,
              onFavoriteToggle: () => onFavorite(i),
              index: i,
              isFirst: i == 0,
              isLast: i == _longNames.length - 1,
            ),
        ],
      ),
    ),
  );
}

TeamStandingModel _team(int i) => TeamStandingModel(
  teamName: [
    'Uzbekistan',
    'United States of America',
    'Bosnia and Herzegovina',
    'Netherlands',
    'Trinidad and Tobago',
    'India',
  ][i],
  rank: i + 1,
  matchPoints: 20 - i,
  gamePoints: 30.5 - i,
  matchesWon: 9 - i,
  matchesDrawn: 2,
  matchesLost: i,
  boardsPlayed: 44,
  players: [
    for (final name in _longNames.take(4))
      PlayerStandingModel(
        countryCode: 'UZB',
        title: 'GM',
        name: name,
        score: 2700,
        scoreChange: 0,
        matchScore: '7/9',
      ),
  ],
);

class _TeamTableHost extends StatefulWidget {
  const _TeamTableHost({required this.onTeam});

  final ValueChanged<int> onTeam;

  @override
  State<_TeamTableHost> createState() => _TeamTableHostState();
}

class _TeamTableHostState extends State<_TeamTableHost> {
  final expanded = <int>{};

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (var i = 0; i < 6; i++)
            FigmaTeamCard(
              key: ValueKey('team-$i'),
              team: _team(i),
              rank: i + 1,
              isExpanded: expanded.contains(i),
              onToggle: () => setState(
                () =>
                    expanded.contains(i) ? expanded.remove(i) : expanded.add(i),
              ),
              onTeamTap: () => widget.onTeam(i),
              expandedChildren: [
                for (final p in _team(i).players)
                  ListTile(title: Text('Board: ${p.name}')),
              ],
            ),
        ],
      ),
    ),
  );
}

final _sections = [
  OfficialPlayerSection(
    id: '100',
    name: 'Open U19 (Boys) Championship Section',
    sourceUrl: 'https://chess-results.com/tnr100.aspx',
    players: [TournamentPlayer(name: 'Player A', played: 4)],
  ),
  OfficialPlayerSection(
    id: '101',
    name: 'Open U17 (Girls) Championship Section',
    sourceUrl: 'https://chess-results.com/tnr101.aspx',
    players: [TournamentPlayer(name: 'Player B', played: 4)],
  ),
];

class _SectionHost extends StatelessWidget {
  const _SectionHost();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            PlayerStandingSectionSelect(tourId: 'tour', sections: _sections),
            Consumer(
              builder: (context, ref, _) => Text(
                'selected:${ref.watch(selectedPlayerStandingSectionProvider('tour')) ?? 'none'}',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Starred Smart Events + countrymen fakes
// ---------------------------------------------------------------------------

class _StarredFavorites extends FavoriteEventsNotifier {
  _StarredFavorites(this.rows);
  final List<FavoriteEvent> rows;
  int refreshes = 0;

  @override
  Future<List<FavoriteEvent>> build() async => rows;

  @override
  Future<List<FavoriteEvent>> readForSmartEventEdit() async {
    refreshes++;
    state = AsyncData(rows);
    return rows;
  }
}

class _NoPins extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

class _NoFavoritePlayers extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => const [];
}

List<Override> _countrymenOverrides() => [
  effectiveCountryProvider.overrideWith(
    (ref) => AsyncValue.data(CountryService().findByCode('NO')!),
  ),
  countryRankingsFetcherProvider.overrideWithValue(({
    required countryCode,
    required filters,
    required searchQuery,
    required limit,
    required offset,
  }) async {
    if (offset > 0) return const <ChessPlayer>[];
    return [
      for (var i = 0; i < 30; i++)
        ChessPlayer(
          fideid: 1503000 + i,
          name: _longNames[i % _longNames.length],
          title: 'GM',
          rating: 2800 - i,
          rapidRating: 2700,
          blitzRating: 2650,
          country: 'NOR',
        ),
    ];
  }),
  favoritePlayersProviderNew.overrideWith(_NoFavoritePlayers.new),
  playerPhotoProvider.overrideWith((ref, id) async => null),
];

const _countrymenHome = Scaffold(body: SafeArea(child: CountrymenPlayersTab()));

void main() {
  // The stock test font draws every glyph a full em wide, which overflows
  // rows that fit with the real face. Measure with the shipped Inter.
  setUpAll(() async {
    final inter = FontLoader('InterDisplay');
    for (final weight in const ['Regular', 'Medium', 'Bold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$weight.otf'));
    }
    await inter.load();
  });

  for (final window in duoWindowCases) {
    for (final scale in _scales) {
      final label = '${window.name} at ${scale}x text';

      testWidgets('knockout bracket: canvas, controls and match sheet fit '
          '$label', (tester) async {
        await _pumpBracket(tester, window, scale);
        expect(tester.takeException(), isNull);
        for (final key in [
          'bracket-zoom-out',
          'bracket-fit-reset',
          'bracket-zoom-in',
        ]) {
          expect(
            find.byKey(ValueKey(key)).hitTestable(),
            findsOneWidget,
            reason: key,
          );
        }
        await _openMatchSheet(tester);
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('Close').hitTestable(), findsOneWidget);
        // The last leg must be reachable inside the sheet.
        await tester.scrollUntilVisible(
          find.text('Game 4'),
          60,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('knockout-match-sheet')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pump();
        expect(find.text('Game 4').hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('knockout-match-sheet')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('standings scorecard rows fit and split taps $label', (
        tester,
      ) async {
        final players = <int>[];
        final games = <int>[];
        await _host(
          tester,
          window,
          scale,
          _ScoreboardHost(onPlayer: players.add, onGame: games.add),
        );
        expect(tester.takeException(), isNull);
        final name = find.byWidgetPredicate(
          (w) =>
              w is RichText && w.text.toPlainText() == 'GM ${_longNames.first}',
        );
        await _tapVisible(tester, name);
        expect(players, [0]);
        await _tapVisible(tester, find.text('2700'));
        expect(games, [0]);
        await _tapVisible(tester, find.text('2711'));
        expect(games, [0, 11]);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('players list rows fit and favorite toggles $label', (
        tester,
      ) async {
        final toggles = <int>[];
        await _host(
          tester,
          window,
          scale,
          _PlayersListHost(onFavorite: toggles.add),
        );
        expect(tester.takeException(), isNull);
        final heart = find.descendant(
          of: find.byKey(const ValueKey('player-row-0')),
          matching: find.bySemanticsLabel('Favorite Icon'),
        );
        await _tapVisible(tester, heart);
        await tester.pump(const Duration(milliseconds: 500));
        expect(toggles, [0]);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('team standings table fits, expands and opens $label', (
        tester,
      ) async {
        final opened = <int>[];
        await _host(tester, window, scale, _TeamTableHost(onTeam: opened.add));
        expect(tester.takeException(), isNull);
        await _tapVisible(tester, find.text('United States of America'));
        expect(opened, [1]);
        final chevron = find.descendant(
          of: find.byKey(const ValueKey('team-1')),
          matching: find.byIcon(Icons.keyboard_arrow_down),
        );
        await _tapVisible(tester, chevron);
        await tester.pumpAndSettle();
        expect(find.text('Board: ${_longNames.first}'), findsWidgets);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('official section picker opens and selects $label', (
        tester,
      ) async {
        await _host(tester, window, scale, const _SectionHost());
        expect(tester.takeException(), isNull);
        await _tapVisible(tester, find.text(_sections.first.name));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(_sections.last.name).hitTestable().last);
        await tester.pumpAndSettle();
        expect(find.text('selected:101'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('starred smart events list and actions fit $label', (
        tester,
      ) async {
        final request = fixtureRequest();
        final favorites = _StarredFavorites([
          fixtureFavorite(
            request,
            name: 'Grandmaster classical games over 2700 average rating',
          ),
        ]);
        await _host(
          tester,
          window,
          scale,
          const StarredSmartEventsScreen(),
          overrides: [
            favoriteEventsProvider.overrideWith(() => favorites),
            spaceShortcutsProvider.overrideWith(_NoPins.new),
          ],
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(SmartEventStar).hitTestable(), findsOneWidget);
        await tester.ensureVisible(find.textContaining('to My Space'));
        await tester.pump();
        expect(
          find.textContaining('to My Space').hitTestable(),
          findsOneWidget,
        );
        await _tapVisible(tester, find.byTooltip('Refresh subscriptions'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(favorites.refreshes, 1);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets(
        'countrymen ranking tab fits and hearts are hittable $label',
        (tester) async {
          await _host(
            tester,
            window,
            scale,
            _countrymenHome,
            overrides: _countrymenOverrides(),
          );
          await tester.pump(const Duration(milliseconds: 500));
          expect(tester.takeException(), isNull);
          expect(find.byType(FigmaPlayerCard), findsWidgets);
          expect(
            find.bySemanticsLabel('Add to favorites').hitTestable(),
            findsWidgets,
          );
          expect(tester.takeException(), isNull);
          await _teardown(tester);
        },
      );
    }
  }

  for (final t in _hingeTransitions) {
    final label = '${t.from.name} to ${t.to.name}';

    testWidgets('knockout match sheet survives $label', (tester) async {
      await _pumpBracket(tester, t.from, 1.3);
      await _openMatchSheet(tester);
      await _resize(tester, t.to);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('knockout-match-sheet')),
        findsOneWidget,
      );
      expect(find.byTooltip('Close').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('knockout-match-sheet')), findsNothing);
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    });

    testWidgets('team table keeps expanded rows $label', (tester) async {
      await _host(tester, t.from, 1.3, _TeamTableHost(onTeam: (_) {}));
      final chevron = find.descendant(
        of: find.byKey(const ValueKey('team-0')),
        matching: find.byIcon(Icons.keyboard_arrow_down),
      );
      await _tapVisible(tester, chevron);
      await tester.pumpAndSettle();
      final state = tester.state<_TeamTableHostState>(
        find.byType(_TeamTableHost),
      );
      await _resize(tester, t.to);
      expect(tester.takeException(), isNull);
      expect(
        tester.state<_TeamTableHostState>(find.byType(_TeamTableHost)),
        same(state),
      );
      expect(state.expanded, {0});
      expect(find.text('Board: ${_longNames.first}'), findsWidgets);
      await _teardown(tester);
    });

    testWidgets('official section choice survives $label', (tester) async {
      await _host(tester, t.from, 1.3, const _SectionHost());
      await _tapVisible(tester, find.text(_sections.first.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_sections.last.name).hitTestable().last);
      await tester.pumpAndSettle();
      await _resize(tester, t.to);
      expect(tester.takeException(), isNull);
      expect(find.text('selected:101'), findsOneWidget);
      expect(find.text(_sections.last.name).hitTestable(), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('players list keeps a toggled favorite $label', (tester) async {
      await _host(tester, t.from, 1.3, _PlayersListHost(onFavorite: (_) {}));
      final heart = find.descendant(
        of: find.byKey(const ValueKey('player-row-2')),
        matching: find.bySemanticsLabel('Favorite Icon'),
      );
      await _tapVisible(tester, heart);
      await tester.pump(const Duration(milliseconds: 500));
      final before = tester.element(find.byKey(const ValueKey('player-row-2')));
      await _resize(tester, t.to);
      expect(tester.takeException(), isNull);
      expect(before.mounted, isTrue);
      expect(
        tester.element(find.byKey(const ValueKey('player-row-2'))),
        same(before),
      );
      await _teardown(tester);
    });

    testWidgets('countrymen ranking keeps scroll position $label', (
      tester,
    ) async {
      await _host(
        tester,
        t.from,
        1.3,
        _countrymenHome,
        overrides: _countrymenOverrides(),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final scrollable = find
          .descendant(
            of: find.byType(CountrymenPlayersTab),
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(position.maxScrollExtent * 0.4);
      await tester.pump();
      final offset = position.pixels;
      expect(offset, greaterThan(0));
      final before = tester.element(scrollable);
      await _resize(tester, t.to);
      expect(before.mounted, isTrue);
      expect(tester.takeException(), isNull);
      final after = tester.state<ScrollableState>(scrollable).position;
      expect(after.pixels, greaterThan(0));
      expect(
        find.bySemanticsLabel('Add to favorites').hitTestable(),
        findsWidgets,
      );
      await _teardown(tester);
    });
  }
}
