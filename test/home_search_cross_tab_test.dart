import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/group_event/widget/search_results_widget.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_top_bar_parity_test.dart' show HomeShell, pumpHomeShell;

// The reported steps on the real home shell: the Events and Home tab screens
// under one app, switched by the bottom nav, sharing one provider container.
void main() {
  testWidgets(
    'Events searched "carlsen", Home searches "nakamura": the cards are Nakamura',
    (tester) async {
      final shell = await _shell(tester);

      // 1. Events: search carlsen and leave it there.
      await _type(tester, E2eIds.eventsSearchField, 'carlsen');
      expect(shell.read(searchTabQueryProvider), 'carlsen');

      // 2. Home: search nakamura.
      await shell.show(BottomNavBarItem.forYou);
      expect(shell.read(searchTabQueryProvider), 'carlsen');
      await _type(tester, E2eIds.forYouSearchField, 'nakamura');

      final results = find.byType(SearchResultsWidget);
      expect(results, findsOneWidget);
      expect(
        find.descendant(of: results, matching: find.textContaining('Nakamura')),
        findsWidgets,
      );
      expect(
        find.descendant(of: results, matching: find.textContaining('Carlsen')),
        findsNothing,
      );
      await shell.dispose();
    },
  );

  testWidgets('a fresh launch: Home search shows player cards', (tester) async {
    final shell = await _shell(tester);
    await shell.show(BottomNavBarItem.forYou);
    expect(shell.read(searchTabQueryProvider), isEmpty);

    await _type(tester, E2eIds.forYouSearchField, 'carlsen');

    expect(
      find.descendant(
        of: find.byType(SearchResultsWidget),
        matching: find.textContaining('Carlsen'),
      ),
      findsWidgets,
    );
    await shell.dispose();
  });

  testWidgets('one letter on Home asks to keep typing, not "No events match"', (
    tester,
  ) async {
    final shell = await _shell(tester);
    await shell.show(BottomNavBarItem.forYou);

    await _type(tester, E2eIds.forYouSearchField, 'k');

    expect(find.text('Keep typing to search'), findsOneWidget);
    expect(find.textContaining('No events match'), findsNothing);
    expect(find.text('No results found'), findsNothing);
    await shell.dispose();
  });

  testWidgets(
    'one letter on Events keeps the dropdown off "No results found"',
    (tester) async {
      final shell = await _shell(tester);

      await _type(tester, E2eIds.eventsSearchField, 'k');

      expect(find.text('No results found'), findsNothing);
      expect(find.textContaining('No events match'), findsNothing);
      await shell.dispose();
    },
  );
}

Future<HomeShell> _shell(WidgetTester tester) => pumpHomeShell(
  tester,
  size: const Size(393, 852),
  light: false,
  premium: false,
  overrides: [
    supabaseCombinedSearchProvider.overrideWith(
      (ref, query) async =>
          _resultsByQuery[query.trim()] ?? EnhancedSearchResult.empty(),
    ),
  ],
);

/// Types into the search field, then waits out every debounce on the path
/// (the bar's 300ms, the Events tab's 300ms, the dropdown's 400ms).
Future<void> _type(WidgetTester tester, String fieldId, String text) async {
  final field = find.byKey(e2eKey(fieldId));
  expect(field, findsOneWidget);
  await tester.tap(field);
  await tester.pump();
  await tester.enterText(field, text);
  for (var i = 0; i < 12; i++) {
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
