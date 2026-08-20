import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/player_name_share_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: Builder(
      builder: (context) {
        ResponsiveHelper.init(context);
        return Scaffold(body: child);
      },
    ),
  );
}

void main() {
  testWidgets(
    'tapping the player name opens the existing share preview directly',
    (tester) async {
      var shareCalls = 0;

      await tester.pumpWidget(
        _host(
          PlayerNameShareTarget(
            playerName: 'Vaishali Rameshbabu',
            onShare: () async => shareCalls += 1,
            child: const Text('Vaishali Rameshbabu'),
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
      _host(
        PlayerNameShareTarget(
          playerName: 'Vaishali Rameshbabu',
          onShare: () async {},
          child: const Text('Vaishali Rameshbabu'),
        ),
      ),
    );

    final semantics = tester.getSemantics(find.byType(PlayerNameShareTarget));
    expect(semantics.label, contains('Vaishali Rameshbabu'));
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  });

  testWidgets('shows a quiet outward share hint beside the name', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        PlayerNameShareTarget(
          playerName: 'Vaishali Rameshbabu',
          onShare: () async {},
          child: const Text('Vaishali Rameshbabu'),
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_outward_rounded), findsOneWidget);
  });

  testWidgets('can hide the share hint when requested', (tester) async {
    await tester.pumpWidget(
      _host(
        PlayerNameShareTarget(
          playerName: 'Vaishali Rameshbabu',
          onShare: () async {},
          showShareHint: false,
          child: const Text('Vaishali Rameshbabu'),
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_outward_rounded), findsNothing);
  });
}
