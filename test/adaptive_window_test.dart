import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:chessever2/utils/adaptive_window.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Representative compact and expanded window sizes. Layouts depend on the
// available logical space, without relying on a particular device model.
const _duoOuter = Size(466, 678);
const _duoInnerLandscape = Size(951, 669);
const _duoInnerPortrait = Size(669, 951);

void main() {
  group('ResponsiveHelper on iPhone Duo', () {
    test('the outer display is a phone', () {
      ResponsiveHelper.initFromSize(_duoOuter);
      expect(ResponsiveHelper.isPhone, isTrue);
      expect(ResponsiveHelper.isPortrait, isTrue);
    });

    test('the inner display is a tablet in both orientations', () {
      ResponsiveHelper.initFromSize(_duoInnerLandscape);
      expect(ResponsiveHelper.isTablet, isTrue);
      expect(ResponsiveHelper.isLandscape, isTrue);

      ResponsiveHelper.initFromSize(_duoInnerPortrait);
      expect(ResponsiveHelper.isTablet, isTrue);
      expect(ResponsiveHelper.isPortrait, isTrue);
    });

    test('the inner display stays a tablet with the side column removed', () {
      ResponsiveHelper.initFromSize(Size(_duoInnerLandscape.width - 80, 669));
      expect(ResponsiveHelper.isTablet, isTrue);
    });

    test('half of the inner display in Split View is a phone', () {
      ResponsiveHelper.initFromSize(const Size(475, 669));
      expect(ResponsiveHelper.isPhone, isTrue);
    });

    test('a tall narrow window keeps compact navigation', () {
      ResponsiveHelper.initFromSize(const Size(500, 1300));
      expect(ResponsiveHelper.isPhone, isTrue);
    });

    test('column count respects local pane width including gaps', () {
      expect(ResponsiveHelper.columnsForWidth(270), 1);
      expect(ResponsiveHelper.columnsForWidth(575), 1);
      expect(ResponsiveHelper.columnsForWidth(576), 2);
      expect(ResponsiveHelper.columnsForWidth(871), 2);
      expect(ResponsiveHelper.columnsForWidth(872), 3);
      expect(ResponsiveHelper.columnsForWidth(2000), 3);
    });
  });

  group('resolveWindowFold', () {
    WindowFold? resolve(
      Size size, {
      List<DisplayFeature> features = const [],
    }) => resolveWindowFold(windowSize: size, displayFeatures: features);

    test('a reported horizontal hinge retains its occluded area', () {
      final fold = resolve(
        _duoInnerPortrait,
        features: const [
          DisplayFeature(
            bounds: Rect.fromLTRB(0, 465, 669, 485),
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ],
      )!;
      expect(fold.axis, Axis.horizontal);
      expect(fold.bounds.top, 465);
      expect(fold.bounds.height, 20);
      expect(fold.leadingExtentFrom(0), isNull);
      expect(fold.trailingStart, isNull);
    });

    test('window dimensions alone never invent a hinge', () {
      expect(resolve(_duoInnerLandscape), isNull);
      expect(resolve(_duoInnerPortrait), isNull);
      expect(resolve(_duoOuter), isNull, reason: 'outer display');
      expect(resolve(const Size(475, 669)), isNull, reason: 'Split View');
      expect(resolve(const Size(956, 440)), isNull, reason: 'Pro Max');
      expect(resolve(const Size(1180, 820)), isNull, reason: 'iPad');
      expect(resolve(const Size(744, 1133)), isNull, reason: 'mini');
    });

    test('a reported hinge wins and keeps its width', () {
      final fold = resolve(
        const Size(840, 700),
        features: const [
          DisplayFeature(
            bounds: Rect.fromLTRB(410, 0, 430, 700),
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ],
      )!;
      expect(fold.axis, Axis.vertical);
      expect(fold.reported, isTrue);
      expect(fold.trailingStart, 430 + WindowFold.clearance);
    });

    test('a camera cutout is not a fold', () {
      expect(
        resolve(
          const Size(840, 700),
          features: const [
            DisplayFeature(
              bounds: Rect.fromLTRB(400, 0, 440, 30),
              type: DisplayFeatureType.cutout,
              state: DisplayFeatureState.unknown,
            ),
          ],
        ),
        isNull,
      );
    });
  });

  group('AdaptiveWindowScope', () {
    void setWindow(
      WidgetTester tester,
      Size logical, {
      double left = 0,
      double right = 0,
      double top = 0,
    }) {
      const dpr = 3.0;
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = logical * dpr;
      final padding = FakeViewPadding(
        left: left * dpr,
        right: right * dpr,
        top: top * dpr,
      );
      tester.view.padding = padding;
      tester.view.viewPadding = padding;
    }

    Widget app(Widget home) => MaterialApp(
      builder: (context, child) => AdaptiveWindowScope(child: child!),
      home: home,
    );

    testWidgets('narrows the content area to clear the side column', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      setWindow(tester, _duoOuter, right: 62, top: 20);

      late MediaQueryData seen;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) {
              seen = MediaQuery.of(context);
              return const SizedBox.expand();
            },
          ),
        ),
      );

      expect(seen.size, const Size(466 - 62, 678));
      expect(seen.padding.left, 0);
      expect(seen.padding.right, 0);
      expect(seen.padding.top, 20, reason: 'vertical insets are untouched');
      expect(seen.viewPadding.right, 0);
      expect(tester.getTopLeft(find.byType(SizedBox).last), Offset.zero);
      expect(
        tester.getSize(find.byType(SizedBox).last),
        const Size(466 - 62, 678),
      );
      expect(ResponsiveHelper.screenWidth, 466 - 62);
    });

    testWidgets('is a no-op where there are no side insets', (tester) async {
      addTearDown(tester.view.reset);
      setWindow(tester, const Size(393, 852), top: 59);

      late MediaQueryData seen;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) {
              seen = MediaQuery.of(context);
              return const SizedBox.expand();
            },
          ),
        ),
      );

      expect(seen.size, const Size(393, 852));
      expect(seen.padding.top, 59);
    });

    testWidgets('re-reads ResponsiveHelper on a fold and keeps every State', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      setWindow(tester, _duoOuter);

      await tester.pumpWidget(app(const _StaticReader()));
      final state = tester.state<_StaticReaderState>(
        find.byType(_StaticReader),
      );
      await tester.enterText(find.byType(TextField), 'Carlsen');
      await tester.tap(find.text('count'));
      await tester.pump();

      expect(find.text('phone'), findsOneWidget);
      expect(find.text('taps 1'), findsOneWidget);

      // Open the device: the window becomes the inner display.
      setWindow(tester, _duoInnerLandscape);
      await tester.pump();

      expect(find.text('tablet'), findsOneWidget);
      expect(
        tester.state<_StaticReaderState>(find.byType(_StaticReader)),
        same(state),
      );
      expect(state.initStates, 1);
      expect(find.text('taps 1'), findsOneWidget);
      expect(find.text('Carlsen'), findsOneWidget);

      // Close it again.
      setWindow(tester, _duoOuter);
      await tester.pump();

      expect(find.text('phone'), findsOneWidget);
      expect(state.initStates, 1);
      expect(find.text('Carlsen'), findsOneWidget);
    });

    testWidgets('also reaches readers built inside a LayoutBuilder', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      setWindow(tester, _duoOuter);

      // Fixed constraints, so the LayoutBuilder itself has no reason to
      // rebuild when the window changes.
      await tester.pumpWidget(
        app(
          Center(
            child: SizedBox(
              width: 320,
              height: 320,
              child: LayoutBuilder(builder: (_, _) => const _StaticReader()),
            ),
          ),
        ),
      );
      final state = tester.state<_StaticReaderState>(
        find.byType(_StaticReader),
      );
      expect(find.text('phone'), findsOneWidget);

      setWindow(tester, _duoInnerLandscape);
      await tester.pump();

      expect(find.text('tablet'), findsOneWidget);
      expect(state.initStates, 1);
    });

    testWidgets('an open route and dialog keep their state and Back stack', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      setWindow(tester, _duoOuter);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          builder: (_, child) => AdaptiveWindowScope(child: child!),
          home: const Scaffold(body: Text('Home route')),
          routes: {'/detail': (_) => const Scaffold(body: _StaticReader())},
        ),
      );
      navigator.currentState!.pushNamed('/detail');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sicilian');
      final detail = tester.state<_StaticReaderState>(
        find.byType(_StaticReader),
      );
      showDialog<void>(
        context: detail.context,
        builder: (_) => const AlertDialog(content: Text('Keep this dialog')),
      );
      await tester.pumpAndSettle();

      for (final size in [_duoInnerLandscape, _duoInnerPortrait, _duoOuter]) {
        setWindow(tester, size);
        await tester.pumpAndSettle();
        expect(find.text('Keep this dialog'), findsOneWidget);
        expect(
          tester.state<_StaticReaderState>(find.byType(_StaticReader)),
          same(detail),
        );
      }
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Sicilian'), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Home route'), findsOneWidget);
      expect(navigator.currentState!.canPop(), isFalse);
    });

    testWidgets('keyboard preserves side safety and remaining occlusion', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      setWindow(tester, _duoOuter, left: 20, right: 30);
      tester.view.padding = FakeViewPadding();
      tester.view.viewInsets = FakeViewPadding(left: 180, bottom: 900);
      late MediaQueryData seen;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) {
              seen = MediaQuery.of(context);
              return const SizedBox.expand();
            },
          ),
        ),
      );
      expect(seen.size.width, 416);
      expect(seen.viewInsets.left, 40);
      expect(seen.viewInsets.bottom, 300);
      expect(seen.viewPadding.horizontal, 0);
    });

    testWidgets('tabletop routes clear a reported horizontal obstruction', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      setWindow(tester, _duoInnerPortrait);
      await tester.pumpWidget(app(const _StaticReader()));
      final state = tester.state<_StaticReaderState>(
        find.byType(_StaticReader),
      );
      await tester.enterText(find.byType(TextField), 'Retain tabletop state');
      tester.view.displayFeatures = const [
        DisplayFeature(
          bounds: Rect.fromLTRB(0, 465, 669, 485),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ];
      await tester.pumpAndSettle();
      expect(ResponsiveHelper.screenHeight, 465);
      expect(
        tester.getRect(find.byType(_StaticReader)).bottom,
        lessThanOrEqualTo(465),
      );
      expect(
        tester.state<_StaticReaderState>(find.byType(_StaticReader)),
        same(state),
      );
      expect(find.text('Retain tabletop state'), findsOneWidget);
      tester.view.displayFeatures = const [];
      await tester.pumpAndSettle();
      expect(ResponsiveHelper.screenHeight, _duoInnerPortrait.height);
      expect(state.initStates, 1);
    });

    testWidgets('publishes the inner display hinge in content coordinates', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      setWindow(tester, _duoInnerLandscape, left: 20);
      tester.view.displayFeatures = const [
        DisplayFeature(
          bounds: Rect.fromLTWH(475.5, 0, 0, 669),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ];

      WindowFold? fold;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) {
              fold = AdaptiveWindow.verticalFoldOf(context);
              return const SizedBox.expand();
            },
          ),
        ),
      );

      expect(fold, isNotNull);
      expect(fold!.bounds.left, 475.5 - 20);
      expect(fold!.reported, isTrue);

      tester.view.displayFeatures = const [];
      setWindow(tester, _duoOuter);
      await tester.pump();
      expect(fold, isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });
}

/// Reads [ResponsiveHelper] statics the way most of the app does: without
/// depending on [MediaQuery], so only [AdaptiveWindowScope] can refresh it.
class _StaticReader extends StatefulWidget {
  const _StaticReader();

  @override
  State<_StaticReader> createState() => _StaticReaderState();
}

class _StaticReaderState extends State<_StaticReader> {
  int initStates = 0;
  int taps = 0;
  final controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    initStates++;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceClass = ResponsiveHelper.isTablet ? 'tablet' : 'phone';
    return Material(
      child: Column(
        children: [
          Text(deviceClass),
          Text('taps $taps'),
          TextButton(
            onPressed: () => setState(() => taps++),
            child: const Text('count'),
          ),
          SizedBox(width: 300, child: TextField(controller: controller)),
        ],
      ),
    );
  }
}
