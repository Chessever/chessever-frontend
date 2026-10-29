import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/group_event/widget/search_results_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// The search results Home and Events render (SearchResultsWidget), driven the
// way the reported scenarios drove them.
void main() {
  testWidgets(
    'Home shows its own players while the Events tab still holds "carlsen"',
    (tester) async {
      await _pump(
        tester,
        eventsTabQuery: 'carlsen',
        screenQuery: 'nakamura',
      );

      expect(find.textContaining('Nakamura'), findsWidgets);
      expect(find.textContaining('Carlsen'), findsNothing);
    },
  );

  testWidgets('a fresh launch with no Events search still shows player cards', (
    tester,
  ) async {
    await _pump(tester, eventsTabQuery: '', screenQuery: 'carlsen');

    expect(find.textContaining('Carlsen'), findsWidgets);
  });

  testWidgets('one letter asks to keep typing, never "No events match"', (
    tester,
  ) async {
    await _pump(tester, eventsTabQuery: 'k', screenQuery: 'k');

    expect(find.text('Keep typing to search'), findsOneWidget);
    expect(find.textContaining('No events match'), findsNothing);
    expect(find.text('No events found'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required String eventsTabQuery,
  required String screenQuery,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final scroll = ScrollController();
  addTearDown(scroll.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchTabQueryProvider.overrideWith((ref) => eventsTabQuery),
        supabaseCombinedSearchProvider.overrideWith(
          (ref, query) async =>
              _resultsByQuery[query.trim()] ?? EnhancedSearchResult.empty(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: SearchResultsWidget(
                scrollController: scroll,
                searchQuery: screenQuery,
              ),
            );
          },
        ),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final _event = GroupEventCardModel(
  id: 'tour-1',
  title: 'Sinquefield Cup 2026',
  dates: 'Aug 20, 2026',
  maxAvgElo: 2750,
  timeUntilStart: '',
  tourEventCategory: TourEventCategory.completed,
  timeControl: 'Classical',
  startDate: DateTime.utc(2026, 8, 20),
  endDate: DateTime.utc(2026, 8, 30),
);

EnhancedSearchResult _playerResults(String name, int fideId) {
  final player = SearchPlayer(
    id: '$fideId',
    name: name,
    fideId: fideId,
    rating: 2800,
    tournamentId: _event.id,
    tournamentName: _event.title,
  );
  return EnhancedSearchResult(
    tournamentResults: const [],
    playerResults: [
      SearchResult(
        tournament: _event,
        score: 1,
        matchedText: name,
        type: SearchResultType.player,
        player: player,
      ),
    ],
  );
}

final _resultsByQuery = {
  'carlsen': _playerResults('Carlsen, Magnus', 1503014),
  'nakamura': _playerResults('Nakamura, Hikaru', 2016192),
};
