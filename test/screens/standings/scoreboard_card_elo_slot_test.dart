import 'package:chessever2/screens/standings/widget/scoreboard_card_widget.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Regression: when a matchup has no Elo change, the scorecard row must still
/// reserve the Elo-change column so the result badge lines up with sibling rows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpRows(
    WidgetTester tester, {
    required List<double?> scoreChanges,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: Column(
                  children: [
                    for (var i = 0; i < scoreChanges.length; i++)
                      ScoreboardCardWidget(
                        key: ValueKey('row-$i'),
                        countryCode: 'IND',
                        title: 'GM',
                        name: i == 0 ? 'Nihal Sarin' : 'Opponent $i',
                        score: 2650 + i,
                        scoreChange: scoreChanges[i],
                        matchScore: i == 0 ? '½' : '1',
                        isWhite: true,
                        index: i,
                        isFirst: i == 0,
                        isLast: i == scoreChanges.length - 1,
                        onTap: () {},
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Offset matchBadgeTopLeft(WidgetTester tester, int rowIndex) {
    final row = find.byKey(ValueKey('row-$rowIndex'));
    expect(row, findsOneWidget);
    // Result is a circular Container holding the match score text.
    final badgeText = find.descendant(
      of: row,
      matching: find.text(rowIndex == 0 ? '½' : '1'),
    );
    expect(badgeText, findsOneWidget);
    return tester.getTopLeft(badgeText);
  }

  testWidgets(
    'null scoreChange still reserves Elo slot so result badge aligns',
    (tester) async {
      await pumpRows(
        tester,
        scoreChanges: [null, 2.0],
      );

      final nullChangeBadge = matchBadgeTopLeft(tester, 0);
      final withChangeBadge = matchBadgeTopLeft(tester, 1);

      expect(
        nullChangeBadge.dx,
        closeTo(withChangeBadge.dx, 0.5),
        reason:
            'Result badges must share an x column when Elo change is absent',
      );
    },
  );

  testWidgets(
    'zero scoreChange still reserves Elo slot so result badge aligns',
    (tester) async {
      await pumpRows(
        tester,
        scoreChanges: [0.0, -3.0],
      );

      final zeroChangeBadge = matchBadgeTopLeft(tester, 0);
      final withChangeBadge = matchBadgeTopLeft(tester, 1);

      expect(
        zeroChangeBadge.dx,
        closeTo(withChangeBadge.dx, 0.5),
        reason:
            'Result badges must share an x column when Elo change is zero',
      );
    },
  );

  testWidgets(
    'non-zero scoreChange still paints signed change text in the slot',
    (tester) async {
      await pumpRows(
        tester,
        scoreChanges: [5.0, -2.0],
      );

      expect(find.text('+5'), findsOneWidget);
      expect(find.text('-2'), findsOneWidget);
      // Empty/null slot must not invent a zero label.
      expect(find.text('+0'), findsNothing);
      expect(find.text('0'), findsNothing);
    },
  );

  testWidgets(
    'null scoreChange paints no change text',
    (tester) async {
      await pumpRows(
        tester,
        scoreChanges: [null],
      );

      expect(find.text('+0'), findsNothing);
      expect(find.text('-0'), findsNothing);
      // Rating number is still shown.
      expect(find.text('2650'), findsOneWidget);
      expect(find.text('½'), findsOneWidget);
    },
  );
}
