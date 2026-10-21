import 'package:chessever2/chat/chat_screen.dart';
import 'package:chessever2/widgets/dismiss_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Botvinnik preserves the supported native iOS menu',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(supportsShowingSystemContextMenu: true),
            child: Scaffold(
              body: ChatComposer(
                controller: controller,
                sending: false,
                onSend: () {},
              ),
            ),
          ),
        ),
      );
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(
        field.contextMenuBuilder!(editable.context, editable),
        isA<SystemContextMenu>(),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '${platform.name} toolbar Paste inserts text without losing field focus',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => switch (call.method) {
            'Clipboard.hasStrings' => <String, Object>{'value': true},
            'Clipboard.getData' => <String, Object>{'text': 'Paste test'},
            _ => null,
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            builder: (context, child) => DismissKeyboard(child: child!),
            home: Scaffold(
              body: Center(
                child: ChatComposer(
                  controller: controller,
                  sending: false,
                  onSend: () {},
                ),
              ),
            ),
          ),
        );
        final focusNode = tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode;
        await tester.longPress(find.byType(TextField));
        await tester.pumpAndSettle();
        expect(find.text('Paste'), findsOneWidget);
        await tester.tapAt(const Offset(20, 20));
        await tester.pump();
        expect(focusNode.hasFocus, isFalse);
        await tester.longPress(find.byType(TextField));
        await tester.pumpAndSettle();
        // Separate down/up with a frame, like a real touchscreen, so deferred
        // focus changes cannot be hidden by WidgetTester's instantaneous tap.
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Paste')),
        );
        await tester.pump();
        expect(focusNode.hasFocus, isTrue);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(controller.text, 'Paste test');
        expect(focusNode.hasFocus, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
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
        builder: (context, child) =>
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
        builder: (context, child) =>
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
