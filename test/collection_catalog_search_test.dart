import 'package:chessever2/widgets/game_filter/game_filter_choice_chips.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/game_filter/filter_popup_components.dart';
import 'dart:async';
import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/collections/collection_catalog_list.dart';
import 'package:chessever2/screens/collections/collection_search_filters.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/eco_filter_dropdown.dart';
import 'package:chessever2/widgets/game_filter/wheel_range_filter.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'every tab carries the full combined query and its own offset',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, h) {
              requests.add(r);
              h.resolve(
                Response(
                  requestOptions: r,
                  statusCode: 200,
                  data: {
                    'status': 'success',
                    'data': {
                      'items': [],
                      'total': 0,
                      'limit': 40,
                      'offset': 40,
                    },
                  },
                ),
              );
            },
          ),
        );
      final repo = CollectionsRepository(
        GamebaseRepository(dio, apiKey: 'test'),
        accessToken: () => 'session',
      );
      const query = CollectionSearchQuery(
        text: '[White "Carlsen"]',
        eco: 'B20',
        minYear: 2023,
        maxYear: 2024,
        author: 'Judit Polgar',
        annotated: true,
        result: '1-0',
        sort: 'oldest',
      );
      expect(
        const CollectionSearchQuery(year: 2024).parameters,
        containsPair('year', 2024),
      );
      expect(query.withText('Tal').parameters['author'], 'Judit Polgar');
      expect(query.withText('Tal').parameters['minYear'], 2023);
      await repo.searchBooks(query, 40);
      await repo.searchOpenings(query, 40);
      await repo.searchAuthors(query, 40);
      await repo.fetchPublishedGames(search: query, offset: 40);
      for (final r in requests) {
        expect(r.queryParameters, containsPair('q', '[White "Carlsen"]'));
        for (final entry in query.parameters.entries) {
          expect(r.queryParameters, containsPair(entry.key, entry.value));
        }
        expect(r.queryParameters['offset'], 40);
      }
      expect(requests.last.headers['Authorization'], 'Bearer session');
      expect(
        requests.take(3).every((r) => !r.headers.containsKey('Authorization')),
        isTrue,
      );
      dio.close();
    },
  );

  Widget list(
    CollectionSearchQuery query,
    Future<CatalogBatch<String>> Function(int) load,
  ) => MaterialApp(
    home: Scaffold(
      body: CollectionCatalogList<String>(
        query: query,
        load: load,
        identity: (s) => s,
        indexedItemBuilder: (s, index) => SizedBox(
          height: 100,
          child: Text(s, key: ValueKey('rank_${index + 1}')),
        ),
        padding: EdgeInsets.zero,
        emptyMessage: 'Empty',
      ),
    ),
  );

  testWidgets('changing query discards old requests and starts at zero', (
    tester,
  ) async {
    final old = Completer<CatalogBatch<String>>();
    await tester.pumpWidget(
      list(const CollectionSearchQuery(text: 'old'), (_) => old.future),
    );
    final offsets = <int>[];
    await tester.pumpWidget(
      list(const CollectionSearchQuery(text: 'new'), (offset) async {
        offsets.add(offset);
        return const CatalogBatch(['New result'], 1);
      }),
    );
    await tester.pump();
    old.complete(const CatalogBatch(['Stale result'], 1));
    await tester.pump();
    expect(find.text('New result'), findsOneWidget);
    expect(find.text('Stale result'), findsNothing);
    expect(offsets, [0]);
  });
  testWidgets('failed next page retains rows and retries the same offset', (
    tester,
  ) async {
    final offsets = <int>[];
    var fail = true;
    await tester.pumpWidget(
      list(const CollectionSearchQuery(), (offset) async {
        offsets.add(offset);
        if (offset == 0) return const CatalogBatch(['First'], 2);
        if (fail) throw StateError('offline');
        return const CatalogBatch(['Second'], 2);
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
    expect(find.byKey(const ValueKey('rank_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('rank_2')), findsOneWidget);
    expect(offsets, [0, 1, 1]);
  });
  testWidgets('shared pickers preserve every filter and reset to all years', (
    tester,
  ) async {
    CollectionSearchQuery? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return TextButton(
                onPressed: () async {
                  result = await showCollectionSearchFilters(
                    context,
                    result ??
                        const CollectionSearchQuery(
                          text: 'Tal',
                          annotated: true,
                        ),
                    loadAuthors: () async => ['Bobby Fischer', 'Judit Polgar'],
                  );
                },
                child: const Text('Filters'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    expect(find.byType(FilterPopupFrame), findsOneWidget);
    expect(
      find.byType(GameFilterChoiceChips<GameResultFilter>),
      findsOneWidget,
    );
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Result'), findsOneWidget);
    expect(find.text('Sort'), findsNothing);
    expect(find.text('Annotations'), findsNothing);
    expect(find.text('Unfinished'), findsNothing);
    expect(find.text('Completed'), findsNothing);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('½-½'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.textContaining('Filters match games'), findsNothing);
    expect(find.textContaining('For a specific side'), findsNothing);
    expect(find.byType(WheelRangeFilter), findsNothing);
    await tester.tap(find.text('Year range'));
    await tester.pumpAndSettle();
    expect(find.byType(WheelRangeFilter), findsOneWidget);
    expect(find.byType(ListWheelScrollView), findsNWidgets(2));
    final year = DateTime.now().year;
    var range = tester.widget<WheelRangeFilter>(find.byType(WheelRangeFilter));
    expect(range.currentStart, year - 1);
    expect(range.currentEnd, year);
    await tester.drag(
      find.byType(ListWheelScrollView).first,
      const Offset(0, 32),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<WheelRangeFilter>(find.byType(WheelRangeFilter))
          .currentStart,
      year - 2,
    );
    await tester.tap(find.byKey(const ValueKey('eco-dropdown-header')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(EcoFilterDropdown),
        matching: find.byType(TextField),
      ),
      'B20',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('eco-family-B20-B99')), findsNothing);
    final opening = find
        .byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              (widget.properties.label?.endsWith(', ECO B20') ?? false),
        )
        .first;
    await tester.ensureVisible(opening);
    await tester.pump();
    await tester.tap(opening);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('collections_author')),
    );
    await tester.tap(find.text('All authors').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Judit Polgar'));
    await tester.tap(find.text('Judit Polgar'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('collection_result_filter')),
    );
    await tester.ensureVisible(find.text('1-0'));
    await tester.tap(find.text('1-0'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Apply Filters'));
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();
    expect(result!.text, 'Tal');
    expect(result!.eco, 'B20');
    expect(result!.minYear, year - 2);
    expect(result!.maxYear, year);
    expect(result!.author, 'Judit Polgar');
    expect(result!.annotated, isFalse);
    expect(result!.result, '1-0');
    expect(result!.sort, 'default');
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<WheelRangeFilter>(find.byType(WheelRangeFilter))
          .currentStart,
      year - 2,
    );
    await tester.ensureVisible(find.text('Reset'));
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(result, const CollectionSearchQuery(text: 'Tal'));
    expect(result!.filterCount, 0);
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    expect(find.byType(WheelRangeFilter), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(result, isNull); // Dismissing a draft never applies it.
    expect(tester.takeException(), isNull);
  });
}
