import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/live_first_capsule.dart';
import 'package:chessever2/widgets/live_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The page around one button: what it passes in, changeable mid-test the
/// way a page's live count and Live first state change under it.
class _Host {
  _Host(this.on, this.liveCount);

  bool on;
  int? liveCount;
  late StateSetter _setState;

  void setOn(bool value) => _setState(() => on = value);

  void setCount(int? value) => _setState(() => liveCount = value);
}

/// Hosts one button. When [onTap] is null the button toggles itself, the
/// way a page wires it to its Live first state.
Future<_Host> _pump(
  WidgetTester tester, {
  bool on = false,
  int? liveCount = 3,
  String subject = 'games',
  ThemeData? theme,
  bool reduceMotion = false,
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
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
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

Finder get _button => find.byType(LiveFirstCapsule);
Finder get _glass =>
    find.descendant(of: _button, matching: find.byType(GlassSurface));
Finder get _glyph =>
    find.descendant(of: _button, matching: find.byType(LiveGlyph));

LiveGlyph _glyphOf(WidgetTester tester) => tester.widget<LiveGlyph>(_glyph);

/// Nothing of the button is set in type: no count, no label.
void _expectNoWords(WidgetTester tester) {
  expect(
    find.descendant(of: _button, matching: find.byType(Text)),
    findsNothing,
  );
  expect(
    find.descendant(of: _button, matching: find.byType(RichText)),
    findsNothing,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what it says', () {
    test('off, what a tap does, per subject and count', () {
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
        LiveFirstCapsule.semanticsLabelFor(on: false, liveCount: 0),
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
      // The real count, however large: nothing is drawn, so nothing caps it.
      expect(
        LiveFirstCapsule.semanticsLabelFor(on: false, liveCount: 1200),
        'Show the 1200 live games first',
      );
    });

    test('on, what is in force, and how to undo it', () {
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

    test('no em dash anywhere a reader can hear', () {
      final strings = [
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
        expect(s.contains('—'), isFalse, reason: s);
        expect(s.contains('–'), isFalse, reason: s);
      }
    });
  });

  group('semantics and tooltip', () {
    testWidgets('one toggle button with the right words, the tooltip saying '
        'the same', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, liveCount: 3);
      expect(
        tester.getSemantics(_button),
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
      expect(find.byTooltip('Show the 3 live games first'), findsOneWidget);

      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(_button),
        isSemantics(
          label: 'Live games shown first',
          hint: 'Double tap to restore the usual order',
          isButton: true,
          hasToggledState: true,
          isToggled: true,
          hasTapAction: true,
        ),
      );
      expect(find.byTooltip('Live games shown first'), findsOneWidget);
      // The tooltip is not read a second time.
      expect(
        find.bySemanticsLabel('Show the 3 live games first'),
        findsNothing,
      );
      handle.dispose();
    });

    testWidgets('a new count is read and shown, never drawn', (tester) async {
      final handle = tester.ensureSemantics();
      final host = await _pump(tester, liveCount: 9);
      final size = tester.getSize(_glass);
      host.setCount(1200);
      await tester.pump();
      expect(
        tester.getSemantics(_button),
        isSemantics(label: 'Show the 1200 live games first'),
      );
      expect(find.byTooltip('Show the 1200 live games first'), findsOneWidget);
      // The disc does not change for a number.
      expect(tester.getSize(_glass), size);
      expect(tester.binding.hasScheduledFrame, isFalse);
      _expectNoWords(tester);
      handle.dispose();
    });

    testWidgets('events say events', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, liveCount: 4, subject: 'events', on: true);
      expect(
        tester.getSemantics(_button),
        isSemantics(
          label: 'Live events shown first',
          hint: 'Double tap to restore the usual order',
          isToggled: true,
        ),
      );
      expect(find.byTooltip('Live events shown first'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('Live only reads as hiding', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, liveCount: 3, mode: LiveFirstMode.liveOnly);
      expect(
        tester.getSemantics(_button),
        isSemantics(
          label: 'Show only the 3 live games',
          isButton: true,
          hasToggledState: true,
          isToggled: false,
        ),
      );
      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(_button),
        isSemantics(
          label: 'Only live games shown',
          hint: 'Double tap to show all games',
          isToggled: true,
        ),
      );
      expect(find.byTooltip('Only live games shown'), findsOneWidget);
      _expectNoWords(tester);
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
    testWidgets('icon only: no count and no words, on or off, known or not', (
      tester,
    ) async {
      for (final on in [false, true]) {
        for (final count in [null, 0, 1, 11, 1200]) {
          await _pump(tester, on: on, liveCount: count);
          expect(_glyph, findsOneWidget);
          _expectNoWords(tester);
          expect(find.textContaining('live'), findsNothing);
          if (count != null) {
            expect(find.textContaining('$count'), findsNothing);
          }
        }
      }
    });

    testWidgets('off: arcs in the glass ink, the dot in the live colour, '
        'clear glass', (tester) async {
      await _pump(tester, liveCount: 3);
      final context = tester.element(_button);
      final glyph = _glyphOf(tester);
      expect(glyph.key, LiveFirstCapsule.offGlyphKey);
      expect(glyph.waveColor, GlassStyle.of(context).ink);
      expect(glyph.dotColor, context.colors.accentText);
      expect(glyph.spread, 0);
      expect(tester.widget<GlassSurface>(_glass).tint, isNull);
    });

    testWidgets('on: the glass takes the tonal blue and the whole mark '
        'wears it', (tester) async {
      await _pump(tester, liveCount: 3, on: true);
      final context = tester.element(_button);
      final accent = context.colors.accentText;
      final glyph = _glyphOf(tester);
      expect(glyph.key, LiveFirstCapsule.onGlyphKey);
      expect(glyph.waveColor, accent);
      expect(glyph.dotColor, accent);
      expect(glyph.spread, moreOrLessEquals(0, epsilon: 1e-9));
      expect(
        tester.widget<GlassSurface>(_glass).tint,
        accent.withValues(alpha: LiveFirstCapsule.onTintAlpha),
      );
    });

    testWidgets('still at rest: no pulse, nothing animates', (tester) async {
      await _pump(tester, liveCount: 5);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await _pump(tester, liveCount: 5, on: true);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    for (final size in InkFabSize.values) {
      testWidgets('the ${size.name} disc is the floating button\'s, the mark '
          'at its share and dead centre', (tester) async {
        await _pump(tester, size: size);
        expect(tester.getSize(_glass), Size.square(size.disc));
        expect(tester.getSize(_button), Size.square(size.side));
        final glyph = tester.getRect(_glyph);
        expect(
          glyph.width,
          moreOrLessEquals(size.disc * InkFab.glyphFraction, epsilon: 1e-6),
        );
        expect(glyph.height, moreOrLessEquals(glyph.width, epsilon: 1e-6));
        final glass = tester.getRect(_glass);
        expect(
          glyph.center.dx,
          moreOrLessEquals(glass.center.dx, epsilon: 1e-6),
        );
        expect(
          glyph.center.dy,
          moreOrLessEquals(glass.center.dy, epsilon: 1e-6),
        );
      });
    }

    test('the mark is symmetric and stays inside its grid', () {
      const half = LiveGlyphPainter.grid / 2;
      const rim = LiveGlyphPainter.outerRadius + LiveGlyphPainter.stroke / 2;
      expect(rim, lessThan(half));
      expect(
        rim + LiveGlyphPainter.outerPush,
        lessThan(half + 0.5),
        reason: 'the push stays well inside the disc',
      );
      // Dot, gap, arc, gap, arc: the two gaps are equal.
      const innerGap =
          LiveGlyphPainter.innerRadius -
          LiveGlyphPainter.stroke / 2 -
          LiveGlyphPainter.dotRadius;
      const outerGap =
          LiveGlyphPainter.outerRadius -
          LiveGlyphPainter.innerRadius -
          LiveGlyphPainter.stroke;
      expect(innerGap, moreOrLessEquals(outerGap));
      expect(innerGap, greaterThan(0));
    });
  });

  group('tap', () {
    testWidgets('toggles, ticks the selection haptic, and springs the colour', (
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
      final host = await _pump(tester, liveCount: 3);
      final context = tester.element(_button);
      final ink = GlassStyle.of(context).ink;
      final accent = context.colors.accentText;
      final disc = tester.getSize(_glass);

      await tester.tap(_button);
      expect(host.on, isTrue);
      expect(
        calls.where(
          (c) =>
              c.method == 'HapticFeedback.vibrate' &&
              c.arguments == 'HapticFeedbackType.selectionClick',
        ),
        hasLength(1),
      );

      // Mid-spring: on the way, not jumped, and the arcs out a little.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final mid = _glyphOf(tester);
      expect(mid.waveColor, isNot(ink));
      expect(mid.waveColor, isNot(accent));
      expect(mid.spread, greaterThan(0));
      expect(tester.widget<GlassSurface>(_glass).tint, isNotNull);

      await tester.pumpAndSettle();
      expect(_glyphOf(tester).waveColor, accent);
      expect(_glyphOf(tester).spread, moreOrLessEquals(0, epsilon: 1e-9));
      // The disc never changes size for its state.
      expect(tester.getSize(_glass), disc);

      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(host.on, isFalse);
      expect(_glyphOf(tester).waveColor, ink);
      expect(_glyphOf(tester).spread, 0);
      expect(tester.widget<GlassSurface>(_glass).tint, isNull);
    });

    testWidgets('reduced motion snaps: settled on the very next frame', (
      tester,
    ) async {
      await _pump(tester, liveCount: 3, reduceMotion: true);
      final accent = tester.element(_button).colors.accentText;
      await tester.tap(_button);
      await tester.pump();
      expect(_glyphOf(tester).waveColor, accent);
      expect(_glyphOf(tester).spread, moreOrLessEquals(0, epsilon: 1e-9));
      expect(
        tester.widget<GlassSurface>(_glass).tint,
        accent.withValues(alpha: LiveFirstCapsule.onTintAlpha),
      );
      // Let the press's minimum hold run out: nothing moves after the snap.
      await tester.pumpAndSettle();
      expect(_glyphOf(tester).waveColor, accent);
    });

    testWidgets('a 42pt disc still answers a 44pt target', (tester) async {
      // A 360x780 phone draws the small floating button at 42.
      var taps = 0;
      await _pump(tester, view: const Size(360, 780), onTap: () => taps++);
      expect(InkFabSize.small.disc, 42);
      expect(tester.getSize(_button), const Size.square(44));
      expect(tester.getSize(_glass), const Size.square(42));
      // Half a point outside the glass, still inside the target.
      await tester.tapAt(tester.getTopLeft(_button) + const Offset(22, 0.5));
      await tester.pump(const Duration(milliseconds: 100));
      expect(taps, 1);
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
      testWidgets('the arcs and the dot clear 3:1 in $name, off and on', (
        tester,
      ) async {
        final theme = light ? AppTheme.lightTheme : AppTheme.darkTheme;
        for (final on in [false, true]) {
          await _pump(tester, liveCount: 3, on: on, theme: theme);
          final context = tester.element(_button);
          final tint = tester.widget<GlassSurface>(_glass).tint;
          final glyph = _glyphOf(tester);
          for (final backdrop in backdrops(context, tint)) {
            expect(
              wcagContrast(glyph.waveColor, backdrop),
              greaterThanOrEqualTo(3),
              reason: '$name, on: $on, arcs',
            );
            expect(
              wcagContrast(glyph.dotColor, backdrop),
              greaterThanOrEqualTo(3),
              reason: '$name, on: $on, dot',
            );
          }
        }
      });
    }
  });
}
