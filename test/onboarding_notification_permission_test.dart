import 'dart:io';

import 'package:chessever2/screens/onboarding/notification_permission_step.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The native notification prompt is one-shot: once the user declines it, the
/// app cannot ask again. These guard that it is raised exactly once, from the
/// step that has just given the user a reason to say yes.
void main() {
  Widget host(NotificationPermissionStep step) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(body: step);
        },
      ),
    );
  }

  testWidgets('names the favourites the user just picked', (tester) async {
    var continued = false;

    await tester.pumpWidget(
      host(
        NotificationPermissionStep(
          topPadding: 0,
          bottomPadding: 0,
          players: const [
            NotificationStepPlayer(name: 'Magnus Carlsen', fideId: '1503014'),
            NotificationStepPlayer(name: 'Nakamura, Hikaru', fideId: '2016192'),
          ],
          onContinue: () async => continued = true,
        ),
      ),
    );
    // Entrance delays run up to 450ms + 400ms; a plain pumpAndSettle can
    // return before a pending delay timer has fired.
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    expect(find.text('Never miss a game from your favorites'), findsOneWidget);
    // Surnames, and "Nakamura, Hikaru" resolves the same as "Magnus Carlsen".
    expect(
      find.text('Know the moment Carlsen and Nakamura start a game.'),
      findsOneWidget,
    );
    expect(continued, isFalse);

    await tester.tap(find.text('Continue'));
    // Entrance delays run up to 450ms + 400ms; a plain pumpAndSettle can
    // return before a pending delay timer has fired.
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    expect(continued, isTrue);
  });

  testWidgets('degrades to generic copy when no favourite resolved', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        NotificationPermissionStep(
          topPadding: 0,
          bottomPadding: 0,
          onContinue: () async {},
        ),
      ),
    );
    // Entrance delays run up to 450ms + 400ms; a plain pumpAndSettle can
    // return before a pending delay timer has fired.
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    expect(
      find.text('Know the moment your favorite players start a game.'),
      findsOneWidget,
    );
    expect(find.text('Continue'), findsOneWidget);
  });

  test('the native permission dialog has exactly one trigger', () {
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

    expect(mainSource, isNot(contains('notificationPermissionPromptProvider')));
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
  });
}
