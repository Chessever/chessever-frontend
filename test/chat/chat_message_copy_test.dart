import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/chat/chat_screen.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/cupertino.dart';
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

  Future<void> showAssistantMessage(
    WidgetTester tester, {
    String role = 'assistant',
  }) async {
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
                    message: ChatMessage(
                      id: 'message-1',
                      role: role,
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

  Finder responseText() => find
      .descendant(
        of: find.byType(SelectionArea).last,
        matching: find.byType(RichText),
      )
      .last;

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
    expect(find.text('Message copied'), findsOneWidget);
  });

  testWidgets('selected user text copies from the selection menu', (
    tester,
  ) async {
    await showAssistantMessage(tester, role: 'user');
    await tester.longPressAt(
      tester.getTopLeft(responseText()) + const Offset(50, 10),
    );
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
    expect(find.text('Message copied'), findsOneWidget);
  });

  testWidgets('Copy reads selection reported after the menu was built', (
    tester,
  ) async {
    await showAssistantMessage(tester);
    await tester.longPress(responseText());
    await tester.pumpAndSettle();

    final copyButton = tester.widget<CupertinoTextSelectionToolbarButton>(
      find.ancestor(
        of: find.text('Copy'),
        matching: find.byType(CupertinoTextSelectionToolbarButton),
      ),
    );
    tester
        .widget<SelectionArea>(find.byType(SelectionArea).last)
        .onSelectionChanged!(const SelectedContent(plainText: 'knights'));
    copyButton.onPressed!();
    await tester.pump();

    expect(clipboardText, 'knights');
    expect(find.text('Message copied'), findsOneWidget);
  });

  testWidgets('Copy survives the selection closing during a touch', (
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
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Copy')),
    );
    await tester.pump();
    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .clearSelection();
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(clipboardText, selectedText);
  });

  testWidgets('Copy message survives the selection closing during a touch', (
    tester,
  ) async {
    await showAssistantMessage(tester);
    await tester.longPress(responseText());
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Copy message')),
    );
    await tester.pump();
    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .clearSelection();
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(clipboardText, 'Botvinnik recommends developing your knights.');
  });

  testWidgets('copy keeps the excerpt if selection clears as the menu closes', (
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
    final copyButton = tester.widget<CupertinoTextSelectionToolbarButton>(
      find.ancestor(
        of: find.text('Copy'),
        matching: find.byType(CupertinoTextSelectionToolbarButton),
      ),
    );

    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .clearSelection();
    await tester.pump();
    copyButton.onPressed!();
    await tester.pump();

    expect(clipboardText, selectedText);
  });

  testWidgets('menu Copy message copies the full response after closing', (
    tester,
  ) async {
    await showAssistantMessage(tester);
    await tester.longPress(responseText());
    await tester.pumpAndSettle();

    final copyMessageButton = tester
        .widget<CupertinoTextSelectionToolbarButton>(
          find.ancestor(
            of: find.text('Copy message'),
            matching: find.byType(CupertinoTextSelectionToolbarButton),
          ),
        );
    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .clearSelection();
    await tester.pump();
    copyMessageButton.onPressed!();
    await tester.pump();

    expect(clipboardText, 'Botvinnik recommends developing your knights.');
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
