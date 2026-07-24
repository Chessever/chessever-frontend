import 'package:chessever2/screens/chessboard/widgets/like_learning_prompt_sheet.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the ChessEver like-learning question and actions', (
    tester,
  ) async {
    await _pumpSheet(tester);

    expect(find.text('Did you like this game?'), findsOneWidget);
    expect(
      find.text('Like it to save it in My Likes and find it again later.'),
      findsOneWidget,
    );
    expect(find.text('No'), findsOneWidget);
    expect(find.text('Yes, like it'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returns false from the secondary No action', (tester) async {
    bool? result;
    await _pumpSheet(tester, onResult: (value) => result = value);

    await tester.tap(find.text('No'));
    await tester.pump();

    expect(result, isFalse);
  });

  testWidgets('returns true from the primary like action', (tester) async {
    bool? result;
    await _pumpSheet(tester, onResult: (value) => result = value);

    await tester.tap(find.text('Yes, like it'));
    await tester.pump();

    expect(result, isTrue);
  });
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  ValueChanged<bool>? onResult,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            backgroundColor: context.colors.background,
            body: Align(
              alignment: Alignment.bottomCenter,
              child: LikeLearningPromptSheet(onResult: onResult ?? (_) {}),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}
