// Group G5 ("dialogs") of the popup sweep: every dialog, tooltip and bubble
// of the group sits on the frosted PopupGlass panel, one backdrop filter
// per surface clipped to it, never under an opacity; no overlay blurs the
// whole screen on any frame of its open; content is on screen from the
// first frame; and the glass dialog route keeps a Material route's barrier
// manners (an outside tap asks PopScope first).
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:chessever2/widgets/glass_dialog_route.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dialogs_harness.dart';

/// Whether anything between [element]'s render object and the root fades
/// it below full strength.
bool _faded(Element element) {
  RenderObject? node = element.renderObject?.parent;
  while (node != null) {
    if (node is RenderOpacity && node.opacity < 1) return true;
    if (node is RenderAnimatedOpacity && node.opacity.value < 1) return true;
    node = node.parent;
  }
  return false;
}

/// The surfaces each popup is drawn on: how many glass panels.
const _panels = {
  'race_stop': 1,
  'teaching': 1,
  'rewarded_choice': 1,
  'rewarded_expired': 1,
  'interstitial_intro': 1,
  'update_prompt': 1,
  'nudge_tooltip': 1,
  'discovery_bubble': 1,
  // The lightbox keeps its stage; only its controls sit on a panel.
  'avatar_lightbox': 1,
  // A full-screen dark stage, no panel.
  'celebration': 0,
};

void main() {
  setUpAll(() async {
    await ChessgroundImages.instance.loadAll(
      const BoardSettingsNew().pieceAssets,
      devicePixelRatio: 3,
    );
  });

  for (final light in [false, true]) {
    final theme = light ? 'light' : 'dark';
    for (final scene in dialogScenes) {
      testWidgets('${scene.name} ($theme): glass panel, no full-screen blur, '
          'visible from its first frame', (tester) async {
        muteDialogsPlatform(tester);
        final opener = await scene.open(tester, light: light);
        opener();
        await tester.pump(scene.firstPump);
        var extra = 0;
        while (scene.shown().evaluate().isEmpty && extra < 20) {
          await tester.pump();
          extra++;
        }
        // Every frame of the open, the first included.
        for (var frame = 0; frame < 60; frame++) {
          expect(
            fullScreenBlurs(tester),
            0,
            reason:
                '${scene.name}: a backdrop filter over the whole screen '
                '(frame $frame)',
          );
          final shown = scene.shown().evaluate();
          expect(shown, isNotEmpty, reason: '${scene.name} frame $frame');
          for (final element in shown) {
            expect(
              _faded(element),
              isFalse,
              reason: '${scene.name}: its content under a fade (frame $frame)',
            );
          }
          for (final glass in find.byType(PopupGlass).evaluate()) {
            expect(
              _faded(glass),
              isFalse,
              reason: '${scene.name}: glass under an opacity (frame $frame)',
            );
          }
          await tester.pump(const Duration(milliseconds: 16));
        }

        final panels = _panels[scene.name]!;
        final glass = find.byType(PopupGlass);
        expect(glass, findsNWidgets(panels), reason: scene.name);
        // One backdrop filter per panel, the panel's own, clipped to it.
        final filters = find.byType(BackdropFilter);
        expect(filters, findsNWidgets(panels), reason: scene.name);
        for (final filter in filters.evaluate()) {
          expect(
            find.ancestor(
              of: find.byWidget(filter.widget),
              matching: find.byType(PopupGlass),
            ),
            findsOneWidget,
          );
          expect(
            find.ancestor(
              of: find.byWidget(filter.widget),
              matching: find.byType(ClipRRect),
            ),
            findsWidgets,
          );
        }
        // The popup's words sit on its glass.
        if (panels > 0) {
          final words = tester.getRect(scene.shown().first);
          expect(
            glass.evaluate().any(
              (e) => tester
                  .getRect(find.byWidget(e.widget))
                  .inflate(0.5)
                  .contains(words.topLeft),
            ),
            isTrue,
            reason: '${scene.name}: content off the glass',
          );
          for (final e in glass.evaluate()) {
            final panel = tester.getRect(find.byWidget(e.widget));
            expect(panel.width, lessThan(dialogsScreen.width));
            expect(panel.height, lessThan(dialogsScreen.height * 0.9));
          }
        }
        expect(tester.takeException(), isNull);
        await scene.close?.call(tester);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('the sheet dim behind the legacy Premium sheet never blurs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(body: BackDropFilterWidget()),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    final box = tester.widget<Container>(
      find.descendant(
        of: find.byType(BackDropFilterWidget),
        matching: find.byType(Container),
      ),
    );
    expect((box.decoration! as BoxDecoration).gradient, isNotNull);
  });

  group('glass under a Material alert dialog', () {
    Rect card(WidgetTester tester) => tester.getRect(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Material),
          )
          .first,
    );

    testWidgets('lies exactly under the card, actions stacked or not, and '
        'follows it when the content grows', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var more = false;
      late StateSetter grow;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                grow = setState;
                return GlassAlertFrame(
                  borderRadius: BorderRadius.circular(20),
                  child: AlertDialog(
                    backgroundColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    elevation: 0,
                    title: const Text('Update Available'),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('A new version is available.'),
                          if (more) ...[
                            const SizedBox(height: 15),
                            const Text('Release Notes'),
                            const Text('Faster popups, steadier boards.'),
                          ],
                        ],
                      ),
                    ),
                    // Too wide for one row at 320: they stack.
                    actions: [
                      TextButton(
                        onPressed: () {},
                        child: const Text('Remind me in 3 days'),
                      ),
                      TextButton(
                        onPressed: () {},
                        child: const Text('Update Now'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      final glass = find.byType(PopupGlass);
      expect(tester.getRect(glass), card(tester));
      final before = card(tester);
      grow(() => more = true);
      await tester.pump();
      expect(card(tester).height, greaterThan(before.height));
      expect(tester.getRect(glass), card(tester));
      // Nothing of the content is cut: the notes are on screen, inside.
      expect(
        card(tester).contains(
          tester.getRect(find.text('Faster popups, steadier boards.')).center,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('glass dialog route', () {
    Future<void> open(
      WidgetTester tester, {
      required bool canPop,
      bool barrierDismissible = true,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showGlassDialog<void>(
                    context: context,
                    barrierDismissible: barrierDismissible,
                    builder: (_) => PopScope(
                      canPop: canPop,
                      child: GlassDialog(
                        borderRadius: BorderRadius.circular(16),
                        child: const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Glass dialog'),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
    }

    testWidgets('is there at full strength from its first frame, and rests '
        'at exactly its size', (tester) async {
      await open(tester, canPop: true);
      expect(find.text('Glass dialog'), findsOneWidget);
      expect(_faded(tester.element(find.byType(PopupGlass))), isFalse);
      // No route fade around it at all.
      expect(
        find.ancestor(
          of: find.byType(GlassDialog),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
      var frames = 0;
      while (tester.binding.hasScheduledFrame && frames < 200) {
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
      }
      // The open comes to rest well inside a second.
      expect(frames, lessThan(50));
      final scale = tester.widget<Transform>(
        find
            .ancestor(
              of: find.byType(GlassDialog),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(scale.transform.getMaxScaleOnAxis(), 1);
    });

    testWidgets('an outside tap closes it', (tester) async {
      await open(tester, canPop: true);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Glass dialog'));
      await tester.pumpAndSettle();
      expect(find.text('Glass dialog'), findsOneWidget);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.text('Glass dialog'), findsNothing);
    });

    testWidgets('an outside tap asks PopScope first', (tester) async {
      await open(tester, canPop: false);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.text('Glass dialog'), findsOneWidget);
    });

    testWidgets('a dialog that cannot be dismissed stays', (tester) async {
      await open(tester, canPop: true, barrierDismissible: false);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.text('Glass dialog'), findsOneWidget);
    });

    testWidgets('the scrim fades in and takes no taps', (tester) async {
      await open(tester, canPop: true);
      final alphas = <double>[];
      for (var i = 0; i < 20; i++) {
        final scrim = tester.widget<ColoredBox>(
          find
              .descendant(
                of: find.byType(GlassDialogStage),
                matching: find.byType(ColoredBox),
              )
              .first,
        );
        alphas.add(scrim.color.a);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(alphas.first, 0);
      expect(alphas.last, greaterThan(0.5));
      expect(
        find.ancestor(
          of: find
              .descendant(
                of: find.byType(GlassDialogStage),
                matching: find.byType(ColoredBox),
              )
              .first,
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );
    });
  });
}
