import 'package:chessever2/screens/favorites/rankings/ranking_filter_controls.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motor/motor.dart';

/// Phone-sized view so [ResponsiveHelper] `.w`/`.h` match a real device
/// (default test surface is 800×600 and would overscale chips).
void _usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _pumpControls(
  WidgetTester tester, {
  RankingFilters filters = RankingFilters.defaults,
  ValueChanged<RankingFilters>? onChanged,
  bool showActivity = true,
  ThemeData? theme,
}) async {
  _usePhoneSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: RankingFilterControls(
              filters: filters,
              showActivity: showActivity,
              onChanged: onChanged ?? (_) {},
            ),
          );
        },
      ),
    ),
  );
  // Motor label expand needs a frame past the initial build.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Finder _timeControlChip(String label) =>
    find.byKey(ValueKey('ranking-time-control-${label.toLowerCase()}'));

Finder _categoryChip(String label) =>
    find.byKey(ValueKey('ranking-category-${label.toLowerCase()}'));

void main() {
  testWidgets('shows phone ranking selectors with default selections', (
    tester,
  ) async {
    await _pumpControls(tester);

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    // Selected time control shows its label; the others stay icon-only.
    expect(find.text('Classical'), findsOneWidget);
    expect(find.text('Rapid'), findsNothing);
    expect(find.text('Blitz'), findsNothing);
    for (final label in ['Classical', 'Rapid', 'Blitz']) {
      expect(_timeControlChip(label), findsOneWidget);
    }
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

    await tester.tap(_timeControlChip('Rapid'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(changed?.activity, RankingActivity.active);
    expect(changed?.timeControl, RankingTimeControl.rapid);
    expect(changed?.category, RankingCategory.overall);
  });

  testWidgets('selected time control reveals its label; others stay icon-only', (
    tester,
  ) async {
    await _pumpControls(
      tester,
      filters: RankingFilters.defaults.copyWith(
        timeControl: RankingTimeControl.blitz,
      ),
      showActivity: false,
    );

    expect(
      find.descendant(
        of: _timeControlChip('Blitz'),
        matching: find.text('Blitz'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _timeControlChip('Classical'),
        matching: find.text('Classical'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: _timeControlChip('Rapid'),
        matching: find.text('Rapid'),
      ),
      findsNothing,
    );

    // Label expand uses Motor spring physics.
    expect(find.byType(SingleMotionBuilder), findsWidgets);
  });

  testWidgets('selected chips use the app-wide filter chip treatment', (
    tester,
  ) async {
    await _pumpControls(tester);

    BoxDecoration decorationOf(Finder chip) {
      final container = tester.widget<AnimatedContainer>(
        find.descendant(of: chip, matching: find.byType(AnimatedContainer)),
      );
      return container.decoration! as BoxDecoration;
    }

    expect(decorationOf(_timeControlChip('Classical')).color, kPrimaryColor);
    expect(decorationOf(_categoryChip('Overall')).color, kPrimaryColor);
    expect(decorationOf(_timeControlChip('Rapid')).color, isNot(kPrimaryColor));

    expect(tester.widget<Text>(find.text('Overall')).style?.color, kBlackColor);
    expect(
      tester.widget<Text>(find.text('Classical')).style?.color,
      kBlackColor,
    );
  });

  testWidgets('one-line rail fits phone width without horizontal scroll', (
    tester,
  ) async {
    await _pumpControls(tester, showActivity: false);

    expect(tester.takeException(), isNull);
    // FittedBox scale-down keeps every chip on-screen; no swipe needed.
    expect(find.byType(FittedBox), findsOneWidget);
    expect(find.byType(Scrollable), findsNothing);

    // Rightmost category is hit-testable without dragging.
    await tester.tap(_categoryChip('Girls'));
    await tester.pump();
  });

  testWidgets('chips are chip-sized while keeping a real tap target', (
    tester,
  ) async {
    await _pumpControls(tester);

    final chip = _timeControlChip('Classical');
    final painted =
        tester
            .getSize(
              find.descendant(
                of: chip,
                matching: find.byType(AnimatedContainer),
              ),
            )
            .height;
    final touch =
        tester
            .getSize(
              find.descendant(of: chip, matching: find.byType(GestureDetector)),
            )
            .height;

    expect(
      painted,
      lessThanOrEqualTo(36),
      reason: 'a chip that tall reads as an action button',
    );
    expect(
      touch,
      greaterThanOrEqualTo(36),
      reason: 'the small chip must still be comfortably tappable',
    );
    expect(touch, greaterThan(painted));
  });

  testWidgets(
    'time controls and categories share one compact Motor-expand rail',
    (tester) async {
      await _pumpControls(tester, showActivity: false);

      expect(find.byType(FittedBox), findsOneWidget);
      expect(find.byType(SingleMotionBuilder), findsWidgets);

      expect(
        find.descendant(
          of: _timeControlChip('Classical'),
          matching: find.text('Classical'),
        ),
        findsOneWidget,
      );
      for (final label in ['Rapid', 'Blitz']) {
        final key = find.byKey(
          ValueKey('ranking-time-control-${label.toLowerCase()}'),
        );
        expect(key, findsOneWidget);
        expect(
          find.descendant(of: key, matching: find.text(label)),
          findsNothing,
        );

        final semantics = tester.widget<Semantics>(
          find.descendant(of: key, matching: find.byType(Semantics)).first,
        );
        expect(semantics.properties.label, label);
      }

      // Same baseline for both groups.
      expect(
        tester
            .getCenter(
              find.byKey(const ValueKey('ranking-time-control-classical')),
            )
            .dy,
        tester
            .getCenter(find.byKey(const ValueKey('ranking-category-overall')))
            .dy,
      );

      // All category labels visible without horizontal scroll.
      for (final label in ['Overall', 'Women', 'Juniors', 'Girls']) {
        expect(find.text(label), findsOneWidget);
      }
    },
  );

  testWidgets('chips keep their geometry and contrast in light theme', (
    tester,
  ) async {
    await _pumpControls(
      tester,
      showActivity: false,
      theme: AppTheme.lightTheme,
    );

    expect(tester.takeException(), isNull);

    final selected =
        tester
                .widget<AnimatedContainer>(
                  find.descendant(
                    of: _timeControlChip('Classical'),
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .decoration!
            as BoxDecoration;
    expect(selected.color, kPrimaryColor);
    expect(tester.widget<Text>(find.text('Overall')).style?.color, kBlackColor);
    expect(find.byType(FittedBox), findsOneWidget);
    expect(find.byType(Scrollable), findsNothing);
  });

  testWidgets('Active/All shares a centre line with the search field', (
    tester,
  ) async {
    _usePhoneSurface(tester);
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Padding(
                padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: SearchBarWidget(
                        hintText: 'Search',
                        margin: 0.sp,
                        autoFocus: false,
                        controller: controller,
                        focusNode: focusNode,
                        onChanged: (_) {},
                        onClose: () {},
                      ),
                    ),
                    SizedBox(width: 8.w),
                    RankingActivityControl(
                      value: RankingActivity.active,
                      onChanged: (_) {},
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    final search = tester.getRect(find.byType(SearchBarWidget));
    final chip = tester.getRect(
      find
          .ancestor(
            of: find.text('Active'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );

    expect(chip.height, lessThan(search.height));
    expect((search.center.dy - chip.center.dy).abs(), lessThan(0.5));
  });
}
