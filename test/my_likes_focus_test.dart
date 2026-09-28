import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/my_likes/my_likes_hub_screen.dart';
import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _EmptyLikes extends LikedGamesNotifier {
  @override
  Future<List<SavedAnalysis>> build() async => const [];
}

MyLikesData _data(int total) => MyLikesData(
  sections: const [],
  openableAnalyses: const [],
  totalLiked: total,
  visibleCount: 0,
);

Future<void> _pump(
  WidgetTester tester, {
  required Widget page,
  int total = 0,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        likedGamesProvider.overrideWith(_EmptyLikes.new),
        myLikesViewProvider.overrideWith((ref) async => _data(total)),
        myLikesTagCountsProvider.overrideWith((ref) async => const {}),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                disableAnimations: true,
              ),
              child: Scaffold(body: page),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

SavedAnalysis _like(String pgn) => SavedAnalysis(
  id: 'saved-like',
  userId: 'viewer',
  title: 'A liked game',
  chessGame: ChessGame.fromPgn('saved-like', pgn),
  analysisState: const {},
  variationComments: const {},
  lastViewedPosition: -1,
  tags: const [],
  isFavorite: false,
  createdAt: DateTime(2026, 9, 26),
  updatedAt: DateTime(2026, 9, 26),
);

void main() {
  testWidgets('no likes lands on About; Games and About remain selectable', (
    tester,
  ) async {
    await _pump(tester, page: const MyLikesHubScreen());
    expect(MyLikesHubScreen.tabs, ['Games', 'Players', 'About']);
    final pages = tester.widget<PageView>(find.byType(PageView));
    expect(pages.controller!.page, 2);
    expect(find.text('Keep the games you love'), findsOneWidget);
    expect(find.text('Events'), findsNothing);
    await tester.tap(find.text('Games'));
    await tester.pump();
    await tester.pump();
    expect(pages.controller!.page, 0);
    expect(find.text('No likes yet'), findsOneWidget);
    await tester.tap(find.text('About'));
    await tester.pump();
    await tester.pump();
    expect(pages.controller!.page, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('My Likes drops count, My Space and share header controls', (
    tester,
  ) async {
    await _pump(tester, page: const MyLikesGamesPage(), total: 5);
    expect(find.text('5 liked games'), findsNothing);
    expect(find.byTooltip('Add to My Space'), findsNothing);
    expect(find.byTooltip('Export as PGN'), findsNothing);
    expect(find.byIcon(Icons.ios_share_rounded), findsNothing);
    expect(
      find.text('Double-tap the chessboard to like a game.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('inline double-tap guidance disappears after five likes', (
    tester,
  ) async {
    await _pump(tester, page: const MyLikesGamesPage(), total: 6);
    expect(
      find.text('Double-tap the chessboard to like a game.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('About stays scrollable and readable with large text', (
    tester,
  ) async {
    await _pump(tester, page: const MyLikesAboutPage(), textScale: 2);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('Keep the games you love'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('saved cards retain real snapshot clocks, including zero', () {
    final game = savedAnalysisToCardGame(
      _like('''[White "White"]
[Black "Black"]
[Result "1-0"]
[WhiteClockSeconds "0"]
[BlackClockSeconds "65"]

1. e4 e5 1-0'''),
    );
    expect(game.whiteClockSeconds, 0);
    expect(game.whiteTimeDisplay, '00:00');
    expect(game.blackClockSeconds, 65);
    expect(game.blackTimeDisplay, '01:05');
  });

  test('latest PGN clock belongs to the player who made that move', () {
    final game = savedAnalysisToCardGame(
      _like('''[White "White"]
[Black "Black"]
[Result "1-0"]

1. e4 {[%clk 0:10:00]} e5 {[%clk 0:09:00]}
2. Nf3 {[%clk 0:08:00]} Nc6 {[%clk 0:07:00]} 1-0'''),
    );
    expect(game.whiteClockSeconds, 480);
    expect(game.blackClockSeconds, 420);
    expect(game.whiteTimeDisplay, '08:00');
    expect(game.blackTimeDisplay, '07:00');
  });

  test('saved cards keep absent clocks unknown instead of inventing time', () {
    final game = savedAnalysisToCardGame(
      _like('''[White "White"]
[Black "Black"]
[Result "1-0"]

1. e4 e5 1-0'''),
    );
    expect(game.whiteClockSeconds, isNull);
    expect(game.blackClockSeconds, isNull);
    expect(game.whiteClockCentiseconds, 0);
    expect(game.blackClockCentiseconds, 0);
  });
}
