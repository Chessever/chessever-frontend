import 'package:chessever2/widgets/player_name_share_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'tapping the player name opens the existing share preview directly',
    (tester) async {
      var shareCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerNameShareTarget(
              playerName: 'Vaishali Rameshbabu',
              onShare: () async => shareCalls += 1,
              child: const Text('Vaishali Rameshbabu'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Vaishali Rameshbabu'));
      await tester.pump();

      expect(shareCalls, 1);
      expect(find.byType(BottomSheet), findsNothing);
    },
  );

  testWidgets('player name share target is exposed as an accessible button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerNameShareTarget(
            playerName: 'Vaishali Rameshbabu',
            onShare: () async {},
            child: const Text('Vaishali Rameshbabu'),
          ),
        ),
      ),
    );

    final semantics = tester.getSemantics(find.byType(PlayerNameShareTarget));
    expect(semantics.label, contains('Vaishali Rameshbabu'));
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  });
}
