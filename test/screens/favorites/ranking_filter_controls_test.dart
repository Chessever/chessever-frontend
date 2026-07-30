import 'package:chessever2/screens/favorites/rankings/ranking_filter_controls.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpControls(
  WidgetTester tester, {
  RankingFilters filters = RankingFilters.defaults,
  ValueChanged<RankingFilters>? onChanged,
  bool showActivity = true,
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
              showActivity: showActivity,
              onChanged: onChanged ?? (_) {},
            ),
          );
        },
      ),
    ),
  );
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
    for (final label in ['Classical', 'Rapid', 'Blitz']) {
      expect(_timeControlChip(label), findsOneWidget);
      expect(find.text(label), findsNothing);
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

    BoxDecoration decorationOf(Finder chip) {
      final container = tester.widget<AnimatedContainer>(
        find.descendant(of: chip, matching: find.byType(AnimatedContainer)),
      );
      return container.decoration! as BoxDecoration;
    }

    expect(decorationOf(_timeControlChip('Classical')).color, kPrimaryColor);
    expect(decorationOf(_categoryChip('Overall')).color, kPrimaryColor);
    expect(decorationOf(_timeControlChip('Rapid')).color, isNot(kPrimaryColor));

    final selectedLabel = tester.widget<Text>(find.text('Overall'));
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
      findsOneWidget,
      reason: 'the combined filter rail fades at its edges',
    );
  });

  // These are filter chips, not action buttons. An earlier pass gave them a
  // 44.h floor height, which made them read as tappable slabs and left them
  // taller than the search field beside them. The painted box stays small; the
  // tap target is bought with padding outside it.
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
      lessThan(34),
      reason: 'a chip that tall reads as an action button',
    );
    expect(
      touch,
      greaterThanOrEqualTo(40),
      reason: 'the small chip must still be comfortably tappable',
    );
    expect(touch, greaterThan(painted));
  });

  // Time control is conveyed by ChessEver's established owl/rabbit/lightning
  // assets. Keeping those icon-only lets the ranking categories share the same
  // swipeable rail instead of spending a second line above the player list.
  testWidgets(
    'time controls and categories share one icon-first swipeable rail',
    (tester) async {
      await _pumpControls(tester, showActivity: false);

      final strips =
          tester.stateList<ScrollableState>(find.byType(Scrollable)).toList();
      expect(strips, hasLength(1));
      expect(strips.single.position.maxScrollExtent, greaterThan(0));
      expect(find.byType(ShaderMask), findsOneWidget);

      for (final label in ['Classical', 'Rapid', 'Blitz']) {
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

  // The selected fill and label are fixed colours, so light theme is the case
  // that can silently lose contrast or shift geometry.
  testWidgets('chips keep their geometry and contrast in light theme', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: RankingFilterControls(
                filters: RankingFilters.defaults,
                showActivity: false,
                onChanged: (_) {},
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

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

    final strips =
        tester.stateList<ScrollableState>(find.byType(Scrollable)).toList();
    expect(strips, hasLength(1));
    expect(strips.single.position.maxScrollExtent, greaterThan(0));
  });

  // The Active/All chips sit beside the search field. They are shorter than it,
  // so the two must share a mid-line — otherwise the row reads as misaligned.
  testWidgets('Active/All shares a centre line with the search field', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
