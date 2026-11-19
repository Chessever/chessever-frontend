import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/actions/space_remove_confirmation.dart';
import 'package:chessever2/screens/my_space/library/space_library_bridge.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_database.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The pins in memory; every open recorded.
class _Store extends SpaceShortcutsNotifier {
  _Store(this.seed);

  final List<SpaceShortcut> seed;
  final opened = <String>[];

  @override
  Future<List<SpaceShortcut>> build() async => seed;

  @override
  Future<void> markOpened(String id) async => opened.add(id);
}

class _Hidden extends SpaceHiddenAutoKeys {
  @override
  Set<String> build() => const {};
}

final _link = SpaceShortcut(
  id: 'link-pin',
  kind: SpaceShortcutKind.link,
  targetId: 'https://chessever.com/player/1503014',
  title: 'Carlsen scorecard',
  createdAt: DateTime(2026, 9, 20),
);

final _database = SpaceShortcut(
  id: 'db-pin',
  kind: SpaceShortcutKind.folder,
  targetId: 'folder-1',
  title: 'Najdorf prep',
  createdAt: DateTime(2026, 9, 20),
);

LibraryFolder _folder({String? shareToken, bool subscribed = false}) =>
    LibraryFolder(
      id: 'folder-1',
      userId: 'owner',
      name: 'Najdorf prep',
      color: '#333333',
      icon: 'folder',
      orderIndex: 0,
      shareToken: shareToken,
      isSubscribed: subscribed,
      createdAt: DateTime(2026, 10),
      updatedAt: DateTime(2026, 10),
    );

Future<_Store> _pump(
  WidgetTester tester,
  Widget Function(BuildContext context, WidgetRef ref) build, {
  List<SpaceShortcut> pins = const [],
}) async {
  final store = _Store(pins);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        spaceShortcutsProvider.overrideWith(() => store),
        spaceHiddenAutoKeysProvider.overrideWith(_Hidden.new),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Consumer(
          builder: (context, ref, _) {
            ResponsiveHelper.init(context);
            ref.watch(spaceShortcutsProvider);
            return Scaffold(
              body: Center(
                child: SizedBox(width: 358, child: build(context, ref)),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return store;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  group('database rows hold into the Library card\'s rows', () {
    // `FolderCard._menuActions`, with its My Space row and Delete taken out:
    // My Space puts its own pin's row where Library has its My Space row,
    // and never deletes or unsubscribes.
    for (final (name, folder, rows) in [
      ('owned', _folder(), ['Publish / edit collection', 'Share', 'Rename']),
      (
        'shared',
        _folder(shareToken: 'token'),
        ['Publish / edit collection', 'Copy Link', 'Stop Sharing', 'Rename'],
      ),
      ('subscribed', _folder(subscribed: true), <String>[]),
    ]) {
      testWidgets('$name, in Library\'s order', (tester) async {
        late List<LibraryMenuAction> actions;
        await _pump(tester, (context, ref) {
          actions = spaceLibraryFolderActions(context, ref, folder);
          return const SizedBox();
        });
        expect([for (final a in actions) a.label], rows);
        expect(actions.where((a) => a.destructive), isEmpty);
      });
    }

    testWidgets('with no Open row Library does not have, and Remove from My '
        'Space last', (tester) async {
      await _pump(
        tester,
        (context, ref) => SpaceSavedRow(
          shortcut: _database,
          menuActions: (menuContext) =>
              spaceLibraryFolderActions(menuContext, ref, _folder()),
        ),
        pins: [_database],
      );
      await tester.longPress(find.byType(SpaceSavedRow));
      await _settle(tester);
      for (final label in [
        'Publish / edit collection',
        'Share',
        'Rename',
        'Remove from My Space',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.textContaining('Open'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Rename')).dy,
        lessThan(tester.getTopLeft(find.text('Remove from My Space')).dy),
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a row other than a database or Prep opens through "Open" and '
      'what it opens, the event card\'s wording', (tester) async {
    await _pump(
      tester,
      (context, ref) => SpaceSavedRow(shortcut: _link),
      pins: [_link],
    );
    await tester.longPress(find.byType(SpaceSavedRow));
    await _settle(tester);
    expect(find.text('Open link'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
    expect(find.text('Remove from My Space'), findsOneWidget);
    expect(spaceOpenLabel(SpaceShortcutKind.event), 'Open event');
    expect(spaceOpenLabel(SpaceShortcutKind.smartEvent), 'Open smart event');
  });

  testWidgets('a screen reader reaches the row\'s menu: one button with a '
      'tap and a long-press', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      (context, ref) => SpaceSavedRow(shortcut: _link),
      pins: [_link],
    );
    final node = tester.getSemantics(find.byType(SpaceSavedRow));
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.hasAction(SemanticsAction.longPress), isTrue);
    expect(data.label, contains('Carlsen scorecard'));

    tester.semantics.longPress(
      find.semantics.byLabel(RegExp('Carlsen scorecard')),
    );
    await _settle(tester);
    expect(find.text('Remove from My Space'), findsOneWidget);
    handle.dispose();
  });

  group('one press and one haptic, the event card\'s', () {
    late List<String> haptics;

    setUp(() {
      haptics = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              haptics.add('${call.arguments}');
            }
            return null;
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    testWidgets('a saved row presses to 0.96 and taps once, light', (
      tester,
    ) async {
      await _pump(
        tester,
        (context, ref) => SpaceSavedRow(shortcut: _link),
        pins: [_link],
      );
      final press = tester.widget<TappableScale>(
        find.descendant(
          of: find.byType(SpaceSavedRow),
          matching: find.byType(TappableScale),
        ),
      );
      expect(press.scaleDown, 0.96);
      // The hold sits inside the press, as on an event card.
      expect(
        find.descendant(
          of: find.byType(TappableScale),
          matching: find.byType(CardContextMenu),
        ),
        findsOneWidget,
      );
      haptics.clear();
      // The open's own failure is not under test; only the press is.
      press.onTap();
      expect(haptics, ['HapticFeedbackType.lightImpact']);
      await _settle(tester);
    });

    testWidgets('the menu\'s Open row adds no second tap haptic', (
      tester,
    ) async {
      await _pump(
        tester,
        (context, ref) => SpaceSavedRow(shortcut: _link),
        pins: [_link],
      );
      await tester.longPress(find.byType(SpaceSavedRow));
      await _settle(tester);
      haptics.clear();
      await tester.tap(find.text('Open link'));
      await _settle(tester);
      // The row's own selection tick, nothing more.
      expect(haptics, ['HapticFeedbackType.lightImpact']);
    });
  });

  testWidgets('removing a smart event says where its notifications stop: '
      'the star on its card', (tester) async {
    final smart = SpaceShortcut(
      id: 'se',
      kind: SpaceShortcutKind.smartEvent,
      targetId: 'criteria',
      title: 'GM Games',
      createdAt: DateTime(2026, 9, 20),
    );
    await _pump(
      tester,
      (context, ref) => TextButton(
        onPressed: () => confirmSpaceSmartEventRemoval(context, [smart]),
        child: const Text('remove'),
      ),
    );
    await tester.tap(find.text('remove'));
    await _settle(tester);
    expect(find.textContaining('unstar it on its card'), findsOneWidget);
    expect(find.textContaining('Build a Smart Event'), findsNothing);
    expect(find.textContaining('bell'), findsNothing);
  });
}
