import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/space_section_header.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart'
    show WallPressable;
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget header, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
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
            child: Scaffold(body: Column(children: [header])),
          );
        },
      ),
    ),
  );
}

void main() {
  test('the Library\'s files are Databases on My Space', () {
    expect(spaceGroupTitle(SpaceSection.library), 'Databases');
    expect(spaceGroupTitle(SpaceSection.events), 'Events');
    expect(spaceGroupTitle(SpaceSection.links), 'Shortcuts');
  });

  testWidgets('name, count and See all on one 44 line; See all is always '
      'there, even for a group that shows everything', (tester) async {
    var opened = 0;
    await _pump(
      tester,
      SpaceSectionHeader(title: 'Events', count: 2, onSeeAll: () => opened++),
    );
    expect(find.text('Events'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.textContaining('See all', findRichText: true), findsOneWidget);
    expect(
      tester.getSize(find.byType(SpaceSectionHeader)).height,
      moreOrLessEquals(44, epsilon: 0.5),
    );
    await tester.tap(find.bySemanticsLabel('See all 2 Events'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(opened, 1);
  });

  testWidgets('the name is a 44 target of its own that opens what See all '
      'opens, and gives under the finger', (tester) async {
    var opened = 0;
    await _pump(
      tester,
      SpaceSectionHeader(title: 'Games', count: 7, onSeeAll: () => opened++),
    );
    final title = find.bySemanticsLabel('Games, 7');
    expect(title, findsOneWidget);
    expect(tester.getSize(title).height, greaterThanOrEqualTo(43.5));

    // The name gives under the finger: the same press the See all action
    // wears.
    final press = tester.widget<WallPressable>(
      find.ancestor(of: find.text('Games'), matching: find.byType(WallPressable)),
    );
    expect(press.pressScale, 0.97);
    await tester.tap(title);
    await tester.pump(const Duration(milliseconds: 400));
    expect(opened, 1);

    await tester.tap(find.bySemanticsLabel('See all 7 Games'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(opened, 2);
  });

  testWidgets('My Space and Discovery wear the identical head: the same '
      'widget, See all label, arrow and title style', (tester) async {
    await _pump(
      tester,
      Column(
        children: [
          SpaceSectionHeader(
            title: 'Players',
            count: 10,
            gutter: discoveryGutter,
            onSeeAll: () {},
          ),
          DiscoverySeeAllHeader(title: 'Most liked', onOpen: () {}),
        ],
      ),
    );
    final heads = tester
        .widgetList<DiscoverySectionHeader>(find.byType(DiscoverySectionHeader))
        .toList();
    expect(heads, hasLength(2));
    final actions = tester
        .widgetList<DiscoveryAction>(find.byType(DiscoveryAction))
        .toList();
    expect(actions, hasLength(2));
    for (final a in actions) {
      expect(a.label, 'See all');
      expect(a.arrow, isTrue);
      expect(a.onTap, isNotNull);
    }
    final space = tester.widget<Text>(find.text('Players'));
    final discovery = tester.widget<Text>(find.text('Most liked'));
    expect(space.style, discovery.style);
    // The two heads stand the same height, their titles on one inset.
    expect(
      tester.getSize(find.byType(DiscoverySectionHeader).first).height,
      tester.getSize(find.byType(DiscoverySectionHeader).last).height,
    );
    expect(
      tester.getTopLeft(find.text('Players')).dx,
      tester.getTopLeft(find.text('Most liked')).dx,
    );
  });

  testWidgets('title and count share a baseline, and hold at 1.3x text', (
    tester,
  ) async {
    await _pump(
      tester,
      SpaceSectionHeader(title: 'Smart Events', count: 12, onSeeAll: () {}),
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);
    final title = tester.getBottomLeft(find.text('Smart Events')).dy;
    final count = tester.getBottomLeft(find.text('12')).dy;
    expect(count, moreOrLessEquals(title, epsilon: 0.5));
  });
}
