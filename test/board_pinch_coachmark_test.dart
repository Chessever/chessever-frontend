import 'package:chessever2/screens/chessboard/widgets/board_pinch_coachmark.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({
    required VoidCallback onDismiss,
    required VoidCallback onDontShowAgain,
  }) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: BoardPinchCoachmark(
              currentStep: 2,
              totalSteps: 2,
              onDismiss: onDismiss,
              onDontShowAgain: onDontShowAgain,
            ),
          );
        },
      ),
    );
  }

  testWidgets('pinch teaching renders the dialog card', (tester) async {
    await tester.pumpWidget(host(onDismiss: () {}, onDontShowAgain: () {}));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('Pinch to Resize'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
    expect(find.text("Don't show again"), findsOneWidget);
  });

  testWidgets('"Got it" dismisses via onDismiss', (tester) async {
    var dismissals = 0;
    var dontShowAgain = 0;
    await tester.pumpWidget(
      host(
        onDismiss: () => dismissals++,
        onDontShowAgain: () => dontShowAgain++,
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.text('Got it'));
    // Exit fade + the overlay's 500ms settle delay.
    await tester.pump(const Duration(milliseconds: 600));

    expect(dismissals, 1);
    expect(dontShowAgain, 0);
  });

  testWidgets('"Don\'t show again" routes to onDontShowAgain', (tester) async {
    var dismissals = 0;
    var dontShowAgain = 0;
    await tester.pumpWidget(
      host(
        onDismiss: () => dismissals++,
        onDontShowAgain: () => dontShowAgain++,
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.text("Don't show again"));
    await tester.pump(const Duration(milliseconds: 600));

    expect(dontShowAgain, 1);
    expect(dismissals, 0);
  });
}
