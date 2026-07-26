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
import 'package:skeletonizer/skeletonizer.dart' as skel;

Future<void> _pumpCard(
  WidgetTester tester,
  String countryCode, {
  bool isInactive = false,
  bool showRank = true,
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
                showRank: showRank,
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

  testWidgets('colors W primary and L danger for win-loss matchScore', (
    tester,
  ) async {
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
                    countryCode: '',
                    title: 'GM',
                    name: 'Morphy, Paul',
                    score: 2800,
                    scoreChange: 0,
                    matchScore: '12W-4L',
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
    await tester.pump();

    final richFinder = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText() == '12W-4L',
    );
    expect(richFinder, findsOneWidget);

    final root = tester.widget<RichText>(richFinder).text as TextSpan;
    TextSpan? winSpan;
    TextSpan? lossSpan;
    void walk(InlineSpan span) {
      if (span is TextSpan) {
        if (span.text == '12W') winSpan = span;
        if (span.text == '4L') lossSpan = span;
        for (final child in span.children ?? const <InlineSpan>[]) {
          walk(child);
        }
      }
    }

    walk(root);
    expect(winSpan, isNotNull);
    expect(winSpan!.style?.color, kPrimaryColor);
    expect(lossSpan, isNotNull);
    expect(lossSpan!.style?.color, kRedColor);
  });

  group('pending match score', () {
    Future<void> pumpScoreSlot(
      WidgetTester tester, {
      required bool pending,
      String? matchScore,
      bool reserveSlot = true,
    }) async {
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
                      countryCode: '',
                      title: 'GM',
                      name: 'Morphy, Paul',
                      score: 2800,
                      scoreChange: 0,
                      matchScore: matchScore,
                    ),
                    rank: 1,
                    showFavoriteButton: false,
                    matchScorePending: pending,
                    reserveMatchScoreSlot: reserveSlot,
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

    // The name and rating must never wait on the second source behind the
    // score, and the slot has to hold width so the number does not shove the
    // name when it lands.
    testWidgets('holds the slot while the score is still resolving', (
      tester,
    ) async {
      await pumpScoreSlot(tester, pending: true);

      expect(find.text('Morphy, Paul'), findsOneWidget);
      expect(find.text('2800'), findsOneWidget);
      // Skeletonizer is abstract, so match on the interface rather than a
      // concrete runtime type.
      expect(
        find.byWidgetPredicate((w) => w is skel.Skeletonizer),
        findsWidgets,
      );
      final slot = tester.getSize(find.text('000W-000L'));
      expect(slot.width, greaterThan(0));
    });

    // A settled lookup with no record is not "still loading" — an empty slot
    // beats a placeholder that shimmers forever.
    testWidgets('shows nothing once a lookup settles with no record', (
      tester,
    ) async {
      await pumpScoreSlot(tester, pending: false);

      expect(find.text('000W-000L'), findsNothing);
      expect(find.text('Morphy, Paul'), findsOneWidget);
    });

    testWidgets('a resolved record wins over the placeholder', (tester) async {
      await pumpScoreSlot(tester, pending: true, matchScore: '12W-4L');

      expect(find.text('000W-000L'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == '12W-4L',
        ),
        findsOneWidget,
      );
    });

    // The whole point of the reserved slot: the name column must land on the
    // same x whether the row is still resolving, short, or long.
    testWidgets('name ends on the same x for pending, short and long records', (
      tester,
    ) async {
      Future<double> nameRight({bool pending = false, String? score}) async {
        await pumpScoreSlot(tester, pending: pending, matchScore: score);
        return tester.getRect(find.text('Morphy, Paul')).right;
      }

      final whilePending = await nameRight(pending: true);
      final shortRecord = await nameRight(score: '5W-2L');
      final longRecord = await nameRight(score: '172W-41L');

      expect(shortRecord, whilePending);
      expect(longRecord, whilePending);
    });

    testWidgets('lists that do not opt in keep the slot content-sized', (
      tester,
    ) async {
      await pumpScoreSlot(
        tester,
        pending: false,
        matchScore: '5W-2L',
        reserveSlot: false,
      );
      final unreserved = tester.getRect(find.text('Morphy, Paul')).right;

      await pumpScoreSlot(tester, pending: false, matchScore: '5W-2L');
      final reserved = tester.getRect(find.text('Morphy, Paul')).right;

      expect(unreserved, greaterThan(reserved));
    });
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

  // A ranking list is about the rating, so it takes the trailing slot from the
  // heart — and must not then be printed a second time under the name.
  testWidgets('trailingRating replaces the heart and is not duplicated', (
    tester,
  ) async {
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
                    countryCode: 'NOR',
                    title: 'GM',
                    name: 'Carlsen, Magnus',
                    score: 2823,
                    scoreChange: 0,
                    matchScore: null,
                  ),
                  rank: 1,
                  trailingRating: 2823,
                  showFavoriteButton: false,
                  onTap: () {},
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.favorite), findsNothing);
    expect(find.byIcon(Icons.favorite_border), findsNothing);
    expect(
      find.text('2823'),
      findsOneWidget,
      reason: 'the inline rating under the name must be dropped, not repeated',
    );
    // Sits in the trailing slot, hard right.
    expect(tester.getRect(find.text('2823')).right, greaterThan(300));
  });

  // A search hit inside a ranked list holds no world rank, so the slot goes
  // empty rather than claiming one — and it must not fall back to the
  // "still resolving" shimmer either.
  testWidgets('an unranked row leaves the slot empty, not shimmering', (
    tester,
  ) async {
    await _pumpCard(tester, 'NOR', showRank: false);

    expect(find.text('1'), findsNothing);
    expect(find.text('00'), findsNothing);

    // The slot still holds its width, so the name lands where it always does.
    final withRank = await () async {
      await _pumpCard(tester, 'NOR');
      return tester.getRect(find.text('Test, Player')).left;
    }();
    await _pumpCard(tester, 'NOR', showRank: false);
    expect(tester.getRect(find.text('Test, Player')).left, withRank);
  });
}
