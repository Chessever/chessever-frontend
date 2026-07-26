import 'package:chessever2/screens/favorites/rankings/ranking_filter_controls.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpControls(
  WidgetTester tester, {
  RankingFilters filters = RankingFilters.defaults,
  ValueChanged<RankingFilters>? onChanged,
}) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: RankingFilterControls(
              filters: filters,
              onChanged: onChanged ?? (_) {},
            ),
          );
        },
      ),
    ),
  );
}

void main() {
  testWidgets('shows phone ranking selectors with default selections', (
    tester,
  ) async {
    await _pumpControls(tester);

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Classical'), findsOneWidget);
    expect(find.text('Rapid'), findsOneWidget);
    expect(find.text('Blitz'), findsOneWidget);
    expect(find.text('Overall'), findsOneWidget);
    expect(find.text('Women'), findsOneWidget);
    expect(find.text('Juniors'), findsOneWidget);
    expect(find.text('Girls'), findsOneWidget);

    final selected = tester.widgetList<Semantics>(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.selected == true,
      ),
    );
    expect(selected.length, 3);
  });

  testWidgets('changing time control preserves activity and category', (
    tester,
  ) async {
    RankingFilters? changed;
    await _pumpControls(tester, onChanged: (value) => changed = value);

    await tester.tap(find.text('Rapid'));
    await tester.pump();

    expect(changed?.activity, RankingActivity.active);
    expect(changed?.timeControl, RankingTimeControl.rapid);
    expect(changed?.category, RankingCategory.overall);
  });

  // These controls sit right under the Favorites/Games/Rankings switcher, so
  // they have to wear the same chip treatment as the rest of the app's filters
  // (solid kPrimaryColor + black label) rather than inventing a second accent.
  testWidgets('selected chips use the app-wide filter chip treatment', (
    tester,
  ) async {
    await _pumpControls(tester);

    BoxDecoration decorationOf(String label) {
      final container = tester.widget<AnimatedContainer>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return container.decoration! as BoxDecoration;
    }

    expect(decorationOf('Classical').color, kPrimaryColor);
    expect(decorationOf('Overall').color, kPrimaryColor);
    expect(decorationOf('Rapid').color, isNot(kPrimaryColor));

    final selectedLabel = tester.widget<Text>(find.text('Classical'));
    expect(selectedLabel.style?.color, kBlackColor);
  });

  // A horizontally scrolling strip must not guillotine the chip sitting on the
  // boundary, and it must not overflow at phone width either.
  testWidgets('filter strips scroll instead of overflowing at phone width', (
    tester,
  ) async {
    await _pumpControls(tester);

    expect(tester.takeException(), isNull);
    expect(
      find.byType(ShaderMask),
      findsNWidgets(2),
      reason: 'both the time-control and category strips fade at their edges',
    );
  });
}
