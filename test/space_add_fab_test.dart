import 'package:chessever2/screens/my_space/widgets/space_add_fab.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_edit_mode_provider.dart';
import 'package:chessever2/screens/my_space/sheets/space_add_sheet.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _EmptyShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

Future<void> _pumpFab(
  WidgetTester tester, {
  ThemeData? theme,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [spaceShortcutsProvider.overrideWith(_EmptyShortcuts.new)],
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              backgroundColor: context.colors.background,
              floatingActionButton: const SpaceAddFab(),
              body: const SizedBox.expand(),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets(
    'supported sources and Edit fit a small phone; Smart event opens its builder',
    (tester) async {
      await _pumpFab(tester, size: const Size(320, 568), textScale: 1.3);
      await tester.tap(find.byType(SpaceAddFab));
      await _settle(tester);
      expect(kSpaceAddChoices.map((choice) => choice.label), [
        'Database',
        'Smart event',
      ]);
      expect(kSpaceAddChoices.map((choice) => choice.label), [
        'Database',
        'Smart event',
      ]);
      for (final label in ['Event', 'Player', 'Game', 'Opening', 'My Likes']) {
        expect(find.text(label), findsNothing);
      }
      for (final choice in kSpaceAddChoices) {
        expect(choice.section.supportsAddingToMySpace, isTrue);
        final row = find.bySemanticsLabel(choice.label);
        expect(row.hitTestable(), findsOneWidget);
        final rect = tester.getRect(row);
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(568));
        expect(rect.height, greaterThanOrEqualTo(44));
      }
      expect(find.bySemanticsLabel('Edit').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Smart event'));
      await _settle(tester);
      expect(find.byType(SpaceAddSheet), findsOneWidget);
      expect(
        tester.widget<SpaceAddSheet>(find.byType(SpaceAddSheet)).section,
        SpaceSection.smartEvents,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('Edit and Done editing remain reachable on a short phone with '
      'large text and share the page edit state', (tester) async {
    await _pumpFab(tester, size: const Size(320, 480), textScale: 1.8);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SpaceAddFab)),
    );
    expect(container.read(spaceEditModeProvider), isFalse);

    await tester.tap(find.byType(SpaceAddFab));
    await _settle(tester);
    final edit = find.bySemanticsLabel('Edit');
    await tester.ensureVisible(edit);
    await _settle(tester);
    expect(edit.hitTestable(), findsOneWidget);
    expect(tester.getRect(edit).height, greaterThanOrEqualTo(44));
    await tester.tap(edit);
    await _settle(tester);
    expect(container.read(spaceEditModeProvider), isTrue);
    expect(find.byType(SpaceAddSheet), findsNothing);

    await tester.tap(find.byType(SpaceAddFab));
    await _settle(tester);
    final done = find.bySemanticsLabel('Done editing');
    await tester.ensureVisible(done);
    await _settle(tester);
    expect(done.hitTestable(), findsOneWidget);
    expect(tester.getRect(done).bottom, lessThanOrEqualTo(480));
    await tester.tap(done);
    await _settle(tester);
    expect(container.read(spaceEditModeProvider), isFalse);
    expect(find.text('Done editing'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  for (final light in [false, true]) {
    testWidgets('the "+" opens a popover pointing at it with every type, '
        '(${light ? 'light' : 'dark'})', (tester) async {
      await _pumpFab(
        tester,
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      );

      expect(find.bySemanticsLabel(SpaceAddFab.label), findsOneWidget);
      final fab = tester.getRect(find.byType(SpaceAddFab));
      expect(fab.width, greaterThanOrEqualTo(48));

      await tester.tap(find.byType(SpaceAddFab));
      await _settle(tester);

      expect(kSpaceAddChoices.map((choice) => choice.label), [
        'Database',
        'Smart event',
      ]);
      for (final label in ['Event', 'Player', 'Game', 'Opening', 'My Likes']) {
        expect(find.text(label), findsNothing);
      }
      for (final choice in kSpaceAddChoices) {
        expect(find.text(choice.label), findsOneWidget, reason: choice.label);
        // Every row is a full touch target.
        expect(
          tester.getSize(find.bySemanticsLabel(choice.label)).height,
          greaterThanOrEqualTo(44),
        );
      }
      // The popover sits above the button, right-aligned with it.
      final card = tester.getRect(find.text('Smart event'));
      expect(card.bottom, lessThan(fab.top));
      expect(card.right, lessThanOrEqualTo(fab.right));
      expect(tester.takeException(), isNull);

      // A tap outside closes it and picks nothing.
      await tester.tapAt(const Offset(40, 120));
      await _settle(tester);
      expect(find.text('Smart event'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('with reduced motion the popover opens and closes at once', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpFab(tester);

    await tester.tap(find.byType(SpaceAddFab));
    await tester.pump();
    await tester.pump();
    expect(find.text('Database'), findsOneWidget);

    await tester.tapAt(const Offset(40, 120));
    await tester.pump();
    await tester.pump();
    expect(find.text('Database'), findsNothing);
  });
}
