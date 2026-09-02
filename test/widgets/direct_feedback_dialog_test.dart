import 'dart:typed_data';

import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/review_prompt/direct_feedback_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    Future<FeedbackPicture?> Function()? pickPicture,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return DirectFeedbackDialog(pickPicture: pickPicture);
            },
          ),
        ),
      ),
    );
  }

  testWidgets('opens directly on the feedback form', (tester) async {
    await pumpDialog(tester);

    expect(find.text('Your Feedback'), findsOneWidget);
    expect(find.text('Add picture'), findsOneWidget);
    expect(find.text('Enjoying ChessEver?'), findsNothing);
    expect(find.text('Feature Request'), findsNothing);
  });

  testWidgets('attaches and removes an optional picture', (tester) async {
    await pumpDialog(
      tester,
      pickPicture:
          () async => FeedbackPicture(
            bytes: Uint8List.fromList(const [1, 2, 3]),
            fileName: 'position.png',
          ),
    );

    await tester.tap(find.text('Add picture'));
    await tester.pumpAndSettle();

    expect(find.text('position.png'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('position.png'), findsNothing);
    expect(find.text('Add picture'), findsOneWidget);
  });

  testWidgets('asks the user to grant photo access when permission is denied', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      pickPicture: () async {
        throw const FeedbackPicturePermissionDeniedException();
      },
    );

    await tester.tap(find.text('Add picture'));
    await tester.pumpAndSettle();

    expect(find.text('Allow photo access to attach a picture.'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('returns feedback and attached picture from the same page', (
    tester,
  ) async {
    DirectFeedbackResult? result;
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await showDirectFeedbackDialog(
                      context,
                      pickPicture:
                          () async => FeedbackPicture(
                            bytes: Uint8List.fromList(const [4, 5, 6]),
                            fileName: 'board.jpg',
                          ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'The clocks are unclear.');
    await tester.tap(find.text('Add picture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(result?.feedback, 'The clocks are unclear.');
    expect(result?.picture?.fileName, 'board.jpg');
    expect(result?.picture?.bytes, Uint8List.fromList(const [4, 5, 6]));
  });
}
