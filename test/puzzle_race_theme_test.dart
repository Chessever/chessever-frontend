import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/feed/race/puzzle_rating_range.dart';
import 'package:chessever2/screens/feed/race/race_client.dart';
import 'package:chessever2/screens/feed/race/race_controller.dart';
import 'package:chessever2/screens/feed/race/race_flames.dart';
import 'package:chessever2/screens/feed/race/race_lobby_screen.dart';
import 'package:chessever2/screens/feed/race/race_stats_store.dart';
import 'package:chessever2/screens/feed/race/race_widgets.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'puzzle_race_fakes.dart';

/// Puzzle Race in both themes: every word and glyph on screen measured
/// against what it is painted on, the way out of every view (visible control
/// and system back alike), the difficulty, and the flames.

class _TestBoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

final _themes = {'dark': AppTheme.darkTheme, 'light': AppTheme.lightTheme};

/// The lobby pushed over a plain home route, so a pop has somewhere to go.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  RaceHarness h, {
  required ThemeData theme,
  Size size = const Size(393, 852),
  RaceServerStats? kept,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final container = ProviderContainer(
    overrides: [
      raceDepsProvider.overrideWithValue(h.deps()),
      boardSettingsProviderNew.overrideWith(_TestBoardSettings.new),
      raceServerStatsSourceProvider.overrideWithValue(
        FakeRaceServerStatsSource(kept),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => RaceLobbyScreen.open(context),
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await _settle(tester, frames: 30);
  return container;
}

Future<void> _unmount(WidgetTester tester) async {
  final scope = tester.widgetList<UncontrolledProviderScope>(
    find.byType(UncontrolledProviderScope),
  );
  final containers = [for (final s in scope) s.container];
  await tester.pumpWidget(const SizedBox.shrink());
  for (final c in containers) {
    c.dispose();
  }
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _settle(WidgetTester tester, {int frames = 4}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _settle(tester);
}

/// Solo from the lobby to the first puzzle on the board.
Future<void> _race(WidgetTester tester, RaceHarness h) async {
  await _tap(tester, 'race_start_solo');
  h.server.last.push(snapshot());
  await _settle(tester);
  h.server.last.push(snapshot(state: 'running', startedAt: h.clock - 2000));
  h.server.last.push(puzzle());
  await _settle(tester);
  await tester.pump(const Duration(milliseconds: 400));
}

/// Multiplayer, signed in: into a room of two whose ladder runs 1000-1500.
Future<FakeRaceSocket> _room(WidgetTester tester, RaceHarness h) async {
  await _tap(tester, 'race_multiplayer');
  await _tap(tester, 'race_create_room');
  final socket = h.server.last;
  socket.push(
    snapshot(
      multiplayer: true,
      startRating: 1000,
      maxRating: 1500,
      players: [
        player(),
        player(id: kRival, name: 'Hikaru', connected: false),
      ],
    ),
  );
  await _settle(tester);
  return socket;
}

// ------------------------------------------------------------- contrast

double _contrast(Color fg, Color bg) {
  final base = bg.a >= 1 ? bg : Color.alphaBlend(bg, const Color(0xFF000000));
  final top = Color.alphaBlend(fg, base);
  final a = top.computeLuminance();
  final b = base.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

bool _underBoard(Element element) {
  var inside = false;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget.runtimeType.toString() == 'Chessboard') {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

/// What [element] is painted on: the nearest filled ancestor, else [page].
Color _backdrop(Element element, Color page) {
  Color? found;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    Color? fill;
    if (widget is DecoratedBox) {
      final decoration = widget.decoration;
      if (decoration is BoxDecoration) fill = decoration.color;
    } else if (widget is ColoredBox) {
      fill = widget.color;
    } else if (widget is InputDecorator) {
      if (widget.decoration.filled ?? false) {
        fill = widget.decoration.fillColor;
      }
    } else if (widget is Material && widget.type != MaterialType.transparency) {
      fill = widget.color;
    }
    if (fill != null && fill.a > 0.5) {
      found = fill;
      return false;
    }
    return true;
  });
  return found ?? page;
}

double _opacity(Element element) {
  var opacity = 1.0;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Opacity) opacity *= widget.opacity;
    return true;
  });
  return opacity;
}

/// Every word on screen clears AA (4.5:1, or 3:1 from 24px) against what it
/// sits on, every glyph clears 3:1, and no line is cut short. Returns how
/// many strings it measured, so a caller can tell it looked at something.
int _expectLegible(WidgetTester tester, String where) {
  final context = tester.element(find.byType(RaceLobbyScreen));
  final page = context.colors.background;
  final failures = <String>[];
  var measured = 0;

  for (final element in find.byType(RichText).evaluate()) {
    if (_underBoard(element)) continue;
    final widget = element.widget as RichText;
    final paragraph = element.renderObject! as RenderParagraph;
    if (!paragraph.hasSize || paragraph.size.isEmpty) continue;
    if (paragraph.didExceedMaxLines) {
      failures.add('cut: "${widget.text.toPlainText()}"');
    }
    final bg = _backdrop(element, page);
    final opacity = _opacity(element);
    void visit(InlineSpan span, Color? color, double size) {
      if (span is! TextSpan) return;
      final ink = span.style?.color ?? color;
      final px = span.style?.fontSize ?? size;
      final text = span.text?.trim() ?? '';
      if (text.isNotEmpty && ink != null) {
        measured += 1;
        final ratio = _contrast(ink.withValues(alpha: ink.a * opacity), bg);
        final min = px >= 24 ? 3.0 : 4.5;
        if (ratio < min) {
          failures.add('"$text" ${ratio.toStringAsFixed(2)}:1 < $min');
        }
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child, ink, px);
      }
    }

    visit(widget.text, null, 14);
  }

  for (final element in find.byType(FeedGlyph).evaluate()) {
    if (_underBoard(element)) continue;
    final glyph = element.widget as FeedGlyph;
    final ratio = _contrast(glyph.color, _backdrop(element, page));
    measured += 1;
    if (ratio < 3) failures.add('glyph ${ratio.toStringAsFixed(2)}:1 < 3');
  }

  expect(failures, isEmpty, reason: where);
  return measured;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the race tokens read in both themes', () {
    for (final entry in _themes.entries) {
      final colors = entry.value.extension<AppColors>()!;
      final light = entry.value.brightness == Brightness.light;

      test('${entry.key}: hearts, frame and verdicts', () {
        final page = colors.background;
        // Filled hearts at their faintest jitter, and an empty slot.
        expect(
          _contrast(colors.danger.withValues(alpha: 0.78), page),
          greaterThanOrEqualTo(3),
        );
        final ghost = raceLegible(
          colors.textPrimary.withValues(alpha: 0.16),
          on: page,
          toward: colors.textPrimary,
          min: 3,
        );
        expect(_contrast(ghost, page), greaterThanOrEqualTo(3));
        // On paper every frame step clears 3:1, and each is darker than the
        // one before it.
        if (light) {
          var previous = 0.0;
          for (final level in [1, 4, 7, 10, 13]) {
            final ratio = _contrast(
              raceFrameTone(colors, level, paper: true),
              page,
            );
            expect(ratio, greaterThanOrEqualTo(3), reason: 'level $level');
            expect(ratio, greaterThan(previous), reason: 'level $level');
            previous = ratio;
          }
        }
        expect(
          _contrast(raceQuietInk(colors), page),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(raceQuietInk(colors, on: colors.surface), colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(
            raceQuietInk(colors, on: colors.surfaceRecessed),
            colors.surfaceRecessed,
          ),
          greaterThanOrEqualTo(4.5),
        );
      });
    }

    testWidgets('verdict inks clear AA on the page in both themes', (
      tester,
    ) async {
      for (final theme in _themes.values) {
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        );
        final page = context.colors.background;
        expect(
          _contrast(raceVerdictInk(context, solved: true), page),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(raceVerdictInk(context, solved: false), page),
          greaterThanOrEqualTo(4.5),
        );
      }
    });
  });

  for (final entry in _themes.entries) {
    final name = entry.key;
    final theme = entry.value;

    group('$name: every view is legible', () {
      testWidgets('lobby, a guest with flames', (tester) async {
        final h = RaceHarness();
        h.stats.bests = const RaceBests(survivalBest: 31, flames: 30);
        await _pump(tester, h, theme: theme);
        expect(find.text('30 flames'), findsOneWidget);
        expect(find.text('Sign in to keep your flames'), findsOneWidget);
        expect(_expectLegible(tester, 'lobby'), greaterThan(20));
        // The custom range, and a disabled Join beside an empty code.
        await _tap(tester, 'race_difficulty_custom');
        await _tap(tester, 'race_multiplayer');
        _expectLegible(tester, 'lobby, custom, multiplayer guest');
        await _unmount(tester);
      });

      testWidgets('lobby for a signed-in player, a failure, a room', (
        tester,
      ) async {
        final h = RaceHarness(token: 'jwt');
        await _pump(tester, h, theme: theme);
        await _tap(tester, 'race_multiplayer');
        _expectLegible(tester, 'lobby, multiplayer');
        h.api.failures.add(const RaceApiException('network'));
        await _tap(tester, 'race_create_room');
        expect(find.byKey(const ValueKey('race_retry')), findsOneWidget);
        _expectLegible(tester, 'lobby, failed');
        await _tap(tester, 'race_retry');
        final socket = h.server.last;
        socket.push(
          snapshot(
            multiplayer: true,
            startRating: 1000,
            maxRating: 1500,
            players: [
              player(),
              player(id: kRival, name: 'Hikaru', connected: false),
            ],
          ),
        );
        await _settle(tester);
        // An older room may still carry a ceiling; the start is what shows.
        expect(
          find.text('Survival · starts at 1000 · up to 8 players'),
          findsOneWidget,
        );
        _expectLegible(tester, 'room');
        await _unmount(tester);
      });

      testWidgets('the race, its opponents, and the stop dialog', (
        tester,
      ) async {
        final h = RaceHarness(token: 'jwt');
        await _pump(tester, h, theme: theme);
        final socket = await _room(tester, h);
        socket.push(
          snapshot(
            multiplayer: true,
            state: 'running',
            startedAt: h.clock - 2000,
            players: [
              player(score: 1),
              player(id: kRival, name: 'Hikaru', score: 3, finished: true),
              player(id: 'away01', name: 'Anish', connected: false),
            ],
          ),
        );
        socket.push(puzzle());
        await _settle(tester);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('done'), findsOneWidget);
        _expectLegible(tester, 'race');

        await tester.tap(find.byKey(const ValueKey('race_stop')));
        await _settle(tester, frames: 15);
        expect(find.text('End this run?'), findsOneWidget);
        _expectLegible(tester, 'stop dialog');
        await tester.tap(find.text('Keep racing'));
        await _settle(tester, frames: 15);
        await _unmount(tester);
      });

      testWidgets('results, solved and missed', (tester) async {
        final h = RaceHarness();
        await _pump(tester, h, theme: theme);
        await _race(tester, h);
        final socket = h.server.last;
        final race = tester
            .element(find.byType(RaceLobbyScreen))
            .findAncestorWidgetOfExactType<UncontrolledProviderScope>()!
            .container
            .read(raceControllerProvider.notifier);
        race.submitMove('a1a8');
        socket.push(verdict(score: 1, level: 1));
        socket.push(puzzle(index: 1, rating: 1210, level: 1));
        await _settle(tester);
        await tester.pump(const Duration(seconds: 1));
        race.submitMove('b1b7');
        socket.push(verdict(index: 1, correct: false, score: 1, mistakes: 1));
        socket.push(
          finished(
            results: [
              result(
                score: 1,
                mistakes: 1,
                elapsedMs: 9000,
                finishReason: 'stopped',
                flames: 1,
              ),
            ],
          ),
        );
        await _settle(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Race over'), findsOneWidget);
        expect(find.text('Solved'), findsOneWidget);
        expect(find.text('Missed'), findsOneWidget);
        expect(find.text('+1 flame'), findsOneWidget);
        _expectLegible(tester, 'results');
        await _unmount(tester);
      });
    });
  }

  group('light mode, 360dp, 1.3x text: nothing overflows or is cut', () {
    Future<void> check(WidgetTester tester, String where) async {
      expect(tester.takeException(), isNull, reason: where);
      _expectLegible(tester, where);
    }

    testWidgets('lobby, race and results', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final h = RaceHarness(token: 'jwt');
      h.stats.bests = const RaceBests(flames: 1234, survivalBest: 88);
      await _pump(
        tester,
        h,
        theme: AppTheme.lightTheme,
        size: const Size(360, 640),
      );
      await check(tester, 'lobby');
      await _tap(tester, 'race_difficulty_custom');
      await _tap(tester, 'race_multiplayer');
      await check(tester, 'lobby, custom, multiplayer');
      await _tap(tester, 'race_create_room');
      h.server.last.push(
        snapshot(
          multiplayer: true,
          startRating: 1500,
          // The square test glyphs are far wider than real ones, so a short
          // name keeps "(you)" beside it; a long one would give way.
          players: [
            player(name: 'Wei'),
            player(id: kRival, name: 'Hikaru', ready: true),
          ],
        ),
      );
      await _settle(tester);
      expect(
        find.text('Survival · starts at 1500 · up to 8 players'),
        findsOneWidget,
      );
      await check(tester, 'room');
      await _tap(tester, 'race_leave_room');
      await _tap(tester, 'race_solo');
      await _race(tester, h);
      await check(tester, 'race');
      // The corner control keeps its 44 box and its word.
      final end = tester.getSize(find.byKey(const ValueKey('race_stop')));
      expect(end.height, greaterThanOrEqualTo(44));
      expect(end.width, greaterThanOrEqualTo(44));
      h.server.last.push(
        finished(
          results: [
            result(elapsedMs: 9000, finishReason: 'stopped', flames: 0),
          ],
        ),
      );
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await check(tester, 'results');
      await _unmount(tester);
    });
  });

  group('the way out', () {
    testWidgets('setup: the named corner control and system back both leave', (
      tester,
    ) async {
      final h = RaceHarness();
      await _pump(tester, h, theme: AppTheme.lightTheme);
      expect(find.bySemanticsLabel('Back to Feed'), findsOneWidget);
      expect(find.text('Feed'), findsOneWidget);
      final back = tester.getSize(find.byKey(const ValueKey('race_back')));
      expect(back.height, greaterThanOrEqualTo(44));

      await tester.binding.handlePopRoute();
      await _settle(tester, frames: 30);
      expect(find.byType(RaceLobbyScreen), findsNothing);

      await tester.tap(find.text('open'));
      await _settle(tester, frames: 30);
      await tester.tap(find.byKey(const ValueKey('race_back')));
      await _settle(tester, frames: 30);
      expect(find.byType(RaceLobbyScreen), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a room: system back leaves the room, as Leave does', (
      tester,
    ) async {
      final h = RaceHarness(token: 'jwt');
      final container = await _pump(tester, h, theme: AppTheme.lightTheme);
      final socket = await _room(tester, h);
      expect(find.byKey(const ValueKey('race_room_code')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await _settle(tester, frames: 10);
      // Still in the race, back at the setup, and the seat is given up.
      expect(find.byType(RaceLobbyScreen), findsOneWidget);
      expect(container.read(raceControllerProvider).phase, RacePhase.setup);
      expect(socket.sentTypes, contains('stop'));

      await _room(tester, h);
      await tester.tap(find.byKey(const ValueKey('race_leave_room')));
      await _settle(tester, frames: 10);
      expect(container.read(raceControllerProvider).phase, RacePhase.setup);
      expect(find.byType(RaceLobbyScreen), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('a run: system back asks first, exactly like End', (
      tester,
    ) async {
      final h = RaceHarness();
      final container = await _pump(tester, h, theme: AppTheme.lightTheme);
      await _race(tester, h);
      expect(find.bySemanticsLabel('End the run'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await _settle(tester, frames: 15);
      expect(find.text('End this run?'), findsOneWidget);
      await tester.tap(find.text('Keep racing'));
      await _settle(tester, frames: 15);
      expect(container.read(raceControllerProvider).phase, RacePhase.running);
      expect(find.byType(RaceLobbyScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await _settle(tester, frames: 15);
      await tester.tap(find.text('End run'));
      await _settle(tester, frames: 15);
      expect(h.server.last.sentTypes.last, 'stop');
      await _unmount(tester);
    });

    testWidgets('results: back to the Feed from the corner or the row', (
      tester,
    ) async {
      final h = RaceHarness();
      await _pump(tester, h, theme: AppTheme.lightTheme);
      await _race(tester, h);
      h.server.last.push(
        finished(results: [result(elapsedMs: 9000, finishReason: 'stopped')]),
      );
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey('race_back_to_feed')));
      await _settle(tester, frames: 30);
      expect(find.byType(RaceLobbyScreen), findsNothing);
      await _unmount(tester);
    });
  });

  group('difficulty', () {
    testWidgets('the saved range shows, and the race starts from it', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        kPuzzleRatingRangePrefsKey: '1500-2000',
      });
      final h = RaceHarness();
      await _pump(tester, h, theme: AppTheme.darkTheme);
      final strong = tester.getSemantics(
        find.byKey(const ValueKey('race_difficulty_strong')),
      );
      expect(strong.flagsCollection.isSelected, Tristate.isTrue);
      // A preset reads as where the race starts, not a band.
      expect(find.text('Starts at 1500'), findsOneWidget);
      final custom = tester.getSemantics(
        find.byKey(const ValueKey('race_difficulty_custom')),
      );
      expect(custom.flagsCollection.isSelected, Tristate.isFalse);
      expect(find.text('Your own start'), findsOneWidget);
      // A preset keeps its start to itself: no slider.
      expect(find.byKey(const ValueKey('race_custom_slider')), findsNothing);

      await _tap(tester, 'race_start_solo');
      expect(h.api.creates.last.minRating, 1500);
      // The ladder climbs freely: the band's top is never sent.
      expect(h.api.creates.last.maxRating, isNull);
      await _unmount(tester);
    });

    testWidgets('a preset is kept for next time', (tester) async {
      final h = RaceHarness();
      await _pump(tester, h, theme: AppTheme.lightTheme);
      await _tap(tester, 'race_difficulty_expert');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPuzzleRatingRangePrefsKey), '2000-2500');
      await _tap(tester, 'race_start_solo');
      expect(h.api.creates.last.minRating, 2000);
      expect(h.api.creates.last.maxRating, isNull);
      await _unmount(tester);
    });

    testWidgets('Custom opens a start of your own that saves on release', (
      tester,
    ) async {
      final h = RaceHarness();
      final container = await _pump(tester, h, theme: AppTheme.lightTheme);
      // The first-time range (800-1400) is no preset: Custom, with its
      // slider, is what is chosen.
      expect(find.byKey(const ValueKey('race_custom_slider')), findsOneWidget);
      await _tap(tester, 'race_difficulty_club');
      expect(find.byKey(const ValueKey('race_custom_slider')), findsNothing);
      await _tap(tester, 'race_difficulty_custom');
      final slider = find.byKey(const ValueKey('race_custom_slider'));
      expect(slider, findsOneWidget);
      expect(find.text('Starts at 1000'), findsWidgets);

      await tester.ensureVisible(slider);
      await tester.pump();
      final rect = tester.getRect(slider);
      // The same 44 the two-handle range stood at: nothing below moves.
      expect(rect.height, 44);
      final track = rect.width - 44;
      final thumb = Offset(
        rect.left + 22 + track * (1000 - 400) / 2600,
        rect.center.dy,
      );
      await tester.dragFrom(thumb, const Offset(90, 0));
      await _settle(tester, frames: 10);

      final range = container.read(puzzleRatingRangeProvider);
      expect(range.min, greaterThan(1000));
      // The band's top (the Feed's) holds unless the start climbs past it.
      expect(range.max, math.max(1500, range.min + 200));
      expect(range.preset, isNull);
      expect(find.text('Starts at ${range.min}'), findsWidgets);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(kPuzzleRatingRangePrefsKey),
        '${range.min}-${range.max}',
      );
      await _tap(tester, 'race_start_solo');
      expect(h.api.creates.last.minRating, range.min);
      expect(h.api.creates.last.maxRating, isNull);
      await _unmount(tester);
    });

    testWidgets('a screen reader step saves at once, the handle named', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        kPuzzleRatingRangePrefsKey: '800-1500',
      });
      final semantics = tester.ensureSemantics();
      final h = RaceHarness();
      final container = await _pump(tester, h, theme: AppTheme.darkTheme);
      final slider = find.byKey(const ValueKey('race_custom_slider'));
      await tester.ensureVisible(slider);
      await tester.pump();
      // One handle: where the race starts.
      expect(find.semantics.byValue('Starting rating 800'), findsOne);

      final handle = find.semantics.byValue(RegExp('^Starting rating'));
      tester.semantics.increase(handle);
      await _settle(tester);
      expect(
        container.read(puzzleRatingRangeProvider),
        const PuzzleRatingRange(850, 1500),
      );
      expect(find.semantics.byValue('Starting rating 850'), findsOne);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPuzzleRatingRangePrefsKey), '850-1500');

      // Stepping onto a preset's range (Club, 1000-1500) keeps Custom and
      // its handle where the screen reader is.
      for (var i = 0; i < 3; i++) {
        tester.semantics.increase(handle);
        await _settle(tester);
      }
      expect(
        container.read(puzzleRatingRangeProvider),
        PuzzleRatingPreset.club.range,
      );
      expect(slider, findsOneWidget);

      // Past the band's top, the top is pushed along to stay 200 above.
      for (var i = 0; i < 7; i++) {
        tester.semantics.increase(handle);
        await _settle(tester);
      }
      expect(
        container.read(puzzleRatingRangeProvider),
        const PuzzleRatingRange(1350, 1550),
      );
      semantics.dispose();
      await _unmount(tester);
    });

    testWidgets('the results are spoken when they replace the run', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final spoken = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
            message,
          ) async {
            final map = message as Map<Object?, Object?>;
            if (map['type'] == 'announce') {
              final data = map['data']! as Map<Object?, Object?>;
              spoken.add(data['message']! as String);
            }
            return null;
          });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<dynamic>(
              SystemChannels.accessibility,
              null,
            ),
      );
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(supportsAnnounce: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      final h = RaceHarness();
      await _pump(tester, h, theme: AppTheme.darkTheme);
      await _race(tester, h);
      expect(spoken, isEmpty);
      h.server.last.push(
        finished(
          results: [
            result(
              score: 7,
              elapsedMs: 9000,
              finishReason: 'lives',
              flames: 12,
            ),
          ],
        ),
      );
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(find.byKey(const ValueKey('race_final_score')), findsOneWidget);
      expect(spoken, ['7 solved. Out of lives. 12 flames earned.']);
      semantics.dispose();
      await _unmount(tester);
    });

    testWidgets('where nothing is announced, the results are a live region', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final h = RaceHarness();
      await _pump(tester, h, theme: AppTheme.lightTheme);
      await _race(tester, h);
      h.server.last.push(
        finished(
          results: [result(score: 1, elapsedMs: 9000, finishReason: 'lives')],
        ),
      );
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      final live = find.semantics.byPredicate(
        (node) => node.flagsCollection.isLiveRegion,
      );
      expect(live, findsOne);
      expect(live.evaluate().single.label, '1 solved. Out of lives.');
      semantics.dispose();
      await _unmount(tester);
    });
  });

  group('flames in the lobby', () {
    testWidgets('a signed-in player sees the kept count, no sign-in line', (
      tester,
    ) async {
      final h = RaceHarness(token: 'jwt');
      h.stats.bests = const RaceBests(flames: 12, survivalBest: 3);
      await _pump(
        tester,
        h,
        theme: AppTheme.lightTheme,
        kept: const RaceServerStats(flames: 120, survivalBest: 40),
      );
      expect(find.text('120 flames'), findsOneWidget);
      expect(find.text('Best 40'), findsOneWidget);
      expect(find.text('Sign in to keep your flames'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('no flames yet: no count, just the promise', (tester) async {
      final h = RaceHarness();
      await _pump(tester, h, theme: AppTheme.lightTheme);
      expect(find.byKey(const ValueKey('race_lobby_flames')), findsNothing);
      expect(find.textContaining('Solves earn flames'), findsOneWidget);
      await _unmount(tester);
    });
  });
}
