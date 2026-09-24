import 'dart:async';

import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/providers/streak_providers.dart';
import 'package:chessever2/screens/streaks/streak_player_screen.dart';
import 'package:chessever2/screens/streaks/widgets/player_run_strip.dart';
import 'package:chessever2/screens/streaks/widgets/player_streak_format.dart';
import 'package:chessever2/screens/streaks/widgets/streak_share_card.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Store double: in memory, never touches SQLite or Supabase.
class _FakeSpaceShortcuts extends SpaceShortcutsNotifier {
  List<SpaceShortcut> get _list => state.valueOrNull ?? const [];

  @override
  Future<List<SpaceShortcut>> build() async => const [];

  @override
  Future<bool> add(SpaceShortcut draft) async {
    if (_list.any((s) => s.key == draft.key)) return false;
    state = AsyncData([draft, ..._list]);
    return true;
  }

  @override
  Future<SpaceShortcut?> removeTarget(
    SpaceShortcutKind kind,
    String targetId,
  ) async {
    final key = SpaceShortcut.keyFor(kind, targetId);
    SpaceShortcut? hit;
    for (final s in _list) {
      if (s.key == key) hit = s;
    }
    state = AsyncData([
      for (final s in _list)
        if (s.key != key) s,
    ]);
    return hit;
  }
}

Map<String, dynamic> _game(
  String id,
  String result, {
  required String day,
  String? round,
  String? opponent,
  String? title,
  int? rating,
  int streakAfter = 0,
}) => {
  'game_id': id,
  'result': result,
  'game_day': day,
  'round_name': ?round,
  'tour_name': 'Olympiad 2026',
  'opponent_name': opponent ?? 'Rival, Some',
  'opponent_title': ?title,
  'opponent_rating': ?rating,
  'streak_after': streakAfter,
};

/// Ding Liren: 6 classical wins in a row after a loss, 2 in rapid, cold in
/// blitz with a best of 12.
PlayerStreaks _ding({int classicalWins = 6}) {
  final classical = <Map<String, dynamic>>[
    _game('c-old1', 'win', day: '2026-08-01', round: 'Round 3'),
    _game('c-old2', 'loss', day: '2026-08-02', round: 'Round 4'),
    _game('c-loss', 'loss', day: '2026-09-12', round: 'Round 9'),
    for (var i = 1; i <= classicalWins; i++)
      _game(
        'c-w$i',
        'win',
        day: '2026-09-${(12 + i).toString().padLeft(2, '0')}',
        round: 'Round $i',
        opponent: i == 3 ? 'Wei, Yi' : 'Rival, Some',
        title: 'GM',
        rating: 2600 + i * 10,
        streakAfter: i,
      ),
  ];
  return PlayerStreaks.fromJson(
    {
      'fide_id': 8603677,
      'name': 'Ding, Liren',
      'title': 'GM',
      'fed': 'CHN',
      'birth_year': 1992,
      'rating': 2733,
      'rapid_rating': 2740,
      'blitz_rating': 2720,
    },
    [
      {
        'time_class': 'standard',
        'current_streak': classicalWins,
        'best_streak': 9,
        'best_streak_at': '2025-03-10T12:00:00Z',
        'streak_start_game_day': '2026-09-13',
        'run_opp_avg': 2654,
        'run_opp_best': 2754,
        'run_opp_best_name': 'Wei, Yi',
        'run_opp_best_title': 'GM',
        'games': classical,
      },
      {
        'time_class': 'rapid',
        'current_streak': 2,
        'best_streak': 7,
        'streak_start_game_day': '2026-09-20',
        'games': [
          _game('r-loss', 'loss', day: '2026-09-19', round: 'Round 2'),
          _game('r-w1', 'win', day: '2026-09-20', round: 'Round 3'),
          _game('r-w2', 'win', day: '2026-09-20', round: 'Round 4'),
        ],
      },
      {
        'time_class': 'blitz',
        'current_streak': 0,
        'best_streak': 12,
        'games': [
          _game('b-w1', 'win', day: '2026-09-01', round: 'Round 1'),
          _game('b-loss', 'loss', day: '2026-09-01', round: 'Round 2'),
        ],
      },
    ],
  )!;
}

Future<List<String>> _pump(
  WidgetTester tester, {
  required FutureOr<PlayerStreaks?> Function() load,
  StreakTimeClass? initialClass,
  String? fallbackName,
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final opened = <String>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerStreaksProvider.overrideWith((ref, id) => load()),
        spaceShortcutsProvider.overrideWith(_FakeSpaceShortcuts.new),
        playerPhotoProvider.overrideWith((ref, fideId) async => null),
        streakOpenGameProvider.overrideWithValue((id) async {
          opened.add(id);
          return true;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return StreakPlayerScreen(
              fideId: 8603677,
              initialClass: initialClass,
              fallbackName: fallbackName,
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  return opened;
}

String _count(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('streak-player-count')))
    .textSpan!
    .toPlainText()
    .replaceAll('\uFFFC', '');

Color? _squareColor(WidgetTester tester, String gameId) {
  final box = tester.widget<Container>(
    find
        .descendant(
          of: find.byKey(ValueKey('streak-run-$gameId')),
          matching: find.byType(Container),
        )
        .first,
  );
  return (box.decoration as BoxDecoration?)?.color;
}

/// [text] under the run square of [gameId] (the recent rows repeat the day).
Finder _squareLabel(String gameId, String text) => find.descendant(
  of: find.byKey(ValueKey('streak-run-$gameId')),
  matching: find.text(text),
);

/// Calendar-year age, as the model counts it (never a hard-coded year).
final int _age = DateTime.now().toUtc().year - 1992;

void main() {
  testWidgets('scoreboard shows every class with its live and best run', (
    tester,
  ) async {
    await _pump(tester, load: () => _ding());

    expect(find.text('Liren Ding'), findsOneWidget);
    expect(find.text('GM · 2733 · China · $_age y'), findsOneWidget);
    for (final label in ['Classical', 'Rapid', 'Blitz']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Best 9'), findsOneWidget);
    expect(find.text('Best 7'), findsOneWidget);
    expect(find.text('Best 12'), findsOneWidget);

    // Opens on the hottest class: classical, 6 in a row.
    expect(_count(tester), '6');
    expect(find.text('On fire'), findsOneWidget);
    expect(find.text('classical wins in a row'), findsOneWidget);
  });

  testWidgets('the run is the anchor loss then every win, each opening its '
      'game', (tester) async {
    final opened = await _pump(tester, load: () => _ding());

    expect(find.text('This run'), findsOneWidget);
    expect(find.text('since Sep 13'), findsOneWidget);
    // Loss plus six wins; older games are not part of the run.
    expect(find.byKey(const ValueKey('streak-run-c-loss')), findsOneWidget);
    for (var i = 1; i <= 6; i++) {
      expect(find.byKey(ValueKey('streak-run-c-w$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('streak-run-c-old1')), findsNothing);

    // Quiet tones, not fire: a plain tile for the loss, a low win tint, the
    // latest win one step deeper.
    const c = AppColors.dark;
    expect(_squareColor(tester, 'c-loss'), c.surface);
    expect(
      _squareColor(tester, 'c-w1'),
      Color.alphaBlend(c.success.withValues(alpha: 0.14), c.surface),
    );
    expect(
      _squareColor(tester, 'c-w6'),
      Color.alphaBlend(c.success.withValues(alpha: 0.26), c.surface),
    );
    for (final id in ['c-loss', 'c-w1', 'c-w6']) {
      expect([
        StreakFire.loss,
        StreakFire.outer,
        StreakFire.light,
      ], isNot(contains(_squareColor(tester, id))));
    }

    // The day it was played sits under each square, never the round.
    expect(_squareLabel('c-loss', 'Sep 12'), findsOneWidget);
    expect(_squareLabel('c-w1', 'Sep 13'), findsOneWidget);
    expect(_squareLabel('c-w6', 'Sep 18'), findsOneWidget);
    expect(find.text('R1'), findsNothing);
    expect(find.text('R6'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('streak-run-c-w3')));
    await tester.pump();
    expect(opened, ['c-w3']);

    // The strongest win and the averages below the run.
    expect(find.text('Strongest win'), findsOneWidget);
    expect(find.text('2654'), findsOneWidget);
    expect(find.text('9 · Mar 2025'), findsOneWidget);
  });

  testWidgets('tapping a class card switches the whole card', (tester) async {
    await _pump(tester, load: () => _ding());

    await tester.tap(find.byKey(const ValueKey('streak-class-rapid')));
    await tester.pump();
    expect(_count(tester), '2');
    expect(find.text('rapid wins in a row'), findsOneWidget);
    expect(find.byKey(const ValueKey('streak-run-r-loss')), findsOneWidget);
    expect(find.byKey(const ValueKey('streak-run-c-loss')), findsNothing);
    expect(find.text('GM · 2740 · China · $_age y'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('streak-class-blitz')));
    await tester.pump();
    expect(_count(tester), '0');
    expect(find.text('No live run'), findsOneWidget);
    expect(find.text('Best ever 12 blitz wins in a row'), findsOneWidget);
    // No live run: the section shows where the count restarted.
    expect(find.text('Where it restarted'), findsOneWidget);
    expect(find.text('Strongest win'), findsNothing);
  });

  testWidgets('opens on the class it was linked with', (tester) async {
    await _pump(
      tester,
      load: () => _ding(),
      initialClass: StreakTimeClass.rapid,
    );
    expect(_count(tester), '2');
    expect(find.text('rapid wins in a row'), findsOneWidget);
  });

  testWidgets('a long run folds behind +N and expands on tap', (tester) async {
    await _pump(tester, load: () => _ding(classicalWins: 20));

    expect(find.byKey(const ValueKey('streak-run-fold')), findsOneWidget);
    expect(find.text('+6'), findsOneWidget);
    expect(find.byKey(const ValueKey('streak-run-c-loss')), findsOneWidget);
    expect(find.byKey(const ValueKey('streak-run-c-w6')), findsNothing);
    expect(find.byKey(const ValueKey('streak-run-c-w7')), findsOneWidget);
    expect(find.byKey(const ValueKey('streak-run-c-w20')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('streak-run-fold')));
    await tester.pump();
    expect(find.byKey(const ValueKey('streak-run-fold')), findsNothing);
    expect(find.byKey(const ValueKey('streak-run-c-w1')), findsOneWidget);
  });

  testWidgets('recent games list the latest ten decisive games', (
    tester,
  ) async {
    final opened = await _pump(tester, load: () => _ding(classicalWins: 12));
    expect(find.text('Recent games'), findsOneWidget);
    expect(find.byKey(const ValueKey('streak-recent-c-w12')), findsOneWidget);
    expect(find.byKey(const ValueKey('streak-recent-c-w3')), findsOneWidget);
    expect(find.byKey(const ValueKey('streak-recent-c-w2')), findsNothing);

    await tester.ensureVisible(
      find.byKey(const ValueKey('streak-recent-c-w12')),
    );
    await tester.tap(find.byKey(const ValueKey('streak-recent-c-w12')));
    await tester.pump();
    expect(opened, ['c-w12']);
  });

  testWidgets('Add to My Space pins a streak shortcut and flips its icon', (
    tester,
  ) async {
    await _pump(tester, load: () => _ding());
    final button = find.byKey(const ValueKey('streak-player-space'));
    expect(
      find.descendant(
        of: button,
        matching: find.byIcon(Icons.dashboard_customize_outlined),
      ),
      findsOneWidget,
    );

    await tester.tap(button);
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StreakPlayerScreen)),
    );
    final saved = container.read(spaceShortcutsProvider).valueOrNull!;
    expect(saved, hasLength(1));
    expect(saved.single.kind, SpaceShortcutKind.streak);
    expect(saved.single.targetId, '8603677');
    expect(saved.single.params['timeClass'], 'standard');
    expect(saved.single.params['playerName'], 'Ding, Liren');
    expect(
      find.descendant(
        of: button,
        matching: find.byIcon(Icons.dashboard_customize),
      ),
      findsOneWidget,
    );
    // Let the confirmation snack run out.
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('not found shows the fallback name and no streak data', (
    tester,
  ) async {
    await _pump(tester, load: () => null, fallbackName: 'Carlsen, Magnus');
    expect(find.text('Magnus Carlsen'), findsOneWidget);
    expect(find.text('No streak data yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('streak-player-share')), findsNothing);
  });

  testWidgets('loading keeps the fallback name on screen', (tester) async {
    final pending = Completer<PlayerStreaks?>();
    await _pump(
      tester,
      load: () => pending.future,
      fallbackName: 'Carlsen, Magnus',
    );
    expect(find.text('Magnus Carlsen'), findsOneWidget);
    expect(find.text('No streak data yet'), findsNothing);
    pending.complete(null);
    await tester.pump();
  });

  testWidgets('share card lays out at 360 x 640 without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Center(
              child: StreakShareCard(
                player: _ding(),
                timeClass: StreakTimeClass.standard,
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('in a row'), findsOneWidget);
    expect(find.text('Liren Ding'), findsOneWidget);
    expect(find.text('Classical wins over the board'), findsOneWidget);
    expect(find.text('streaks.chessever.com'), findsOneWidget);
    expect(
      streakShareUrl(8603677, StreakTimeClass.standard),
      'https://streaks.chessever.com/p/8603677?tc=standard',
    );
  });

  test('a run square is labelled with the day its game was played', () {
    StreakGame game({String? day, String? sortAt}) => StreakGame(
      gameId: 'g',
      result: 'win',
      gameDay: day,
      roundName: 'Round 13',
      sortAt: sortAt,
    );
    expect(streakSquareLabel(game(day: '2026-02-17')), 'Feb 17');
    // No year in a square, even for last season: the run head carries it.
    expect(streakSquareLabel(game(day: '2025-12-18')), 'Dec 18');
    // A game without a ledger day falls back to its sort timestamp.
    expect(
      streakSquareLabel(game(sortAt: '2026-03-04T15:30:00+00:00')),
      'Mar 4',
    );
    expect(
      streakSquareLabel(game(day: 'n/a', sortAt: '2026-03-04T15:30:00Z')),
      'Mar 4',
    );
    expect(streakSquareLabel(game()), '');
  });

  test('list days carry the year only outside the current one', () {
    final now = DateTime.utc(2026, 9, 24);
    expect(streakListDay('2026-09-14', now: now), 'Sep 14');
    expect(streakListDay('2025-12-18', now: now), 'Dec 18, 2025');
    expect(streakListDay(null, now: now), isNull);
    expect(streakMonthYear(DateTime.utc(2025, 3, 9)), 'Mar 2025');
  });

  test('result tones clear AA in both themes and never burn', () {
    for (final (colors, light) in [
      (AppColors.dark, false),
      (AppColors.light, true),
    ]) {
      final win = streakResultToneFor(colors, light: light, win: true);
      final latest = streakResultToneFor(
        colors,
        light: light,
        win: true,
        latest: true,
      );
      final loss = streakResultToneFor(colors, light: light, win: false);
      for (final t in [win, latest, loss]) {
        expect(
          wcagContrast(t.ink, t.fill),
          greaterThanOrEqualTo(4.5),
          reason: '${light ? 'light' : 'dark'} ${t.ink} on ${t.fill}',
        );
        expect(t.fill.a, 1.0, reason: 'fills are pre-blended, opaque');
        expect([
          StreakFire.outer,
          StreakFire.light,
          StreakFire.loss,
        ], isNot(contains(t.fill)));
      }
      // The latest win reads as a step, and the loss is not a tinted wash.
      expect(latest.fill, isNot(win.fill));
      expect(loss.fill, colors.surface);
      expect(loss.ink, colors.danger);
      expect(win.ink, light ? colors.successStrong : colors.success);
    }
  });

  testWidgets('the run keeps one label size and fits at 360dp with large '
      'text', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final run = _ding(classicalWins: 16).run(StreakTimeClass.standard)!;
    for (final scale in [1.3, 2.0]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: PlayerRunStrip(run: run, onOpenGame: (_) {}),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final labels = [
        for (final c in streakRunCells(run))
          find.descendant(
            of: find.byKey(
              c.isFold
                  ? const ValueKey('streak-run-fold')
                  : ValueKey('streak-run-${c.game!.gameId}'),
            ),
            matching: find.text(
              c.isFold ? 'earlier' : streakSquareLabel(c.game!),
            ),
          ),
      ];
      final scalers = {
        for (final f in labels) tester.widget<Text>(f).textScaler,
      };
      expect(scalers, hasLength(1), reason: 'one label size at x$scale');
      // Neighbours on a row never touch.
      final rects = [for (final f in labels) tester.getRect(f)];
      for (var i = 1; i < rects.length; i++) {
        final a = rects[i - 1];
        final b = rects[i];
        if ((a.top - b.top).abs() > 1) continue;
        expect(
          b.left - a.right,
          greaterThanOrEqualTo(3),
          reason: 'labels ${i - 1} and $i at x$scale',
        );
      }
    }
  });

  test('run cells fold past fourteen wins', () {
    final run = _ding(classicalWins: 16).run(StreakTimeClass.standard)!;
    final cells = streakRunCells(run);
    expect(cells.first.game?.gameId, 'c-loss');
    expect(cells[1].isFold, isTrue);
    expect(cells[1].hidden, 2);
    expect(cells.length, 1 + 1 + kStreakRunFold);
    expect(streakRunCells(run, expanded: true).length, 17);
  });
}
