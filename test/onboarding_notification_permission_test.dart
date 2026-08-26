import 'dart:io';

import 'package:chessever2/screens/onboarding/notification_permission_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('explains favorite alerts before continuing to native permission', (
    tester,
  ) async {
    var continued = false;

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationPermissionStep(
          onContinue: () async {
            continued = true;
          },
        ),
      ),
    );

    expect(find.text('Never miss a game from your favorites'), findsOneWidget);
    expect(
      find.text(
        'Turn on notifications to know when your favorite players begin playing.',
      ),
      findsOneWidget,
    );
    expect(find.text('Continue'), findsOneWidget);
    expect(continued, isFalse);

    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(continued, isTrue);
  });

  test(
    'notification permission is only requested from the post-favorites step',
    () {
      final mainSource = File('lib/main.dart').readAsStringSync();
      final authSource =
          File('lib/widgets/auth_state_listener.dart').readAsStringSync();
      final selectionSource =
          File(
            'lib/screens/onboarding/player_selection_screen.dart',
          ).readAsStringSync();
      final flowSource =
          File(
            'lib/screens/onboarding/onboarding_flow_screen.dart',
          ).readAsStringSync();

      expect(
        mainSource,
        isNot(contains('notificationPermissionPromptProvider')),
      );
      expect(authSource, isNot(contains('requestPermissionIfNotGranted')));
      expect(selectionSource, isNot(contains('requestPermissionIfNotGranted')));
      expect(
        'requestPermissionIfNotGranted'.allMatches(flowSource),
        hasLength(1),
        reason:
            'The native permission dialog must have one onboarding trigger, '
            'immediately after Favorites.',
      );
      expect(flowSource, contains('NotificationPermissionStep('));
    },
  );
}
