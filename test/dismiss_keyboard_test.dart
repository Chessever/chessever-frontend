import 'package:chessever2/widgets/dismiss_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tapping outside a focused TextField unfocuses it', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder:
            (context, child) =>
                DismissKeyboard(child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          body: Column(
            children: [TextField(focusNode: focusNode), const Text('outside')],
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
        builder:
            (context, child) =>
                DismissKeyboard(child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: focusNode),
              TextButton(onPressed: () => taps++, child: const Text('Action')),
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

  testWidgets('an exclusion keeps focus while its control receives the tap', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        builder:
            (context, child) =>
                DismissKeyboard(child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: focusNode),
              KeyboardDismissExclusion(
                focusNode: focusNode,
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('Search result'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.tap(find.text('Search result'));
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
    expect(taps, 1);
  });

  testWidgets('outside tap hides an orphaned visible iOS keyboard', (
    tester,
  ) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      MaterialApp(
        builder:
            (context, child) =>
                DismissKeyboard(child: child ?? const SizedBox.shrink()),
        home: const Scaffold(body: Text('outside')),
      ),
    );

    final platformCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (call) async {
        platformCalls.add(call.method);
        return null;
      },
    );
    addTearDown(tester.testTextInput.register);

    expect(find.byType(EditableText), findsNothing);
    await tester.tap(find.text('outside'));
    await tester.pump();

    expect(platformCalls, contains('TextInput.hide'));
  });
}
