import 'package:chessever2/widgets/dismiss_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tapping outside a focused TextField unfocuses it', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            DismissKeyboard(child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: focusNode),
              const Text('outside'),
            ],
          ),
        ),
      ),
    );

    expect(focusNode.hasFocus, isFalse);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.tap(find.text('outside'));
    await tester.pump();
    expect(focusNode.hasFocus, isFalse);
  });

  testWidgets('tapping a sibling control unfocuses without eating the tap', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            DismissKeyboard(child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: focusNode),
              TextButton(
                onPressed: () => taps++,
                child: const Text('Action'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.tap(find.text('Action'));
    await tester.pump();
    expect(focusNode.hasFocus, isFalse);
    expect(taps, 1);
  });
}
