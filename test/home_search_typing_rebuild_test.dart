import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/search/search_overlay_widget.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _OverlayHarness extends StatelessWidget {
  const _OverlayHarness({required this.query, required this.onResultsBuild});

  final String query;
  final VoidCallback onResultsBuild;

  @override
  Widget build(BuildContext context) {
    ResponsiveHelper.init(context);
    return Scaffold(
      body: SearchOverlay(
        query: query,
        onTournamentTap: (_) {},
        onPlayerTap: (_) {},
        onOpeningTap: (_) {},
        debugOnResultsBuild: onResultsBuild,
      ),
    );
  }
}

void main() {
  testWidgets('raw keystrokes do not rebuild the expensive results subtree', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        supabaseCombinedSearchProvider('seed').overrideWith(
          (ref) async => EnhancedSearchResult(
            tournamentResults: [
              SearchResult(
                tournament: const GroupEventCardModel(
                  id: 'event-1',
                  title: 'Seed Invitational',
                  dates: 'Aug 21',
                  maxAvgElo: 2700,
                  timeUntilStart: '',
                  tourEventCategory: TourEventCategory.ongoing,
                  timeControl: 'Standard',
                  endDate: null,
                  startDate: null,
                ),
                score: 100,
                matchedText: 'Seed Invitational',
                type: SearchResultType.tournament,
              ),
            ],
            playerResults: const [],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(searchQueryProvider.notifier).state = 'seed';
    container.read(debouncedSearchQueryProvider.notifier).state = 'seed';
    var resultsBuilds = 0;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: _OverlayHarness(
            query: 'seed',
            onResultsBuild: () => resultsBuilds++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Seed Invitational'), findsOneWidget);
    resultsBuilds = 0;

    container.read(searchQueryProvider.notifier).state = 'seeda';
    await tester.pump();
    container.read(searchQueryProvider.notifier).state = 'seedab';
    await tester.pump();

    expect(resultsBuilds, 0);
    expect(find.text('Searching...'), findsOneWidget);
  });

  testWidgets(
    'opening suggestions keep the established event and player columns',
    (tester) async {
      const event = GroupEventCardModel(
        id: 'event-1',
        title: 'Najdorf Masters',
        dates: 'Aug 21',
        maxAvgElo: 2700,
        timeUntilStart: '',
        tourEventCategory: TourEventCategory.ongoing,
        timeControl: 'Standard',
        endDate: null,
        startDate: null,
      );
      const player = SearchPlayer(
        id: 'player-1',
        name: 'Miguel Najdorf',
        title: 'GM',
        rating: 2540,
        fideId: 100001,
        fed: 'ARG',
        tournamentId: 'event-1',
        tournamentName: 'Najdorf Masters',
      );
      final container = ProviderContainer(
        overrides: [
          supabaseCombinedSearchProvider('najdorf').overrideWith(
            (ref) async => const EnhancedSearchResult(
              tournamentResults: [
                SearchResult(
                  tournament: event,
                  score: 100,
                  matchedText: 'Najdorf Masters',
                  type: SearchResultType.tournament,
                ),
              ],
              playerResults: [
                SearchResult(
                  tournament: event,
                  score: 100,
                  matchedText: 'Miguel Najdorf',
                  type: SearchResultType.player,
                  player: player,
                ),
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(searchQueryProvider.notifier).state = 'najdorf';
      container.read(debouncedSearchQueryProvider.notifier).state = 'najdorf';

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: _OverlayHarness(query: 'najdorf', onResultsBuild: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Openings ('), findsOneWidget);
      expect(find.text('Events (1)'), findsOneWidget);
      expect(find.text('Players (1)'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Events (1)')).dx,
        lessThan(tester.getTopLeft(find.text('Players (1)')).dx),
      );
    },
  );
}
