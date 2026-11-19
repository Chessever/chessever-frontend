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

  testWidgets(
    'a stack shares a right edge and the live count never moves either button',
    (tester) async {
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
      expect(tester.getSize(capsule), Size.square(InkFabSize.small.side));
      expect(tester.getTopRight(capsule).dx, closeTo(corner.dx, 0.01));

      final liveRect = tester.getRect(capsule);
      await tester.pumpWidget(page(live: 120));
      await tester.pumpAndSettle();
      expect(
        tester.getTopRight(search),
        offsetMoreOrLessEquals(corner, epsilon: 0.01),
      );
      expect(tester.getRect(capsule), liveRect);
    },
  );

  testWidgets('the stack steps 12 between buttons, and its reach clears the '
      'list under it: every button, the margin and the home indicator', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(bottom: 34 * 3);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34 * 3);
    addTearDown(tester.view.reset);
    late BuildContext body;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Builder(
                builder: (context) {
                  body = context;
                  return const SizedBox.expand();
                },
              ),
              floatingActionButton: InkFabStack(
                children: [
                  InkFab(
                    key: const ValueKey('small'),
                    label: 'Small',
                    size: InkFabSize.small,
                    onTap: () {},
                    glyph: (color, size) =>
                        Icon(Icons.tune_rounded, size: size, color: color),
                  ),
                  const SearchInkFab(key: ValueKey('search'), label: 'Search'),
                ],
              ),
            );
          },
        ),
      ),
    );

    expect(InkFabStack.step, 12);
    final small = tester.getRect(find.byKey(const ValueKey('small')));
    final search = tester.getRect(find.byKey(const ValueKey('search')));
    expect(search.top - small.bottom, InkFabStack.step);
    // Flush on the right edge.
    expect(small.right, closeTo(search.right, 0.01));

    // On the 393x852 base: 52 + 16 + 34, and 44 + 12 more per small one.
    expect(InkFabStack.extent(), 52 + kFloatingActionButtonMargin);
    expect(InkFabStack.reach(body), 52 + 16 + 34);
    expect(InkFabStack.reach(body, smallAbove: 1), 52 + 12 + 44 + 16 + 34);
    expect(
      InkFabStack.reach(body, smallAbove: 1) -
          InkFabStack.extent(smallAbove: 1),
      34,
    );
    // The stack's top is exactly that far up from the window's foot.
    expect(852 - small.top, InkFabStack.reach(body, smallAbove: 1));
  });

  testWidgets('a lone button sits in the stack at the stack\'s corner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget page({required bool stacked}) => MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          const search = SearchInkFab(key: ValueKey('search'), label: 'Search');
          return Scaffold(
            floatingActionButton: stacked
                ? const InkFabStack(children: [search])
                : search,
          );
        },
      ),
    );
    await tester.pumpWidget(page(stacked: false));
    await tester.pumpAndSettle();
    final bare = tester.getRect(find.byKey(const ValueKey('search')));
    // A fresh page each time: the Scaffold's own switch between two
    // different buttons is not what is measured here.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(page(stacked: true));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('search'))), bare);
  });
}
