import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/eco_filter_dropdown.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _HomeFilterHarness extends StatelessWidget {
  const _HomeFilterHarness();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: Center(
              child: FilterPopup(onApplyFilters: (_) {}, onResetFilters: () {}),
            ),
          );
        },
      ),
    );
  }
}

class _EcoDropdownHarness extends StatelessWidget {
  const _EcoDropdownHarness({this.value = GameEcoFilter.all, this.onChanged});

  final GameEcoFilter value;
  final ValueChanged<GameEcoFilter>? onChanged;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: EcoFilterDropdown(
              value: value,
              onChanged: onChanged ?? (_) {},
            ),
          );
        },
      ),
    );
  }
}

Finder _ecoSuggestionRows() => find.byWidgetPredicate(
  (widget) =>
      widget is GestureDetector &&
      widget.key is ValueKey<String> &&
      ((widget.key! as ValueKey<String>).value.startsWith('eco-family-') ||
          (widget.key! as ValueKey<String>).value.startsWith('eco-code-')),
);

void main() {
  testWidgets('empty ECO browser keeps categories collapsed by default', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const _EcoDropdownHarness());
    await tester.tap(find.text('All Openings').first);
    await tester.pumpAndSettle();

    for (final category in ['A', 'B', 'C']) {
      expect(find.byKey(ValueKey('eco-category-$category')), findsOneWidget);
    }
    final categoryTops = [
      for (final category in ['A', 'B', 'C', 'D', 'E'])
        tester.getTopLeft(find.byKey(ValueKey('eco-category-$category'))).dy,
    ];
    expect(categoryTops, orderedEquals(categoryTops.toList()..sort()));
    expect(_ecoSuggestionRows(), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('eco-category-B')));
    await tester.tap(find.byKey(const ValueKey('eco-category-B')));
    await tester.pumpAndSettle();
    expect(_ecoSuggestionRows(), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('eco-category-B')));
    await tester.pumpAndSettle();
    expect(_ecoSuggestionRows(), findsNothing);
  });

  testWidgets('browse order runs broad family to child family to exact code', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const _EcoDropdownHarness());
    await tester.tap(find.text('All Openings').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('eco-category-B')));
    await tester.pumpAndSettle();

    const sicilian = ValueKey('eco-family-B20-B99');
    const najdorf = ValueKey('eco-family-B9');
    expect(find.byKey(sicilian), findsOneWidget);
    expect(find.byKey(najdorf), findsNothing);

    await tester.ensureVisible(
      find.byKey(const ValueKey('eco-expand-B20-B99')),
    );
    await tester.tap(find.byKey(const ValueKey('eco-expand-B20-B99')));
    await tester.pumpAndSettle();
    expect(find.byKey(najdorf), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(sicilian)).dy,
      lessThan(tester.getTopLeft(find.byKey(najdorf)).dy),
    );
    expect(find.byKey(const ValueKey('eco-code-B97')), findsNothing);

    await tester.ensureVisible(find.byKey(najdorf));
    await tester.tap(find.byKey(const ValueKey('eco-expand-B9')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('eco-code-B97')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(najdorf)).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('eco-code-B97'))).dy,
      ),
    );
  });

  testWidgets('selected exact opening reveals only its browse ancestry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _EcoDropdownHarness(value: GameEcoFilter.forCode('B97')),
    );
    await tester.tap(find.text('B97').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('eco-code-B97')), findsOneWidget);
    expect(find.byKey(const ValueKey('eco-category-B')), findsOneWidget);
    expect(find.byKey(const ValueKey('eco-category-A')), findsOneWidget);
    expect(find.byKey(const ValueKey('eco-code-A00')), findsNothing);
  });

  testWidgets('family disclosure expands without selecting the family', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    GameEcoFilter? selected;

    await tester.pumpWidget(
      _EcoDropdownHarness(onChanged: (value) => selected = value),
    );
    await tester.tap(find.text('All Openings').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('eco-category-B')));
    await tester.pumpAndSettle();

    final disclosure = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('eco-expand-'),
    );
    expect(disclosure, findsWidgets);
    await tester.ensureVisible(disclosure.first);
    await tester.tap(disclosure.first);
    await tester.pumpAndSettle();

    expect(selected, isNull);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('home popup shows its actions without scrolling on a phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _HomeFilterHarness(),
      ),
    );
    await tester.pumpAndSettle();

    final applyButton = find.widgetWithText(ElevatedButton, 'Apply Filters');
    expect(applyButton, findsOneWidget);
    expect(tester.getRect(applyButton).bottom, lessThanOrEqualTo(844));
  });

  testWidgets('home popup selects the Najdorf family without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _HomeFilterHarness(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(EcoFilterDropdown), findsOneWidget);
    final openingHeader = find.text('All Openings').first;
    await tester.ensureVisible(openingHeader);
    await tester.tap(openingHeader);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -180),
    );
    await tester.pump();

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Najdorf');
    await tester.pump();

    final family = find.byKey(const ValueKey('eco-family-B9'));
    expect(family, findsOneWidget);
    await tester.ensureVisible(family);
    await tester.pump();
    await tester.tap(family);
    await tester.pumpAndSettle();

    expect(container.read(filterPopupProvider).eco.code, 'B9');
    expect(find.text('Sicilian: Najdorf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("home popup bulk-selects the complete King's Indian family", (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _HomeFilterHarness(),
      ),
    );
    await tester.pumpAndSettle();

    final openingHeader = find.text('All Openings').first;
    await tester.ensureVisible(openingHeader);
    await tester.tap(openingHeader);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -180),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), "King's Indian");
    await tester.pump();

    final family = find.byKey(const ValueKey('eco-family-E6+E7+E8+E9'));
    expect(family, findsOneWidget);
    expect(find.text('E60-E99'), findsOneWidget);
    expect(find.textContaining('indexed'), findsNothing);
    expect(find.textContaining('ECO codes'), findsNothing);
    tester.widget<GestureDetector>(family).onTap?.call();
    await tester.pumpAndSettle();

    final selected = container.read(filterPopupProvider).eco;
    expect(selected.isFamily, isTrue);
    expect(selected.ecoPrefixes, ['E6', 'E7', 'E8', 'E9']);
  });

  testWidgets('home popup exposes a deep variant as an exact-code scope', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _HomeFilterHarness(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('All Openings').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -180),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Poisoned pawn');
    await tester.pump();

    final exactCode = find.byWidgetPredicate(
      (widget) =>
          widget is GestureDetector &&
          widget.key is ValueKey<String> &&
          ((widget.key! as ValueKey<String>).value).startsWith('eco-line-B97:'),
    );
    final openingList = find.descendant(
      of: find.byType(EcoFilterDropdown),
      matching: find.byType(Scrollable),
    );
    final scrollable = tester.state<ScrollableState>(openingList.last);
    for (
      var attempt = 0;
      attempt < 6 && exactCode.evaluate().isEmpty;
      attempt++
    ) {
      scrollable.position.jumpTo(
        (scrollable.position.pixels + 180).clamp(
          0,
          scrollable.position.maxScrollExtent,
        ),
      );
      await tester.pump();
    }
    expect(exactCode, findsOneWidget);
    expect(
      find.descendant(of: exactCode, matching: find.textContaining('Sicilian')),
      findsWidgets,
    );
    expect(
      find.descendant(of: exactCode, matching: find.textContaining('Najdorf')),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: exactCode,
        matching: find.textContaining('Poisoned pawn'),
      ),
      findsWidgets,
    );
    tester.widget<GestureDetector>(exactCode).onTap?.call();
    await tester.pumpAndSettle();

    final selected = container.read(filterPopupProvider).eco;
    expect(selected.code, 'B97');
    expect(selected.isFamily, isFalse);
  });

  testWidgets(
    'home popup exposes Gurgenidze CSV leaves without ancestor noise',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _HomeFilterHarness(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('All Openings').first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -180),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Gurgen');
      await tester.pump();

      expect(find.text('B20-B99'), findsNothing);
      expect(find.text('Gurgenidze variation'), findsWidgets);
      expect(find.text('Gurgenidze counter-attack'), findsOneWidget);
      expect(find.text('Gurgenidze system'), findsOneWidget);

      final counterAttack = find.ancestor(
        of: find.text('Gurgenidze counter-attack'),
        matching: find.byType(GestureDetector),
      );
      tester.widget<GestureDetector>(counterAttack).onTap?.call();
      await tester.pumpAndSettle();

      final selected = container.read(filterPopupProvider).eco;
      expect(selected.code, 'B15');
      expect(selected.isFamily, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
