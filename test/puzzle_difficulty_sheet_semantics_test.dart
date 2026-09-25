import 'package:chessever2/screens/feed/puzzles/puzzle_difficulty_sheet.dart';
import 'package:chessever2/screens/feed/race/puzzle_rating_range.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// The difficulty sheet to a screen reader: the presets are one group with
/// one pick, Custom says whether its wheels are open, and each wheel has a
/// name and moves a step at a time.
void main() {
  SemanticsNode node(WidgetTester tester, String key) =>
      tester.getSemantics(find.byKey(ValueKey('puzzle_difficulty_$key')));

  testWidgets('a preset reads as the pick of a group, Custom as shut', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, PuzzleRatingPreset.strong.range, (_) {});

    expect(
      node(tester, 'strong'),
      isSemantics(
        label: 'Strong, 1500–2000',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
      ),
    );
    expect(
      node(tester, 'club'),
      isSemantics(
        label: 'Club, 1000–1500',
        hasSelectedState: true,
        isSelected: false,
        isInMutuallyExclusiveGroup: true,
      ),
    );
    expect(
      node(tester, 'custom'),
      isSemantics(
        label: 'Custom',
        isSelected: false,
        hasExpandedState: true,
        isExpanded: false,
      ),
    );
    // Folded away, the wheels are not there to find.
    expect(find.bySemanticsLabel('Lowest rating'), findsNothing);
    expect(find.bySemanticsLabel('Highest rating'), findsNothing);

    final custom = node(tester, 'custom');
    custom.owner!.performAction(custom.id, SemanticsAction.tap);
    await _settle(tester);
    expect(
      node(tester, 'custom'),
      isSemantics(hasExpandedState: true, isExpanded: true),
    );
    expect(find.bySemanticsLabel('Lowest rating'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('each wheel is named and adjusts a step, keeping the span', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final applied = <PuzzleRatingRange>[];
    await _pump(tester, const PuzzleRatingRange(1200, 1400), applied.add);

    expect(
      node(tester, 'custom'),
      isSemantics(
        label: 'Custom, 1200–1400',
        isSelected: true,
        hasExpandedState: true,
        isExpanded: true,
      ),
    );
    expect(
      node(tester, 'lowest'),
      isSemantics(
        label: 'Lowest rating',
        value: '1200',
        increasedValue: '1250',
        decreasedValue: '1150',
        isSlider: true,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );
    expect(
      node(tester, 'highest'),
      isSemantics(
        label: 'Highest rating',
        value: '1400',
        increasedValue: '1450',
        decreasedValue: '1350',
        isSlider: true,
      ),
    );

    // Raising the low end past the minimum span carries the high end along.
    final lowest = node(tester, 'lowest');
    lowest.owner!.performAction(lowest.id, SemanticsAction.increase);
    await _settle(tester);
    expect(applied.last, const PuzzleRatingRange(1250, 1450));

    // Lowering the high end does the same the other way.
    final highest = node(tester, 'highest');
    highest.owner!.performAction(highest.id, SemanticsAction.decrease);
    await _settle(tester);
    expect(applied.last, const PuzzleRatingRange(1200, 1400));
    expect(node(tester, 'lowest'), isSemantics(value: '1200'));
    handle.dispose();
  });

  testWidgets('the stand-in nodes leave the wheels their touches', (
    tester,
  ) async {
    final applied = <PuzzleRatingRange>[];
    await _pump(tester, const PuzzleRatingRange(1200, 1400), applied.add);
    await tester.drag(
      find.byType(ListWheelScrollView).first,
      const Offset(0, -80),
    );
    await _settle(tester);
    expect(applied, isNotEmpty);
    expect(applied.last.min, greaterThan(1200));
  });

  testWidgets('a wheel at its end offers no step past it', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const PuzzleRatingRange(kPuzzleRatingFloor, kPuzzleRatingCeiling),
      (_) {},
    );
    expect(
      node(tester, 'lowest'),
      isSemantics(hasDecreaseAction: false, hasIncreaseAction: true),
    );
    expect(
      node(tester, 'highest'),
      isSemantics(hasIncreaseAction: false, hasDecreaseAction: true),
    );
    handle.dispose();
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(
  WidgetTester tester,
  PuzzleRatingRange initial,
  ValueChanged<PuzzleRatingRange> onCustom,
) async {
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(393, 852)),
      child: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: PuzzleDifficultySheet(
            initial: initial,
            onPreset: (_) {},
            onCustom: onCustom,
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}
