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

  // These are filter chips, not action buttons. An earlier pass gave them a
  // 44.h floor height, which made them read as tappable slabs and left them
  // taller than the search field beside them. The painted box stays small; the
  // tap target is bought with padding outside it.
  testWidgets('chips are chip-sized while keeping a real tap target', (
    tester,
  ) async {
    await _pumpControls(tester);

    final painted =
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('Classical'),
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            )
            .height;
    final touch =
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('Classical'),
                    matching: find.byType(GestureDetector),
                  )
                  .first,
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

  // The three time controls have to fit the phone width outright — overflowing
  // by even a few pixels just reads as a clipped chip. The four categories are
  // meant to scroll, per the card's "swipeable" requirement.
  //
  // Asserted on the real scroll extent rather than by adding up widths: `.w`
  // scales, so the strip's 16.w inset is 24px here, not 16.
  testWidgets('time controls fit exactly; categories stay swipeable', (
    tester,
  ) async {
    await _pumpControls(tester, showActivity: false);

    final strips =
        tester.stateList<ScrollableState>(find.byType(Scrollable)).toList();
    expect(strips, hasLength(2));

    expect(
      strips[0].position.maxScrollExtent,
      0,
      reason: 'Classical/Rapid/Blitz must not be clipped at phone width',
    );
    expect(
      strips[1].position.maxScrollExtent,
      greaterThan(0),
      reason: 'Overall/Women/Juniors/Girls is a swipeable strip',
    );
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
