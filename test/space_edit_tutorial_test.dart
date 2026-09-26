import 'dart:async';

import 'package:chessever2/screens/chessboard/widgets/switch_views_tutorial_overlay.dart'
    show TutorialStepIndicator;
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryAction;
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/my_prep_screen.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_edit_grid.dart';
import 'package:chessever2/screens/my_space/widgets/space_edit_tutorial.dart';
import 'package:chessever2/screens/my_space/widgets/space_opening_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// My Prep's openings in memory; never touches SQLite or Supabase.
class _Store extends SpaceShortcutsNotifier {
  _Store(this._seed);

  final List<SpaceShortcut> _seed;

  List<SpaceShortcut> get _list => state.valueOrNull ?? const [];

  @override
  Future<List<SpaceShortcut>> build() async => _seed;

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

  @override
  Future<void> restore(SpaceShortcut item) async {
    if (_list.any((s) => s.key == item.key)) return;
    state = AsyncData(SpaceShortcutsNotifier.inDisplayOrder([item, ..._list]));
  }

  @override
  Future<void> moveWithinSection(String key, int toIndex) async {
    final plan = SpaceShortcutsNotifier.planSectionMove(_list, key, toIndex);
    if (plan != null) state = AsyncData(plan.list);
  }

  @override
  Future<void> markOpened(String id) async {}

  int get openings => [
    for (final s in _list)
      if (s.section == SpaceSection.openings) s,
  ].length;
}

/// The tips' memory in memory: due until shown or skipped; the Players'
/// tips kept apart.
class _Tips extends SpaceEditTutorialStore {
  _Tips({this.isDue = true, this.playersDone = false});

  bool isDue;
  bool playersDone;
  int shown = 0;
  int skipped = 0;

  @override
  bool due() => isDue;

  @override
  bool playersShown() => playersDone;

  @override
  void markShown() {
    shown++;
    isDue = false;
  }

  @override
  void markPlayersShown() => playersDone = true;

  @override
  void markSkipped() {
    skipped++;
    isDue = false;
  }
}

SpaceShortcut _line(String eco, String name, String id, double sort) {
  final draft = spaceOpeningDraft(targetId: eco, name: name);
  return SpaceShortcut(
    id: id,
    kind: draft.kind,
    targetId: draft.targetId,
    title: draft.title,
    subtitle: draft.subtitle,
    params: draft.params,
    sortIndex: sort,
    createdAt: DateTime(2026, 9, 20),
  );
}

final _lines = [
  _line('C67', 'Berlin Defence', 'o1', 7),
  _line('B90', 'Sicilian Najdorf', 'o2', 6),
  _line('E97', "King's Indian, Mar del Plata", 'o3', 5),
];

Future<_Store> _pumpPrep(
  WidgetTester tester,
  _Tips tips, {
  bool reducedMotion = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = _Store(_lines);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        spaceShortcutsProvider.overrideWith(() => store),
        gamesListViewModeProvider.overrideWithValue(
          GamesListViewMode.gamesCard,
        ),
        spaceEditTutorialStoreProvider.overrideWithValue(tips),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reducedMotion),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const Scaffold(body: MyPrepOpeningsPage());
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return store;
}

/// Lets springs (Edit's circles, the tips' fades) run out.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _enterEdit(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
  await _settle(tester);
}

final _tips = find.byType(SpaceEditTutorial);
final _next = find.byKey(const ValueKey<String>('space_edit_tips_next'));
final _back = find.byKey(const ValueKey<String>('space_edit_tips_back'));
final _skip = find.byKey(const ValueKey<String>('space_edit_tips_skip'));

int _step(WidgetTester tester) => tester
    .widget<TutorialStepIndicator>(find.byType(TutorialStepIndicator))
    .currentStep;

/// What a screen reader hears of the card: only the step on it.
FinderBase<SemanticsNode> _heard(Pattern label) =>
    find.semantics.byLabel(label);

final _check = find.byType(SpaceEditCheck);

/// How far [check]'s circle is filled, 0 to 1, as it paints it.
double _filled(WidgetTester tester, Finder check) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: check, matching: find.byType(CustomPaint)).first,
  );
  // The painter is private; its fill is all this reads.
  // ignore: avoid_dynamic_calls
  return (paint.painter! as dynamic).t as double;
}

/// How opaque [finder]'s widget is drawn: every Opacity above it, together.
double _opacity(WidgetTester tester, Finder finder) {
  var opacity = 1.0;
  tester.element(finder).visitAncestorElements((e) {
    final w = e.widget;
    if (w is Opacity) opacity *= w.opacity;
    return true;
  });
  return opacity;
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(minutes: 6));
}

void main() {
  test('Players start at selecting (they order themselves); every other '
      'group starts at holding to reorder', () {
    final players = spaceEditTutorialSteps(SpaceSection.players);
    expect(
      [for (final s in players) s.title],
      ['Tap to Select', 'Remove the Selected', 'Done to Finish'],
    );
    expect(players.first.body, contains('Tap a player'));
    for (final section in SpaceSection.values) {
      if (section == SpaceSection.players) continue;
      expect(
        [for (final s in spaceEditTutorialSteps(section)) s.title],
        [
          'Hold to Reorder',
          'Tap to Select',
          'Remove the Selected',
          'Done to Finish',
        ],
        reason: section.name,
      );
    }
  });

  group('the store', () {
    test('fails closed without preferences: never due, and writes nothing', () {
      SharedPreferences? none() => null;
      final store = SpaceEditTutorialStore(none);
      expect(store.due(), isFalse);
      store.markShown();
      store.markSkipped();
      expect(store.due(), isFalse);
    });

    test('due until shown; shown once is shown for good', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = SpaceEditTutorialStore(() => prefs);
      expect(store.due(), isTrue);
      store.markShown();
      expect(store.due(), isFalse);
      expect(prefs.getInt(kSpaceEditWalkthroughShownDateKey), isNotNull);
    });

    test('a skip is remembered', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = SpaceEditTutorialStore(() => prefs);
      store.markSkipped();
      expect(store.due(), isFalse);
      expect(prefs.getBool(kSpaceEditWalkthroughDontShowKey), isTrue);
    });

    test('an earlier skip, or an earlier showing, keeps them away', () async {
      SharedPreferences.setMockInitialValues({
        kSpaceEditWalkthroughDontShowKey: true,
      });
      final skipped = await SharedPreferences.getInstance();
      expect(SpaceEditTutorialStore(() => skipped).due(), isFalse);

      SharedPreferences.setMockInitialValues({
        kSpaceEditWalkthroughShownDateKey: 1758800000000,
      });
      final shown = await SharedPreferences.getInstance();
      expect(SpaceEditTutorialStore(() => shown).due(), isFalse);
    });

    List<String> due(SpaceEditTutorialStore store, SpaceSection section) => [
      for (final s in spaceEditTutorialStepsDue(store, section)) s.title,
    ];

    test('the Players\' tips leave holding to reorder to teach, once, on '
        'the next page that reorders', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = SpaceEditTutorialStore(() => prefs);
      expect(due(store, SpaceSection.players), [
        'Tap to Select',
        'Remove the Selected',
        'Done to Finish',
      ]);
      expect(due(store, SpaceSection.events), hasLength(4));

      store.markPlayersShown();
      expect(prefs.getInt(kSpaceEditWalkthroughPlayersShownDateKey), isNotNull);
      expect(store.due(), isTrue);
      expect(due(store, SpaceSection.players), isEmpty);
      for (final section in SpaceSection.values) {
        if (section == SpaceSection.players) continue;
        expect(due(store, section), ['Hold to Reorder'], reason: section.name);
      }

      store.markShown();
      for (final section in SpaceSection.values) {
        expect(due(store, section), isEmpty, reason: section.name);
      }
    });

    test('the whole tips first leave the Players nothing; a skip ends every '
        'page\'s', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = SpaceEditTutorialStore(() => prefs);
      store.markShown();
      expect(due(store, SpaceSection.players), isEmpty);

      SharedPreferences.setMockInitialValues({});
      final other = await SharedPreferences.getInstance();
      final skipper = SpaceEditTutorialStore(() => other);
      skipper
        ..markPlayersShown()
        ..markSkipped();
      for (final section in SpaceSection.values) {
        expect(due(skipper, section), isEmpty, reason: section.name);
      }
    });
  });

  testWidgets('the first Edit shows the tips once: Next walks every step, '
      'Got it leaves, and Edit again shows none', (tester) async {
    final tips = _Tips();
    await _pumpPrep(tester, tips);
    expect(_tips, findsNothing);

    await _enterEdit(tester);
    expect(_tips, findsOneWidget);
    expect(tips.shown, 1);
    // Edit is open under them.
    expect(find.byType(SpaceEditGrid), findsOneWidget);

    final semantics = tester.ensureSemantics();
    const titles = [
      'Hold to Reorder',
      'Tap to Select',
      'Remove the Selected',
      'Done to Finish',
    ];
    for (final (i, title) in titles.indexed) {
      expect(_step(tester), i + 1);
      expect(_heard(RegExp('^Step ${i + 1} of 4\\s+$title')), findsOne);
      // Only the step on the card is read out.
      for (final other in titles) {
        if (other == title) continue;
        expect(_heard(RegExp('Step \\d of 4\\s+$other')), findsNothing);
      }
      expect(
        find.descendant(
          of: _next,
          matching: find.text(i == 3 ? 'Got it' : 'Next'),
        ),
        findsOneWidget,
      );
      await tester.tap(_next);
      await _settle(tester);
    }
    semantics.dispose();
    await tester.pump(SpaceEditTutorial.fadeOut);
    await _settle(tester);
    expect(_tips, findsNothing);

    // Done, then Edit again: no tips.
    await tester.tap(find.byKey(const ValueKey<String>('space_edit_done')));
    await _settle(tester);
    await _enterEdit(tester);
    expect(_tips, findsNothing);
    expect(tips.shown, 1);
    expect(find.byType(SpaceEditCheck), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('Back returns a step and is inert on the first; a tap on the '
      'scrim moves on, as on the board', (tester) async {
    final tips = _Tips();
    await _pumpPrep(tester, tips);
    await _enterEdit(tester);
    expect(_step(tester), 1);

    // Back holds its place on the first step, but does nothing there.
    await tester.tap(_back, warnIfMissed: false);
    await _settle(tester);
    expect(_step(tester), 1);

    await tester.tap(_next);
    await _settle(tester);
    expect(_step(tester), 2);
    // Next stays where it was: nothing in the row moved.
    final nextAt = tester.getCenter(_next);
    await tester.tap(_back);
    await _settle(tester);
    expect(_step(tester), 1);
    expect(tester.getCenter(_next), nextAt);

    // Anywhere on the scrim moves on.
    await tester.tapAt(const Offset(12, 420));
    await _settle(tester);
    expect(_step(tester), 2);
    expect(tips.skipped, 0);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('Skip ends the tips for good, and every Edit control works '
      'after: select, Remove, Undo, reorder, Done', (tester) async {
    final tips = _Tips();
    final store = await _pumpPrep(tester, tips);
    await _enterEdit(tester);
    expect(_tips, findsOneWidget);

    await tester.tap(_skip);
    expect(tips.skipped, 1);
    await tester.pump(SpaceEditTutorial.fadeOut);
    await _settle(tester);
    expect(_tips, findsNothing);

    await tester.tap(find.byType(SpaceEditCheck).last);
    await _settle(tester);
    expect(find.text('Remove 1', findRichText: true), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('space_edit_remove')));
    await _settle(tester);
    expect(store.openings, 2);
    expect(find.text('Removed from My Space'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await _settle(tester);
    expect(store.openings, 3);

    // A hold still lifts a card: the first line goes under the second.
    final one = tester.getRect(find.byType(SpaceOpeningCard).at(0));
    final two = tester.getRect(find.byType(SpaceOpeningCard).at(1));
    final gesture = await tester.startGesture(one.center);
    await tester.pump(kSpaceEditLiftDelay + const Duration(milliseconds: 60));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(Offset(0, (two.center.dy - one.center.dy) / 5));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await _settle(tester);
    expect(
      [
        for (final s in store.state.valueOrNull!)
          if (s.section == SpaceSection.openings) s.key,
      ],
      [_lines[1].key, _lines[0].key, _lines[2].key],
    );

    await tester.tap(find.byKey(const ValueKey<String>('space_edit_done')));
    await _settle(tester);
    expect(find.byType(SpaceEditCheck), findsNothing);

    await _enterEdit(tester);
    expect(_tips, findsNothing);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('not due: Edit opens with no tips', (tester) async {
    final tips = _Tips(isDue: false);
    await _pumpPrep(tester, tips);
    await _enterEdit(tester);
    expect(_tips, findsNothing);
    expect(tips.shown, 0);
    expect(find.byType(SpaceEditCheck), findsNWidgets(3));
    await tester.tap(find.byKey(const ValueKey<String>('space_edit_done')));
    await _settle(tester);
    expect(find.byType(SpaceEditCheck), findsNothing);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('each step gives way to the next after its time, the border '
      'drawing it; the last one leaves on its own', (tester) async {
    final tips = _Tips();
    await _pumpPrep(tester, tips);
    await _enterEdit(tester);
    expect(_step(tester), 1);
    await tester.pump(const Duration(seconds: 4));
    expect(_step(tester), 1);
    await tester.pump(const Duration(seconds: 4, milliseconds: 100));
    expect(_step(tester), 2);
    for (var i = 0; i < 3; i++) {
      await tester.pump(SpaceEditTutorial.stepTime);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(SpaceEditTutorial.fadeOut);
    await _settle(tester);
    expect(_tips, findsNothing);
    expect(tips.skipped, 0);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('reduced motion: nothing runs on a clock or loops, and the '
      'tips leave at once', (tester) async {
    final tips = _Tips();
    final semantics = tester.ensureSemantics();
    await _pumpPrep(tester, tips, reducedMotion: true);
    await _enterEdit(tester);
    expect(_tips, findsOneWidget);
    // Shown whole at once, not stranded at the fade's first frame: the
    // card, its dots, the hand, the buttons, and the step read out.
    expect(_opacity(tester, find.text('Hold to Reorder')), 1);
    expect(_opacity(tester, find.text('Tap to Select')), 0);
    expect(_opacity(tester, find.byType(TutorialStepIndicator)), 1);
    expect(_opacity(tester, find.byIcon(Icons.touch_app_rounded)), 1);
    expect(_opacity(tester, _next), 1);
    expect(_opacity(tester, _skip), 1);
    expect(_heard(RegExp(r'^Step 1 of 4\s+Hold to Reorder')), findsOne);
    // The dots jump.
    expect(
      tester
          .widget<TutorialStepIndicator>(find.byType(TutorialStepIndicator))
          .duration,
      Duration.zero,
    );
    // No clock: the first step stands as long as the reader needs.
    await tester.pump(const Duration(seconds: 20));
    expect(_step(tester), 1);
    // Nothing on the tips asks for a frame while it stands still.
    await _settle(tester);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.tap(_next);
    await tester.pump();
    expect(_step(tester), 2);
    expect(_opacity(tester, find.text('Tap to Select')), 1);
    expect(_opacity(tester, find.text('Hold to Reorder')), 0);
    expect(_opacity(tester, _back), 1);
    expect(_heard(RegExp(r'^Step 2 of 4\s+Tap to Select')), findsOne);
    // The hand's card shows its circle filled, as the step says.
    expect(_filled(tester, find.descendant(of: _tips, matching: _check)), 1);
    // Once the button's own ink has faded, nothing runs.
    await _settle(tester);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.tap(_back);
    await tester.pump();
    expect(_step(tester), 1);
    semantics.dispose();

    for (var i = 0; i < 3; i++) {
      await tester.tap(_next);
      await tester.pump();
    }
    expect(_step(tester), 4);
    await tester.tap(_next);
    await tester.pump();
    expect(_tips, findsNothing);

    // Edit's own circle fills at a tap, and empties at the next.
    expect(_filled(tester, _check.first), 0);
    await tester.tap(_check.first);
    await tester.pump();
    expect(_filled(tester, _check.first), 1);
    expect(find.text('Remove 1', findRichText: true), findsOneWidget);
    await tester.tap(_check.first);
    await tester.pump();
    expect(_filled(tester, _check.first), 0);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('the hand\'s picture is no control: a tap on it moves on, as '
      'on the scrim, and its Done on the last step leaves', (tester) async {
    final tips = _Tips();
    await _pumpPrep(tester, tips);
    await _enterEdit(tester);
    final done = find.descendant(
      of: _tips,
      matching: find.byType(DiscoveryAction),
    );
    expect(done, findsNWidgets(2));
    // Remove and Done lie faded under the first step's card: they take
    // nothing.
    await tester.tap(done.last, warnIfMissed: false);
    await _settle(tester);
    expect(_step(tester), 2);
    await tester.tap(find.byIcon(Icons.touch_app_rounded), warnIfMissed: false);
    await _settle(tester);
    expect(_step(tester), 3);
    await tester.tap(done.last, warnIfMissed: false);
    await _settle(tester);
    expect(_step(tester), 4);
    // "Tap Done to leave Edit": the tips' Done does leave them.
    await tester.tap(done.last, warnIfMissed: false);
    await tester.pump(SpaceEditTutorial.fadeOut);
    await _settle(tester);
    expect(_tips, findsNothing);
    expect(tips.skipped, 0);
    // Edit stays open under them; its own Done was never touched.
    expect(find.byType(SpaceEditCheck), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('leaving takes away the tips\' own route: a page pushed over '
      'them as they fade stays', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showSpaceEditTutorial(
                    context,
                    section: SpaceSection.events,
                  ),
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(_tips, findsOneWidget);

    await tester.tap(_skip);
    await tester.pump(const Duration(milliseconds: 100));
    // A notification tap, say, lands mid-fade.
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Pushed')),
        ),
      ),
    );
    await tester.pump(SpaceEditTutorial.fadeOut);
    await _settle(tester);
    expect(find.text('Pushed'), findsOneWidget);
    expect(find.byType(SpaceEditTutorial, skipOffstage: false), findsNothing);

    navigator.currentState!.pop();
    await _settle(tester);
    expect(find.text('open'), findsOneWidget);
    expect(find.byType(SpaceEditTutorial, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('after the Players\' tips, My Prep\'s first Edit teaches '
      'holding alone', (tester) async {
    final tips = _Tips(playersDone: true);
    await _pumpPrep(tester, tips);
    await _enterEdit(tester);
    expect(_tips, findsOneWidget);
    expect(tips.shown, 1);
    expect(find.text('Hold to Reorder'), findsOneWidget);
    expect(find.text('Tap to Select'), findsNothing);
    expect(find.byType(TutorialStepIndicator), findsNothing);
    expect(find.descendant(of: _next, matching: find.text('Got it')), findsOne);
    // No step to go back to, so no room kept for Back: Skip and Got it
    // stand together, spaced as on the board, the pair centred.
    expect(_back, findsNothing);
    final skip = tester.getRect(_skip);
    final gotIt = tester.getRect(_next);
    expect(gotIt.left - skip.right, moreOrLessEquals(24.w, epsilon: 0.5));
    expect(skip.left, moreOrLessEquals(390 - gotIt.right, epsilon: 1));
    await tester.tap(_next);
    await tester.pump(SpaceEditTutorial.fadeOut);
    await _settle(tester);
    expect(_tips, findsNothing);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('large text on a small phone: the hand gives way, never the '
      'buttons; Skip, Back and Next stay on the screen', (tester) async {
    // The tips over a bare page at [size] and [scale]: walks every step,
    // checking the buttons stand whole, clear of the edges, and that the
    // hand is drawn whole or not at all. Returns whether it was drawn.
    Future<List<bool>> walk(Size size, double scale, {EdgeInsets? pad}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final inset = pad ?? EdgeInsets.zero;
      tester.view.padding = FakeViewPadding(
        top: inset.top,
        bottom: inset.bottom,
      );
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showSpaceEditTutorial(
                      context,
                      section: SpaceSection.events,
                    ),
                    child: const Text('open'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
      final screen = (Offset.zero & size).deflate(8);
      final hand = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_WholeOrNone',
      );
      final drawn = <bool>[];
      for (var i = 0; i < 4; i++) {
        final reason = '$size at ${scale}x, step ${i + 1}';
        for (final button in [_skip, _next, if (i > 0) _back]) {
          final r = tester.getRect(button);
          expect(
            screen.contains(r.topLeft) && screen.contains(r.bottomRight),
            isTrue,
            reason: '$reason: $r',
          );
        }
        final demo = tester.getSize(hand).height;
        expect(demo == 0 || demo > 100, isTrue, reason: reason);
        drawn.add(demo > 0);
        await tester.tap(_next);
        await _settle(tester);
      }
      await tester.pump(SpaceEditTutorial.fadeOut);
      await _settle(tester);
      expect(_tips, findsNothing);
      expect(tester.takeException(), isNull);
      return drawn;
    }

    // As the tips were designed: the hand under the card on every step.
    expect(await walk(const Size(390, 844), 1), everyElement(isTrue));
    await _drain(tester);
    for (final (size, scale, pad) in [
      (const Size(375, 667), 2.0, null),
      (const Size(360, 780), 2.0, const EdgeInsets.only(top: 24, bottom: 48)),
      (const Size(375, 667), 3.0, const EdgeInsets.only(top: 20)),
      (const Size(390, 844), 3.0, const EdgeInsets.only(top: 47, bottom: 34)),
    ]) {
      await walk(size, scale, pad: pad);
      await _drain(tester);
    }
  });

  testWidgets('back leaves the tips, and leaves Edit open', (tester) async {
    final tips = _Tips();
    await _pumpPrep(tester, tips);
    await _enterEdit(tester);
    expect(_tips, findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump(SpaceEditTutorial.fadeOut);
    await _settle(tester);
    expect(_tips, findsNothing);
    expect(find.byType(SpaceEditCheck), findsNWidgets(3));
    expect(tips.skipped, 0);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });
}
