import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/library/widgets/miniatures_filter_dialog.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MiniaturesFilterHarness extends StatelessWidget {
  const _MiniaturesFilterHarness();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return const Scaffold(
            body: Center(
              child: MiniaturesFilterDialog(
                initialFilter: MiniatureGamesFilter(),
              ),
            ),
          );
        },
      ),
    );
  }
}

void main() {
  test('sort does not count as an active Miniatures dialog filter', () {
    const filter = MiniatureGamesFilter(sort: MiniatureGamesSort.rating);

    expect(filter.dialogActiveCount, 0);
  });

  test('single opening input maps ECO codes and opening names', () {
    final eco = MiniatureOpeningFilterInput.parse(' b90 ');
    expect(eco.eco, 'B90');
    expect(eco.opening, isNull);
    expect(eco.ecoCategories, isEmpty);

    final opening = MiniatureOpeningFilterInput.parse(' Sicilian Defense ');
    expect(opening.eco, isNull);
    expect(opening.opening, 'Sicilian Defense');
    expect(opening.ecoCategories, isEmpty);
  });

  testWidgets('Miniatures filters use the compact approved order', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const _MiniaturesFilterHarness());
    await tester.pumpAndSettle();

    const orderedSections = <String>[
      'Ended by move',
      'Time Control',
      'Level',
      'Opening',
      'Result',
      'Year',
    ];
    final sectionOffsets = <double>[];
    for (final label in orderedSections) {
      expect(find.text(label), findsOneWidget);
      sectionOffsets.add(tester.getTopLeft(find.text(label)).dy);
    }
    expect(sectionOffsets, orderedEquals([...sectionOffsets]..sort()));

    expect(find.text('≤ 25'), findsOneWidget);
    expect(find.text('≤ 20'), findsOneWidget);
    expect(find.text('≤ 15'), findsOneWidget);
    expect(find.text('By move 25'), findsNothing);
    expect(find.text('Sort'), findsNothing);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Example: B90 or Sicilian Defense'), findsOneWidget);
    for (final category in const ['A', 'B', 'C', 'D', 'E']) {
      expect(find.text(category), findsNothing);
    }
  });
}
