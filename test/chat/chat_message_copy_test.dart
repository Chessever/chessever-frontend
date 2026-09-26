import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/chat/chat_screen.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? clipboardText;
  StateSetter? rebuildBubble;

  setUp(() {
    clipboardText = null;
    rebuildBubble = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboardText =
                  (call.arguments as Map<Object?, Object?>)['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return <String, String?>{'text': clipboardText};
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> showAssistantMessage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuildBubble = setState;
                  return ChatMessageBubble(
                    message: const ChatMessage(
                      id: 'assistant-1',
                      role: 'assistant',
                      content: 'Botvinnik recommends developing your knights.',
                    ),
                    isStreaming: false,
                    feedbackPending: false,
                    onReferencePressed: (_) {},
                    onFeedbackPressed: (_, _) {},
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Finder responseText() => find.descendant(
    of: find.byType(SelectionArea).last,
    matching: find.byType(RichText),
  ).last;

  testWidgets('selected assistant text copies to the system clipboard', (
    tester,
  ) async {
    await showAssistantMessage(tester);
    await tester.longPress(responseText());
    await tester.pumpAndSettle();
    final paragraph = tester.renderObject<RenderParagraph>(responseText());
    final selection = paragraph.selections.single;
    final selectedText = paragraph.text.toPlainText().substring(
      selection.start,
      selection.end,
    );

    await tester.tap(find.text('Copy'));
    await tester.pump();

    expect(clipboardText, selectedText);
  });

  testWidgets('copy button copies the full assistant response', (tester) async {
    await showAssistantMessage(tester);
    await tester.tap(find.byTooltip('Copy message'));
    await tester.pump();

    expect(clipboardText, 'Botvinnik recommends developing your knights.');
  });

  testWidgets('selection survives a message rebuild while handles are open', (
    tester,
  ) async {
    await showAssistantMessage(tester);
    await tester.longPress(responseText());
    await tester.pumpAndSettle();

    final selectableBefore = tester.element(responseText());
    rebuildBubble!(() {});
    await tester.pump();

    expect(tester.element(responseText()), same(selectableBefore));
    final paragraph = tester.renderObject<RenderParagraph>(responseText());
    final initialSelection = paragraph.selections.single;
    final box = paragraph.getBoxesForSelection(initialSelection).single;
    final handle = paragraph.localToGlobal(box.toRect().bottomRight);
    final gesture = await tester.startGesture(handle);
    await tester.pump();
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(paragraph.selections, isNotEmpty);
    expect(paragraph.selections.single.end, greaterThan(initialSelection.end));
    final selection = paragraph.selections.single;
    final selectedText = paragraph.text.toPlainText().substring(
      selection.start,
      selection.end,
    );
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(clipboardText, selectedText);
  });
}
