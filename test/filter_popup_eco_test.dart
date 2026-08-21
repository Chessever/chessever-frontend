import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/eco_filter_dropdown.dart';
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

void main() {
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
}
