import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_country_flags/flutter_country_flags.dart' as fcf;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<void> _pumpCard(
  WidgetTester tester,
  String countryCode, {
  bool isInactive = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerPhotoProvider.overrideWith((ref, fideId) async => null),
      ],
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
                isInactive: isInactive,
                onTap: () {},
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
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

  testWidgets('uses muted danger title badge for inactive ranking rows', (
    tester,
  ) async {
    await _pumpCard(tester, 'NOR', isInactive: true);

    final avatar = tester.widget<PlayerInitialsAvatar>(
      find.byType(PlayerInitialsAvatar),
    );
    expect(avatar.titleBadgeColor, AppColors.dark.dangerMuted);
  });
}
