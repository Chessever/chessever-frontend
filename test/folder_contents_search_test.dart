import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/library/folder_contents_screen.dart';
import 'package:chessever2/screens/library/providers/book_games_paginated_provider.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart' show PageTitle;
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/search_no_matches.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Every page the screen asked for, and an empty answer to each: no
/// Supabase, and the screen's query is read off the keys.
final List<BookPaginationKey> _asked = [];

class _FakeBook
    extends
        AutoDisposeFamilyAsyncNotifier<PaginatedBookState, BookPaginationKey>
    implements BookGamesNotifier {
  @override
  Future<PaginatedBookState> build(BookPaginationKey arg) async {
    _asked.add(arg);
    return PaginatedBookState(totalCount: arg.search.isEmpty ? 12 : 0);
  }

  @override
  Future<void> loadMore() async {}

  @override
  Future<void> refresh() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _database = LibraryFolder(
  id: 'db-1',
  userId: 'user-1',
  name: 'Sicilian repertoire',
  color: '#0FB4E5',
  icon: 'folder',
  orderIndex: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Finder get _fab => find.byKey(const ValueKey('folder_search_fab'));
Finder get _field => find.byKey(const ValueKey('folder_search_field'));
Finder get _close => find.byTooltip('Close search');
Finder get _searchHeader => find.byType(SearchModeHeader);
Finder _inSearch(Finder finder) =>
    find.descendant(of: _searchHeader, matching: finder);

/// Lets springs finish without waiting on a caret's blink.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _asked.clear();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bookGamesPaginatedProvider.overrideWith(_FakeBook.new),
        folderTagCountsProvider.overrideWith((ref, key) async => const {}),
        childLibraryFoldersProvider.overrideWith((ref, id) => const []),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return FolderContentsScreen(folder: _database);
          },
        ),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  group('A database searches like every list (Trello #1420)', () {
    testWidgets('no field pinned on the page: the title is centred, the '
        'search floats, and the count heads the list', (tester) async {
      await _pump(tester);

      expect(
        find.byKey(const ValueKey(E2eIds.folderContentsRoot)),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(_fab, findsOneWidget);
      expect(find.byType(SearchInkFab), findsOneWidget);
      expect(find.byTooltip('Search games'), findsOneWidget);

      final back = tester.getRect(find.byType(PageBackButton));
      expect(back.left, closeTo(SearchHeaderMetrics.leadingInset, 0.01));
      final title = find.descendant(
        of: find.byType(PageTitle),
        matching: find.text('Sicilian repertoire'),
      );
      expect(title, findsOneWidget);
      expect(tester.getRect(title).left, greaterThan(back.right));
      expect(find.text('12 games'), findsOneWidget);
    });

    testWidgets('the field opens in the header, Filters held where they '
        'were, the query runs over the whole database, and closing drops it', (
      tester,
    ) async {
      await _pump(tester);
      final back = tester.getRect(find.byType(PageBackButton));
      final filters = tester.getRect(find.byType(SearchModeFilterButton));

      await tester.tap(_fab);
      await _settle(tester);

      expect(_field, findsOneWidget);
      expect(tester.getRect(_close), rectMoreOrLessEquals(back, epsilon: 0.5));
      expect(
        tester.getRect(_inSearch(find.byType(SearchModeFilterButton))),
        rectMoreOrLessEquals(filters, epsilon: 0.5),
      );

      await tester.enterText(_field, 'najdorf');
      await tester.pump(const Duration(milliseconds: 300));
      await _settle(tester);
      expect(_asked.last.search, 'najdorf');
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('search_no_matches_title')))
            .data,
        SearchNoMatches.titleFor(query: 'najdorf'),
      );

      // Its way back empties the words; the search stays open.
      await tester.tap(find.byKey(const ValueKey('search_no_matches_clear')));
      await _settle(tester);
      expect(_asked.last.search, isEmpty);
      expect(_field, findsOneWidget);

      await tester.enterText(_field, 'scheveningen');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(_close);
      await _settle(tester);
      expect(_field, findsNothing);
      expect(_asked.last.search, isEmpty);
      expect(find.text('12 games'), findsOneWidget);
    });
  });
}
