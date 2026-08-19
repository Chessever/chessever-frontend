import 'package:chessever2/screens/library/widgets/library_gamebase_filter_dialog.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/dismiss_keyboard.dart';
import 'package:chessever2/widgets/game_filter/eco_filter_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _LibraryGamebaseFilterHarness extends StatelessWidget {
  const _LibraryGamebaseFilterHarness();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      builder: (context, child) =>
          DismissKeyboard(child: child ?? const SizedBox.shrink()),
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: Center(
              child: LibraryGamebaseFilterDialog(
                initialFilter: GamebaseFilter(),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LibraryGamebaseFilterRouteHarness extends StatelessWidget {
  const _LibraryGamebaseFilterRouteHarness();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      builder: (context, child) =>
          DismissKeyboard(child: child ?? const SizedBox.shrink()),
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  showLibraryGamebaseFilterDialog(
                    context: context,
                    currentFilter: GamebaseFilter(),
                  );
                },
                child: const Text('Open filters'),
              ),
            ),
          );
        },
      ),
    );
  }
}

TextField _openingSearch(WidgetTester tester) {
  return tester.widget<TextField>(find.byType(TextField));
}

bool _openingSearchHasFocus(WidgetTester tester) {
  final field = _openingSearch(tester);
  return field.focusNode?.hasFocus ?? false;
}

Future<void> _pumpPastExpandAndDelayedFocus(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 150));
}

void main() {
  testWidgets(
    'Opening search does not take focus until the field is tapped',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const _LibraryGamebaseFilterHarness());
      await tester.pumpAndSettle();

      expect(find.byType(LibraryGamebaseFilterDialog), findsOneWidget);
      expect(find.byType(EcoFilterDropdown), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(_openingSearchHasFocus(tester), isFalse);

      final openingHeader = find.text('All Openings').first;
      await tester.ensureVisible(openingHeader);
      await tester.tap(openingHeader);
      await _pumpPastExpandAndDelayedFocus(tester);

      expect(find.text('Search'), findsOneWidget);
      expect(_openingSearchHasFocus(tester), isFalse);

      await tester.tap(find.text('A00'));
      await tester.pumpAndSettle();
      expect(find.text('A00'), findsWidgets);
      expect(find.byType(TextField), findsOneWidget);
      expect(_openingSearchHasFocus(tester), isFalse);

      await tester.tap(find.text('A00').first);
      await _pumpPastExpandAndDelayedFocus(tester);
      expect(_openingSearchHasFocus(tester), isFalse);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(_openingSearchHasFocus(tester), isTrue);

      await tester.enterText(find.byType(TextField), 'Sicilian');
      expect(_openingSearch(tester).controller!.text, 'Sicilian');
      expect(_openingSearchHasFocus(tester), isTrue);

      await tester.tap(find.text('Filters'));
      await tester.pump();
      expect(_openingSearchHasFocus(tester), isFalse);
    },
  );

  testWidgets(
    'Opening search does not steal focus when the filter dialog route opens',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const _LibraryGamebaseFilterRouteHarness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open filters'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(LibraryGamebaseFilterDialog), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(_openingSearchHasFocus(tester), isFalse);

      final openingHeader = find.text('All Openings').first;
      await tester.ensureVisible(openingHeader);
      await tester.tap(openingHeader);
      await _pumpPastExpandAndDelayedFocus(tester);
      expect(_openingSearchHasFocus(tester), isFalse);
    },
  );
}
