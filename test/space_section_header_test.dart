import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/space_section_header.dart';
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
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(children: [header]),
              ),
            ),
          );
        },
      ),
    ),
  );
}

void main() {
  test('the Library\'s files are Databases under My Database', () {
    expect(spaceGroupTitle(SpaceSection.library), 'Databases');
    expect(spaceGroupTitle(SpaceSection.events), 'Events');
    expect(spaceGroupTitle(SpaceSection.links), 'Shortcuts');
  });

  testWidgets('type and count on one 44 line; See all only while some are '
      'hidden', (tester) async {
    await _pump(tester, const SpaceSectionHeader(title: 'Events', count: 2));
    expect(find.text('Events'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('See all'), findsNothing);
    expect(
      tester.getSize(find.byType(SpaceSectionHeader)).height,
      moreOrLessEquals(44, epsilon: 0.5),
    );

    var opened = 0;
    await _pump(
      tester,
      SpaceSectionHeader(title: 'Events', count: 7, onSeeAll: () => opened++),
    );
    await tester.tap(find.bySemanticsLabel('See all 7 Events'));
    expect(opened, 1);
    expect(
      tester.getSize(find.byType(SpaceSectionHeader)).height,
      moreOrLessEquals(44, epsilon: 0.5),
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
