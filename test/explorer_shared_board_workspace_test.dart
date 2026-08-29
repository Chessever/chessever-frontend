import 'package:chessever2/screens/board_editor/board_editor_screen.dart';
import 'package:chessever2/screens/gamebase/utils/explorer_move_sort.dart';
import 'package:chessever2/screens/gamebase/widgets/board_workspace_controls.dart';
import 'package:chessever2/screens/gamebase/widgets/move_statistics_panel.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        ResponsiveHelper.init(context);
        return Scaffold(body: child);
      },
    ),
  );
}

void main() {
  group('shared Explorer and Notation board workspace', () {
    test('Board opens in Explorer and teaches both advanced controls', () {
      expect(boardWorkspaceDefaultPage, 0);
      expect(
        boardWorkspaceViewsCoachmarkMessage,
        contains('Explorer and Notation'),
      );
      expect(
        boardWorkspaceEditorCoachmarkMessage,
        contains('Edit any position'),
      );
    });

    testWidgets(
      'toggle exposes two clear independently tappable active states',
      (tester) async {
        var selected = 0;
        await tester.pumpWidget(
          _app(
            StatefulBuilder(
              builder: (context, setState) => ExplorerViewToggle(
                currentPage: selected,
                onSelected: (value) => setState(() => selected = value),
              ),
            ),
          ),
        );

        expect(find.text('Explorer'), findsOneWidget);
        expect(find.text('Notation'), findsOneWidget);
        expect(
          tester
              .widget<Semantics>(
                find.byKey(const ValueKey('opening_explorer_tab_explorer')),
              )
              .properties
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<Semantics>(
                find.byKey(const ValueKey('opening_explorer_tab_notation')),
              )
              .properties
              .selected,
          isFalse,
        );

        await tester.tap(find.text('Notation'));
        await tester.pumpAndSettle();

        expect(selected, 1);
        expect(
          tester
              .widget<Semantics>(
                find.byKey(const ValueKey('opening_explorer_tab_notation')),
              )
              .properties
              .selected,
          isTrue,
        );
      },
    );

    testWidgets('Explorer header puts filter before named sortable columns', (
      tester,
    ) async {
      ExplorerMoveSortField? selectedField;
      var filterOpened = false;
      await tester.pumpWidget(
        _app(
          ExplorerMovesHeader(
            sort: defaultExplorerMoveSort(ExplorerMoveSortField.games),
            onSort: (field) => selectedField = field,
            onFilter: () => filterOpened = true,
            hasActiveFilters: false,
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('opening_explorer_filter_button')),
        findsOneWidget,
      );
      expect(find.text('Move'), findsNothing);
      expect(find.text('Results'), findsOneWidget);
      expect(find.text('Games'), findsOneWidget);
      expect(find.text('Last'), findsOneWidget);
      expect(find.byIcon(Icons.unfold_more_rounded), findsNothing);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);

      expect(
        tester
            .widget<Semantics>(
              find.byKey(const ValueKey('opening_explorer_sort_games')),
            )
            .properties
            .selected,
        isTrue,
      );

      await tester.tap(
        find.byKey(const ValueKey('opening_explorer_filter_button')),
      );
      await tester.pump();
      expect(filterOpened, isTrue);

      await tester.tap(find.text('Last'));
      await tester.pump();
      expect(selectedField, ExplorerMoveSortField.last);
    });

    testWidgets('embedded Explorer omits an unavailable filter action', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          ExplorerMovesHeader(
            sort: defaultExplorerMoveSort(ExplorerMoveSortField.games),
            onSort: (_) {},
            hasActiveFilters: false,
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('opening_explorer_filter_button')),
        findsNothing,
      );
      expect(find.text('Games'), findsOneWidget);
    });

    testWidgets('Board Editor action uses a chessboard-shaped icon', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const ExplorerBoardEditorIcon()));
      expect(
        find.byKey(const ValueKey('opening_explorer_editor_checkerboard')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.grid_view_rounded), findsNothing);
    });

    test('each column has one useful fixed sort direction', () {
      expect(
        defaultExplorerMoveSort(ExplorerMoveSortField.move).ascending,
        isTrue,
      );
      expect(
        defaultExplorerMoveSort(ExplorerMoveSortField.score).ascending,
        isFalse,
      );
      expect(
        defaultExplorerMoveSort(ExplorerMoveSortField.games).ascending,
        isFalse,
      );
      expect(
        defaultExplorerMoveSort(ExplorerMoveSortField.last).ascending,
        isFalse,
      );
    });

    test('Results alternates highest White then highest Black', () {
      final white = nextExplorerMoveSort(
        defaultExplorerMoveSort(ExplorerMoveSortField.games),
        ExplorerMoveSortField.score,
      );
      expect(white.resultSide, ExplorerResultSortSide.white);
      expect(white.ascending, isFalse);

      final black = nextExplorerMoveSort(white, ExplorerMoveSortField.score);
      expect(black.resultSide, ExplorerResultSortSide.black);
      expect(black.ascending, isFalse);

      final whiteAgain = nextExplorerMoveSort(
        black,
        ExplorerMoveSortField.score,
      );
      expect(whiteAgain.resultSide, ExplorerResultSortSide.white);
    });

    test('overflow menu contains only approved secondary actions', () {
      expect(explorerBoardMenuItems.map((item) => item.label), [
        'Copy PGN',
        'Board Settings',
        'Share',
      ]);
      expect(explorerBoardMenuItems.map((item) => item.action), [
        ExplorerBoardMenuAction.copyPgn,
        ExplorerBoardMenuAction.boardSettings,
        ExplorerBoardMenuAction.share,
      ]);
    });

    test('Board Editor can return an edited position to its caller', () {
      const screen = BoardEditorScreen(
        initialFen: '8/8/8/8/8/8/4K3/7k w - - 0 1',
        returnFenOnDone: true,
      );
      expect(screen.initialFen, contains('4K3'));
      expect(screen.returnFenOnDone, isTrue);
    });
  });
}
