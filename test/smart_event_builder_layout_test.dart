import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/sheets/space_add_sheet.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Store extends SpaceShortcutsNotifier {
  final added = <String>[];

  List<SpaceShortcut> get _list => state.valueOrNull ?? const [];

  @override
  Future<List<SpaceShortcut>> build() async => const [];

  @override
  Future<bool> add(SpaceShortcut draft) async {
    if (_list.any((s) => s.key == draft.key)) return false;
    added.add(draft.key);
    state = AsyncData([draft.copyWith(sortIndex: 99), ..._list]);
    return true;
  }

  @override
  Future<SpaceShortcut?> removeTarget(
    SpaceShortcutKind kind,
    String targetId,
  ) async {
    final key = SpaceShortcut.keyFor(kind, targetId);
    final hit = _list.where((s) => s.key == key).firstOrNull;
    state = AsyncData([
      for (final s in _list)
        if (s.key != key) s,
    ]);
    return hit;
  }

  @override
  Future<void> markOpened(String id) async {}
}

const _controls = ValueKey('smart-builder-controls');
const _cta = ValueKey('smart-builder-cta');

/// Opens the Smart Events add sheet the way the My Space door does.
Future<_Store> _open(
  WidgetTester tester, {
  required Size size,
  bool dark = false,
  double text = 1,
  double safeBottom = 0,
}) async {
  tester.view.physicalSize = Size(size.width * 2, size.height * 2);
  tester.view.devicePixelRatio = 2;
  tester.view.viewPadding = FakeViewPadding(bottom: safeBottom * 2);
  tester.view.padding = FakeViewPadding(bottom: safeBottom * 2);
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  final store = _Store();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        spaceShortcutsProvider.overrideWith(() => store),
        playerPhotoProvider.overrideWith((ref, fideId) async => null),
      ],
      child: MaterialApp(
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              backgroundColor: context.colors.background,
              body: Consumer(
                builder: (context, ref, _) => Center(
                  child: TextButton(
                    onPressed: () => showSpaceAddSheet(
                      context,
                      ref,
                      SpaceSection.smartEvents,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  await _settle(tester);
  return store;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

double _maxScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(_controls),
        matching: find.byType(Scrollable),
      ),
    )
    .position
    .maxScrollExtent;

void main() {
  for (final size in const [Size(360, 780), Size(393, 852)]) {
    for (final dark in [false, true]) {
      for (final safe in [0.0, 34.0]) {
        final name =
            '${size.width.toInt()}x${size.height.toInt()} '
            '${dark ? 'dark' : 'light'} safe=${safe.toInt()}';
        testWidgets('the whole build fits without scrolling at $name', (
          tester,
        ) async {
          await _open(tester, size: size, dark: dark, safeBottom: safe);

          expect(find.text('Build a Smart Event'), findsOneWidget);
          expect(find.text('Build from filters'), findsNothing);
          expect(_maxScroll(tester), 0);
          final cta = tester.getRect(find.byKey(_cta));
          expect(cta.top, greaterThan(0));
          expect(cta.bottom, lessThanOrEqualTo(size.height - safe));
          for (final label in [
            'Level',
            'Time control',
            'Event status',
            'Opening',
          ]) {
            expect(find.text(label), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('large text on a narrow phone keeps every control whole', (
    tester,
  ) async {
    await _open(tester, size: const Size(360, 780), text: 1.3, safeBottom: 34);
    await tester.tap(find.byKey(const ValueKey('smart-builder-level-2200')));
    await tester.tap(
      find.byKey(const ValueKey('smart-builder-toggle-standard')),
    );
    await tester.tap(
      find.byKey(const ValueKey('smart-builder-toggle-completed')),
    );
    await _settle(tester);

    expect(tester.takeException(), isNull);
    final cta = tester.getRect(find.byKey(_cta));
    expect(cta.bottom, lessThanOrEqualTo(780 - 34));
    // Labels never ellipsize: the glyphs step aside instead.
    expect(find.text('Classical'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('the opening browser stays usable over the keyboard', (
    tester,
  ) async {
    await _open(tester, size: const Size(360, 780), dark: true, safeBottom: 34);
    await tester.tap(find.byKey(const ValueKey('smart-builder-opening-field')));
    await _settle(tester);
    final search = find.byKey(const ValueKey('smart-builder-opening-search'));
    await tester.showKeyboard(search);
    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    await _settle(tester);

    expect(tester.takeException(), isNull);
    expect(tester.getRect(search).bottom, lessThanOrEqualTo(780 - 300));
    final any = tester.getRect(
      find.byKey(const ValueKey('smart-builder-opening-any')),
    );
    expect(any.top, greaterThan(tester.getRect(search).bottom));
    expect(any.bottom, lessThanOrEqualTo(780 - 300));
  });

  testWidgets('GM, Blitz, Live and the Najdorf add one Smart Event', (
    tester,
  ) async {
    final store = await _open(tester, size: const Size(393, 852));

    // Nothing picked yet: the add control is visibly off.
    await tester.tap(find.byKey(_cta));
    await tester.pump();
    expect(store.added, isEmpty);

    await tester.tap(find.byKey(const ValueKey('smart-builder-level-2500')));
    await tester.tap(find.byKey(const ValueKey('smart-builder-toggle-blitz')));
    await tester.tap(find.byKey(const ValueKey('smart-builder-toggle-live')));
    await _settle(tester);
    expect(find.text('GM Blitz Games'), findsNothing);
    // Several format picks collapse in the shared name; the line keeps them.
    expect(find.text('GM Games'), findsOneWidget);
    expect(
      find.text('Game average 2500+, blitz, live events'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('smart-builder-opening-field')));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('smart-builder-opening-search')),
      'najdorf',
    );
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('result:B9')));
    await _settle(tester);

    expect(find.text('GM Sicilian: Najdorf'), findsOneWidget);
    await tester.tap(find.byKey(_cta));
    await _settle(tester);
    expect(store.added, ['smartEvent:2500-3200:blitz|live:eco=B9']);
    expect(find.text('Added to My Space'), findsOneWidget);

    // A second tap takes it back out, like every add control in My Space.
    await tester.tap(find.byKey(_cta));
    await _settle(tester);
    expect(find.text('Add to My Space'), findsOneWidget);

    // Tapping the chosen level again clears it, as in the dialog.
    await tester.tap(find.byKey(const ValueKey('smart-builder-level-2500')));
    await _settle(tester);
    expect(find.text('Blitz Sicilian: Najdorf'), findsNothing);
    expect(find.text('Filtered Sicilian: Najdorf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding closes into the add sheet\'s own snack', (tester) async {
    final store = await _open(tester, size: const Size(393, 852));
    await tester.tap(find.byKey(const ValueKey('smart-builder-level-2400')));
    await _settle(tester);
    await tester.tap(find.byKey(_cta));
    await _settle(tester);
    expect(store.added, ['smartEvent:2400-3200:']);
    await tester.tap(find.text('Done'));
    await _settle(tester);
    expect(find.text('Added IM Games to Smart Events'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });

  for (final dark in [false, true]) {
    test(
      'selected ink and the add label clear AA (${dark ? 'dark' : 'light'})',
      () {
        final c = dark ? AppColors.dark : AppColors.light;
        // Segment and toggle labels on the ink fill.
        expect(wcagContrast(c.textInverse, c.textPrimary), greaterThan(4.5));
        final quiet = Color.alphaBlend(
          c.textInverse.withValues(alpha: 0.72),
          c.textPrimary,
        );
        expect(wcagContrast(quiet, c.textPrimary), greaterThan(4.5));
        // Unpicked labels on the track.
        expect(wcagContrast(c.textPrimary, c.background), greaterThan(4.5));
        expect(wcagContrast(c.textSecondary, c.background), greaterThan(4.5));
        // The pick itself reads as a state against its track.
        expect(wcagContrast(c.textPrimary, c.background), greaterThan(3));
        // The add button's label on the brand fill, and once added.
        expect(wcagContrast(c.inkOnAccent, c.brand), greaterThan(4.5));
        expect(wcagContrast(c.textPrimary, c.background), greaterThan(4.5));
        // Opening codes on the track.
        expect(wcagContrast(c.titleAccent, c.background), greaterThan(4.5));
      },
    );
  }
}
