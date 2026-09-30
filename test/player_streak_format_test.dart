import 'dart:io';

import 'package:chessever2/screens/streaks/widgets/player_streak_format.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _tnum = FontFeature.tabularFigures();

/// The test font has no tabular set; Inter's is what the page ships.
Future<void> _loadInter() async {
  final loader = FontLoader('InterDisplay');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    final bytes = File('assets/fonts/Inter-$weight.otf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// Runs [body] with a laid-out context so `.f` and the theme resolve.
Future<void> _withContext(
  WidgetTester tester,
  void Function(BuildContext context) body,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          body(context);
          return const SizedBox();
        },
      ),
    ),
  );
}

double _width(InlineSpan span) {
  final painter = TextPainter(text: span, textDirection: TextDirection.ltr)
    ..layout();
  final w = painter.width;
  painter.dispose();
  return w;
}

void main() {
  setUpAll(_loadInter);

  group('streakFigures', () {
    test('puts the tabular feature on digit runs only', () {
      final span = streakFigures('GM · 2733 · China · 33 y');
      final parts = [
        for (final c in span.children!) c as TextSpan,
      ];
      expect([for (final p in parts) p.text], [
        'GM · ',
        '2733',
        ' · China · ',
        '33',
        ' y',
      ]);
      for (final p in parts) {
        final figure = RegExp(r'^\d+$').hasMatch(p.text!);
        expect(
          p.style?.fontFeatures,
          figure ? [_tnum] : isNull,
          reason: '"${p.text}"',
        );
      }
      expect(span.toPlainText(), 'GM · 2733 · China · 33 y');
    });

    test('keeps words whole and carries the given style', () {
      const ink = TextStyle(color: Color(0xFF123456));
      final words = streakFigures('No games', style: ink);
      expect(words.text, 'No games');
      expect(words.children, isNull);
      expect(words.style, ink);

      final figure = streakFigures('  2754', style: ink);
      expect(figure.style, ink);
      expect(figure.toPlainText(), '  2754');
      final parts = [for (final c in figure.children!) c as TextSpan];
      expect(parts.first.style, isNull);
      expect(parts.last.style?.fontFeatures, [_tnum]);
    });
  });

  testWidgets('streakText is proportional unless a figure opts in', (
    tester,
  ) async {
    await _withContext(tester, (context) {
      final words = streakText(context, size: 14, line: 18);
      final figures = streakText(context, size: 14, line: 18, tabular: true);
      expect(words.fontFeatures, isNull);
      expect(figures.fontFeatures, [_tnum]);
      // The display numerals stay tabular.
      expect(streakDisplay(context, size: 104).fontFeatures, [_tnum]);
    });
  });

  testWidgets('a hyphenated name keeps its natural hyphen, and a mixed line '
      'keeps its figures at tabular width', (tester) async {
    await _withContext(tester, (context) {
      final words = streakText(context, size: 14, line: 18);
      final whole = streakText(context, size: 14, line: 18, tabular: true);

      // Inter's tabular set widens the hyphen; names must not get it.
      const name = 'Maxime Vachier-Lagrave';
      expect(
        _width(TextSpan(text: name, style: words)),
        lessThan(_width(TextSpan(text: name, style: whole)) - 1),
      );

      // Mixed line: the figures measure exactly as tabular figures do, the
      // rest exactly as proportional text does.
      const line = 'GM · 2711 · China · 34 y';
      final mixed = _width(streakFigures(line, style: words));
      final expected =
          _width(TextSpan(text: 'GM · ', style: words)) +
          _width(TextSpan(text: '2711', style: whole)) +
          _width(TextSpan(text: ' · China · ', style: words)) +
          _width(TextSpan(text: '34', style: whole)) +
          _width(TextSpan(text: ' y', style: words));
      expect(mixed, moreOrLessEquals(expected, epsilon: 0.5));
      // "2711" and "2000" hold one width, so a changing figure never
      // shifts its neighbours.
      expect(
        _width(streakFigures('2711', style: words)),
        moreOrLessEquals(
          _width(streakFigures('2000', style: words)),
          epsilon: 0.01,
        ),
      );
    });
  });
}
