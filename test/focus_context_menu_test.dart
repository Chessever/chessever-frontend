import 'dart:math' as math;

import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shared long-press focus menu: the page blurs, the card lifts where it
/// sits, and the actions open against the edge of the card with room for them.
void main() {
  const cardKey = ValueKey('card');
  const previewKey = ValueKey('preview');
  const phone = Size(393, 852);

  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = phone * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  List<LibraryMenuAction> rows(int count, {void Function(int)? onTap}) => [
    for (var i = 0; i < count; i++)
      LibraryMenuAction(
        icon: Icons.copy_rounded,
        label: i == 0 ? 'Copy PGN' : 'Action $i',
        onSelected: () => onTap?.call(i),
      ),
  ];

  Widget host({
    required Rect card,
    required List<LibraryMenuAction> actions,
    bool withPreview = true,
    ThemeData? theme,
    bool reduceMotion = false,
    LibraryContextMenuHandle? handle,
    VoidCallback? onPreviewTap,
  }) {
    return MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      builder: reduceMotion
          ? (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            )
          : null,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: Stack(
              children: [
                Positioned.fromRect(
                  rect: card,
                  child: Builder(
                    builder: (cardContext) => GestureDetector(
                      onLongPress: () => showLibraryContextMenu(
                        context: cardContext,
                        actions: actions,
                        handle: handle,
                        onPreviewTap: onPreviewTap,
                        previewBuilder: withPreview
                            ? (_) => SizedBox(
                                key: previewKey,
                                height: card.height,
                                child: const ColoredBox(
                                  color: Color(0xFF2F5D50),
                                ),
                              )
                            : null,
                      ),
                      child: const ColoredBox(
                        key: cardKey,
                        color: Color(0xFF2F5D50),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.longPress(find.byKey(cardKey));
    await tester.pumpAndSettle();
  }

  /// The opaque surface a label is painted on.
  Color surfaceBehind(WidgetTester tester, Finder text) {
    final boxes = tester.widgetList<DecoratedBox>(
      find.ancestor(of: text, matching: find.byType(DecoratedBox)),
    );
    for (final box in boxes) {
      final decoration = box.decoration;
      if (decoration is BoxDecoration &&
          decoration.color != null &&
          decoration.color!.a == 1.0) {
        return decoration.color!;
      }
    }
    fail('no opaque surface behind the label');
  }

  Rect surfaceRectBehind(WidgetTester tester, Finder text) {
    final elements = find
        .ancestor(of: text, matching: find.byType(DecoratedBox))
        .evaluate();
    for (final element in elements) {
      final decoration = (element.widget as DecoratedBox).decoration;
      if (decoration is BoxDecoration &&
          decoration.color != null &&
          decoration.color!.a == 1.0) {
        final box = element.renderObject! as RenderBox;
        return box.localToGlobal(Offset.zero) & box.size;
      }
    }
    fail('no opaque surface behind the label');
  }

  double luminance(Color c) => c.computeLuminance();
  double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  group('placement', () {
    testWidgets('opens below the card when there is room, card in place', (
      tester,
    ) async {
      usePhone(tester);
      const card = Rect.fromLTWH(16, 100, 361, 120);
      await tester.pumpWidget(host(card: card, actions: rows(3)));
      await open(tester);

      final preview = tester.getRect(find.byKey(previewKey));
      expect(preview.center.dx, closeTo(card.center.dx, 0.5));
      expect(preview.center.dy, closeTo(card.center.dy, 0.5));
      // Lifted, not moved.
      expect(preview.width, greaterThan(card.width));

      final label = tester.getRect(find.text('Copy PGN'));
      expect(label.top, greaterThan(preview.bottom));
      // Leading edges line up on a card wider than the menu.
      final panel = surfaceRectBehind(tester, find.text('Copy PGN'));
      expect(panel.left, closeTo(card.left, 0.5));
      expect(panel.width, lessThanOrEqualTo(card.width));
    });

    testWidgets('flips above when the card sits near the bottom', (
      tester,
    ) async {
      usePhone(tester);
      const card = Rect.fromLTWH(16, 680, 361, 120);
      await tester.pumpWidget(host(card: card, actions: rows(3)));
      await open(tester);

      final preview = tester.getRect(find.byKey(previewKey));
      expect(preview.center.dy, closeTo(card.center.dy, 0.5));
      final panel = surfaceRectBehind(tester, find.text('Copy PGN'));
      expect(panel.bottom, lessThan(preview.top));
      expect(panel.top, greaterThanOrEqualTo(0));
    });

    testWidgets('moves the card only when neither side fits', (tester) async {
      usePhone(tester);
      const card = Rect.fromLTWH(16, 250, 361, 420);
      await tester.pumpWidget(host(card: card, actions: rows(6)));
      await open(tester);

      final preview = tester.getRect(find.byKey(previewKey));
      expect((preview.center.dy - card.center.dy).abs(), greaterThan(10));

      final panel = surfaceRectBehind(tester, find.text('Copy PGN'));
      // Card and menu both whole on screen, and still attached to each other.
      for (final rect in [preview, panel]) {
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(phone.height));
      }
      final attachedBelow = panel.top > preview.bottom;
      final attachedAbove = panel.bottom < preview.top;
      expect(attachedBelow || attachedAbove, isTrue);
      expect(
        attachedBelow ? panel.top - preview.bottom : preview.top - panel.bottom,
        lessThan(24),
      );
    });

    testWidgets('a card too tall to sit beside the menu shrinks to fit', (
      tester,
    ) async {
      usePhone(tester);
      const card = Rect.fromLTWH(16, 40, 361, 760);
      await tester.pumpWidget(host(card: card, actions: rows(4)));
      await open(tester);

      final preview = tester.getRect(find.byKey(previewKey));
      expect(preview.height, lessThan(card.height));
      final panel = surfaceRectBehind(tester, find.text('Copy PGN'));
      for (final rect in [preview, panel]) {
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(phone.height));
      }
      expect(panel.top > preview.bottom || panel.bottom < preview.top, isTrue);
    });

    testWidgets('a menu taller than the room beside the card overlays it', (
      tester,
    ) async {
      usePhone(tester);
      const card = Rect.fromLTWH(16, 300, 361, 120);
      await tester.pumpWidget(host(card: card, actions: rows(18)));
      await open(tester);

      final preview = tester.getRect(find.byKey(previewKey));
      expect(preview.center.dy, closeTo(card.center.dy, 0.5));
      final panel = surfaceRectBehind(tester, find.text('Copy PGN'));
      expect(panel.top, greaterThanOrEqualTo(0));
      expect(panel.bottom, lessThanOrEqualTo(phone.height));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a narrow card on the right opens the menu toward the left', (
      tester,
    ) async {
      usePhone(tester);
      const card = Rect.fromLTWH(300, 120, 80, 80);
      await tester.pumpWidget(host(card: card, actions: rows(2)));
      await open(tester);

      final panel = surfaceRectBehind(tester, find.text('Copy PGN'));
      expect(panel.right, greaterThan(card.right - 20));
      expect(panel.right, lessThanOrEqualTo(phone.width));
      expect(panel.left, lessThan(card.left));
    });
  });

  testWidgets('reports the lift before the first frame and after the close', (
    tester,
  ) async {
    usePhone(tester);
    final events = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Center(
                child: Builder(
                  builder: (cardContext) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPress: () => showLibraryContextMenu(
                      context: cardContext,
                      actions: rows(1),
                      previewBuilder: (_) => const SizedBox(height: 90),
                      onPreviewLiftChanged: events.add,
                    ),
                    child: const SizedBox(key: cardKey, width: 300, height: 90),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.longPress(find.byKey(cardKey));
    // Synchronous with the press: the host can hide its card for frame one.
    expect(events, [true]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy PGN'));
    await tester.pump();
    // Still lifted while the copy travels home.
    expect(events, [true]);
    await tester.pumpAndSettle();
    expect(events, [true, false]);
  });

  testWidgets('handle.close() dismisses without running an action', (
    tester,
  ) async {
    usePhone(tester);
    final handle = LibraryContextMenuHandle();
    var runs = 0;
    await tester.pumpWidget(
      host(
        card: const Rect.fromLTWH(16, 100, 361, 120),
        handle: handle,
        actions: rows(2, onTap: (_) => runs++),
      ),
    );
    await open(tester);
    expect(handle.isOpen, isTrue);

    handle.close();
    await tester.pumpAndSettle();

    expect(find.text('Copy PGN'), findsNothing);
    expect(handle.isOpen, isFalse);
    expect(runs, 0);
    // A stale handle is a no-op.
    handle.close();
    await tester.pumpAndSettle();
  });

  testWidgets('backdrop tap and system back both dismiss', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(
      host(card: const Rect.fromLTWH(16, 100, 361, 120), actions: rows(2)),
    );

    await open(tester);
    await tester.tapAt(const Offset(200, 800));
    await tester.pumpAndSettle();
    expect(find.text('Copy PGN'), findsNothing);

    await open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Copy PGN'), findsNothing);
    // The host page is still there: back closed the menu, not the screen.
    expect(find.byKey(cardKey), findsOneWidget);
  });

  testWidgets('the page behind is blurred while the menu is up', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(
      host(card: const Rect.fromLTWH(16, 100, 361, 120), actions: rows(2)),
    );
    await open(tester);

    final backdrop = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(backdrop.enabled, isTrue);
  });

  group('prominent actions', () {
    testWidgets('render as one row of equal buttons above the list', (
      tester,
    ) async {
      usePhone(tester);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          card: const Rect.fromLTWH(16, 100, 361, 120),
          actions: [
            LibraryMenuAction(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              destructive: true,
              onSelected: () {},
            ),
            LibraryMenuAction(
              icon: Icons.ios_share_rounded,
              label: 'Share',
              prominent: true,
              onSelected: () {},
            ),
            LibraryMenuAction(
              icon: Icons.open_in_new_rounded,
              label: 'Open',
              onSelected: () {},
            ),
            LibraryMenuAction(
              icon: Icons.link_rounded,
              label: 'Copy link',
              prominent: true,
              onSelected: () {},
            ),
            LibraryMenuAction(
              icon: Icons.bookmark_add_outlined,
              label: 'My Space',
              prominent: true,
              onSelected: () {},
            ),
          ],
        ),
      );
      await open(tester);

      final share = tester.getRect(find.bySemanticsLabel('Share'));
      final link = tester.getRect(find.bySemanticsLabel('Copy link'));
      final space = tester.getRect(find.bySemanticsLabel('My Space'));
      // One row, equal widths, every button at least the platform minimum.
      expect(link.top, closeTo(share.top, 0.5));
      expect(space.top, closeTo(share.top, 0.5));
      expect(link.width, closeTo(share.width, 0.5));
      expect(space.width, closeTo(share.width, 0.5));
      expect(share.left, lessThan(link.left));
      expect(link.left, lessThan(space.left));
      for (final rect in [share, link, space]) {
        expect(rect.width, greaterThanOrEqualTo(44));
        expect(rect.height, greaterThanOrEqualTo(44));
      }
      // Icon over label.
      final shareIcon = tester.getRect(find.byIcon(Icons.ios_share_rounded));
      expect(
        shareIcon.bottom,
        lessThanOrEqualTo(tester.getRect(find.text('Share')).top + 0.5),
      );

      final openRow = tester.getRect(find.text('Open'));
      final deleteRow = tester.getRect(find.text('Delete'));
      expect(openRow.top, greaterThan(share.bottom));
      // Destructive is grouped last even though it was passed first.
      expect(deleteRow.top, greaterThan(openRow.bottom));
      semantics.dispose();
    });

    testWidgets('only four fit in the row; the rest fall into the list', (
      tester,
    ) async {
      usePhone(tester);
      await tester.pumpWidget(
        host(
          card: const Rect.fromLTWH(16, 100, 361, 120),
          actions: [
            for (var i = 1; i <= 5; i++)
              LibraryMenuAction(
                icon: Icons.star_outline_rounded,
                label: 'Quick $i',
                prominent: true,
                onSelected: () {},
              ),
          ],
        ),
      );
      await open(tester);

      final first = tester.getRect(find.text('Quick 1'));
      final fourth = tester.getRect(find.text('Quick 4'));
      final fifth = tester.getRect(find.text('Quick 5'));
      expect(fourth.center.dy, closeTo(first.center.dy, 0.5));
      expect(fifth.top, greaterThan(first.bottom));
    });

    testWidgets('a narrow window keeps every quick button readable', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(220, 700) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          card: const Rect.fromLTWH(8, 80, 204, 90),
          actions: [
            for (var i = 1; i <= 4; i++)
              LibraryMenuAction(
                icon: Icons.star_outline_rounded,
                label: 'Quick $i',
                prominent: true,
                onSelected: () {},
              ),
          ],
        ),
      );
      await open(tester);

      final first = tester.getRect(find.text('Quick 1'));
      final second = tester.getRect(find.text('Quick 2'));
      final third = tester.getRect(find.text('Quick 3'));
      expect(second.center.dy, closeTo(first.center.dy, 0.5));
      // Demoted into the list rather than squeezed under 64 wide.
      expect(third.top, greaterThan(first.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a prominent button runs its action once after closing', (
      tester,
    ) async {
      usePhone(tester);
      var shares = 0;
      await tester.pumpWidget(
        host(
          card: const Rect.fromLTWH(16, 100, 361, 120),
          actions: [
            LibraryMenuAction(
              icon: Icons.ios_share_rounded,
              label: 'Share',
              prominent: true,
              onSelected: () => shares++,
            ),
            LibraryMenuAction(
              icon: Icons.open_in_new_rounded,
              label: 'Open',
              onSelected: () {},
            ),
          ],
        ),
      );
      await open(tester);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(shares, 1);
      expect(find.text('Open'), findsNothing);
    });
  });

  group('contrast', () {
    for (final entry in {
      'dark': (AppTheme.darkTheme, AppColors.dark),
      'light': (AppTheme.lightTheme, AppColors.light),
    }.entries) {
      testWidgets('labels and icons clear AA on the panel (${entry.key})', (
        tester,
      ) async {
        usePhone(tester);
        final (theme, colors) = entry.value;
        await tester.pumpWidget(
          host(
            card: const Rect.fromLTWH(16, 100, 361, 120),
            theme: theme,
            actions: [
              LibraryMenuAction(
                icon: Icons.copy_rounded,
                label: 'Copy PGN',
                onSelected: () {},
              ),
              LibraryMenuAction(
                icon: Icons.ios_share_rounded,
                label: 'Share',
                prominent: true,
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
        await open(tester);

        for (final label in ['Copy PGN', 'Share', 'Delete game']) {
          final text = find.text(label);
          final panel = surfaceBehind(tester, text);
          final color = tester.widget<Text>(text).style!.color!;
          expect(
            contrast(Color.alphaBlend(color, panel), panel),
            greaterThanOrEqualTo(4.5),
            reason: '$label on the ${entry.key} panel',
          );
        }
        for (final icon in [
          Icons.copy_rounded,
          Icons.ios_share_rounded,
          Icons.delete_outline_rounded,
        ]) {
          final finder = find.byIcon(icon);
          final panel = surfaceBehind(tester, finder);
          final color = tester.widget<Icon>(finder).color!;
          expect(
            contrast(Color.alphaBlend(color, panel), panel),
            greaterThanOrEqualTo(3.0),
            reason: '$icon on the ${entry.key} panel',
          );
        }

        // The panel stands off the veiled page (a surface-toned card does
        // too). Light: paper against a dimmed page. Dark: a tonal step, with
        // the lip drawing the edge, so only a floor is guarded there.
        final veil = tester
            .widget<ColoredBox>(
              find.descendant(
                of: find.byType(BackdropFilter),
                matching: find.byType(ColoredBox),
              ),
            )
            .color;
        final veiledPage = Color.alphaBlend(veil, colors.background);
        final panel = surfaceBehind(tester, find.text('Copy PGN'));
        expect(
          contrast(panel, veiledPage),
          greaterThanOrEqualTo(entry.key == 'light' ? 1.75 : 1.12),
        );
      });
    }
  });

  testWidgets('reduced motion: no lift or scale, the blur still arrives', (
    tester,
  ) async {
    usePhone(tester);
    const card = Rect.fromLTWH(16, 100, 361, 120);
    await tester.pumpWidget(
      host(card: card, actions: rows(2), reduceMotion: true),
    );
    await tester.longPress(find.byKey(cardKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // Every frame: the copy sits exactly on the card, unscaled.
    expect(tester.getRect(find.byKey(previewKey)), card);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(previewKey)), card);
    final backdrop = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(backdrop.enabled, isTrue);
    expect(find.text('Copy PGN'), findsOneWidget);
    // Nothing on the panel is scaled either.
    final label = tester.getRect(find.text('Copy PGN'));
    final unscaled = tester.getSize(find.text('Copy PGN'));
    expect(label.width, closeTo(unscaled.width, 0.001));
    expect(label.height, closeTo(unscaled.height, 0.001));

    await tester.tapAt(const Offset(200, 800));
    await tester.pumpAndSettle();
    expect(find.text('Copy PGN'), findsNothing);
  });

  testWidgets('announces a menu and exposes every action as a button', (
    tester,
  ) async {
    usePhone(tester);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        card: const Rect.fromLTWH(16, 100, 361, 120),
        actions: [
          ...rows(1),
          LibraryMenuAction(
            icon: Icons.drive_file_move_rounded,
            label: 'Move to database',
            enabled: false,
            onSelected: () {},
          ),
        ],
      ),
    );
    await open(tester);

    expect(
      tester.getSemantics(find.bySemanticsLabel('Popup menu')),
      isSemantics(scopesRoute: true, namesRoute: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Copy PGN')),
      isSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Move to database')),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
    );
    semantics.dispose();
  });

  group('CardContextMenu', () {
    Widget cardHost({
      required Widget Function(List<LibraryMenuAction> actions) build,
      required List<LibraryMenuAction> actions,
    }) {
      return MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Padding(
                padding: const EdgeInsets.fromLTRB(16, 120, 16, 0),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: build(actions),
                ),
              ),
            );
          },
        ),
      );
    }

    Widget card() => SizedBox(
      key: cardKey,
      height: 96,
      child: Material(
        color: const Color(0xFF1A1A1C),
        child: Row(
          children: const [
            Expanded(child: Text('Carlsen - Nakamura')),
            CardMoreButton(),
          ],
        ),
      ),
    );

    testWidgets(
      'long-press lifts the card itself; the dots open the same menu',
      (tester) async {
        usePhone(tester);
        var opened = 0;
        await tester.pumpWidget(
          cardHost(
            actions: [
              LibraryMenuAction(
                icon: Icons.open_in_new_rounded,
                label: 'Open',
                onSelected: () => opened++,
              ),
            ],
            build: (actions) =>
                CardContextMenu(actions: (_) => actions, child: card()),
          ),
        );

        await tester.longPress(find.byKey(cardKey));
        await tester.pumpAndSettle();
        // The original plus its lifted copy.
        expect(find.byKey(cardKey), findsNWidgets(2));
        expect(find.text('Open'), findsOneWidget);
        await tester.tapAt(const Offset(200, 800));
        await tester.pumpAndSettle();
        expect(find.text('Open'), findsNothing);

        await tester.tap(find.byType(CardMoreButton));
        await tester.pumpAndSettle();
        expect(find.byKey(cardKey), findsNWidgets(2));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(opened, 1);
        expect(find.byKey(cardKey), findsOneWidget);
      },
    );

    testWidgets('the original hides while its copy is lifted', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        cardHost(
          actions: rows(1),
          build: (actions) =>
              CardContextMenu(actions: (_) => actions, child: card()),
        ),
      );
      Visibility visibility() => tester.widget<Visibility>(
        find.descendant(
          of: find.byType(CardContextMenu),
          matching: find.byType(Visibility),
        ),
      );

      expect(visibility().visible, isTrue);
      await tester.longPress(find.byKey(cardKey));
      await tester.pump();
      expect(visibility().visible, isFalse);
      await tester.pumpAndSettle();
      expect(visibility().visible, isFalse);

      await tester.tapAt(const Offset(200, 800));
      await tester.pumpAndSettle();
      expect(visibility().visible, isTrue);
      expect(find.byKey(cardKey), findsOneWidget);
    });

    testWidgets('previewBuilder lifts a stand-in instead of a rebuilt card', (
      tester,
    ) async {
      usePhone(tester);
      await tester.pumpWidget(
        cardHost(
          actions: rows(1),
          build: (actions) => CardContextMenu(
            actions: (_) => actions,
            previewBuilder: (_) => const SizedBox(key: previewKey, height: 96),
            child: card(),
          ),
        ),
      );

      await tester.longPress(find.byKey(cardKey));
      await tester.pumpAndSettle();
      expect(find.byKey(cardKey), findsOneWidget);
      expect(find.byKey(previewKey), findsOneWidget);
    });

    testWidgets('disabled wrapper leaves the card alone', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        cardHost(
          actions: rows(1),
          build: (actions) => CardContextMenu(
            enabled: false,
            actions: (_) => actions,
            child: card(),
          ),
        ),
      );

      await tester.longPress(find.byKey(cardKey).first);
      await tester.pumpAndSettle();
      expect(find.text('Copy PGN'), findsNothing);
    });
  });
}
