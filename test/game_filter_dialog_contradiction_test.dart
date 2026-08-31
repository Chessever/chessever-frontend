import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter_dialog.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selecting Live clears and disables final-result choices', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const _DialogHarness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Live'));
    await tester.pump();

    final resultGesture = tester.widget<GestureDetector>(
      find
          .ancestor(
            of: find.text('1-0'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    expect(resultGesture.onTap, isNull);
    expect(find.text('Live games have no final result.'), findsOneWidget);
  });

  testWidgets('Live disables historical year selection', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const _DialogHarness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Live'));
    await tester.pump();

    final yearSection = find.byKey(const ValueKey('game-filter-year-control'));
    expect(yearSection, findsOneWidget);
    expect(
      tester
          .widget<IgnorePointer>(
            find.byKey(const ValueKey('game-filter-year-ignore-pointer')),
          )
          .ignoring,
      isTrue,
    );
    expect(find.text('Live games are always from today.'), findsOneWidget);
  });
}

class _DialogHarness extends StatelessWidget {
  const _DialogHarness();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: Center(child: GameFilterDialog(initialFilter: GameFilter())),
          );
        },
      ),
    );
  }
}
