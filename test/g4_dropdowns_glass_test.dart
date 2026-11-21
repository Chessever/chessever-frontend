// G4 dropdowns and anchored panels: every popover the group owns opens on
// the popover glass (one backdrop filter, clipped to the panel, never under
// an opacity), over a plain fading scrim (nothing blurs the screen), with its
// rows on screen in the first frame; the menus still pick, filter and close.
import 'package:chessever2/screens/library/providers/gamebase_database_search_provider.dart';
import 'package:chessever2/screens/library/widgets/library_gamebase_filters_sheet.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/glass_anchored_route.dart';
import 'package:chessever2/widgets/glass_dropdown.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:chessever2/widgets/smooth_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'g4_dropdowns_harness.dart';

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

/// Every backdrop filter on screen and the size it filters.
List<Size> _filterSizes(WidgetTester tester) => [
  for (final element in find.byType(BackdropFilter).evaluate())
    (element.renderObject! as RenderBox).size,
];

class _Search extends StateNotifier<AsyncValue<GamebaseDatabaseSearchState>>
    implements GamebaseDatabaseSearchNotifier {
  _Search(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpHost(WidgetTester tester, Widget body) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = g4Screen * 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(body: body);
        },
      ),
    ),
  );
}

void main() {
  for (final light in [false, true]) {
    for (final scene in g4Scenes) {
      testWidgets(
        '${scene.name} (${light ? 'light' : 'dark'}): glass panel from the '
        'first frame, no screen blur, dismissible',
        (tester) async {
          await scene.pump(tester, light: light);
          await g4Settle(tester, cap: 30);
          final pageFilters = _filterSizes(tester).length;

          final frames = await g4Open(tester, scene);
          // In the frame the tap scheduled: no frame-late insert.
          expect(frames, 1, reason: 'the popover showed $frames frames late');

          // The popover's own glass (a dialog under it may be glass too).
          final glass = find.descendant(
            of: find.byType(GlassPopoverPanel),
            matching: find.byType(PopupGlass),
          );
          for (var frame = 0; frame < 24; frame++) {
            expect(glass, findsOneWidget, reason: 'frame $frame');
            // The rows are drawn from the first frame: nothing fades them.
            expect(scene.marker().hitTestable(), findsWidgets);
            expect(_underOpacity(tester, scene.marker().last), isFalse);
            expect(_underOpacity(tester, glass), isFalse);
            // One filter more than the page had: the panel's, clipped to it.
            final filters = _filterSizes(tester);
            expect(filters, hasLength(pageFilters + 1), reason: 'frame $frame');
            for (final size in filters) {
              expect(
                size.width < g4Screen.width || size.height < g4Screen.height,
                isTrue,
                reason: 'a backdrop filter covers the screen (frame $frame)',
              );
            }
            final own = find.descendant(
              of: glass,
              matching: find.byType(BackdropFilter),
            );
            expect(own, findsOneWidget);
            expect(
              find.ancestor(of: own, matching: find.byType(ClipRRect)),
              findsWidgets,
            );
            expect(
              filters.any(
                (size) =>
                    size.width >= g4Screen.width - 1 &&
                    size.height >= g4Screen.height - 1,
              ),
              isFalse,
            );
            await tester.pump(const Duration(milliseconds: 16));
          }
          await g4Settle(tester);
          expect(tester.takeException(), isNull);

          // A tap on the page closes it: it folds shut into what opened it
          // (the fold itself is measured by anchored_menu_close_fold_test),
          // its rows no longer take taps, and once folded it is gone.
          await tester.tapAt(const Offset(12, 820));
          await tester.pump();
          expect(scene.marker().hitTestable(), findsNothing);
          await g4Settle(tester);
          expect(glass, findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 30));
        },
      );
    }
  }

  testWidgets('the popover scrim fades in and never blurs', (tester) async {
    final scene = g4Scenes.firstWhere(
      (s) => s.name == 'collections_round_select',
    );
    await scene.pump(tester, light: false);
    await g4Open(tester, scene);
    final alphas = <double>[];
    for (var frame = 0; frame < 30; frame++) {
      // The anchored dim: a plain tint riding the route's spring.
      final scrim = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<GlassScrimPainter>()
          .single;
      alphas.add(scrim.color.a * scrim.progress!.value.clamp(0.0, 1.0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(alphas.first, lessThan(0.05));
    expect(alphas.last, closeTo(AnchoredGlassDim.dark, 0.005));
    for (var i = 1; i < alphas.length; i++) {
      // A spring may overshoot a hair; the tint never drops back visibly.
      expect(alphas[i], greaterThanOrEqualTo(alphas[i - 1] - 0.02));
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a menu inside a glass dialog adds no scrim of its own', (
    tester,
  ) async {
    final scene = g4Scenes.firstWhere((s) => s.name == 'book_filter_in_dialog');
    await scene.pump(tester, light: false);
    int tints() => find
        .byType(ColoredBox)
        .evaluate()
        .where((e) => (e.renderObject! as RenderBox).size == g4Screen)
        .length;
    final before = tints();
    expect(before, greaterThan(0), reason: 'the dialog dims the page');
    await g4Open(tester, scene);
    await g4Settle(tester);
    expect(tints(), before);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('GlassDropdown', () {
    Widget dropdown({
      required String? value,
      required ValueChanged<String?> onChanged,
      List<String> labels = const ['Alpha', 'Bravo', 'Charlie', 'Delta'],
      TextEditingController? search,
      double? itemHeight = kMinInteractiveDimension,
    }) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 120, 24, 0),
      child: Align(
        alignment: Alignment.topCenter,
        child: DropdownButtonHideUnderline(
          child: GlassDropdown<String>(
            value: value,
            isExpanded: true,
            itemHeight: itemHeight,
            searchController: search,
            searchMatch: (item, query) =>
                (item.value ?? '').toLowerCase().contains(query.toLowerCase()),
            menuHeader: search == null
                ? null
                : SizedBox(
                    height: 48,
                    child: TextField(
                      key: const ValueKey('search'),
                      controller: search,
                    ),
                  ),
            menuHeaderHeight: search == null ? 0 : 48,
            items: [
              for (final label in labels)
                DropdownMenuItem(value: label, child: Text(label)),
            ],
            onChanged: onChanged,
          ),
        ),
      ),
    );

    testWidgets('picks an item, drops below the button and closes', (
      tester,
    ) async {
      String? picked;
      await _pumpHost(
        tester,
        dropdown(value: 'Bravo', onChanged: (v) => picked = v),
      );
      final button = tester.getRect(find.byType(GlassDropdown<String>));
      await tester.tap(find.byType(GlassDropdown<String>));
      await tester.pump();
      expect(find.byType(GlassPopoverPanel), findsOneWidget);
      await g4Settle(tester);
      final panel = tester.getRect(find.byType(PopupGlass));
      expect(panel.top, greaterThanOrEqualTo(button.bottom));
      // DropdownButton's menu margins: the rows' text lines up with the
      // button's.
      expect(panel.left, closeTo(button.left - 16, 0.5));
      await tester.tap(find.text('Delta').last);
      await tester.pump();
      // The pick is handed over as the fold begins, never after it.
      expect(picked, 'Delta');
      await g4Settle(tester);
      expect(find.byType(GlassPopoverPanel), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens on a far selection and draws rows lazily', (
      tester,
    ) async {
      final labels = [for (var i = 0; i < 300; i++) 'Row $i'];
      await _pumpHost(
        tester,
        dropdown(value: 'Row 240', labels: labels, onChanged: (_) {}),
      );
      await tester.tap(find.byType(GlassDropdown<String>));
      await tester.pump();
      // The selection is in view at once, and far rows were never built.
      expect(find.text('Row 240').hitTestable(), findsWidgets);
      expect(find.text('Row 0', skipOffstage: false), findsOneWidget);
      expect(
        find
            .descendant(
              of: find.byType(GlassPopoverPanel),
              matching: find.byType(DropdownMenuItem<String>),
            )
            .evaluate()
            .length,
        lessThan(40),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a search header filters the rows', (tester) async {
      final search = TextEditingController();
      addTearDown(search.dispose);
      await _pumpHost(
        tester,
        dropdown(value: 'Alpha', search: search, onChanged: (_) {}),
      );
      await tester.tap(find.byType(GlassDropdown<String>));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('search')), 'ch');
      await tester.pump();
      final menu = find.byType(GlassPopoverPanel);
      expect(
        find.descendant(of: menu, matching: find.text('Charlie')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: menu, matching: find.text('Bravo')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('rows of their own height still open on the selection', (
      tester,
    ) async {
      final labels = [for (var i = 0; i < 60; i++) 'Line $i'];
      await _pumpHost(
        tester,
        dropdown(
          value: 'Line 50',
          labels: labels,
          itemHeight: null,
          onChanged: (_) {},
        ),
      );
      await tester.tap(find.byType(GlassDropdown<String>));
      await tester.pump();
      await tester.pump();
      expect(
        find
            .descendant(
              of: find.byType(GlassPopoverPanel),
              matching: find.text('Line 50'),
            )
            .hitTestable(),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('disabled without onChanged', (tester) async {
      await _pumpHost(tester, dropdown(value: 'Alpha', onChanged: (_) {}));
      await _pumpHost(
        tester,
        const Padding(
          padding: EdgeInsets.all(40),
          child: GlassDropdown<String>(
            value: 'A',
            onChanged: null,
            items: [DropdownMenuItem(value: 'A', child: Text('A'))],
          ),
        ),
      );
      await tester.tap(find.text('A'));
      await tester.pump();
      expect(find.byType(GlassPopoverPanel), findsNothing);
    });
  });

  group('Gamebase filters sheet', () {
    for (final (name, state) in [
      ('loading', const AsyncValue<GamebaseDatabaseSearchState>.loading()),
      (
        'error',
        AsyncValue<GamebaseDatabaseSearchState>.error(
          Exception('offline'),
          StackTrace.empty,
        ),
      ),
    ]) {
      testWidgets('$name: the body is the glass sheet', (tester) async {
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = g4Screen * 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              gamebaseDatabaseSearchProvider.overrideWith(
                (ref) => _Search(state),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  return Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => showGlassModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => const LibraryGamebaseFiltersSheet(),
                        ),
                        child: const Text('open'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        // The sheet spring comes to rest within 45 frames.
        for (var i = 0; i < 45; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(find.byType(GlassSheet), findsOneWidget);
        final glass = find.byType(PopupGlass);
        expect(glass, findsOneWidget);
        expect(
          find.descendant(of: glass, matching: find.byType(BackdropFilter)),
          findsOneWidget,
        );
        expect(_filterSizes(tester), hasLength(1));
        // The glass reaches past the screen's bottom edge, so its rim
        // stays off-screen.
        expect(
          tester.getRect(glass).bottom,
          closeTo(g4Screen.height + GlassSheet.bleed, 0.5),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });
}
