import 'dart:ui' show Tristate;

import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/quick_list_toggles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
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
