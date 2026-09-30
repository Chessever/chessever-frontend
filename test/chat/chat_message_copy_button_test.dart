import 'package:chessever2/chat/chat_screen.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(String text) => MaterialApp(
    home: Builder(
      builder: (context) {
        ResponsiveHelper.init(context);
        return Scaffold(body: ChatMessageCopyButton(text: text));
      },
    ),
  );

  testWidgets('Copy message writes the whole answer and confirms success', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    const answer = 'First paragraph.\n\nSecond paragraph with **analysis**.';
    await tester.pumpWidget(host(answer));
    final button = find.byTooltip('Copy message');
    final size = tester.getSize(find.byType(IconButton));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
    await tester.tap(button);
    await tester.pump();
    expect(copied, answer);
    expect(find.text('Message copied'), findsOneWidget);
  });

  testWidgets('clipboard failure reports a retry instead of copied', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          throw PlatformException(code: 'unavailable');
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    await tester.pumpWidget(host('An answer'));
    await tester.tap(find.byTooltip('Copy message'));
    await tester.pump();
    expect(find.text('Message copied'), findsNothing);
    expect(find.text("Couldn't copy this message. Try again."), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
