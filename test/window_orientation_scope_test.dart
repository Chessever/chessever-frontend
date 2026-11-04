import 'dart:io';

import 'package:chessever2/widgets/window_orientation_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/duo_window_matrix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <List<String>>[];

  test(
    'iPhone native configuration permits portrait and both landscape directions',
    () {
      final info = File('ios/Runner/Info.plist').readAsStringSync();
      final phoneOrientations = RegExp(
        r'<key>UISupportedInterfaceOrientations</key>\s*<array>(.*?)</array>',
        dotAll: true,
      ).firstMatch(info)!.group(1)!;
      for (final orientation in [
        'UIInterfaceOrientationPortrait',
        'UIInterfaceOrientationLandscapeLeft',
        'UIInterfaceOrientationLandscapeRight',
      ]) {
        expect(phoneOrientations, contains('<string>$orientation</string>'));
      }
    },
  );

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

  void metrics(WidgetTester tester, Size size, {bool letterboxed = false}) {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = (letterboxed ? const Size(393, 852) : size) * 3;
    tester.view.display.size = size * 3;
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

  for (final state in duoWindowCases) {
    for (final letterboxed in [false, true]) {
      testWidgets(
        'cold ${state.name} allows rotation, letterboxed=$letterboxed',
        (tester) async {
          metrics(tester, state.size, letterboxed: letterboxed);
          await mount(tester);
          expect(requests, [<String>[]]);
        },
      );
    }
  }

  for (final transition in duoWindowTransitions) {
    testWidgets('${transition.from.name} → ${transition.to.name} never locks', (
      tester,
    ) async {
      metrics(tester, transition.from.size);
      await mount(tester);
      final content = tester.element(find.text('Existing UI'));
      // Display reports first while the viewport still has the old shape.
      tester.view.display.size = transition.to.size * 3;
      await tester.pump();
      expect(requests, [<String>[]]);
      tester.view.physicalSize = transition.to.size * 3;
      await tester.pump();
      expect(requests, [<String>[]]);
      expect(tester.element(find.text('Existing UI')), same(content));
    });
  }

  testWidgets('unknown metrics and keyboard changes cannot introduce a lock', (
    tester,
  ) async {
    metrics(tester, const Size(466, 678));
    tester.view.display.size = Size.zero;
    await mount(tester);
    tester.view.display.size = const Size(466, 678) * 3;
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pump();
    expect(requests, [<String>[]]);
  });

  testWidgets('unmounted scope does not handle later metric changes', (
    tester,
  ) async {
    metrics(tester, const Size(466, 678));
    await mount(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.display.size = const Size(951, 669) * 3;
    await tester.pump();
    expect(requests, [<String>[]]);
  });
}
