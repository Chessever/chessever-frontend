import 'package:chessever2/repository/liked_games/game_like_count_provider.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_provider.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_sheet.dart';
import 'package:chessever2/screens/chessboard/widgets/like_flight.dart';
import 'package:chessever2/screens/chessboard/widgets/notation_footer_actions.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/board_like_heart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

final _liked = StateProvider<bool>((ref) => false);

void main() {
  Future<LikeFlightAnchor> pumpFooter(
    WidgetTester tester, {
    MobileGameReviewState review = const MobileGameReviewState(
      isEligible: true,
    ),
    int? othersLikes,
  }) async {
    final anchor = LikeFlightAnchor();
    addTearDown(anchor.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          likeFlightAnchorProvider.overrideWithValue(anchor),
          isGameLikedProvider.overrideWith((ref, _) => ref.watch(_liked)),
          gameLikeCountProvider.overrideWith((ref, _) async => othersLikes),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: NotationFooterActions(
                  children: [
                    GameAnalysisButton(state: review, onPressed: () {}),
                    const LikeGameButton(likeId: 'game-1', pageIndex: 3),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    return anchor;
  }

  testWidgets('Report and Like sit side by side at one width and height', (
    tester,
  ) async {
    await pumpFooter(tester);
    final report = tester.getRect(find.byType(GameAnalysisButton));
    final like = tester.getRect(find.byType(LikeGameButton));
    expect(report.size, like.size);
    expect(report.width, kNotationFooterButtonWidth);
    expect(report.top, like.top);
    expect(report.right, lessThan(like.left));
    // Centred as one unit.
    final screenCentre = tester.getSize(find.byType(Scaffold)).width / 2;
    expect((report.left + like.right) / 2, closeTo(screenCentre, 0.5));
  });

  testWidgets('Like runs the board gesture of its own page', (tester) async {
    final anchor = await pumpFooter(tester);
    final calls = <Offset>[];
    anchor.registerPageLike(3, calls.add);
    anchor.registerPageLike(4, (_) => fail('another page liked'));

    await tester.tap(find.text('Like'));
    expect(calls, hasLength(1));
    final heart = tester.getCenter(find.byIcon(Icons.favorite_border_rounded));
    expect(calls.single, heart, reason: 'the burst is sourced at the heart');
  });

  testWidgets('a like from anywhere fills the heart and pops it', (
    tester,
  ) async {
    await pumpFooter(tester);
    expect(find.text('Like'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LikeGameButton)),
    );
    container.read(_liked.notifier).state = true;
    await tester.pump();
    expect(find.text('Liked'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

    // Mid-spring the heart is still growing in from small.
    await tester.pump(const Duration(milliseconds: 40));
    final scale = tester
        .widgetList<Transform>(
          find.descendant(
            of: find.byWidgetPredicate((w) => w is SingleMotionBuilder),
            matching: find.byType(Transform),
          ),
        )
        .first
        .transform
        .entry(0, 0);
    expect(scale, lessThan(1));
    await tester.pumpAndSettle();
  });

  testWidgets('an unregistered page leaves Like inert', (tester) async {
    await pumpFooter(tester);
    await tester.tap(find.text('Like'));
    await tester.pump();
    expect(find.text('Like'), findsOneWidget);
  });

  testWidgets('unavailable Report says why on tap', (tester) async {
    await pumpFooter(
      tester,
      review: const MobileGameReviewState(
        unavailableMessage: 'Game analysis starts when the game ends',
      ),
    );
    expect(find.text('Game analysis starts when the game ends'), findsNothing);
    await tester.tap(find.text('Report'));
    await tester.pump();
    expect(
      find.text('Game analysis starts when the game ends'),
      findsOneWidget,
    );
  });

  group('like count in the heart', () {
    String heartText(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find.byType(LikeCountHeart),
            matching: find.byType(Text),
          ),
        )
        .data!;

    testWidgets('shows everyone else, then adds the viewer on a like', (
      tester,
    ) async {
      await pumpFooter(tester, othersLikes: 4);
      await tester.pump();
      expect(find.byType(LikeCountHeart), findsOneWidget);
      expect(heartText(tester), '4');
      expect(
        tester.widget<LikeCountHeart>(find.byType(LikeCountHeart)).fill,
        isNull,
        reason: 'not liked yet: the Most Liked ink heart',
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(LikeGameButton)),
      );
      container.read(_liked.notifier).state = true;
      await tester.pumpAndSettle();
      expect(heartText(tester), '5');
      expect(
        tester.widget<LikeCountHeart>(find.byType(LikeCountHeart)).fill,
        isNotNull,
        reason: 'liked: the heart takes the like colour',
      );
      expect(find.text('Liked'), findsOneWidget);
    });

    testWidgets('a first like turns the plain heart into a 1', (tester) async {
      await pumpFooter(tester, othersLikes: 0);
      await tester.pump();
      expect(find.byType(LikeCountHeart), findsNothing);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

      ProviderScope.containerOf(
        tester.element(find.byType(LikeGameButton)),
      ).read(_liked.notifier).state = true;
      await tester.pumpAndSettle();
      expect(heartText(tester), '1');
    });

    testWidgets('an unknown count keeps the plain heart, no guessed number', (
      tester,
    ) async {
      await pumpFooter(tester);
      await tester.pump();
      expect(find.byType(LikeCountHeart), findsNothing);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    });

    testWidgets('large counts shorten the way Most Liked does', (tester) async {
      await pumpFooter(tester, othersLikes: 1234);
      await tester.pump();
      expect(heartText(tester), '1.2K');
    });

    testWidgets('tapping the heart itself likes', (tester) async {
      final anchor = await pumpFooter(tester, othersLikes: 4);
      await tester.pump();
      final calls = <Offset>[];
      anchor.registerPageLike(3, calls.add);
      await tester.tap(find.byType(LikeCountHeart));
      expect(calls, hasLength(1));
      expect(calls.single, tester.getCenter(find.byType(LikeCountHeart)));
    });

    test('parses the RPC answer and refuses nonsense', () {
      expect(parseGameLikeCount(7), 7);
      expect(parseGameLikeCount(7.0), 7);
      expect(parseGameLikeCount('12'), 12);
      expect(parseGameLikeCount(null), isNull);
      expect(parseGameLikeCount(-1), isNull);
      expect(parseGameLikeCount('x'), isNull);
      expect(displayedGameLikes(others: 3, likedByMe: true), 4);
      expect(displayedGameLikes(others: 3, likedByMe: false), 3);
      expect(displayedGameLikes(others: null, likedByMe: true), isNull);
    });
  });
}
