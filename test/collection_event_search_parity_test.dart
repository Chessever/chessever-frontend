import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/search/search_clear_button.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A collection's search and a tournament's are the one search header
/// (`EventViewShell`, `TournamentDetailScreen`): the field from the gutter,
/// the circled x in it while it holds words, then the page's Filters outside
/// the field (the collection's), then Cancel ending on the gutter.
void main() {
  for (final size in [const Size(390, 844), const Size(1024, 1366)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'collection and tournament search match at $size and ${scale}x text',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          const tournamentKey = ValueKey('tournament_search_reference');
          const collectionKey = ValueKey('collection_search_reference');
          const tournamentCancel = ValueKey('tournament_search_cancel');
          const collectionCancel = ValueKey('collection_search_cancel');
          const filterKey = ValueKey('parity_filter');
          var filtersOpened = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.darkTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  return Scaffold(
                    body: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: ResponsiveHelper.isTablet
                              ? ResponsiveHelper.contentMaxWidth
                              : double.infinity,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SearchModeHeader(
                              key: tournamentKey,
                              hintText: 'Search games',
                              closeKey: tournamentCancel,
                            ),
                            SearchModeHeader(
                              key: collectionKey,
                              hintText: 'Search games',
                              closeKey: collectionCancel,
                              trailing: [
                                SearchModeFilterButton(
                                  key: filterKey,
                                  count: 3,
                                  onTap: () => filtersOpened++,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
          Finder inside(Key header, Finder matching) =>
              find.descendant(of: find.byKey(header), matching: matching);
          for (final header in [tournamentKey, collectionKey]) {
            await tester.enterText(
              inside(header, find.byType(EditableText)),
              'Tal',
            );
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          final tournament = tester.getRect(find.byKey(tournamentKey));
          final collection = tester.getRect(find.byKey(collectionKey));
          Rect field(Key header) => tester.getRect(
            inside(header, find.byType(HomeSearchFieldSurface)),
          );
          Rect word(Key header) =>
              tester.getRect(inside(header, find.text('Cancel')));
          final gutter = SearchHeaderMetrics.gutter;

          // The same row: as wide and as tall.
          expect(collection.width, closeTo(tournament.width, 0.01));
          expect(collection.height, closeTo(tournament.height, 0.01));
          // The same field, from the gutter, as tall, on the same line; the
          // collection's only narrower by its Filters.
          final tournamentField = field(tournamentKey);
          final collectionField = field(collectionKey);
          for (final (frame, row) in [
            (tournamentField, tournament),
            (collectionField, collection),
          ]) {
            expect(frame.left - row.left, closeTo(gutter, 0.01));
          }
          expect(
            collectionField.top - collection.top,
            closeTo(tournamentField.top - tournament.top, 0.01),
          );
          expect(collectionField.height, closeTo(tournamentField.height, 0.01));
          expect(collectionField.right, lessThan(tournamentField.right));
          // Words in both: the circled x in both, inside the field.
          for (final header in [tournamentKey, collectionKey]) {
            final clear = inside(
              header,
              find.byKey(const ValueKey('search_field_clear')),
            );
            expect(clear.hitTestable(), findsOneWidget);
            expect(
              tester.getRect(clear).right,
              lessThanOrEqualTo(field(header).right),
            );
            expect(
              tester.getSize(inside(header, find.byType(SearchClearButton))),
              SearchClearButton.box,
            );
          }
          // The same Cancel, at the same spot, its word ending on the gutter.
          final tournamentWord = word(tournamentKey);
          final collectionWord = word(collectionKey);
          expect(
            collectionWord.left - collection.left,
            closeTo(tournamentWord.left - tournament.left, 0.01),
          );
          expect(collectionWord.size, tournamentWord.size);
          expect(
            tournament.right - tournamentWord.right,
            closeTo(gutter, 0.01),
          );
          expect(
            collection.right - collectionWord.right,
            closeTo(gutter, 0.01),
          );
          expect(
            collectionWord.center.dy - collection.top,
            closeTo(tournamentWord.center.dy - tournament.top, 0.01),
          );
          // Filters outside the field, before Cancel, and they open.
          final filter = tester.getRect(find.byKey(filterKey));
          expect(collectionField.right, lessThanOrEqualTo(filter.left));
          expect(
            filter.right,
            lessThanOrEqualTo(
              tester.getRect(find.byKey(collectionCancel)).left,
            ),
          );
          expect(
            inside(collectionKey, find.byType(SearchCountBadge)),
            findsOneWidget,
          );
          expect(
            inside(tournamentKey, find.byType(SearchModeFilterButton)),
            findsNothing,
          );
          await tester.tap(find.byKey(filterKey));
          expect(filtersOpened, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
