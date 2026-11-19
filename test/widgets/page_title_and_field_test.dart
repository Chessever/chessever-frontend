import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(body: Center(child: child)),
          );
        },
      ),
    ),
  );
}

void main() {
  testWidgets('one title voice: a pushed page is named as a root is', (
    tester,
  ) async {
    await _pump(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [HomeTopBarTitle('Feed'), PageTitle('Favorites')],
      ),
    );
    final context = tester.element(find.byType(PageTitle));
    final voice = HomeTopBarMetrics.titleStyle(context);
    expect(HomeTopBarTitle.style(context), voice);
    expect(PageTitle.style(context), voice);
    final root = tester.widget<Text>(find.text('Feed')).style!;
    final page = tester.widget<Text>(find.text('Favorites')).style!;
    expect(page.fontSize, root.fontSize);
    expect(page.fontWeight, root.fontWeight);
    expect(page.color, root.color);
    expect(page.color, context.colors.textPrimary);
    // The same size on screen too.
    expect(
      tester.getSize(find.text('Favorites')).height,
      tester.getSize(find.text('Feed')).height,
    );
  });

  testWidgets('a page title is a heading, one line, its mark bare and '
      'silent, growing no further than the bar', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      const SizedBox(
        width: 160,
        child: PageTitle(
          'A very long collection name that cannot fit',
          mark: Icon(Icons.bookmark_rounded),
        ),
      ),
      textScale: 2,
    );
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(
      MediaQuery.textScalerOf(tester.element(find.byType(Text))).scale(10),
      closeTo(10 * HomeTopBarMetrics.maxTextScale, 0.001),
    );
    expect(
      tester.getSemantics(find.byType(PageTitle)),
      isSemantics(
        label: 'A very long collection name that cannot fit',
        isHeader: true,
      ),
    );
    // The mark: no tile behind it, at the mark's size, in the icon ink.
    final mark = find.byIcon(Icons.bookmark_rounded);
    expect(tester.getSize(mark), Size.square(PageTitle.markSize));
    expect(
      find.ancestor(of: mark, matching: find.byType(DecoratedBox)),
      findsNothing,
    );
    expect(
      IconTheme.of(tester.element(mark)).color,
      tester.element(mark).colors.iconPrimary,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('one search field: as tall as the home field, filter glyph '
      'or not, lifting with a self-coloured edge', (tester) async {
    final text = TextEditingController();
    final focus = FocusNode();
    addTearDown(text.dispose);
    addTearDown(focus.dispose);
    Widget surfaceOf(double lift, {bool filter = false}) => SizedBox(
      width: 353,
      child: HomeSearchFieldSurface(
        lift: lift,
        child: SimpleSearchBar(
          controller: text,
          focusNode: focus,
          onCloseTap: () {},
          onOpenFilter: filter ? () {} : null,
        ),
      ),
    );
    // In a bar: as tall as it needs, never stretched by the screen.
    Widget field(double lift, {bool filter = false}) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [surfaceOf(lift, filter: filter)],
    );
    final surface = find.byKey(const ValueKey('simple-search-field-surface'));

    await _pump(tester, field(0));
    final context = tester.element(surface);
    final plain = tester.getSize(surface);
    expect(plain.height, HomeSearchFieldSurface.heightOf(context));
    expect(plain.height, HomeTopBarMetrics.fieldExtent(context));
    await _pump(tester, field(0, filter: true));
    expect(tester.getSize(surface), plain);

    BoxDecoration decoration() =>
        tester.widget<DecoratedBox>(surface).decoration as BoxDecoration;
    await _pump(tester, field(0));
    expect(decoration().color, context.colors.surface);
    // At rest the edge is the fill itself: no line.
    expect(decoration().border!.top.color, decoration().color);
    await _pump(tester, field(1));
    expect(decoration().color, HomeSearchFieldSurface.fillOf(context, 1));
    expect(
      decoration().border!.top.color,
      HomeSearchFieldSurface.edgeOf(context, 1),
    );
    expect(decoration().border!.top.color, isNot(decoration().color));
    expect(
      decoration().borderRadius,
      BorderRadius.circular(HomeSearchFieldSurface.radius),
    );
  });
}
