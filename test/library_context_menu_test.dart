import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the long-press menu that replaced "swipe is the only way to manage a
/// saved game": the pressed card is echoed above the actions, every row is
/// reachable, and choosing one runs its callback exactly once after the menu
/// has closed.
void main() {
  const cardKey = ValueKey('card');

  Widget host({
    required List<LibraryMenuAction> actions,
    bool withPreview = true,
    VoidCallback? onPreviewTap,
  }) {
    return MaterialApp(
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: Center(
              child: Builder(
                builder:
                    (cardContext) => GestureDetector(
                      onLongPress:
                          () => showLibraryContextMenu(
                            context: cardContext,
                            actions: actions,
                            previewBuilder:
                                withPreview
                                    // Sizes itself, like a real card: the
                                    // layer must not impose a height that
                                    // could crop the copy.
                                    ? (_) => Container(
                                      key: const ValueKey('preview'),
                                      height: 90,
                                      color: const Color(0xFF222222),
                                    )
                                    : null,
                            onPreviewTap: onPreviewTap,
                          ),
                      child: const SizedBox(
                        key: cardKey,
                        width: 320,
                        height: 90,
                        child: ColoredBox(color: Color(0xFF444444)),
                      ),
                    ),
              ),
            ),
          );
        },
      ),
    );
  }

  testWidgets('long press opens every action plus a preview of the card', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        actions: [
          LibraryMenuAction(
            icon: Icons.open_in_new_rounded,
            label: 'Open game',
            onSelected: () {},
          ),
          LibraryMenuAction(
            icon: Icons.delete_outline_rounded,
            label: 'Delete game',
            destructive: true,
            onSelected: () {},
          ),
        ],
      ),
    );

    await tester.longPress(find.byKey(cardKey));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('preview')), findsOneWidget);
    expect(find.text('Open game'), findsOneWidget);
    expect(find.text('Delete game'), findsOneWidget);
  });

  testWidgets('choosing an action closes the menu and runs it once', (
    tester,
  ) async {
    var deletes = 0;

    await tester.pumpWidget(
      host(
        actions: [
          LibraryMenuAction(
            icon: Icons.open_in_new_rounded,
            label: 'Open game',
            onSelected: () {},
          ),
          LibraryMenuAction(
            icon: Icons.delete_outline_rounded,
            label: 'Delete game',
            destructive: true,
            onSelected: () => deletes++,
          ),
        ],
      ),
    );

    await tester.longPress(find.byKey(cardKey));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete game'));
    await tester.pumpAndSettle();

    expect(deletes, 1);
    expect(find.text('Delete game'), findsNothing);
    expect(find.byKey(const ValueKey('preview')), findsNothing);
  });

  testWidgets('a disabled row is inert', (tester) async {
    var taps = 0;

    await tester.pumpWidget(
      host(
        actions: [
          LibraryMenuAction(
            icon: Icons.drive_file_move_rounded,
            label: 'Move to database',
            enabled: false,
            onSelected: () => taps++,
          ),
          LibraryMenuAction(
            icon: Icons.copy_rounded,
            label: 'Copy PGN',
            onSelected: () {},
          ),
        ],
      ),
    );

    await tester.longPress(find.byKey(cardKey));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Move to database'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(taps, 0);
    expect(find.text('Move to database'), findsOneWidget);
  });

  testWidgets('tapping the preview opens the game and dismisses the menu', (
    tester,
  ) async {
    var opens = 0;

    await tester.pumpWidget(
      host(
        onPreviewTap: () => opens++,
        actions: [
          LibraryMenuAction(
            icon: Icons.copy_rounded,
            label: 'Copy PGN',
            onSelected: () {},
          ),
        ],
      ),
    );

    await tester.longPress(find.byKey(cardKey));
    await tester.pumpAndSettle();

    // The preview itself sits under an IgnorePointer; the layer's own detector
    // is what answers the tap, so the finder is only used to aim at it.
    await tester.tap(
      find.byKey(const ValueKey('preview')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(opens, 1);
    expect(find.text('Copy PGN'), findsNothing);
  });

  testWidgets('menu rows keep a 44dp-plus tap target', (tester) async {
    await tester.pumpWidget(
      host(
        withPreview: false,
        actions: [
          LibraryMenuAction(
            icon: Icons.copy_rounded,
            label: 'Copy PGN',
            onSelected: () {},
          ),
        ],
      ),
    );

    await tester.longPress(find.byKey(cardKey));
    await tester.pumpAndSettle();

    final row = tester.getRect(find.text('Copy PGN'));
    final surface = tester.getRect(
      find
          .ancestor(of: find.text('Copy PGN'), matching: find.byType(Container))
          .first,
    );
    expect(surface.height, greaterThanOrEqualTo(44.0));
    // Label sits inside the row, clear of the rounded corners.
    expect(surface.contains(row.topLeft), isTrue);
    expect(
      surface.contains(row.bottomRight - const Offset(0.01, 0.01)),
      isTrue,
    );
  });

  testWidgets(
    'action labels sit under a Material ancestor (no yellow underline)',
    (tester) async {
      await tester.pumpWidget(
        host(
          actions: [
            LibraryMenuAction(
              icon: Icons.open_in_new_rounded,
              label: 'Open game',
              onSelected: () {},
            ),
            LibraryMenuAction(
              icon: Icons.delete_outline_rounded,
              label: 'Delete game',
              destructive: true,
              onSelected: () {},
            ),
          ],
        ),
      );

      await tester.longPress(find.byKey(cardKey));
      await tester.pumpAndSettle();

      // Exact failure mode of the yellow double-underline: Text without Material.
      expect(
        find.ancestor(
          of: find.text('Open game'),
          matching: find.byType(Material),
        ),
        findsWidgets,
      );
      expect(
        find.ancestor(
          of: find.text('Delete game'),
          matching: find.byType(Material),
        ),
        findsWidgets,
      );
    },
  );
}
