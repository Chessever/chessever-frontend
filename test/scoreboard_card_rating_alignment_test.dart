import 'package:chessever2/screens/standings/widget/scoreboard_card_widget.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets('keeps opponent ratings aligned when rating change is absent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: Column(
                  children: [
                    ScoreboardCardWidget(
                      countryCode: '',
                      name: 'Player With Change',
                      score: 2500,
                      scoreChange: -5,
                      matchScore: '0',
                      isWhite: true,
                      index: 0,
                      isFirst: true,
                      isLast: false,
                      onTap: () {},
                    ),
                    ScoreboardCardWidget(
                      countryCode: '',
                      name: 'Player Without Change',
                      score: 2500,
                      matchScore: '1',
                      isWhite: false,
                      index: 1,
                      isFirst: false,
                      isLast: true,
                      onTap: () {},
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    final ratingFinder = find.text('2500');
    expect(ratingFinder, findsNWidgets(2));

    final ratings = tester.widgetList<Text>(ratingFinder).toList();
    final withChangeX = tester.getTopLeft(find.byWidget(ratings[0])).dx;
    final withoutChangeX = tester.getTopLeft(find.byWidget(ratings[1])).dx;

    expect(withoutChangeX, withChangeX);
  });
}
