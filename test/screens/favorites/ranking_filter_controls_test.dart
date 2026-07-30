import 'package:chessever2/screens/favorites/rankings/ranking_filter_controls.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motor/motor.dart';

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

  testWidgets('filter strips scroll instead of overflowing at phone width', (
    tester,
  ) async {
    await _pumpControls(tester);

    expect(tester.takeException(), isNull);
    expect(
      find.byType(ShaderMask),
      findsOneWidget,
      reason: 'the combined filter rail fades at its edges',
    );
  });

  testWidgets('chips keep original painted size (not densified)', (
    tester,
  ) async {
    await _pumpControls(tester);

    final chip = _timeControlChip('Classical');
    final painted = tester.getSize(
      find.descendant(of: chip, matching: find.byType(AnimatedContainer)),
    );
    final touch = tester.getSize(
      find.descendant(of: chip, matching: find.byType(GestureDetector)),
    );

    // Original chip pad is 8/8 with textXs — painted height stays under button
    // territory but is not the densified 5/5 mini chip.
    expect(painted.height, lessThan(40));
    expect(painted.height, greaterThanOrEqualTo(28));
    expect(touch.height, greaterThan(painted.height));
  });

  testWidgets(
    'time controls and categories share one rail with tighter group gaps only',
    (tester) async {
      await _pumpControls(tester, showActivity: false);

      final strips =
          tester.stateList<ScrollableState>(find.byType(Scrollable)).toList();
      expect(strips, hasLength(1));
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(find.byType(SingleMotionBuilder), findsWidgets);

      expect(
        find.descendant(
          of: _timeControlChip('Classical'),
          matching: find.text('Classical'),
        ),
        findsOneWidget,
      );
      for (final label in ['Rapid', 'Blitz']) {
        expect(
          find.descendant(
            of: _timeControlChip(label),
            matching: find.text(label),
          ),
          findsNothing,
        );
      }

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
    expect(find.byType(Scrollable), findsOneWidget);
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
                padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 0),
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
