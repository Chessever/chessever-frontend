import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/library/widgets/miniatures_filter_dialog.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/adaptive_window.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/duo_window_matrix.dart';

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
  for (final window in duoWindowCases) {
    for (final light in [false, true]) {
      testWidgets('Miniatures filters apply from ${window.name}, '
          '${light ? 'light' : 'dark'}', (tester) async {
        MiniatureGamesFilter? selected;
        await _pumpDuoFilter(
          tester,
          window,
          light: light,
          onResult: (filter) => selected = filter,
        );
        await tester.tap(find.text('≤ 20'));
        await tester.pump();
        expect(find.text('Apply Filters').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Apply Filters'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(selected?.maxMoves, 20);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  for (final transition in duoWindowTransitions) {
    testWidgets('Miniatures filter input survives '
        '${transition.from.name} to ${transition.to.name}', (tester) async {
      MiniatureGamesFilter? selected;
      await _pumpDuoFilter(
        tester,
        transition.from,
        onResult: (filter) => selected = filter,
      );
      final dialogState = tester.state(find.byType(MiniaturesFilterDialog));
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'B90');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 100));
      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller;

      applyDuoWindow(tester, transition.to, mirrorInsets: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        tester.state(find.byType(MiniaturesFilterDialog)),
        same(dialogState),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller,
        same(controller),
      );
      expect(controller?.text, 'B90');
      expect(find.text('Apply Filters').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Apply Filters'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(selected?.eco, 'B90');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

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

Future<void> _pumpDuoFilter(
  WidgetTester tester,
  DuoWindowCase window, {
  bool light = false,
  required ValueChanged<MiniatureGamesFilter?> onResult,
}) async {
  tester.view.devicePixelRatio = 3;
  applyDuoWindow(tester, window);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(1.3)),
        child: AdaptiveWindowScope(child: child!),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => onResult(
                await showMiniaturesFilterDialog(
                  context: context,
                  currentFilter: const MiniatureGamesFilter(),
                ),
              ),
              child: const Text('Open filters'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open filters'));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}
