import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/board_editor/board_editor_screen.dart';
import 'package:chessever2/screens/board_editor/board_editor_space_draft.dart';
import 'package:chessever2/screens/board_editor/board_editor_state.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/my_space/defaults/space_defaults.dart';
import 'package:chessever2/screens/my_space/models/space_auto_item.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/my_space_view.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/sheets/space_add_sheet.dart';
import 'package:chessever2/screens/my_space/sheets/space_add_sources.dart'
    show
        SpaceAddSources,
        kSpaceSheetAddedLabel,
        kSpaceSheetEditorLabel,
        spaceUnbrokenMoves;
import 'package:chessever2/screens/my_space/widgets/space_first_run_hint.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Store extends SpaceShortcutsNotifier {
  _Store([this.initial = const []]);

  final List<SpaceShortcut> initial;
  final added = <String>[];

  List<SpaceShortcut> get _list => state.valueOrNull ?? const [];

  @override
  Future<List<SpaceShortcut>> build() async => initial;

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

class _Hidden extends SpaceHiddenAutoKeys {
  @override
  Set<String> build() => const <String>{};
}

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _RetiredHint extends SpaceFirstRunHintStore {
  @override
  bool readRetired() => true;

  @override
  Future<void> writeRetired() async {}
}

/// A phone: the sheet is full width only below the tablet size.
Future<_Store> _pump(WidgetTester tester, {ThemeData? theme}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = _Store();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        spaceShortcutsProvider.overrideWith(() => store),
        playerPhotoProvider.overrideWith((ref, fideId) async => null),
        spaceFirstRunHintStoreProvider.overrideWithValue(_RetiredHint()),
        spaceHiddenAutoKeysProvider.overrideWith(_Hidden.new),
        spaceAutoRowProvider.overrideWith((ref, s) => SpaceAutoRow.empty),
        // The board editor a row opens.
        boardSettingsProviderNew.overrideWith(_BoardSettings.new),
        ecoPositionIndexProvider.overrideWith(
          (ref) async => buildEcoPositionIndex(),
        ),
        gameCardEvalWithStockfishFallbackProvider.overrideWith(
          (ref, fen) async => CloudEval(
            fen: fen,
            knodes: 1,
            depth: 20,
            pvs: [Pv(moves: 'e2e4', cp: 20)],
          ),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              backgroundColor: context.colors.background,
              body: const MySpaceView(),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  return store;
}

Future<void> _openOpeningsSheet(WidgetTester tester) async {
  final door = find.text(SpaceSection.openings.doorLabel);
  await tester.scrollUntilVisible(
    door,
    300,
    scrollable: find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(door);
  // The sheet slides in on a spring.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpWidget(const SizedBox.shrink());
}

/// The sheet alone, on a phone, over a My Space that holds [pinned].
Future<_Store> _pumpSheet(
  WidgetTester tester, {
  List<SpaceShortcut> pinned = const [],
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = _Store(pinned);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [spaceShortcutsProvider.overrideWith(() => store)],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const Scaffold(
              body: SpaceAddSheet(section: SpaceSection.openings),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return store;
}

/// The add toggle on the row titled [title].
Finder _toggleOf(String title) => find.descendant(
  of: find
      .ancestor(of: find.text(title), matching: find.byType(GestureDetector))
      .first,
  matching: find.byType(SpaceAddToggle),
);

/// The sheet's own list (the search field scrolls too).
Finder get _sheetList => find
    .descendant(
      of: find.byType(SpaceAddSources),
      matching: find.byType(Scrollable),
    )
    .first;

Color _colorOf(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  return paragraph.text.style!.color!;
}

void main() {
  testWidgets('the Openings door opens its picker in place', (tester) async {
    await _pump(tester);
    await _openOpeningsSheet(tester);

    expect(find.text('Add to Openings'), findsOneWidget);
    expect(find.text('Popular at 2700+'), findsOneWidget);
    // Nothing is in My Space: every line is new, most played first.
    final first = kSpaceDefaultOpenings.first.tileName;
    final next = kSpacePopularOpenings.first.tileName;
    expect(
      tester.getTopLeft(find.text(first)).dy,
      lessThan(tester.getTopLeft(find.text(next)).dy),
    );
    expect(find.text(kSpaceSheetAddedLabel), findsNothing);
    expect(find.byTooltip('Board editor'), findsWidgets);
    expect(find.byType(SpaceAddToggle), findsWidgets);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('adding holds the tile back, then it lands with one Undo', (
    tester,
  ) async {
    final store = await _pump(tester);
    await _openOpeningsSheet(tester);

    final sveshnikov = kSpacePopularOpenings.first;
    final draft = spaceEliteOpeningDraft(sveshnikov)!;
    await tester.tap(
      find.descendant(
        of: find
            .ancestor(
              of: find.text(sveshnikov.tileName),
              matching: find.byType(GestureDetector),
            )
            .first,
        matching: find.byType(SpaceAddToggle),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.added, [draft.key]);

    // Behind the sheet the row holds it back: the name shows once, on the
    // sheet's own row.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(sveshnikov.tileName), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Add to Openings'), findsNothing);
    expect(
      find.text('Added ${sveshnikov.tileName} to Openings'),
      findsOneWidget,
    );
    // The tile is on the row now.
    expect(find.text(sveshnikov.tileName), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(sveshnikov.tileName), findsNothing);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('search reaches the whole catalogue', (tester) async {
    await _pump(tester);
    await _openOpeningsSheet(tester);

    await tester.enterText(find.byType(TextField), 'Najdorf');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('All openings'), findsOneWidget);
    expect(find.textContaining('Najdorf'), findsWidgets);
    expect(find.text('Popular at 2700+'), findsNothing);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  for (final light in [true, false]) {
    testWidgets('the picker clears AA in ${light ? 'light' : 'dark'} mode', (
      tester,
    ) async {
      await _pump(
        tester,
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      );
      await _openOpeningsSheet(tester);
      final colors = light ? AppColors.light : AppColors.dark;
      final sheet = colors.surface;

      void expectText(Finder f, String what) {
        expect(
          wcagContrast(_colorOf(tester, f), sheet),
          greaterThanOrEqualTo(4.5),
          reason: what,
        );
      }

      expectText(find.text('Add to Openings'), 'title');
      expectText(find.text('Done'), 'Done');
      expectText(find.text('Popular at 2700+'), 'group label');
      final o = kSpacePopularOpenings.first;
      expectText(find.text(o.tileName), 'row title');
      expectText(find.text(spaceUnbrokenMoves(o.moves)), 'row moves');
      expectText(find.text(o.eco), 'ECO code');
      // The add mark is a control: 3:1 at least, in both states.
      expect(wcagContrast(colors.textPrimary, sheet), greaterThanOrEqualTo(3));
      expect(wcagContrast(colors.accentText, sheet), greaterThanOrEqualTo(3));
      // The search field and its hint.
      expect(
        wcagContrast(colors.textSecondary, colors.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
      await _drain(tester);
    });
  }

  testWidgets('openings not in My Space lead, the added ones follow, '
      'marked as added', (tester) async {
    final seeded = SpaceShortcutsNotifier.planSeed(const [], spaceSeedDrafts());
    await _pumpSheet(tester, pinned: seeded);

    // New options first: the defaults are in, so the next line leads.
    final lead = kSpacePopularOpenings.first.tileName;
    expect(find.text('Popular at 2700+'), findsOneWidget);
    expect(find.text(lead), findsOneWidget);
    expect(find.bySemanticsLabel('Save $lead to My Space'), findsOneWidget);

    // The two defaults sit under their own label, after every new line,
    // each already checked.
    await tester.scrollUntilVisible(
      find.text(kSpaceDefaultOpenings.last.tileName),
      300,
      scrollable: _sheetList,
    );
    await tester.pump(const Duration(milliseconds: 100));
    final label = tester.getTopLeft(find.text(kSpaceSheetAddedLabel)).dy;
    final lastNew = kSpacePopularOpenings.last.tileName;
    expect(tester.getTopLeft(find.text(lastNew)).dy, lessThan(label));
    for (final o in kSpaceDefaultOpenings) {
      expect(tester.getTopLeft(find.text(o.tileName)).dy, greaterThan(label));
      expect(
        find.bySemanticsLabel('Remove ${o.tileName} from My Space'),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a removed default is a new option again, and re-adds', (
    tester,
  ) async {
    // Only the Rossolimo is left; the QGD Three Knights was removed.
    final seeded = SpaceShortcutsNotifier.planSeed(
      const [],
      spaceSeedDrafts(),
    ).where((s) => s.title != kSpaceDefaultOpenings.first.tileName).toList();
    final store = await _pumpSheet(tester, pinned: seeded);

    final removed = kSpaceDefaultOpenings.first;
    final lead = find.text(removed.tileName);
    expect(lead, findsOneWidget);
    expect(
      tester.getTopLeft(lead).dy,
      lessThan(
        tester.getTopLeft(find.text(kSpacePopularOpenings.first.tileName)).dy,
      ),
    );

    // Adding it keeps it where it is, now checked: the order holds while
    // the sheet is open.
    final before = tester.getTopLeft(lead);
    await tester.tap(_toggleOf(removed.tileName));
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.added, [spaceEliteOpeningDraft(removed)!.key]);
    expect(
      find.bySemanticsLabel('Remove ${removed.tileName} from My Space'),
      findsOneWidget,
    );
    expect(tester.getTopLeft(lead), before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an opening row opens the board editor on its position', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    await _openOpeningsSheet(tester);

    final o = kSpaceDefaultOpenings.first;
    final fen = spaceEliteOpeningDraft(o)!.targetId;
    final button = find.descendant(
      of: find
          .ancestor(
            of: find.text(o.tileName),
            matching: find.byType(GestureDetector),
          )
          .first,
      matching: find.bySemanticsLabel(kSpaceSheetEditorLabel),
    );
    expect(button, findsOneWidget);
    // Beside the save toggle, and reachable without a pointer.
    expect(
      find.bySemanticsLabel('Save ${o.tileName} to My Space'),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(button)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );

    await tester.tap(button);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The sheet is gone and the editor is up, set on that position.
    expect(find.text('Add to Openings'), findsNothing);
    final editor = find.byType(BoardEditorScreen);
    expect(editor, findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(editor));
    expect(
      container.read(boardEditorProvider).fullFen.split(' ').take(4),
      fen.split(' ').take(4),
    );
    expect(tester.takeException(), isNull);
    handle.dispose();
    await _drain(tester);
  });

  testWidgets('every searched opening can open in the board editor', (
    tester,
  ) async {
    await _pump(tester);
    await _openOpeningsSheet(tester);

    await tester.enterText(find.byType(TextField), 'Sicilian');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    final rows = find.byType(SpaceAddToggle).evaluate().length;
    expect(rows, greaterThan(0));
    expect(find.byTooltip('Board editor'), findsNWidgets(rows));
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('rows hold at 360dp and 1.3x text', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _Store();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          spaceShortcutsProvider.overrideWith(() => store),
          spaceFirstRunHintStoreProvider.overrideWithValue(_RetiredHint()),
          spaceHiddenAutoKeysProvider.overrideWith(_Hidden.new),
          spaceAutoRowProvider.overrideWith((ref, s) => SpaceAutoRow.empty),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              textScaler: TextScaler.linear(1.3),
            ),
            child: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return const Scaffold(
                  body: SpaceAddSheet(section: SpaceSection.openings),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Popular at 2700+'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
