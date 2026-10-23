import 'package:chessever2/widgets/layout_swap_scroll_keeper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a list swapped for a grid keeps the share already scrolled', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final columns = ValueNotifier<int>(1);
    addTearDown(columns.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: columns,
          builder: (context, count, _) => LayoutSwapScrollKeeper(
            controller: controller,
            layout: count,
            child: count == 1
                ? ListView.builder(
                    controller: controller,
                    itemCount: 100,
                    itemExtent: 100,
                    itemBuilder: (_, i) => Text('row $i'),
                  )
                : GridView.builder(
                    controller: controller,
                    itemCount: 100,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: count,
                      mainAxisExtent: 150,
                    ),
                    itemBuilder: (_, i) => Text('cell $i'),
                  ),
          ),
        ),
      ),
    );

    final listMax = controller.position.maxScrollExtent;
    controller.jumpTo(listMax * 0.6);
    await tester.pump();

    columns.value = 2;
    await tester.pump();
    await tester.pump();

    final gridMax = controller.position.maxScrollExtent;
    expect(gridMax, isNot(listMax));
    expect(controller.offset, closeTo(gridMax * 0.6, 1));

    columns.value = 1;
    await tester.pump();
    await tester.pump();
    expect(controller.offset, closeTo(listMax * 0.6, 1));
  });

  testWidgets('the top of a list stays the top', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final columns = ValueNotifier<int>(1);
    addTearDown(columns.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: columns,
          builder: (context, count, _) => LayoutSwapScrollKeeper(
            controller: controller,
            layout: count,
            child: count == 1
                ? ListView.builder(
                    controller: controller,
                    itemCount: 50,
                    itemExtent: 100,
                    itemBuilder: (_, i) => Text('row $i'),
                  )
                : GridView.count(
                    controller: controller,
                    crossAxisCount: count,
                    children: [for (var i = 0; i < 50; i++) Text('cell $i')],
                  ),
          ),
        ),
      ),
    );

    columns.value = 2;
    await tester.pump();
    await tester.pump();
    expect(controller.offset, 0);
  });
}
