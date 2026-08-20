import 'package:chessever2/screens/standings/widget/scoreboard_card_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required VoidCallback onPlayerTap,
    required VoidCallback onTap,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: ScoreboardCardWidget(
                  countryCode: 'USA',
                  title: 'WGM',
                  name: 'Atousa Pourkashiyan',
                  score: 2308,
                  scoreChange: -3,
                  matchScore: '1',
                  isWhite: true,
                  index: 0,
                  isFirst: true,
                  isLast: true,
                  onPlayerTap: onPlayerTap,
                  onTap: onTap,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  testWidgets('player name opens performance without opening the game', (
    tester,
  ) async {
    var performanceOpens = 0;
    var gameOpens = 0;
    await pumpCard(
      tester,
      onPlayerTap: () => performanceOpens += 1,
      onTap: () => gameOpens += 1,
    );

    final playerName = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText() == 'WGM Atousa Pourkashiyan',
    );
    await tester.tap(playerName);
    await tester.pump();

    expect(performanceOpens, 1);
    expect(gameOpens, 0);
  });

  testWidgets('rating and result keep opening the game', (tester) async {
    var performanceOpens = 0;
    var gameOpens = 0;
    await pumpCard(
      tester,
      onPlayerTap: () => performanceOpens += 1,
      onTap: () => gameOpens += 1,
    );

    await tester.tap(find.text('2308'));
    await tester.pump();
    await tester.tap(find.text('1'));
    await tester.pump();

    expect(performanceOpens, 0);
    expect(gameOpens, 2);
  });
}
