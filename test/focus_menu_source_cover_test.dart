import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The focus menu keeps the pressed card out of its own blur, sets a
/// fill-less copy on the surface it came from, and leaves a focused search
/// field (and its keyboard) alone.
void main() {
  const cardKey = ValueKey('card');
  const previewKey = ValueKey('preview');
  const page = Color(0xFF123456);
  const card = Rect.fromLTWH(16, 160, 361, 96);

  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(393, 852) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  List<LibraryMenuAction> actions() => [
    LibraryMenuAction(
      icon: Icons.copy_rounded,
      label: 'Copy PGN',
      onSelected: () {},
    ),
  ];

  Widget host({
    Widget? under,
    Widget body = const ColoredBox(color: Color(0xFF2F5D50)),
    ValueChanged<bool>? onPreviewLiftChanged,
    Widget? above,
  }) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            backgroundColor: page,
            body: Stack(
              children: [
                if (under != null) under,
                Positioned.fromRect(
                  rect: card,
                  child: Builder(
                    builder: (cardContext) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: () => showLibraryContextMenu(
                        context: cardContext,
                        actions: actions(),
                        onPreviewLiftChanged: onPreviewLiftChanged,
                        previewBuilder: (_) => KeyedSubtree(
                          key: previewKey,
                          child: SizedBox(height: card.height, child: body),
                        ),
                      ),
                      child: KeyedSubtree(key: cardKey, child: body),
                    ),
                  ),
                ),
                if (above != null) above,
              ],
            ),
          );
        },
      ),
    );
  }

  Finder slot() => find.byWidgetPredicate(
    (widget) => widget is ColoredBox && widget.color == page,
  );

  /// Painted beside the copy, under it: the page itself is a Material, so
  /// the only box in the page's colour is the plate.
  Finder plate() => find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).color == page,
  );

  testWidgets('covers the card with the page surface while its copy is up', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(host());
    await tester.longPress(find.byKey(cardKey));
    await tester.pump();
    // From the first frame, so the blur never samples the original.
    expect(tester.getRect(slot()), card);
    await tester.pumpAndSettle();
    expect(tester.getRect(slot()), card);
    // Painted under the veil, never inside it.
    expect(
      find.descendant(of: find.byType(BackdropFilter), matching: slot()),
      findsNothing,
    );

    await tester.tapAt(const Offset(200, 800));
    await tester.pumpAndSettle();
    expect(slot(), findsNothing);
  });

  testWidgets('only covers the part of the card left on screen', (
    tester,
  ) async {
    usePhone(tester);
    final scroll = ScrollController(initialScrollOffset: 50);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              backgroundColor: page,
              body: Column(
                children: [
                  const SizedBox(height: 200),
                  Expanded(
                    child: ListView(
                      controller: scroll,
                      children: [
                        Builder(
                          builder: (cardContext) => GestureDetector(
                            onLongPress: () => showLibraryContextMenu(
                              context: cardContext,
                              actions: actions(),
                              previewBuilder: (_) => const SizedBox(
                                height: 96,
                                child: ColoredBox(color: Color(0xFF2F5D50)),
                              ),
                            ),
                            child: const SizedBox(
                              key: cardKey,
                              height: 96,
                              child: ColoredBox(color: Color(0xFF2F5D50)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2000),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.longPressAt(const Offset(200, 220));
    await tester.pumpAndSettle();
    // The list clips the card at its top edge; the header above stays clear.
    expect(tester.getRect(slot()), const Rect.fromLTRB(0, 200, 393, 246));
  });

  testWidgets('leaves the hiding to a host that hides its own card', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(host(onPreviewLiftChanged: (_) {}));
    await tester.longPress(find.byKey(cardKey));
    await tester.pumpAndSettle();
    expect(find.text('Copy PGN'), findsOneWidget);
    expect(slot(), findsNothing);
  });

  testWidgets('never guesses over a background it cannot read', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(
      host(
        under: const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF000000), Color(0xFFFFFFFF)],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.longPress(find.byKey(cardKey));
    await tester.pumpAndSettle();
    expect(find.text('Copy PGN'), findsOneWidget);
    expect(slot(), findsNothing);
  });

  testWidgets('a flat backdrop layer under the card is the surface', (
    tester,
  ) async {
    usePhone(tester);
    const layer = Color(0xFF3A2B1C);
    await tester.pumpWidget(
      host(
        under: Positioned.fill(child: Container(color: layer)),
      ),
    );
    await tester.longPress(find.byKey(cardKey));
    await tester.pumpAndSettle();
    final cover = find.byWidgetPredicate(
      (widget) => widget is ColoredBox && widget.color == layer,
    );
    // The backdrop itself, plus the cover over the card.
    expect(cover, findsNWidgets(2));
    expect(tester.getRect(cover.last), card);
    expect(slot(), findsNothing);
  });

  testWidgets('sets a fill-less copy on the surface it sat on', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(
      host(
        body: const Align(
          alignment: Alignment.centerLeft,
          child: Text('Carlsen - Nakamura'),
        ),
      ),
    );
    await tester.longPress(find.byKey(cardKey));
    await tester.pumpAndSettle();
    expect(plate(), findsOneWidget);
    // Exactly the copy's box: it neither shifts the copy nor pads it.
    expect(tester.getRect(plate()), tester.getRect(find.byKey(previewKey)));
  });

  testWidgets('a card with its own fill lifts on nothing extra', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(host());
    await tester.longPress(find.byKey(cardKey));
    await tester.pumpAndSettle();
    expect(plate(), findsNothing);
  });

  testWidgets('a focused search field keeps its focus through the menu', (
    tester,
  ) async {
    usePhone(tester);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      host(
        above: Positioned(
          left: 16,
          right: 16,
          top: 60,
          child: TextField(focusNode: focus),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    await tester.longPress(find.byKey(cardKey));
    await tester.pumpAndSettle();
    expect(find.text('Copy PGN'), findsOneWidget);
    expect(focus.hasFocus, isTrue);

    await tester.tapAt(const Offset(200, 800));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('a keyboard moving under the open menu does not move it', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(host());
    await tester.longPress(find.byKey(cardKey));
    await tester.pumpAndSettle();
    final before = tester.getRect(find.text('Copy PGN'));

    // Tall enough that a live read would flip the menu above the card.
    tester.view.viewInsets = const FakeViewPadding(bottom: 600 * 3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getRect(find.text('Copy PGN')), before);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Copy PGN')), before);
  });
}
