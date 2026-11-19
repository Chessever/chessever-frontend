import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/live_first_capsule.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The page around one capsule: what it passes in, changeable mid-test the
/// way a page's live count and Live first state change under it.
class _Host {
  _Host(this.on, this.liveCount);

  bool on;
  int? liveCount;
  late StateSetter _setState;

  void setOn(bool value) => _setState(() => on = value);

  void setCount(int? value) => _setState(() => liveCount = value);
}

/// Hosts one capsule. When [onTap] is null the capsule toggles itself, the
/// way a page wires it to its Live first state.
Future<_Host> _pump(
  WidgetTester tester, {
  bool on = false,
  int? liveCount = 3,
  String subject = 'games',
  ThemeData? theme,
  bool reduceMotion = false,
  double textScale = 1,
  Size view = const Size(393, 852),
  InkFabSize size = InkFabSize.small,
  LiveFirstMode mode = LiveFirstMode.reorder,
  VoidCallback? onTap,
}) async {
  tester.view.physicalSize = view;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final host = _Host(on, liveCount);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduceMotion,
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (context, setState) {
                    host._setState = setState;
                    return LiveFirstCapsule(
                      on: host.on,
                      liveCount: host.liveCount,
                      subject: subject,
                      size: size,
                      mode: mode,
                      onTap: onTap ?? () => setState(() => host.on = !host.on),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  // A second pump in one test reuses the element, so a changed state springs
  // there: let it land, so every test starts from rest.
  await tester.pumpAndSettle();
  return host;
}

Finder get _capsule => find.byType(LiveFirstCapsule);
Finder get _glass =>
    find.descendant(of: _capsule, matching: find.byType(GlassSurface));
Finder get _offWords => find.byKey(const ValueKey('live_first_capsule_off'));
Finder get _onWords => find.byKey(const ValueKey('live_first_capsule_on'));

double _settledWidth(WidgetTester tester, String label) =>
    LiveFirstCapsule.widthFor(
      tester.element(_capsule),
      label,
      InkFabSize.small,
    );

/// How strongly [words] are drawn right now: 0 when not built at all.
double _opacityOf(WidgetTester tester, Finder words) {
  if (words.evaluate().isEmpty) return 0;
  return tester
      .widget<Opacity>(find.ancestor(of: words, matching: find.byType(Opacity)))
      .opacity;
}

/// Plays whatever the capsule is springing toward one 60Hz frame at a time,
/// from the frame that first draws the change to the one it rests on, and
/// checks on every frame that any words drawn at all end well inside the
/// glass (the rounded rim is at most ~2pt deep at the words' height; ask for
/// 4). Returns how many frames it took.
Future<int> _expectWordsInsideGlassEveryFrame(
  WidgetTester tester,
  String reason,
) async {
  var frames = 0;
  do {
    await tester.pump(const Duration(milliseconds: 16));
    frames++;
    final glass = tester.getRect(_glass);
    final k = glass.height / 44;
    for (final words in [_offWords, _onWords]) {
      if (_opacityOf(tester, words) == 0) continue;
      final rect = tester.getRect(words);
      expect(
        rect.right,
        lessThanOrEqualTo(glass.right - 4 * k + 0.01),
        reason: '$reason: frame $frames, words past the rim',
      );
      expect(
        rect.left,
        greaterThan(glass.left),
        reason: '$reason: frame $frames, words before the rim',
      );
    }
  } while (tester.binding.hasScheduledFrame && frames < 120);
  expect(frames, lessThan(120), reason: '$reason: never settled');
  return frames;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The app's own Inter, so widths and the gaps a spring opens are the ones a
  // phone draws, not the test font's square glyphs.
  setUpAll(() async {
    final font = FontLoader('InterDisplay');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Inter-$weight.otf'));
    }
    await font.load();
  });

  group('words', () {
    test('off is a verb and the live count, or "See live" when unknown', () {
      expect(LiveFirstCapsule.labelFor(on: false, liveCount: 3), 'See 3 live');
      expect(LiveFirstCapsule.labelFor(on: false, liveCount: 1), 'See 1 live');
      expect(
        LiveFirstCapsule.labelFor(on: false, liveCount: 42),
        'See 42 live',
      );
      expect(LiveFirstCapsule.labelFor(on: false), 'See live');
      expect(LiveFirstCapsule.labelFor(on: false, liveCount: 0), 'See live');
      expect(LiveFirstCapsule.labelFor(on: false, liveCount: -2), 'See live');
      // Off reads the same whatever on would do.
      expect(
        LiveFirstCapsule.labelFor(
          on: false,
          liveCount: 3,
          mode: LiveFirstMode.liveOnly,
        ),
        'See 3 live',
      );
    });

    test('on names the order in force: Live first, or Live only', () {
      expect(LiveFirstCapsule.labelFor(on: true, liveCount: 3), 'Live first');
      expect(LiveFirstCapsule.labelFor(on: true), 'Live first');
      expect(
        LiveFirstCapsule.labelFor(
          on: true,
          liveCount: 3,
          mode: LiveFirstMode.liveOnly,
        ),
        'Live only',
      );
      expect(LiveFirstCapsule.onLabelFor(LiveFirstMode.reorder), 'Live first');
      expect(LiveFirstCapsule.onLabelFor(LiveFirstMode.liveOnly), 'Live only');
    });

    test('a huge count is capped so the capsule stays a capsule', () {
      expect(LiveFirstCapsule.countText(999), '999');
      expect(LiveFirstCapsule.countText(1000), '999+');
      expect(
        LiveFirstCapsule.labelFor(on: false, liveCount: 12045),
        'See 999+ live',
      );
    });

    test('no em dash anywhere a reader can see or hear', () {
      final strings = [
        LiveFirstCapsule.onLabel,
        LiveFirstCapsule.liveOnlyLabel,
        LiveFirstCapsule.unknownLabel,
        LiveFirstCapsule.labelFor(on: false, liveCount: 7),
        for (final mode in LiveFirstMode.values)
          for (final on in [false, true])
            for (final count in [null, 1, 5])
              for (final subject in ['games', 'events']) ...[
                LiveFirstCapsule.semanticsLabelFor(
                  on: on,
                  liveCount: count,
                  subject: subject,
                  mode: mode,
                ),
                ?LiveFirstCapsule.semanticsHintFor(
                  on: on,
                  subject: subject,
                  mode: mode,
                ),
              ],
      ];
      for (final s in strings) {
        expect(s.contains('\u2014'), isFalse, reason: s);
        expect(s.contains('\u2013'), isFalse, reason: s);
      }
    });
  });

  group('semantics', () {
    test('say what a tap does, per subject and count', () {
      expect(
        LiveFirstCapsule.semanticsLabelFor(on: false, liveCount: 3),
        'Show the 3 live games first',
      );
      expect(
        LiveFirstCapsule.semanticsLabelFor(on: false, liveCount: 1),
        'Show the live game first',
      );
      expect(
        LiveFirstCapsule.semanticsLabelFor(on: false),
        'Show live games first',
      );
      expect(
        LiveFirstCapsule.semanticsLabelFor(
          on: false,
          liveCount: 4,
          subject: 'events',
        ),
        'Show the 4 live events first',
      );
      expect(
        LiveFirstCapsule.semanticsLabelFor(
          on: false,
          liveCount: 1,
          subject: 'events',
        ),
        'Show the live event first',
      );
      // The real count is read aloud even when the drawn one is capped.
      expect(
        LiveFirstCapsule.semanticsLabelFor(on: false, liveCount: 1200),
        'Show the 1200 live games first',
      );
      expect(
        LiveFirstCapsule.semanticsLabelFor(on: true, liveCount: 3),
        'Live games shown first',
      );
      expect(
        LiveFirstCapsule.semanticsLabelFor(on: true, subject: 'events'),
        'Live events shown first',
      );
      expect(LiveFirstCapsule.semanticsHintFor(on: false), isNull);
      // Nothing was hidden: a tap only puts the usual order back.
      expect(
        LiveFirstCapsule.semanticsHintFor(on: true),
        'Double tap to restore the usual order',
      );
    });

    test('where finished games are hidden, it says so, and how to get them '
        'back', () {
      const only = LiveFirstMode.liveOnly;
      expect(
        LiveFirstCapsule.semanticsLabelFor(on: true, mode: only),
        'Only live games shown',
      );
      expect(
        LiveFirstCapsule.semanticsHintFor(on: true, mode: only),
        'Double tap to show all games',
      );
      expect(
        LiveFirstCapsule.semanticsLabelFor(on: false, liveCount: 3, mode: only),
        'Show only the 3 live games',
      );
      expect(
        LiveFirstCapsule.semanticsLabelFor(on: false, liveCount: 1, mode: only),
        'Show only the live game',
      );
      expect(
        LiveFirstCapsule.semanticsLabelFor(on: false, mode: only),
        'Show only live games',
      );
      expect(LiveFirstCapsule.semanticsHintFor(on: false, mode: only), isNull);
    });

    testWidgets('the node is one toggle button with the right words', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, liveCount: 3);
      expect(
        tester.getSemantics(_capsule),
        isSemantics(
          label: 'Show the 3 live games first',
          isButton: true,
          hasToggledState: true,
          isToggled: false,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(_capsule);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(_capsule),
        isSemantics(
          label: 'Live games shown first',
          hint: 'Double tap to restore the usual order',
          isButton: true,
          hasToggledState: true,
          isToggled: true,
          hasTapAction: true,
        ),
      );
      // The drawn words are not read a second time.
      expect(find.bySemanticsLabel('Live first'), findsNothing);
      handle.dispose();
    });

    testWidgets('events say events', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, liveCount: 4, subject: 'events', on: true);
      expect(
        tester.getSemantics(_capsule),
        isSemantics(
          label: 'Live events shown first',
          hint: 'Double tap to restore the usual order',
          isToggled: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('Live only reads as hiding, on screen and aloud', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, liveCount: 3, mode: LiveFirstMode.liveOnly);
      expect(find.text('See 3 live'), findsOneWidget);
      expect(
        tester.getSemantics(_capsule),
        isSemantics(
          label: 'Show only the 3 live games',
          isButton: true,
          hasToggledState: true,
          isToggled: false,
        ),
      );
      await tester.tap(_capsule);
      await tester.pumpAndSettle();
      expect(find.text('Live only'), findsOneWidget);
      expect(find.text('Live first'), findsNothing);
      expect(
        tester.getSemantics(_capsule),
        isSemantics(
          label: 'Only live games shown',
          hint: 'Double tap to show all games',
          isToggled: true,
        ),
      );
      // It settles at the width of its own words.
      expect(
        tester.getSize(_capsule).width,
        _settledWidth(tester, 'Live only'),
      );
      expect(_opacityOf(tester, _onWords), 1.0);
      handle.dispose();
    });

    testWidgets('a semantic tap toggles it too', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await _pump(tester, onTap: () => taps++);
      tester.semantics.tap(
        find.semantics.byLabel('Show the 3 live games first'),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(taps, 1);
      handle.dispose();
    });
  });

  group('drawn', () {
    testWidgets(
      'off shows a still dot, a verb and the count; on shows Live first',
      (tester) async {
        await _pump(tester, liveCount: 3);
        expect(find.text('See 3 live'), findsOneWidget);
        expect(find.text('Live first'), findsNothing);
        // At rest the label is at full strength: never left half faded.
        expect(
          find.ancestor(of: _offWords, matching: find.byType(Opacity)),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Opacity>(
                find.ancestor(of: _offWords, matching: find.byType(Opacity)),
              )
              .opacity,
          1.0,
        );
        // No tint on the glass while off.
        expect(tester.widget<GlassSurface>(_glass).tint, isNull);

        await _pump(tester, liveCount: 3, on: true);
        expect(find.text('Live first'), findsOneWidget);
        expect(find.text('See 3 live'), findsNothing);
        expect(tester.widget<GlassSurface>(_glass).tint, isNotNull);
      },
    );

    testWidgets('an unknown count reads See live', (tester) async {
      await _pump(tester, liveCount: null);
      expect(find.text('See live'), findsOneWidget);
    });

    testWidgets('the count is set in tabular figures', (tester) async {
      await _pump(tester, liveCount: 18);
      final style = tester.widget<Text>(find.text('See 18 live')).style!;
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    testWidgets('the dot is still: nothing animates at rest', (tester) async {
      await _pump(tester, liveCount: 5);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('it settles at the width of its words', (tester) async {
      await _pump(tester, liveCount: 3);
      expect(
        tester.getSize(_capsule).width,
        _settledWidth(tester, 'See 3 live'),
      );
      expect(
        tester.getSize(_capsule).width,
        greaterThanOrEqualTo(InkFabSize.small.side),
      );
    });

    testWidgets('words and mark sit inside the glass, centred on it', (
      tester,
    ) async {
      for (final on in [false, true]) {
        await _pump(tester, liveCount: 3, on: on);
        final glass = tester.getRect(_glass);
        final words = tester.getRect(on ? _onWords : _offWords);
        expect(words.left, greaterThan(glass.left));
        expect(words.right, lessThanOrEqualTo(glass.right - 12));
        expect(words.top, greaterThanOrEqualTo(glass.top));
        expect(words.bottom, lessThanOrEqualTo(glass.bottom));
        expect(words.center.dy, moreOrLessEquals(glass.center.dy, epsilon: .5));
        final mark = tester.getRect(
          find.descendant(of: _glass, matching: find.byType(CustomPaint)).last,
        );
        expect(mark.center.dy, moreOrLessEquals(glass.center.dy, epsilon: .5));
        expect(mark.left, greaterThan(glass.left + 8));
      }
    });
  });

  group('tap', () {
    testWidgets('toggles, ticks the selection haptic, and springs the width', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pump(tester, liveCount: 3);
      final off = _settledWidth(tester, 'See 3 live');
      final on = _settledWidth(tester, 'Live first');
      expect(on, isNot(off));

      await tester.tap(_capsule);
      expect(
        calls.where(
          (c) =>
              c.method == 'HapticFeedback.vibrate' &&
              c.arguments == 'HapticFeedbackType.selectionClick',
        ),
        hasLength(1),
      );

      // Mid-spring: on the way, not jumped.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      final mid = tester.getSize(_capsule).width;
      expect(mid, isNot(moreOrLessEquals(off)));
      expect(mid, isNot(moreOrLessEquals(on)));

      await tester.pumpAndSettle();
      expect(tester.getSize(_capsule).width, on);
      expect(find.text('Live first'), findsOneWidget);
      expect(find.text('See 3 live'), findsNothing);

      await tester.tap(_capsule);
      await tester.pumpAndSettle();
      expect(tester.getSize(_capsule).width, off);
      expect(find.text('See 3 live'), findsOneWidget);
      expect(find.text('Live first'), findsNothing);
    });

    testWidgets('a new count springs the width too', (tester) async {
      final host = await _pump(tester, liveCount: 9);
      final nine = tester.getSize(_capsule).width;
      host.setCount(120);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      final mid = tester.getSize(_capsule).width;
      await tester.pumpAndSettle();
      final settled = tester.getSize(_capsule).width;
      expect(settled, greaterThan(nine));
      expect(mid, greaterThan(nine));
      expect(mid, lessThan(settled));
      expect(find.text('See 120 live'), findsOneWidget);
      expect(_opacityOf(tester, _offWords), 1.0);
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('words never reach past the glass while it springs, '
          'text at ${scale}x', (tester) async {
        final host = await _pump(tester, liveCount: 9, textScale: scale);

        // A count that gains digits: the new words wait until there is room.
        host.setCount(999);
        await _expectWordsInsideGlassEveryFrame(tester, '9 to 999 at $scale');
        expect(find.text('See 999 live'), findsOneWidget);
        expect(_opacityOf(tester, _offWords), 1.0);
        expect(
          tester.getSize(_capsule).width,
          _settledWidth(tester, 'See 999 live'),
        );

        host.setCount(1000);
        await _expectWordsInsideGlassEveryFrame(
          tester,
          '999 to 999+ at $scale',
        );
        host.setCount(9);
        await _expectWordsInsideGlassEveryFrame(tester, '999+ to 9 at $scale');
        host.setCount(12045);
        await _expectWordsInsideGlassEveryFrame(tester, '9 to 999+ at $scale');
        expect(find.text('See 999+ live'), findsOneWidget);
        expect(_opacityOf(tester, _offWords), 1.0);

        // On and off from the widest count, both ways.
        host.setOn(true);
        await _expectWordsInsideGlassEveryFrame(tester, 'off 999+ to on');
        expect(_opacityOf(tester, _onWords), 1.0);
        host.setOn(false);
        await _expectWordsInsideGlassEveryFrame(tester, 'on to off 999+');
        expect(_opacityOf(tester, _offWords), 1.0);

        // And from the narrowest, with the count unknown.
        host.setCount(null);
        await _expectWordsInsideGlassEveryFrame(tester, '999+ to See live');
        host.setOn(true);
        await _expectWordsInsideGlassEveryFrame(tester, 'See live to on');
        host.setCount(4);
        await _expectWordsInsideGlassEveryFrame(tester, 'count under on');
        host.setOn(false);
        await _expectWordsInsideGlassEveryFrame(tester, 'on to See 4 live');

        // A turn back mid-spring is followed from wherever it is.
        host.setCount(9);
        await tester.pump(const Duration(milliseconds: 16));
        host.setCount(999);
        await tester.pump(const Duration(milliseconds: 16));
        host.setOn(true);
        await _expectWordsInsideGlassEveryFrame(tester, 'interrupted');
        expect(_opacityOf(tester, _onWords), 1.0);
      });
    }

    testWidgets(
      'a count gaining a digit dims only briefly, then reads in full',
      (tester) async {
        final host = await _pump(tester, liveCount: 9);
        host.setCount(10);
        // The frame that draws the change still shows the words, since a digit
        // is narrower than the room the trailing padding keeps.
        await tester.pump();
        expect(_opacityOf(tester, _offWords), greaterThan(0));
        var frames = 1;
        while (_opacityOf(tester, _offWords) < 1 && frames < 30) {
          await tester.pump(const Duration(milliseconds: 16));
          frames++;
        }
        expect(frames, lessThanOrEqualTo(6), reason: 'back in full by ~100ms');
        await tester.pumpAndSettle();
        expect(find.text('See 10 live'), findsOneWidget);
      },
    );

    testWidgets('with reduced motion a new count snaps, words whole at once', (
      tester,
    ) async {
      final host = await _pump(tester, liveCount: 9, reduceMotion: true);
      host.setCount(999);
      await tester.pump();
      expect(
        tester.getSize(_capsule).width,
        _settledWidth(tester, 'See 999 live'),
      );
      expect(_opacityOf(tester, _offWords), 1.0);
      // Nothing moves after the snap.
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.getSize(_capsule).width,
        _settledWidth(tester, 'See 999 live'),
      );
      expect(_opacityOf(tester, _offWords), 1.0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('reduced motion snaps: settled on the very next frame', (
      tester,
    ) async {
      await _pump(tester, liveCount: 3, reduceMotion: true);
      final on = _settledWidth(tester, 'Live first');
      await tester.tap(_capsule);
      await tester.pump();
      expect(tester.getSize(_capsule).width, on);
      expect(find.text('Live first'), findsOneWidget);
      expect(find.text('See 3 live'), findsNothing);
      expect(
        tester
            .widget<Opacity>(
              find.ancestor(of: _onWords, matching: find.byType(Opacity)),
            )
            .opacity,
        1.0,
      );
      // Let the press's minimum hold run out: nothing moves after the snap.
      await tester.pumpAndSettle();
      expect(tester.getSize(_capsule).width, on);
      expect(find.text('Live first'), findsOneWidget);
    });

    testWidgets('a 42pt capsule still answers a 44pt target', (tester) async {
      // A 360x780 phone draws the small floating button at 42.
      var taps = 0;
      await _pump(tester, view: const Size(360, 780), onTap: () => taps++);
      expect(InkFabSize.small.disc, 42);
      expect(tester.getSize(_capsule).height, 44);
      expect(tester.getSize(_glass).height, 42);
      // Half a point outside the glass, still inside the target.
      await tester.tapAt(tester.getTopLeft(_capsule) + const Offset(20, 0.5));
      await tester.pump(const Duration(milliseconds: 100));
      expect(taps, 1);
    });

    testWidgets('the regular size matches the main floating button', (
      tester,
    ) async {
      await _pump(tester, size: InkFabSize.regular);
      expect(tester.getSize(_glass).height, InkFabSize.regular.disc);
      expect(tester.getSize(_capsule).height, InkFabSize.regular.side);
    });
  });

  group('contrast', () {
    // The glass's plate over what floats under it: the page and its cards.
    List<Color> backdrops(BuildContext context, Color? tint) {
      final colors = context.colors;
      var plate = GlassStyle.of(context).plate;
      if (tint != null) plate = Color.alphaBlend(tint, plate);
      return [
        Color.alphaBlend(plate, colors.background),
        Color.alphaBlend(plate, colors.surface),
      ];
    }

    for (final light in [false, true]) {
      final name = light ? 'light' : 'dark';
      testWidgets('words clear AA and the mark clears 3:1 in $name', (
        tester,
      ) async {
        final theme = light ? AppTheme.lightTheme : AppTheme.darkTheme;
        for (final on in [false, true]) {
          await _pump(tester, liveCount: 3, on: on, theme: theme);
          final context = tester.element(_capsule);
          final tint = tester.widget<GlassSurface>(_glass).tint;
          final words = tester.widget<Text>(on ? _onWords : _offWords);
          for (final backdrop in backdrops(context, tint)) {
            expect(
              wcagContrast(words.style!.color!, backdrop),
              greaterThanOrEqualTo(4.5),
              reason: '$name, on: $on, words',
            );
            expect(
              wcagContrast(context.colors.accentText, backdrop),
              greaterThanOrEqualTo(3),
              reason: '$name, on: $on, mark',
            );
          }
        }
      });
    }
  });
}
