// Details of the anchored glass that are easy to lose: the add button's
// pointer is one piece with its panel (soft joins, no notch, kept off the
// panel's rounded corners), a dropdown's scrollbar thumb is never sliced by
// the panel's rounded corners, and a dropdown dims the page with the one
// anchored dim (the chip panels, the popover, the tag picker and the game
// switcher are held to it in their own tests).
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/glass_anchored_route.dart';
import 'package:chessever2/widgets/glass_dropdown.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the popover pointer', () {
    const pointer = PopupGlassPointer(width: 18, height: 9, tipX: 208);
    const size = Size(236, 160);
    final radius = BorderRadius.circular(16);
    final outline = pointer.silhouette(size, radius);
    const bottom = 160.0 - 9;

    test('is one outline with the panel: no gap at the base', () {
      // Just below the bottom edge, across the pointer's base and its
      // flares: inside, so the rim and the frost run through unbroken.
      for (var x = 208.0 - 9 + 0.5; x <= 208 + 9 - 0.5; x += 1) {
        expect(
          outline.contains(Offset(x, bottom + 0.25)),
          isTrue,
          reason: '$x',
        );
      }
      // Beside the flares, below the edge: outside.
      expect(outline.contains(Offset(208 - 9 - 3 - 1, bottom + 0.5)), isFalse);
      expect(outline.contains(Offset(208 + 9 + 3 + 1, bottom + 0.5)), isFalse);
    });

    test('meets the edge in a soft fillet, and its tip is rounded off', () {
      // The fillet fills the corner where a hard join would leave a notch:
      // a hair outside the straight side, at the base.
      expect(
        outline.contains(const Offset(208 - 9 - 1, bottom + 0.15)),
        isTrue,
      );
      expect(
        outline.contains(const Offset(208 + 9 + 1, bottom + 0.15)),
        isTrue,
      );
      // The tip still points at the button, rounded a little short of a
      // needle point.
      expect(outline.contains(const Offset(208, 160 - 1.2)), isTrue);
      expect(outline.contains(const Offset(208, 160 - 0.05)), isFalse);
      final bounds = outline.getBounds();
      expect(bounds.bottom, lessThanOrEqualTo(160));
      expect(bounds.bottom, greaterThan(160 - 1.5));
    });

    test('keeps its flares off the rounded corners', () {
      // A tip so close to the corner that a full flare would run into the
      // curve: the flare gives way, the corner keeps its round.
      const tight = PopupGlassPointer(width: 18, height: 9, tipX: 236 - 25);
      final path = tight.silhouette(size, radius);
      // On the corner's curve, just outside it: still outside.
      final corner = Offset(236 - 16 + 16 * 0.7071, bottom - 16 + 16 * 0.7071);
      expect(path.contains(corner + const Offset(0.6, 0.6)), isFalse);
      expect(path.contains(corner - const Offset(1, 1)), isTrue);
    });
  });

  testWidgets('a dropdown scrollbar sits inside the rim, clear of the '
      'rounded corners, with round caps', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(393, 852) * 3;
    addTearDown(tester.view.reset);
    final radius = BorderRadius.circular(20);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Padding(
                padding: const EdgeInsets.only(top: 80, left: 16, right: 16),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: GlassDropdown<int>(
                    value: 0,
                    isExpanded: true,
                    menuMaxHeight: 300,
                    borderRadius: radius,
                    onChanged: (_) {},
                    items: [
                      for (var i = 0; i < 30; i++)
                        DropdownMenuItem(value: i, child: Text('Round $i')),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.byType(GlassDropdown<int>));
    await tester.pumpAndSettle();

    final scrollbar = tester.widget<RawScrollbar>(find.byType(RawScrollbar));
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.mainAxisMargin, greaterThanOrEqualTo(radius.topRight.y));
    expect(scrollbar.crossAxisMargin, greaterThan(0));
    expect(scrollbar.radius, isNotNull);
    expect(scrollbar.radius!.x, closeTo((scrollbar.thickness ?? 0) / 2, 0.01));
    // A quiet tonal thumb, not a bright bar.
    expect(scrollbar.thumbColor!.a, lessThan(0.4));
  });

  for (final light in [false, true]) {
    testWidgets('a dropdown dims with the one anchored dim '
        '(${light ? 'light' : 'dark'})', (tester) async {
      final theme = light ? AppTheme.lightTheme : AppTheme.darkTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: Center(
                  child: GlassDropdown<int>(
                    value: 0,
                    onChanged: (_) {},
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('One')),
                      DropdownMenuItem(value: 1, child: Text('Two')),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.byType(GlassDropdown<int>));
      await tester.pumpAndSettle();
      final context = tester.element(find.text('Two').last);
      final dim = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<GlassScrimPainter>()
          .single;
      expect(dim.color, AnchoredGlassDim.colorOf(context));
      // One strength per theme, the scrim's own colour.
      expect(
        dim.color.a,
        closeTo(light ? AnchoredGlassDim.light : AnchoredGlassDim.dark, 0.001),
      );
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
    });
  }
}
