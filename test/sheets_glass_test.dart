// Bottom sheets: every sheet's surface is the one sheet glass, over a plain
// scrim; nothing blurs the whole screen on any frame of the open. A frosted
// sheet has one backdrop filter, clipped to it and never animated; a tall or
// busy sheet is solid (no live blur). The smooth sheet hands its result back
// the moment it closes and slides out on the route's exit.
import 'dart:async';
import 'dart:typed_data';

import 'package:chessever2/screens/gamebase/widgets/position_games_sheet.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:chessever2/widgets/smooth_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sheets_harness.dart';
import 'sheets_scenes.dart';

/// Whether any render object between [finder]'s and the root fades it.
bool _underOpacity(WidgetTester tester, Finder finder) {
  RenderObject? node = tester.renderObject(finder).parent;
  while (node != null) {
    if (node is RenderOpacity && node.opacity < 1) return true;
    if (node is RenderAnimatedOpacity && node.opacity.value < 1) return true;
    node = node.parent;
  }
  return false;
}

/// The backdrop filters on screen: their filter and size.
List<(String, Size)> _backdrops(WidgetTester tester) => [
  for (final e in find.byType(BackdropFilter).evaluate())
    (
      (e.widget as BackdropFilter).filter.toString(),
      (e.renderObject! as RenderBox).size,
    ),
];

void main() {
  late Uint8List shareImage;
  var shareImageReady = false;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder-publishable-key',
      // No deep-link listener (app_links has no test platform).
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
  });

  for (final light in [false, true]) {
    final theme = light ? 'light' : 'dark';
    for (final name in sheetScenes(
      shareImage: Uint8List(0),
    ).map((s) => s.name)) {
      testWidgets('$name sits on the glass, $theme', (tester) async {
        sheetsPhone(tester);
        if (!shareImageReady) {
          shareImage = await sheetsSharePng(tester);
          shareImageReady = true;
        }
        final scene = sheetScenes(
          shareImage: shareImage,
        ).firstWhere((s) => s.name == name);
        await tester.pumpWidget(
          sheetsHost(
            opener: scene.opener,
            light: light,
            overrides: scene.overrides,
          ),
        );
        await tester.pump();
        sheetsTapOpen(tester);
        await tester.pump();

        // Every frame of the open: at most one backdrop filter, never the
        // screen's size, its blur the panel's fixed frost (not animated).
        final expected =
            'blur(${PopupGlassStyle.blurSigma}, ${PopupGlassStyle.blurSigma}';
        for (var frame = 0; frame < 40; frame++) {
          final backdrops = _backdrops(tester);
          expect(backdrops.length, lessThanOrEqualTo(1), reason: '$frame');
          for (final (filter, size) in backdrops) {
            expect(filter, contains(expected), reason: 'frame $frame');
            expect(
              size.height,
              lessThan(sheetsScreen.height),
              reason: 'frame $frame',
            );
          }
          await tester.pump(const Duration(milliseconds: 16));
        }
        await sheetsSettle(tester, limit: 120);

        final glass = find.byType(PopupGlass);
        expect(glass, findsOneWidget);
        final panel = tester.getRect(glass);
        expect(_underOpacity(tester, glass), isFalse);
        final filters = find.descendant(
          of: glass,
          matching: find.byType(BackdropFilter),
        );
        final declared = tester.widget<PopupGlass>(glass).solid;
        // A sheet that says it is solid (its content animates, or covers
        // nearly all of it) has no backdrop filter at all.
        expect(filters, declared ? findsNothing : findsOneWidget);
        expect(_backdrops(tester), hasLength(declared ? 0 : 1));
        var live = false;
        if (!declared) {
          expect(
            find.ancestor(of: filters, matching: find.byType(ClipRRect)),
            findsWidgets,
          );
          expect(tester.getRect(filters).width, lessThanOrEqualTo(panel.width));
          expect(
            tester.getRect(filters).height,
            lessThanOrEqualTo(panel.height),
          );
          // The frost rule: a sheet taller than 60% of the screen is solid.
          final tall =
              panel.height >
              sheetsScreen.height * PopupGlassStyle.frostMaxScreenShare;
          live = tester.renderObject<RenderBackdropFilter>(filters).enabled;
          expect(live, !tall, reason: '$name, ${panel.height} tall');
        }
        // The tall and busy ones never blur live: sign-in (its particles
        // never stop), the games sheet (its cards cover it), the explorer's
        // filters and the tracking explainer (full-height pages, declared
        // solid), My Space's add sheet (88%) and the share preview (79%,
        // its picture covers it) by the rule.
        if (const {
          'auth_upgrade',
          'position_games',
          'explorer_filter',
          'att_explainer',
          'my_space_add',
          'share_preview',
        }.contains(name)) {
          expect(live, isFalse, reason: '$name blurs live');
        }
        // A short sheet keeps its frost.
        if (const {
          'add_to_library',
          'sort_options',
          'start_picker',
          'puzzle_difficulty',
        }.contains(name)) {
          expect(live, isTrue, reason: '$name lost its frost');
        }

        // The page is dimmed by the glass scrim, the strength the plate is
        // solved against.
        final context = tester.element(glass);
        final scrim = glassSheetBarrier(context);
        final barriers = tester
            .widgetList<ModalBarrier>(find.byType(ModalBarrier))
            .map((b) => b.color)
            .whereType<Color>()
            .where((c) => c.a > 0);
        final tints = tester
            .widgetList<ColoredBox>(find.byType(ColoredBox))
            .map((b) => b.color)
            .where((c) => c.a > 0);
        expect(
          [...barriers, ...tints].any(
            (c) =>
                c.toARGB32() == scrim.toARGB32() ||
                (c.a - scrim.a).abs() < 0.01 && c.r == scrim.r,
          ),
          isTrue,
          reason: 'no glass scrim under $name',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  group('the smooth sheet', () {
    Future<Future<String?>> open(
      WidgetTester tester, {
      bool reduceMotion = false,
    }) async {
      sheetsPhone(tester);
      late Future<String?> result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => result = showSmoothBottomSheet<String>(
                      context: context,
                      builder: (context) => SizedBox(
                        height: 300,
                        child: Center(
                          child: TextButton(
                            onPressed: () =>
                                Navigator.of(context).pop('picked'),
                            child: const Text('Pick'),
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await sheetsSettle(tester);
      return result;
    }

    testWidgets('hands its result back on the closing frame, then slides '
        'out over a page that takes taps again', (tester) async {
      final result = await open(tester);
      final rested = tester.getRect(find.byType(PopupGlass));
      String? got;
      var done = false;
      unawaited(
        result.then((value) {
          got = value;
          done = true;
        }),
      );
      await tester.tap(find.text('Pick'));
      await tester.pump();
      // No 350 ms wait for the result: it lands with the pop.
      expect(done, isTrue);
      expect(got, 'picked');
      // The sheet is still there, on its way down, and never faded.
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(PopupGlass), findsOneWidget);
      expect(_underOpacity(tester, find.byType(PopupGlass)), isFalse);
      expect(
        tester.getRect(find.byType(PopupGlass)).top,
        greaterThan(rested.top),
      );
      // The page under it is live again while it leaves.
      expect(find.text('Open').hitTestable(), findsOneWidget);
      await sheetsSettle(tester);
      expect(find.byType(PopupGlass), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tap on the page closes it at once', (tester) async {
      final result = await open(tester);
      var done = false;
      unawaited(result.then((_) => done = true));
      await tester.tapAt(const Offset(196, 80));
      await tester.pump();
      expect(done, isTrue);
      await sheetsSettle(tester);
      expect(find.byType(PopupGlass), findsNothing);
    });

    testWidgets('a short pull springs back; a long one closes it', (
      tester,
    ) async {
      final result = await open(tester);
      var done = false;
      unawaited(result.then((_) => done = true));
      final rested = tester.getRect(find.byType(PopupGlass));
      await tester.drag(
        find.byType(PopupGlass),
        const Offset(0, 60),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(done, isFalse);
      await sheetsSettle(tester);
      expect(
        tester.getRect(find.byType(PopupGlass)).top,
        moreOrLessEquals(rested.top, epsilon: 0.5),
      );
      await tester.drag(
        find.byType(PopupGlass),
        const Offset(0, 180),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(done, isTrue);
      await sheetsSettle(tester);
      expect(find.byType(PopupGlass), findsNothing);
    });

    testWidgets('under reduced motion it is gone the moment it closes', (
      tester,
    ) async {
      final result = await open(tester, reduceMotion: true);
      var done = false;
      unawaited(result.then((_) => done = true));
      await tester.tap(find.text('Pick'));
      await tester.pump();
      expect(done, isTrue);
      expect(find.byType(PopupGlass).hitTestable(), findsNothing);
      expect(find.text('Pick'), findsNothing);
      await sheetsSettle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('its glass is open at the bottom, rounded at the top', (
      tester,
    ) async {
      await open(tester);
      final glass = tester.widget<PopupGlass>(find.byType(PopupGlass));
      expect(glass.openBottom, isTrue);
      expect(glass.borderRadius.bottomLeft, Radius.zero);
      expect(glass.borderRadius.topLeft.x, greaterThan(0));
    });
  });

  testWidgets('the dark explorer glass is solved a step deeper and denser', (
    tester,
  ) async {
    for (final light in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
          home: const ExplorerSheetGlass(radius: 16, child: SizedBox()),
        ),
      );
      // The theme switch animates; read the settled one.
      await tester.pumpAndSettle();
      final glass = tester.widget<PopupGlass>(find.byType(PopupGlass));
      final colors = tester.element(find.byType(PopupGlass)).colors;
      if (light) {
        expect(glass.tone, colors.background);
        // Every frosted light sheet's coverage: the paper, never grey.
        expect(glass.cover, GlassSheet.lightCover);
      } else {
        expect(
          glass.tone,
          Color.lerp(
            colors.surfaceRecessed,
            colors.surface,
            ExplorerSheetGlass.darkDeepen,
          ),
        );
        expect(glass.cover, ExplorerSheetGlass.darkCover);
      }
      expect(glass.openBottom, isTrue);
    }
  });
}
