import 'package:chessever2/widgets/page_spring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Three pages, 400 wide, and a context to read the motion setting from.
class _Pages extends StatelessWidget {
  const _Pages({required this.controller, required this.onContext});

  final PageController controller;
  final ValueChanged<BuildContext> onContext;

  @override
  Widget build(BuildContext context) {
    onContext(context);
    return PageView(
      controller: controller,
      children: [for (var i = 0; i < 3; i++) Center(child: Text('page $i'))],
    );
  }
}

Future<(PageController, BuildContext)> _pump(
  WidgetTester tester, {
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = PageController();
  addTearDown(controller.dispose);
  late BuildContext context;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: const Size(400, 800),
        disableAnimations: reduceMotion,
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: _Pages(controller: controller, onContext: (c) => context = c),
      ),
    ),
  );
  return (controller, context);
}

void main() {
  testWidgets('springs to the page and lands on it exactly, then rests', (
    tester,
  ) async {
    final (controller, context) = await _pump(tester);
    var done = false;
    PageSpring.to(controller, 2, context: context).then((_) => done = true);

    final pixels = <double>[controller.position.pixels];
    var frames = 0;
    while (tester.binding.hasScheduledFrame && frames < 120) {
      await tester.pump(const Duration(milliseconds: 16));
      frames++;
      pixels.add(controller.position.pixels);
    }
    expect(controller.position.pixels, 800);
    expect(controller.page, 2);
    expect(done, isTrue);
    // Critically damped: always toward the page, never past it.
    for (var i = 1; i < pixels.length; i++) {
      expect(pixels[i], greaterThanOrEqualTo(pixels[i - 1]));
      expect(pixels[i], lessThanOrEqualTo(800));
    }
    // A spring from rest: it starts gently and is quickest mid-way.
    final steps = [
      for (var i = 1; i < pixels.length; i++) pixels[i] - pixels[i - 1],
    ];
    final fastest = steps.reduce((a, b) => a > b ? a : b);
    expect(steps.first, lessThan(fastest));
    // Parked once home: no sub-pixel creep scheduling frames.
    expect(frames * 16, lessThan(700));
  });

  testWidgets('reduced motion jumps', (tester) async {
    final (controller, context) = await _pump(tester, reduceMotion: true);
    await PageSpring.to(controller, 1, context: context);
    // There at once: no frame of motion.
    expect(controller.position.pixels, 400);
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.position.pixels, 400);
  });

  testWidgets('another tab mid-flight turns round carrying the speed', (
    tester,
  ) async {
    final (controller, context) = await _pump(tester);
    var firstDone = false;
    PageSpring.to(
      controller,
      2,
      context: context,
    ).then((_) => firstDone = true);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final before = controller.position.pixels;
    expect(before, inExclusiveRange(0, 800));

    controller.springTo(0, context: context);
    await tester.pump(const Duration(milliseconds: 16));
    // Still moving the way it was: it turns round, it does not stop dead
    // and restart from rest.
    expect(controller.position.pixels, greaterThan(before));
    // The first spring has handed over.
    expect(firstDone, isTrue);

    await tester.pumpAndSettle();
    expect(controller.position.pixels, 0);
  });

  testWidgets('a list goes back to its top on the same spring, or jumps '
      'with reduced motion', (tester) async {
    for (final reduceMotion in [false, true]) {
      final controller = ScrollController(initialScrollOffset: 3000);
      late BuildContext context;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (c) {
                context = c;
                return ListView.builder(
                  controller: controller,
                  itemCount: 200,
                  itemBuilder: (_, i) =>
                      SizedBox(height: 50, child: Text('$i')),
                );
              },
            ),
          ),
        ),
      );
      expect(controller.offset, 3000);
      var done = false;
      controller.springToOffset(0, context: context).then((_) => done = true);
      if (reduceMotion) {
        // There at once: no frame of motion.
        expect(controller.offset, 0);
      } else {
        final spring = SpringCurve.of(PageSpring.motion);
        // A spring from rest, settled in about the time a tab change takes.
        expect(spring.duration, lessThan(const Duration(milliseconds: 700)));
        // The first frame starts the clock; the next one moves.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(controller.offset, inExclusiveRange(0, 3000));
        await tester.pump(spring.duration);
        expect(controller.offset, 0);
      }
      await tester.pump();
      expect(done, isTrue);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });

  testWidgets('a finger takes over at once', (tester) async {
    final (controller, context) = await _pump(tester);
    var done = false;
    PageSpring.to(controller, 2, context: context).then((_) => done = true);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final gesture = await tester.startGesture(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 16));
    expect(done, isTrue);
    final held = controller.position.pixels;
    await tester.pump(const Duration(milliseconds: 100));
    // Held under the finger.
    expect(controller.position.pixels, held);
    await gesture.up();
    await tester.pumpAndSettle();
    // Let go, it settles on a page as after any swipe.
    expect(controller.page! % 1, 0);
  });
}
