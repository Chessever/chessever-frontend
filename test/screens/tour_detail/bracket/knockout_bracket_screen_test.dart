import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/bracket/models/knockout_bracket.dart';
import 'package:chessever2/screens/tour_detail/bracket/providers/knockout_bracket_provider.dart';
import 'package:chessever2/screens/tour_detail/bracket/views/knockout_bracket_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('malformed selected leg cannot resolve to a later valid game', () {
    final malformed = Games(
      id: 'malformed',
      roundId: 'round',
      roundSlug: 'round',
      tourId: 'tour',
      tourSlug: 'tour',
      players: const [],
      status: '*',
    );
    final valid = Games(
      id: 'valid',
      roundId: 'round',
      roundSlug: 'round',
      tourId: 'tour',
      tourSlug: 'tour',
      players: [_player('Alpha'), _player('Beta')],
      status: '1-0',
      lastMove: 'e2e4',
    );

    final malformedSelection = bracketNavigationSelection(
      games: [malformed, valid],
      selectedGameId: malformed.id,
    );
    expect(malformedSelection.games.map((game) => game.gameId), ['valid']);
    expect(malformedSelection.selectedIndex, -1);

    final validSelection = bracketNavigationSelection(
      games: [malformed, valid],
      selectedGameId: valid.id,
    );
    expect(validSelection.selectedIndex, 0);
  });

  testWidgets('shows loading, empty, and error states', (tester) async {
    await _pump(tester, const AsyncValue<KnockoutBracket>.loading());
    expect(
      find.byKey(const ValueKey('knockout-bracket-loading')),
      findsOneWidget,
    );

    await _pump(tester, AsyncValue.data(_emptyBracket()));
    expect(
      find.byKey(const ValueKey('knockout-bracket-empty')),
      findsOneWidget,
    );

    await _pump(
      tester,
      AsyncValue<KnockoutBracket>.error(Exception('network'), StackTrace.empty),
    );
    expect(
      find.byKey(const ValueKey('knockout-bracket-error')),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('loading skeleton clips cleanly on a short portrait viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pump(tester, const AsyncValue<KnockoutBracket>.loading());
    await tester.pump();

    expect(
      find.byKey(const ValueKey('knockout-bracket-loading')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders portrait graph controls, partial note, and leg sheet', (
    tester,
  ) async {
    await _pump(tester, AsyncValue.data(_populatedBracket()));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('knockout-bracket-viewer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('knockout-bracket-canvas')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bracket-camera-controls')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('bracket-zoom-out')), findsOneWidget);
    expect(find.byKey(const ValueKey('bracket-fit-reset')), findsOneWidget);
    expect(find.byKey(const ValueKey('bracket-zoom-in')), findsOneWidget);
    expect(find.byKey(const ValueKey('bracket-gesture-hint')), findsOneWidget);
    expect(find.byKey(const ValueKey('bracket-partial-note')), findsOneWidget);
    expect(find.text('Finals'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bracket-match-final-match')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('knockout-match-sheet')), findsOneWidget);
    expect(find.text('Match details'), findsOneWidget);
    expect(find.text('Game 1'), findsOneWidget);
    expect(find.text('1-0'), findsOneWidget);
    expect(find.byKey(const ValueKey('bracket-leg-game-1')), findsOneWidget);
  });

  testWidgets('fit control switches to current-round focus action', (
    tester,
  ) async {
    await _pump(tester, AsyncValue.data(_populatedBracket()));
    await tester.pump();

    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const ValueKey('knockout-bracket-viewer')),
    );
    expect(viewer.panAxis, PanAxis.free);
    expect(viewer.panEnabled, isTrue);
    expect(viewer.scaleEnabled, isTrue);
    expect(viewer.minScale, lessThanOrEqualTo(0.04));

    await tester.tap(find.byKey(const ValueKey('bracket-fit-reset')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.center_focus_strong_rounded), findsOneWidget);
  });

  testWidgets('keeps camera controls above the bottom system inset', (
    tester,
  ) async {
    const bottomInset = 34.0;
    await _pump(
      tester,
      AsyncValue.data(_populatedBracket()),
      bottomViewPadding: bottomInset,
    );
    await tester.pump();

    final scaffoldBottom = tester.getBottomRight(find.byType(Scaffold)).dy;
    final controlsBottom =
        tester
            .getBottomRight(
              find.byKey(const ValueKey('bracket-camera-controls')),
            )
            .dy;
    expect(
      controlsBottom,
      lessThanOrEqualTo(scaffoldBottom - bottomInset - 16),
    );
  });

  testWidgets('does not label an in-progress but non-live stage as live', (
    tester,
  ) async {
    await _pump(
      tester,
      AsyncValue.data(
        _populatedBracket(stageState: KnockoutStageState.inProgress),
      ),
    );
    await tester.pump();

    expect(find.text('LIVE'), findsNothing);
  });

  testWidgets('leg sheet shares forfeit and PGN-fallback result parsing', (
    tester,
  ) async {
    await _pump(tester, AsyncValue.data(_populatedBracket(gameStatus: '+:-')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bracket-match-final-match')));
    await tester.pumpAndSettle();
    expect(find.text('1-0'), findsOneWidget);

    await _pump(
      tester,
      AsyncValue.data(
        _populatedBracket(
          gameStatus: '*',
          gamePgn: '[Result "0-1"]\n\n1. e4 e5 0-1',
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bracket-match-final-match')));
    await tester.pumpAndSettle();
    expect(find.text('0-1'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);

    await _pump(
      tester,
      AsyncValue.data(_populatedBracket(gameStatus: '*', gamePgn: null)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bracket-match-final-match')));
    await tester.pumpAndSettle();
    expect(find.text('—'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);
  });

  testWidgets('proven winner styling mutes a provisional aggregate leader', (
    tester,
  ) async {
    await _pump(
      tester,
      AsyncValue.data(_populatedBracket(leaderDiffersFromWinner: true)),
    );
    await tester.pump();

    final colors = tester.element(find.byType(KnockoutBracketScreen)).colors;
    Text leaderScore() => tester.widget<Text>(find.text('1').first);
    expect(leaderScore().style?.color, colors.textTertiary);

    await tester.tap(find.byKey(const ValueKey('bracket-match-final-match')));
    await tester.pumpAndSettle();
    final sheetLeaderScore = find.descendant(
      of: find.byKey(const ValueKey('knockout-match-sheet')),
      matching: find.text('1'),
    );
    final aggregateLeaderScore = tester
        .widgetList<Text>(sheetLeaderScore)
        .singleWhere((text) => text.style?.fontSize == 19);
    expect(aggregateLeaderScore.style?.color, colors.textTertiary);
  });
}

Future<void> _pump(
  WidgetTester tester,
  AsyncValue<KnockoutBracket> state, {
  double bottomViewPadding = 0,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [knockoutBracketProvider.overrideWithValue(state)],
      child: MaterialApp(
        key: UniqueKey(),
        theme: AppTheme.darkTheme,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                viewPadding: EdgeInsets.only(bottom: bottomViewPadding),
              ),
              child: child!,
            ),
        home: const Scaffold(body: KnockoutBracketScreen()),
      ),
    ),
  );
}

KnockoutBracket _emptyBracket() => KnockoutBracket(
  stages: const [],
  edges: const [],
  selectedStageKey: null,
  currentStageKey: null,
  isPartial: true,
);

KnockoutBracket _populatedBracket({
  KnockoutStageState stageState = KnockoutStageState.completed,
  String? gameStatus,
  String? gamePgn,
  bool leaderDiffersFromWinner = false,
}) {
  const alpha = BracketParticipant(
    id: 'alpha',
    name: 'Alpha',
    title: 'GM',
    rating: 2700,
  );
  const beta = BracketParticipant(
    id: 'beta',
    name: 'Beta',
    title: 'GM',
    rating: 2680,
  );
  final game = Games(
    id: 'game-1',
    roundId: 'final-round',
    roundSlug: 'game-1',
    tourId: 'final-tour',
    tourSlug: 'final-tour',
    players: [_player('Alpha'), _player('Beta')],
    status: gameStatus ?? (leaderDiffersFromWinner ? '0-1' : '1-0'),
    pgn: gamePgn,
    lastMove: 'e2e4',
  );
  final match = KnockoutMatch(
    key: 'final-match',
    stageKey: 'finals',
    participant1: alpha,
    participant2: beta,
    games: [game],
    participant1Score: leaderDiffersFromWinner ? 0 : 1,
    participant2Score: leaderDiffersFromWinner ? 1 : 0,
    leader: leaderDiffersFromWinner ? beta : alpha,
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
        state: stageState,
        isLive: false,
        matches: [match],
      ),
    ],
    edges: const [],
    selectedStageKey: 'finals',
    currentStageKey: 'finals',
    isPartial: true,
  );
}

Player _player(String name) => Player(
  name: name,
  title: 'GM',
  rating: 2700,
  fideId: 0,
  fed: '',
  clock: 0,
  team: '',
);
