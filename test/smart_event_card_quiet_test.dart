import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/smart_event_card.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _accent = Color(0xFFA3E635);

Future<void> _pump(
  WidgetTester tester, {
  required bool quiet,
  ThemeData? theme,
  int minElo = 2500,
  Set<String> formats = const {'standard', 'rapid'},
  bool live = false,
  String? summary = 'Game average 2500+, classical or rapid',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: SmartEventCard(
              tierLabel: 'GM',
              minElo: minElo,
              liveCount: 3,
              avgElo: 2728,
              accentColor: _accent,
              quiet: quiet,
              formatsAndStates: formats,
              summary: summary,
              live: live,
              onTap: () {},
            ),
          );
        },
      ),
    ),
  );
}

Iterable<Decoration> _decorations(WidgetTester tester) sync* {
  for (final e
      in find
          .descendant(
            of: find.byType(SmartEventCard),
            matching: find.byType(Container),
          )
          .evaluate()) {
    final decoration = (e.widget as Container).decoration;
    if (decoration != null) yield decoration;
  }
}

bool _isAccent(Color c) => c.toARGB32() | 0xFF000000 == _accent.toARGB32();

void main() {
  for (final quiet in [true, false]) {
    testWidgets('fully there on its first frame (quiet: $quiet)', (
      tester,
    ) async {
      await _pump(tester, quiet: quiet);

      final faded = find.descendant(
        of: find.byType(SmartEventCard),
        matching: find.byWidgetPredicate(
          (w) =>
              (w is Opacity && w.opacity < 1) ||
              (w is FadeTransition && w.opacity.value < 1),
        ),
      );
      expect(faded, findsNothing);
      expect(find.text('GM Games'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
    testWidgets('no hue anywhere: no accent fill, edge or bloom '
        '(${theme.brightness.name})', (tester) async {
      await _pump(tester, quiet: false, theme: theme);
      for (final d in _decorations(tester)) {
        if (d is! BoxDecoration) continue;
        if (d.color case final c?) expect(_isAccent(c), isFalse);
        final border = d.border;
        if (border is Border) expect(_isAccent(border.top.color), isFalse);
        for (final s in d.boxShadow ?? const <BoxShadow>[]) {
          expect(_isAccent(s.color), isFalse);
        }
      }
      expect(find.byType(CustomPaint).evaluate().where((e) {
        final w = e.widget as CustomPaint;
        return w.painter != null &&
            w.painter.runtimeType.toString().contains('Facet');
      }), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the plate shows the combination as the builder draws it', (
    tester,
  ) async {
    await _pump(tester, quiet: true);
    expect(
      find.descendant(
        of: find.byType(SmartEventPlate),
        matching: find.text('GM'),
      ),
      findsOneWidget,
    );
    expect(find.text('2500+'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SmartEventPlate),
        matching: find.byType(TimeControlGlyph),
      ),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('3 events', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Ø 2728', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Game average 2500+, classical or rapid'), findsOneWidget);
  });

  testWidgets('a floor off the tiers reads alone; nothing picked reads as '
      'the boards glyph', (tester) async {
    await _pump(tester, quiet: true, minElo: 2700, formats: const {});
    expect(find.text('2700+'), findsOneWidget);
    expect(find.byType(TimeControlGlyph), findsNothing);

    await _pump(tester, quiet: true, minElo: 0, formats: const {});
    expect(find.text('2700+'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SmartEventPlate),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
  });

  testWidgets('a live member event reads LIVE, as an event card does', (
    tester,
  ) async {
    await _pump(tester, quiet: true, live: true);
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('Game average 2500+, classical or rapid'), findsNothing);
  });
}
