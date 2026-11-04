import 'dart:async';

import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/group_event/widget/all_events_tab_widget.dart';
import 'package:chessever2/screens/group_event/widget/search_results_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/adaptive_window.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'fixtures/duo_window_matrix.dart';

enum _Surface { events, search, searchLoading, searchEmpty, searchError }

void main() {
  for (final window in duoWindowCases) {
    for (final light in [false, true]) {
      for (final surface in _Surface.values) {
        testWidgets('${surface.name} cold starts in ${window.name}, '
            '${light ? 'light' : 'dark'} with navigation reserved', (
          tester,
        ) async {
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          String? selected;
          await _pump(
            tester,
            window,
            surface,
            scroll,
            light: light,
            onSelect: (event) => selected = event.id,
          );
          expect(tester.takeException(), isNull);
          if (surface == _Surface.events || surface == _Surface.search) {
            expect(find.byType(EventCard), findsWidgets);
            _expectCardsInsideWidth(tester);
            if (surface == _Surface.events) {
              await tester.tap(find.byType(EventCard).hitTestable().first);
              expect(selected, isNotNull);
            }
          } else if (surface == _Surface.searchEmpty) {
            expect(find.text('No events found'), findsOneWidget);
          } else if (surface == _Surface.searchError) {
            expect(find.text('Something went wrong'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  for (final transition in duoWindowTransitions) {
    for (final surface in [_Surface.events, _Surface.search]) {
      testWidgets('${surface.name} retains its place: '
          '${transition.from.name} to ${transition.to.name}', (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final queries = <String>[];
        String? selected;
        await _pump(
          tester,
          transition.from,
          surface,
          scroll,
          queries: queries,
          onSelect: (event) => selected = event.id,
        );
        final element = find
            .byType(
              surface == _Surface.events
                  ? AllEventsTabWidget
                  : SearchResultsWidget,
            )
            .evaluate()
            .single;
        scroll.jumpTo(scroll.position.maxScrollExtent * 0.4);
        await tester.pump();
        await tester.pump();
        expect(scroll.offset, greaterThan(0));
        final share = scroll.offset / scroll.position.maxScrollExtent;

        applyDuoWindow(tester, transition.to, mirrorInsets: true);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(tester.takeException(), isNull);
        expect(element.mounted, isTrue);
        expect(scroll.positions, hasLength(1));
        expect(scroll.offset, greaterThan(0));
        expect(
          scroll.offset / scroll.position.maxScrollExtent,
          closeTo(share, 0.2),
        );
        _expectCardsInsideWidth(tester);
        if (surface == _Surface.search) {
          // A resize must not issue another query or replace its results.
          expect(queries, ['championship']);
        } else {
          await tester.tap(find.byType(EventCard).hitTestable().first);
          expect(selected, isNotNull);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

Future<void> _pump(
  WidgetTester tester,
  DuoWindowCase window,
  _Surface surface,
  ScrollController scroll, {
  bool light = false,
  List<String>? queries,
  ValueChanged<GroupEventCardModel>? onSelect,
}) async {
  tester.view.devicePixelRatio = 3;
  applyDuoWindow(tester, window);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        favoriteEventsProvider.overrideWith(_NoFavorites.new),
        eventImageProvider.overrideWith(
          (ref, id) async => const EventImageData(),
        ),
        liveGroupBroadcastIdsProvider.overrideWith(
          (ref) => Stream.value(const <String>[]),
        ),
        supabaseCombinedSearchProvider.overrideWith((ref, query) {
          queries?.add(query);
          return switch (surface) {
            _Surface.searchLoading => Completer<EnhancedSearchResult>().future,
            _Surface.searchEmpty => Future.value(EnhancedSearchResult.empty()),
            _Surface.searchError => Future.error(StateError('offline')),
            _ => Future.value(_results),
          };
        }),
      ],
      child: MaterialApp(
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.3)),
          child: AdaptiveWindowScope(child: child!),
        ),
        home: Builder(
          builder: (context) {
            final size = MediaQuery.sizeOf(context);
            final reserved = size.width < 600
                ? 0.0
                : size.width > size.height
                ? 110.0
                : 90.0;
            return Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(left: reserved),
                  child: SizedBox.expand(
                    key: const ValueKey('duo_content_body'),
                    child: surface == _Surface.events
                        ? AllEventsTabWidget(
                            filteredEvents: _events,
                            scrollController: scroll,
                            onSelect: onSelect ?? (_) {},
                          )
                        : SearchResultsWidget(
                            scrollController: scroll,
                            searchQuery: 'championship',
                          ),
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
  await tester.pump(const Duration(milliseconds: 500));
}

void _expectCardsInsideWidth(WidgetTester tester) {
  final body = tester.getRect(find.byKey(const ValueKey('duo_content_body')));
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    if (!paragraph.attached || paragraph.size.isEmpty) continue;
    final rect = MatrixUtils.transformRect(
      paragraph.getTransformTo(null),
      Offset.zero & paragraph.size,
    );
    if (rect.bottom <= body.top || rect.top >= body.bottom) continue;
    final text = (element.widget as RichText).text.toPlainText();
    expect(rect.left, greaterThanOrEqualTo(body.left), reason: text);
    expect(rect.right, lessThanOrEqualTo(body.right), reason: text);
  }
}

final _events = List.generate(
  30,
  (index) => GroupEventCardModel(
    id: 'duo-event-$index',
    title: 'European Individual Chess Championship ${2000 + index}',
    dates: 'November 4 - 18, 2026',
    startDate: DateTime(2026, 11, 4),
    endDate: DateTime(2026, 11, 18),
    maxAvgElo: 2750,
    timeUntilStart: '',
    tourEventCategory: TourEventCategory.completed,
    timeControl: '90+30',
    eventSource: EventSource.lichessBroadcast,
  ),
);

final _results = EnhancedSearchResult(
  tournamentResults: [
    for (final event in _events)
      SearchResult(
        tournament: event,
        score: 1,
        matchedText: 'championship',
        type: SearchResultType.tournament,
      ),
  ],
  playerResults: [
    for (final (index, name) in [
      'Carlsen, Magnus',
      'Nakamura, Hikaru',
      'Vachier-Lagrave, Maxime',
      'Nepomniachtchi, Ian',
    ].indexed)
      SearchResult(
        tournament: _events.first,
        score: 1,
        matchedText: name,
        type: SearchResultType.player,
        player: SearchPlayer(
          id: 'duo-player-$index',
          name: name,
          rating: 2800,
          tournamentId: _events.first.id,
          tournamentName: _events.first.title,
        ),
      ),
  ],
);

class _NoFavorites extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const [];
}
