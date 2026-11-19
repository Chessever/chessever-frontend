import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/live_first_capsule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A 360x780 phone scales 44 down to 40, so the small disc draws at its
  // floor of 42: under the 44pt minimum target.
  testWidgets('the small button keeps its drawn size and a 44pt target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Center(
                child: InkFab(
                  label: 'Filters',
                  size: InkFabSize.small,
                  onTap: () => taps++,
                  glyph: (color, size) =>
                      Icon(Icons.tune_rounded, size: size, color: color),
                ),
              ),
            );
          },
        ),
      ),
    );

    expect(InkFabSize.small.disc, 42);
    expect(InkFabSize.small.side, 44);
    final fab = find.byType(InkFab);
    expect(tester.getSize(fab), const Size(44, 44));
    final disc = find.descendant(
      of: fab,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle,
      ),
    );
    expect(tester.getSize(disc), const Size(42, 42));
    expect(tester.getCenter(disc), tester.getCenter(fab));

    // Half a point outside the disc, still inside the target.
    await tester.tapAt(tester.getTopLeft(fab) + const Offset(0.5, 22));
    expect(taps, 1);
  });

  testWidgets('the regular button is its own target', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Center(child: SearchInkFab(onTap: () {})),
            );
          },
        ),
      ),
    );
    expect(InkFabSize.regular.side, InkFabSize.regular.disc);
    expect(
      tester.getSize(find.byType(InkFab)),
      Size.square(InkFabSize.regular.disc),
    );
  });

  testWidgets('a stack keeps its buttons on one right edge: a wider one '
      'above grows leftward, never pulling the search off its corner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget page({required int live}) => MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            floatingActionButton: InkFabStack(
              children: [
                LiveFirstCapsule(on: false, liveCount: live, onTap: () {}),
                const SearchInkFab(key: ValueKey('search'), label: 'Search'),
              ],
            ),
          );
        },
      ),
    );
    final search = find.byKey(const ValueKey('search'));
    final capsule = find.byType(LiveFirstCapsule);

    await tester.pumpWidget(page(live: 3));
    await tester.pumpAndSettle();
    final corner = tester.getTopRight(search);
    expect(
      tester.getSize(capsule).width,
      greaterThan(tester.getSize(search).width),
    );
    expect(tester.getTopRight(capsule).dx, closeTo(corner.dx, 0.01));

    // A count with more digits: the capsule widens, the search stays put.
    await tester.pumpWidget(page(live: 120));
    await tester.pumpAndSettle();
    expect(
      tester.getTopRight(search),
      offsetMoreOrLessEquals(corner, epsilon: 0.01),
    );
    expect(tester.getTopRight(capsule).dx, closeTo(corner.dx, 0.01));
  });
}
