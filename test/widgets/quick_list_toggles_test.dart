import 'dart:ui' show Tristate;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/quick_list_toggles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool light = false,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(body: Center(child: child));
        },
      ),
    ),
  );
}

SemanticsData _semantics(WidgetTester tester, String label) =>
    tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();

void main() {
  group('QuickToggleIconButton semantics', () {
    testWidgets('an enabled glyph offers its tap to assistive tech', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await _pump(
        tester,
        QuickToggleIconButton(
          label: 'Filters',
          onTap: () => taps++,
          child: const Icon(Icons.tune_rounded),
        ),
      );

      final data = _semantics(tester, 'Filters');
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);

      tester.semantics.tap(find.semantics.byLabel('Filters'));
      expect(taps, 1);
      semantics.dispose();
    });

    testWidgets('a disabled glyph offers no tap', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        const QuickToggleIconButton(
          label: 'Filters',
          onTap: null,
          child: Icon(Icons.tune_rounded),
        ),
      );

      final data = _semantics(tester, 'Filters');
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      semantics.dispose();
    });
  });

  for (final light in [false, true]) {
    testWidgets(
      'quick filters share toolbar ink in ${light ? 'light' : 'dark'} mode',
      (tester) async {
        var pressed = false;
        await _pump(
          tester,
          StatefulBuilder(
            builder: (context, setState) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClassicalToggleButton(
                  pressed: pressed,
                  onTap: () => setState(() => pressed = !pressed),
                ),
                QuickToggleIconButton(
                  label: 'Filters',
                  selected: pressed,
                  onTap: () {},
                  child: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
          ),
          light: light,
        );

        final classical = find.byType(ClassicalToggleButton);
        final owl = find.byType(SvgPicture);
        final filter = find.byIcon(Icons.tune_rounded);
        final colors = tester.element(filter).colors;

        void expectInk(Color ink) {
          expect(
            tester.widget<SvgPicture>(owl).colorFilter,
            ColorFilter.mode(ink, BlendMode.srcIn),
          );
          expect(IconTheme.of(tester.element(filter)).color, ink);
        }

        expect(tester.getSize(classical), const Size.square(44));
        expect(tester.getSize(owl), tester.getSize(filter));
        expect(tester.getCenter(owl), tester.getCenter(classical));
        expectInk(colors.iconPrimary);

        await tester.tap(classical);
        await tester.pump();
        expectInk(colors.accentText);
      },
    );
  }

  group('BoardViewToggleButton', () {
    testWidgets('draws the board mark at an icon\'s optical size', (
      tester,
    ) async {
      var taps = 0;
      await _pump(tester, BoardViewToggleButton(onTap: () => taps++));

      final box = tester.getSize(find.byType(BoardViewGlyph));
      final svg = tester.getSize(find.byType(SvgPicture));
      expect(box.width, box.height);
      // A Material icon's ink keeps to the middle 20 of its 24 units.
      expect(svg.width, closeTo(box.width * 20 / 24, 0.01));
      expect(svg.height, closeTo(box.height * 20 / 24, 0.01));
      // Centred in its box.
      expect(
        tester.getCenter(find.byType(SvgPicture)),
        tester.getCenter(find.byType(BoardViewGlyph)),
      );

      expect(find.byTooltip(BoardViewToggleButton.label), findsOneWidget);
      expect(BoardViewToggleButton.label, 'Change board view');
      await tester.tap(find.byType(BoardViewToggleButton));
      expect(taps, 1);
    });
  });
}
