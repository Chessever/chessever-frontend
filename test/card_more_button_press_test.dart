import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The 3-dot inside a pressable card presses itself, never the card, and a
/// card held in its press-scale lifts from the size it was held at.
void main() {
  const cardKey = ValueKey('card');

  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(393, 852) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  List<LibraryMenuAction> actions() => [
    LibraryMenuAction(
      icon: Icons.open_in_new_rounded,
      label: 'Open',
      onSelected: () {},
    ),
  ];

  /// A card the way the library builds one: its own press-scale inside, a
  /// filled surface, and a trailing 3-dot.
  Widget pressableCard({required VoidCallback onTap}) => CardContextMenu(
    actions: (_) => actions(),
    child: TappableScale(
      onTap: onTap,
      child: SizedBox(
        key: cardKey,
        height: 96,
        child: ColoredBox(
          color: const Color(0xFF1A1A1C),
          child: Row(
            children: const [
              Expanded(child: Text('Carlsen - Nakamura')),
              CardMoreButton(),
            ],
          ),
        ),
      ),
    ),
  );

  Widget host(Widget body) => MaterialApp(
    theme: AppTheme.darkTheme,
    home: Builder(
      builder: (context) {
        ResponsiveHelper.init(context);
        return Scaffold(body: body);
      },
    ),
  );

  /// The horizontal scale (a 2D scale leaves z at 1, so the max axis would).
  double scaleOf(WidgetTester tester, Finder transform) =>
      tester.widget<Transform>(transform).transform.entry(0, 0);

  Finder cardTransform() => find
      .descendant(
        of: find.byType(TappableScale),
        matching: find.byType(Transform),
      )
      .first;

  Finder dotTransform() => find
      .descendant(
        of: find.byType(CardMoreButton),
        matching: find.byType(Transform),
      )
      .last;

  Future<void> frames(WidgetTester tester, Duration total) async {
    const step = Duration(milliseconds: 16);
    for (var t = Duration.zero; t < total; t += step) {
      await tester.pump(step);
    }
  }

  testWidgets('holding the dots presses the dots, not the card', (
    tester,
  ) async {
    usePhone(tester);
    var cardTaps = 0;
    await tester.pumpWidget(
      host(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 120, 16, 0),
          child: Align(
            alignment: Alignment.topCenter,
            child: pressableCard(onTap: () => cardTaps++),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CardMoreButton)),
    );
    // Well past the press timeout, where every tap under the finger would
    // otherwise report its press.
    await frames(tester, const Duration(milliseconds: 300));

    expect(scaleOf(tester, cardTransform()), 1.0);
    expect(scaleOf(tester, dotTransform()), closeTo(0.97, 0.002));
    final fill = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(CardMoreButton),
            matching: find.byType(DecoratedBox),
          )
          .last,
    );
    expect((fill.decoration as BoxDecoration).color!.a, greaterThan(0));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(cardTaps, 0);
  });

  testWidgets('a fling that starts on the dots still scrolls the list', (
    tester,
  ) async {
    usePhone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            for (var i = 0; i < 12; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: pressableCard(onTap: () {}),
              ),
          ],
        ),
      ),
    );

    await tester.drag(find.byType(CardMoreButton).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(find.text('Open'), findsNothing);
  });

  testWidgets('a card held in its press-scale lifts from the held size', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(
      host(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 120, 16, 0),
          child: Align(
            alignment: Alignment.topCenter,
            child: pressableCard(onTap: () {}),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getTopLeft(find.byKey(cardKey)) + const Offset(40, 48),
    );
    // Held until just before the long-press: the card is pressed in.
    await frames(tester, kLongPressTimeout - const Duration(milliseconds: 20));
    final held = tester.getRect(find.byKey(cardKey));
    final rest = tester.getSize(find.byKey(cardKey));
    expect(held.width, lessThan(rest.width - 4));

    // The long-press fires; the next frame is the copy's first.
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byKey(cardKey), findsNWidgets(2));
    final copy = tester.getRect(find.byKey(cardKey).last);
    expect(copy.width, closeTo(held.width, 1.5));
    expect(copy.center.dx, closeTo(held.center.dx, 1.5));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });
}
