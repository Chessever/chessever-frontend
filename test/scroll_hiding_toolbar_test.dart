import 'package:chessever2/screens/chessboard/widgets/scroll_hiding_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'video top bar auto-hides while bottom controls remain visible',
    (tester) async {
      Widget app(bool video) => MaterialApp(
        home: ScrollHidingToolbar(
          autoHide: video,
          resetKey: video,
          toolbar: AppBar(title: const Text('Toolbar')),
          bottomBar: const SizedBox(height: 50, child: Text('Controls')),
          builder:
              (context, toolbar, bottomBar) => Scaffold(
                appBar: toolbar,
                bottomNavigationBar: bottomBar,
                body: const SingleChildScrollView(
                  physics: ClampingScrollPhysics(),
                  child: SizedBox(height: 2000, width: double.infinity),
                ),
              ),
        ),
      );
      double height() =>
          tester
              .widget<Scaffold>(find.byType(Scaffold))
              .appBar!
              .preferredSize
              .height;
      await tester.pumpWidget(app(true));
      await tester.pump(const Duration(seconds: 2));
      expect(height(), kToolbarHeight);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(height(), 0);
      expect(find.text('Controls').hitTestable(), findsOneWidget);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 80),
      );
      await tester.pumpAndSettle();
      expect(height(), kToolbarHeight);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(height(), 0);
      await tester.pumpWidget(app(false));
      await tester.pump(const Duration(seconds: 4));
      expect(height(), kToolbarHeight);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('hiding video restores default board position and both bars', (
    tester,
  ) async {
    Widget app(bool video) => MaterialApp(
      home: ScrollHidingToolbar(
        resetKey: video,
        toolbar: AppBar(title: const Text('Game toolbar')),
        bottomBar: const SizedBox(height: 50, child: Text('Move controls')),
        builder:
            (context, toolbar, bottomBar) => Scaffold(
              appBar: toolbar,
              bottomNavigationBar: bottomBar,
              body:
                  video
                      ? const SingleChildScrollView(
                        child: SizedBox(
                          height: 2000,
                          child: Text('Video board'),
                        ),
                      )
                      : const Column(
                        children: [
                          Text('Default board'),
                          Expanded(child: SizedBox()),
                        ],
                      ),
            ),
      ),
    );
    await tester.pumpWidget(app(true));
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Scaffold>(find.byType(Scaffold))
          .appBar!
          .preferredSize
          .height,
      0,
    );
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Scaffold>(find.byType(Scaffold))
          .appBar!
          .preferredSize
          .height,
      kToolbarHeight,
    );
    expect(tester.getTopLeft(find.text('Default board')).dy, kToolbarHeight);
    expect(find.text('Move controls').hitTestable(), findsOneWidget);
  });

  testWidgets('swipe up hides only the top bar and swipe down restores it', (
    tester,
  ) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: ScrollHidingToolbar(
          toolbar: AppBar(title: const Text('Game toolbar')),
          bottomBar: const SizedBox(height: 50, child: Text('Move controls')),
          builder:
              (context, toolbar, bottomBar) => Scaffold(
                appBar: toolbar,
                bottomNavigationBar: bottomBar,
                body: SingleChildScrollView(
                  controller: controller,
                  child: const SizedBox(height: 2000, child: Text('Board')),
                ),
              ),
        ),
      ),
    );
    double height() =>
        tester
            .widget<Scaffold>(find.byType(Scaffold))
            .appBar!
            .preferredSize
            .height;
    expect(height(), kToolbarHeight);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -150),
    );
    await tester.pumpAndSettle();
    expect(height(), 0);
    expect(find.text('Move controls').hitTestable(), findsOneWidget);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 80));
    await tester.pumpAndSettle();
    expect(height(), kToolbarHeight);

    expect(find.text('Move controls').hitTestable(), findsOneWidget);

    // Live-move/programmatic scrolling must not hide the toolbar.
    controller.animateTo(
      450,
      duration: const Duration(milliseconds: 250),
      curve: Curves.linear,
    );
    await tester.pumpAndSettle();
    expect(height(), kToolbarHeight);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'nested notation scroll and horizontal swipes leave toolbar visible',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScrollHidingToolbar(
            toolbar: AppBar(title: const Text('Game toolbar')),
            bottomBar: const SizedBox(height: 50, child: Text('Move controls')),
            builder:
                (context, toolbar, bottomBar) => Scaffold(
                  appBar: toolbar,
                  body: SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 200,
                          child: ListView(
                            key: const ValueKey('notation'),
                            children: const [SizedBox(height: 2000)],
                          ),
                        ),
                        SizedBox(
                          height: 100,
                          child: ListView(
                            key: const ValueKey('flags'),
                            scrollDirection: Axis.horizontal,
                            children: const [SizedBox(width: 2000)],
                          ),
                        ),
                        const SizedBox(height: 2000),
                      ],
                    ),
                  ),
                ),
          ),
        ),
      );
      for (final entry
          in {
            'notation': const Offset(0, -100),
            'flags': const Offset(-100, 0),
          }.entries) {
        await tester.drag(find.byKey(ValueKey(entry.key)), entry.value);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Scaffold>(find.byType(Scaffold))
              .appBar!
              .preferredSize
              .height,
          kToolbarHeight,
        );
      }
    },
  );
}
