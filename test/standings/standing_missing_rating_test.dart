import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

PlayerStandingModel _standing(int? rating) => PlayerStandingModel.fromPlayer(
  TournamentPlayer(
    name: 'Unrated, Player',
    federation: '',
    played: 3,
    rating: rating,
    score: 2,
  ),
);

Future<void> _pumpCard(WidgetTester tester, PlayerStandingModel player) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [playerPhotoProvider.overrideWith((ref, id) async => null)],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: FigmaPlayerCard(
                player: player,
                rank: 1,
                showFavoriteButton: false,
                onTap: () {},
              ),
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  test('a missing rating is unknown, not a published 0', () {
    final missing = _standing(null);
    expect(missing.hasRating, isFalse);
    expect(missing.score, 0, reason: 'still sorts as the lowest rating');

    final published = _standing(0);
    expect(published.hasRating, isTrue);
    expect(_standing(2412).hasRating, isTrue);

    final roundTrip = PlayerStandingModel.fromJson(missing.toJson());
    expect(roundTrip.hasRating, isFalse);
    expect(roundTrip, missing);
    expect(missing.copyWith(overallRank: 4).hasRating, isFalse);
    expect(
      PlayerStandingModel.fromJson(const {'name': 'Old cache', 'score': 2100})
          .hasRating,
      isTrue,
    );
  });

  testWidgets('a standings row leaves a missing rating blank', (tester) async {
    await _pumpCard(tester, _standing(null));
    await tester.pump();
    expect(find.text('Unrated, Player'), findsOneWidget);
    expect(find.text('0'), findsNothing);

    await _pumpCard(tester, _standing(2412));
    await tester.pump();
    expect(find.text('2412'), findsOneWidget);
  });
}
