import 'package:chessever2/repository/gamebase/memorial_player.dart';
import 'package:chessever2/repository/gamebase/memorial_player_about.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/tabs/memorial_player_about_tab.dart';
import 'package:chessever2/screens/player_profile/widgets/player_profile_share_image_card.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('memorial knowledge renders history, biography, and sources', (
    tester,
  ) async {
    const overview = MemorialPlayerOverview(
      player: MemorialPlayer(
        id: 'tal',
        profileKey: 'memorial:tal',
        routeId: 'tal',
        sourceIdentity: 'memorial:tal',
        name: 'Tal, Mikhail',
        fed: 'LAT',
        ratingClassical: 2705,
        hasGames: true,
        sourceBacked: true,
        title: 'GM',
        birthDate: '1936-11-09',
        deathDate: '1992-06-28',
      ),
      about: MemorialPlayerAbout(
        birthPlace: 'Riga, Latvia',
        deathPlace: 'Moscow, Russia',
        summary: ['World Chess Champion and celebrated attacking player.'],
        achievements: [
          MemorialPlayerAchievement(
            year: '1960',
            label: 'Became World Chess Champion',
          ),
        ],
        sources: [
          MemorialPlayerSource(
            label: 'Biographical source',
            url: 'https://example.com/tal',
          ),
        ],
      ),
      history: MemorialPlayerHistory(
        peakPeriod: '1980-01',
        peakRapidPeriod: '1990-01',
        ratingListSpan: MemorialRatingListSpan(
          firstPeriod: '1967-06',
          lastPeriod: '1992-01',
        ),
        points: [
          MemorialRatingHistoryPoint(
            numericPeriod: 196706,
            classical: 2600,
            rapid: 2500,
          ),
          MemorialRatingHistoryPoint(
            numericPeriod: 198001,
            classical: 2705,
            rapid: 2550,
          ),
          MemorialRatingHistoryPoint(
            numericPeriod: 199001,
            classical: 2690,
            rapid: 2600,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: MemorialPlayerKnowledge(
                  overview: overview,
                  fallbackName: 'Tal, Mikhail',
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Historical ratings'), findsOneWidget);
    expect(find.text('2705'), findsOneWidget);
    expect(find.text('Life and career'), findsOneWidget);
    expect(find.text('Grandmaster'), findsOneWidget);
    expect(find.text('Riga, Latvia'), findsOneWidget);
    expect(find.textContaining('World Chess Champion'), findsWidgets);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Biographical source'), findsOneWidget);
    await tester.tap(find.text('Rapid'));
    await tester.pumpAndSettle();
    expect(find.text('2600'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('memorial share card renders exact historical labels and stats', (
    tester,
  ) async {
    const analytics = PlayerAnalytics(
      openingStats: [],
      colorStats: ColorStatistics(
        whiteGames: 2,
        whiteWins: 1,
        whiteDraws: 1,
        whiteLosses: 0,
        blackGames: 1,
        blackWins: 0,
        blackDraws: 0,
        blackLosses: 1,
      ),
      resultStats: ResultStatistics(
        totalGames: 3,
        wins: 1,
        draws: 1,
        losses: 1,
      ),
      recentForm: [1, 0.5, 0],
      avgOpponentRating: 2620,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return SingleChildScrollView(
              child: PlayerProfileShareImageCard(
                width: 320,
                playerName: 'Tal, Mikhail',
                title: 'GM',
                countryCode: 'LAT',
                fideId: 600000,
                photoFuture: Future<String?>.value(null),
                initials: 'TM',
                standardRating: 2705,
                rapidRating: null,
                blitzRating: null,
                analytics: analytics,
                isMemorial: true,
                lifespan: '1936 - 1992',
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Memorial profile'), findsOneWidget);
    expect(find.text('Peak classical'), findsOneWidget);
    expect(find.text('Historical FIDE ID 600000'), findsOneWidget);
    expect(find.text('2705'), findsOneWidget);
    expect(find.text('1936 - 1992'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
