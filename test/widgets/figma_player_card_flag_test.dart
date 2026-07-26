import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_country_flags/flutter_country_flags.dart' as fcf;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<void> _pumpCard(WidgetTester tester, String countryCode) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: FigmaPlayerCard(
                player: PlayerStandingModel(
                  countryCode: countryCode,
                  title: 'GM',
                  name: 'Test, Player',
                  score: 2520,
                  scoreChange: 0,
                  matchScore: '1/1',
                ),
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
  testWidgets('renders FIDE flag for explicit FIDE federation', (tester) async {
    await _pumpCard(tester, 'FIDE');

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(fcf.FlutterCountryFlags), findsNothing);
  });

  testWidgets('does not reserve a flag image for missing federation', (
    tester,
  ) async {
    await _pumpCard(tester, '');

    expect(find.byType(Image), findsNothing);
    expect(find.byType(fcf.FlutterCountryFlags), findsNothing);
  });
}
