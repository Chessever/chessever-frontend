import 'package:chessever2/utils/adaptive_window.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/window_orientation_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/duo_window_matrix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final orientationRequests = <List<String>>[];

  setUp(() {
    orientationRequests.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            orientationRequests.add(List<String>.from(call.arguments as List));
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  EdgeInsets setWindow(
    WidgetTester tester,
    DuoWindowCase state, {
    double keyboard = 0,
    bool mirrorInsets = false,
  }) {
    final safe = state.landscape
        ? EdgeInsets.only(
            left: mirrorInsets ? 20 : 62,
            right: mirrorInsets ? 62 : 20,
            bottom: 21,
          )
        : const EdgeInsets.only(top: 59, bottom: 34);
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = state.size * 3;
    tester.view.display.size = state.size * 3;
    tester.view.viewPadding = FakeViewPadding(
      left: safe.left * 3,
      right: safe.right * 3,
      top: safe.top * 3,
      bottom: safe.bottom * 3,
    );
    tester.view.padding = FakeViewPadding(
      left: safe.left * 3,
      right: safe.right * 3,
      top: safe.top * 3,
      bottom: keyboard == 0 ? safe.bottom * 3 : 0,
    );
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
    return safe;
  }

  Widget app(GlobalKey<NavigatorState> navigator, Widget home) => MaterialApp(
    navigatorKey: navigator,
    builder: (_, child) => MediaQuery.withClampedTextScaling(
      minScaleFactor: 1.3,
      maxScaleFactor: 1.3,
      child: WindowOrientationScope(child: AdaptiveWindowScope(child: child!)),
    ),
    home: home,
  );

  void resetAfter(WidgetTester tester) {
    addTearDown(tester.view.reset);
    addTearDown(tester.view.display.reset);
  }

  for (final state in duoWindowCases) {
    testWidgets('${state.name}: real root scopes clear insets at cold start', (
      tester,
    ) async {
      resetAfter(tester);
      final safe = setWindow(tester, state);
      const contentKey = ValueKey('cold-content');
      await tester.pumpWidget(
        app(
          GlobalKey<NavigatorState>(),
          const Scaffold(body: SizedBox.expand(key: contentKey)),
        ),
      );
      expect(orientationRequests, [<String>[]]);
      expect(ResponsiveHelper.screenWidth, state.size.width - safe.horizontal);
      expect(ResponsiveHelper.isLandscape, state.landscape);
      final rect = tester.getRect(find.byKey(contentKey));
      expect(rect.left, safe.left);
      expect(rect.right, state.size.width - safe.right);
      expect(tester.takeException(), isNull);
    });
  }

  for (final transition in duoWindowTransitions) {
    for (final keyboard in [0.0, 240.0]) {
      testWidgets(
        '${transition.from.name} → ${transition.to.name}: route, dialog, edits; keyboard=$keyboard',
        (tester) async {
          resetAfter(tester);
          setWindow(tester, transition.from);
          final navigator = GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            app(navigator, const Scaffold(body: Text('Home route'))),
          );
          navigator.currentState!.push(
            MaterialPageRoute<void>(builder: (_) => const _EditProbe()),
          );
          await tester.pumpAndSettle();
          final probe = tester.state<_EditProbeState>(find.byType(_EditProbe));
          await tester.enterText(find.byType(TextField), 'Najdorf');
          await tester.tap(find.text('Mark'));
          await tester.pump();
          showDialog<void>(
            context: probe.context,
            builder: (_) => const AlertDialog(content: Text('Open dialog')),
          );
          await tester.pumpAndSettle();

          final safe = setWindow(
            tester,
            transition.to,
            keyboard: keyboard,
            mirrorInsets: true,
          );
          await tester.pumpAndSettle();
          expect(find.text('Open dialog'), findsOneWidget);
          expect(
            tester.state<_EditProbeState>(find.byType(_EditProbe)),
            same(probe),
          );
          expect(probe.controller.text, 'Najdorf');
          expect(probe.marks, 1);
          expect(orientationRequests, [<String>[]]);
          expect(
            ResponsiveHelper.screenWidth,
            transition.to.size.width - safe.horizontal,
          );
          expect(tester.takeException(), isNull);

          navigator.currentState!.pop();
          await tester.pumpAndSettle();
          expect(find.text('Najdorf'), findsOneWidget);
          navigator.currentState!.pop();
          await tester.pumpAndSettle();
          expect(find.text('Home route'), findsOneWidget);
          expect(navigator.currentState!.canPop(), isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

class _EditProbe extends StatefulWidget {
  const _EditProbe();

  @override
  State<_EditProbe> createState() => _EditProbeState();
}

class _EditProbeState extends State<_EditProbe> {
  final controller = TextEditingController();
  int marks = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        children: [
          TextField(controller: controller),
          Text('Marks: $marks'),
          TextButton(
            onPressed: () => setState(() => marks++),
            child: const Text('Mark'),
          ),
        ],
      ),
    ),
  );
}
