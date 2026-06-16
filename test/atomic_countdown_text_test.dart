import 'package:chessever2/widgets/atomic_countdown_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets('renders unknown live clock as placeholder, not zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AtomicCountdownText(
            clockCentiseconds: 0,
            lastMoveTime: null,
            isActive: false,
            style: TextStyle(),
          ),
        ),
      ),
    );

    expect(find.text('--:--'), findsOneWidget);
    expect(find.text('00:00'), findsNothing);
  });

  testWidgets('keeps explicit zero clock displayable', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AtomicCountdownText(
            clockSeconds: 0,
            clockCentiseconds: 0,
            lastMoveTime: null,
            isActive: false,
            style: TextStyle(),
          ),
        ),
      ),
    );

    expect(find.text('00:00'), findsOneWidget);
  });
}
