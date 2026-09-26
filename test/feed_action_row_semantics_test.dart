import 'package:chessever2/screens/feed/widgets/feed_action_row.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Feed's controls are reachable without touch: each semantics node
/// carries its tap (TalkBack, Switch Access, Voice Access), and its name
/// starts with the word on screen (Voice Control).
void main() {
  testWidgets('FeedPressable exposes a working tap action', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await _pump(
      tester,
      FeedPressable(
        key: const ValueKey('pressable'),
        semanticsLabel: 'Replay',
        onTap: () => taps++,
        child: const SizedBox(width: 44, height: 44),
      ),
    );
    final node = tester.getSemantics(find.byKey(const ValueKey('pressable')));
    expect(
      node,
      isSemantics(
        label: 'Replay',
        isButton: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    node.owner!.performAction(node.id, SemanticsAction.tap);
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('a disabled FeedPressable offers no tap', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      FeedPressable(
        key: const ValueKey('pressable'),
        semanticsLabel: 'Next game',
        enabled: false,
        onTap: () {},
        child: const SizedBox(width: 44, height: 44),
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('pressable'))),
      isSemantics(
        label: 'Next game',
        isButton: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );
    handle.dispose();
  });

  for (final state in [false, true]) {
    testWidgets('action row names match the visible labels (state: $state)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final tapped = <String>[];
      await _pump(
        tester,
        FeedActionRow(
          height: 56,
          liked: state,
          inSpace: state,
          saved: state,
          likeIconKey: GlobalKey(),
          onLike: () => tapped.add('like'),
          onSpace: () => tapped.add('space'),
          onShare: () => tapped.add('share'),
          onSave: () => tapped.add('save'),
          onAnalyze: () => tapped.add('analyze'),
        ),
      );
      SemanticsNode node(String key) =>
          tester.getSemantics(find.byKey(ValueKey(key)));

      expect(
        node('feed_analyze_button'),
        isSemantics(
          label: 'Analyze',
          hint: 'Open game on the board',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        node('feed_space_button'),
        isSemantics(
          label: 'My Space',
          hint: state ? 'Remove from My Space' : 'Add to My Space',
          isButton: true,
          hasSelectedState: true,
          isSelected: state,
          hasTapAction: true,
        ),
      );
      expect(
        node('feed_share_button'),
        isSemantics(label: 'Share', isButton: true, hasTapAction: true),
      );
      expect(
        node('feed_save_button'),
        isSemantics(
          label: state ? 'Saved' : 'Save',
          hint: state
              ? 'Choose the databases it is saved in'
              : 'Save to a database',
          isButton: true,
          hasSelectedState: true,
          isSelected: state,
          hasTapAction: true,
        ),
      );
      expect(
        node('feed_like_button'),
        isSemantics(
          label: state ? 'Liked' : 'Like',
          isButton: true,
          hasSelectedState: true,
          isSelected: state,
          hasTapAction: true,
        ),
      );

      for (final key in [
        'feed_analyze_button',
        'feed_space_button',
        'feed_share_button',
        'feed_save_button',
        'feed_like_button',
      ]) {
        final n = node(key);
        n.owner!.performAction(n.id, SemanticsAction.tap);
      }
      expect(tapped, ['analyze', 'space', 'share', 'save', 'like']);
      handle.dispose();
    });
  }
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(393, 852)),
      child: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: Center(child: SizedBox(width: 361, child: child)),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}
