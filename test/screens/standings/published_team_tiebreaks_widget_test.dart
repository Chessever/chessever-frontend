import 'package:chessever2/repository/supabase/tour/published_tiebreak.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/figma_team_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets(
    'published team values stay visible without expansion at narrow large text scale',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var opened = false;
      const values = [
        PublishedTiebreak(
          points: 9.5,
          description: 'Buchholz Cut-1',
          extendedCode: 'TB1',
        ),
        PublishedTiebreak(
          points: 0,
          description: 'Direct encounter',
          extendedCode: 'TB2',
        ),
      ];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.8)),
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: FigmaTeamCard(
                        team: const TeamStandingModel(
                          teamName: 'Published team',
                          rank: 2,
                          officialRound: 4,
                          matchPoints: 6,
                          gamePoints: 9.5,
                          matchesWon: 3,
                          matchesDrawn: 0,
                          matchesLost: 1,
                          boardsPlayed: 0,
                          players: [],
                          tiebreaks: values,
                        ),
                        rank: 2,
                        isExpanded: false,
                        onToggle: () {},
                        onTeamTap: () => opened = true,
                        expandedChildren: const [],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Buchholz Cut-1: 9.5'), findsOneWidget);
      expect(find.text('Direct encounter: 0'), findsOneWidget);
      final card = tester.getRect(find.byType(FigmaTeamCard));
      for (final text in ['Buchholz Cut-1: 9.5', 'Direct encounter: 0']) {
        final bounds = tester.getRect(find.text(text));
        expect(bounds.left, greaterThanOrEqualTo(card.left));
        expect(bounds.right, lessThanOrEqualTo(card.right));
        expect(bounds.bottom, lessThanOrEqualTo(card.bottom));
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Published team'));
      expect(opened, isTrue);
    },
  );
}
