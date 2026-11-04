import 'package:chessever2/widgets/window_orientation_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <List<String>>[];
  const portrait = [
    'DeviceOrientation.portraitUp',
    'DeviceOrientation.portraitDown',
  ];

  setUp(() {
    requests.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            requests.add(List<String>.from(call.arguments as List));
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  void metrics(
    WidgetTester tester, {
    required Size display,
    Size view = const Size(393, 852),
    double dpr = 3,
  }) {
    tester.view.devicePixelRatio = dpr;
    tester.view.display.size = display * dpr;
    tester.view.physicalSize = view * dpr;
  }

  Future<void> mount(WidgetTester tester) async {
    addTearDown(tester.view.reset);
    addTearDown(tester.view.display.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => WindowOrientationScope(child: child!),
        home: const Scaffold(body: Text('Existing UI')),
      ),
    );
  }

  testWidgets('expanded display releases lock despite compact app viewport', (
    tester,
  ) async {
    metrics(tester, display: const Size(951, 669));
    await mount(tester);
    expect(requests, [<String>[]]);
    expect(
      MediaQuery.sizeOf(tester.element(find.text('Existing UI'))),
      const Size(393, 852),
    );
  });

  testWidgets('display-only unfold and refold update orientation policy', (
    tester,
  ) async {
    metrics(tester, display: const Size(466, 678));
    await mount(tester);
    expect(requests, [portrait]);
    final content = tester.element(find.text('Existing UI'));

    // The locked viewport has not resized yet. The display still unlocks it.
    tester.view.display.size = const Size(951, 669) * 3;
    await tester.pump();
    expect(requests, [portrait, <String>[]]);
    expect(tester.element(find.text('Existing UI')), same(content));

    tester.view.display.size = const Size(466, 678) * 3;
    await tester.pump();
    expect(requests, [portrait, <String>[], portrait]);
  });

  testWidgets('ordinary phone remains portrait when held sideways', (
    tester,
  ) async {
    metrics(tester, display: const Size(393, 852));
    await mount(tester);
    metrics(tester, display: const Size(852, 393), view: const Size(852, 393));
    await tester.pump();
    expect(requests, [portrait]);
  });

  testWidgets(
    'side safe areas cannot turn expanded display into portrait lock',
    (tester) async {
      metrics(
        tester,
        display: const Size(626, 890),
        view: const Size(626, 890),
      );
      tester.view.viewPadding = const FakeViewPadding(right: 240);
      tester.view.padding = const FakeViewPadding(right: 240);
      await mount(tester);
      expect(requests, [<String>[]]);
    },
  );

  testWidgets('iPad split window stays free to rotate', (tester) async {
    metrics(
      tester,
      display: const Size(1194, 834),
      view: const Size(375, 834),
      dpr: 2,
    );
    await mount(tester);
    expect(requests, [<String>[]]);
  });

  testWidgets(
    'unknown display metrics do not introduce a startup portrait lock',
    (tester) async {
      metrics(tester, display: Size.zero);
      await mount(tester);
      expect(requests, [<String>[]]);
      tester.view.display.size = const Size(393, 852) * 3;
      await tester.pump();
      expect(requests, [<String>[], portrait]);
    },
  );

  testWidgets(
    'rotation and keyboard metrics do not repeatedly request orientation',
    (tester) async {
      metrics(tester, display: const Size(951, 669));
      await mount(tester);
      metrics(
        tester,
        display: const Size(669, 951),
        view: const Size(669, 951),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pump();
      expect(requests, [<String>[]]);
    },
  );

  testWidgets('unmounted orientation scope stops observing display metrics', (
    tester,
  ) async {
    metrics(tester, display: const Size(393, 852));
    await mount(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.display.size = const Size(951, 669) * 3;
    await tester.pump();
    expect(requests, [portrait]);
  });
}
