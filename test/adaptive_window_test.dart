import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:chessever2/utils/adaptive_window.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// iPhone Duo, in points. Apple publishes the panels (outer 1398 x 2034 px,
// inner 1878 x 2670 px) and App Store Connect a 2007 x 2853 screenshot size;
// at 3x these are the logical sizes. Confirm in Xcode's Device Hub.
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
  });

  group('resolveWindowFold', () {
    WindowFold? resolve(
      Size size, {
      double dpr = 3,
      TargetPlatform platform = TargetPlatform.iOS,
      List<DisplayFeature> features = const [],
    }) => resolveWindowFold(
      windowSize: size,
      displayFeatures: features,
      devicePixelRatio: dpr,
      platform: platform,
    );

    test('opened like a book, the hinge runs down the middle', () {
      final fold = resolve(_duoInnerLandscape)!;
      expect(fold.axis, Axis.vertical);
      expect(fold.bounds.left, 475.5);
      expect(fold.bounds.height, 669);
      expect(fold.reported, isFalse);
      expect(fold.leadingExtentFrom(12), 475.5 - WindowFold.clearance - 12);
      expect(fold.trailingStart, 475.5 + WindowFold.clearance);
    });

    test('the inner display in portrait has a horizontal hinge', () {
      final fold = resolve(_duoInnerPortrait)!;
      expect(fold.axis, Axis.horizontal);
      expect(fold.bounds.top, 475.5);
      expect(fold.leadingExtentFrom(0), isNull);
      expect(fold.trailingStart, isNull);
    });

    test('no other iPhone or iPad window has one', () {
      expect(resolve(_duoOuter), isNull, reason: 'outer display');
      expect(resolve(const Size(475, 669)), isNull, reason: 'Split View');
      expect(resolve(const Size(956, 440)), isNull, reason: 'Pro Max');
      expect(resolve(const Size(1180, 820), dpr: 2), isNull, reason: 'iPad');
      expect(resolve(const Size(744, 1133), dpr: 2), isNull, reason: 'mini');
    });

    test('Android only reports a fold, it is never inferred', () {
      expect(
        resolve(_duoInnerLandscape, platform: TargetPlatform.android),
        isNull,
      );
    });

    test('a reported hinge wins and keeps its width', () {
      final fold = resolve(
        const Size(840, 700),
        platform: TargetPlatform.android,
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
          platform: TargetPlatform.android,
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

    testWidgets('publishes the inner display hinge in content coordinates', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      setWindow(tester, _duoInnerLandscape, left: 20);

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
      expect(fold!.reported, isFalse);

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
