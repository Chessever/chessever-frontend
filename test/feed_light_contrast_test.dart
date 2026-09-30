import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_widgets.dart';
import 'package:chessever2/screens/feed/widgets/feed_action_row.dart';
import 'package:chessever2/screens/feed/widgets/feed_classification.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/screens/feed/widgets/feed_post_header.dart';
import 'package:chessever2/screens/feed/widgets/feed_scrub.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The colours the Feed's widgets actually resolve, measured against what
/// they sit on, in both themes: text at 4.5:1, icons and marks at 3:1.
void main() {
  for (final light in [true, false]) {
    final name = light ? 'light' : 'dark';
    AppColors colors() => light ? AppColors.light : AppColors.dark;

    testWidgets('$name: header text reads on the page', (tester) async {
      await _pump(
        tester,
        light,
        FeedPostHeader(
          height: 44,
          parts: [
            const FeedHeaderPart(
              pieces: [
                FeedHeaderPiece.text(
                  'Your favorite',
                  tone: FeedHeaderTone.secondary,
                ),
                FeedHeaderPiece.gap(5),
                FeedHeaderPiece.text('Caruana', tone: FeedHeaderTone.strong),
              ],
            ),
            FeedHeaderPart(
              pieces: const [FeedHeaderPiece.text('Sinquefield Cup')],
              onTap: () {},
            ),
          ],
        ),
      );
      final page = colors().background;
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        final color = text.style!.color!;
        final min = text.data == FeedPostHeader.separator ? 3.0 : 4.5;
        expect(
          feedContrast(_over(color, page), page),
          greaterThanOrEqualTo(min),
          reason: '"${text.data}"',
        );
      }
    });

    testWidgets('$name: the action row reads on the page', (tester) async {
      await _pump(
        tester,
        light,
        FeedActionRow(
          height: 56,
          liked: true,
          inSpace: false,
          saved: true,
          likeIconKey: GlobalKey(),
          onLike: () {},
          onSpace: () {},
          onShare: () {},
          onSave: () {},
          onAnalyze: () {},
        ),
      );
      final page = colors().background;
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(
          feedContrast(text.style!.color!, page),
          greaterThanOrEqualTo(4.5),
          reason: text.data,
        );
      }
      // The liked heart is a mark: 3:1. The saved disk is in ink, as the
      // words are and as My Space's tick is: the heart is the row's one
      // colour.
      expect(feedContrast(colors().danger, page), greaterThanOrEqualTo(3));
      final disk = tester.widget<FeedGlyph>(
        find.byWidgetPredicate(
          (w) => w is FeedGlyph && w.svg == FeedGlyphs.saved,
        ),
      );
      expect(disk.color, colors().textPrimary);
      expect(feedContrast(disk.color, page), greaterThanOrEqualTo(4.5));
    });

    testWidgets('$name: move-class words on the scrub report', (tester) async {
      for (final moveClass in [
        MoveClass.inaccuracy,
        MoveClass.mistake,
        MoveClass.blunder,
        MoveClass.best,
        MoveClass.great,
        MoveClass.brilliant,
        MoveClass.missedWin,
      ]) {
        await _pump(
          tester,
          light,
          FeedMoveInfoRow(
            item: _item(moveClass),
            ply: 1,
            trailing: 'move 1 of 1',
            height: 24,
          ),
        );
        final label = tester.widget<Text>(find.text(feedClassLabel(moveClass)));
        expect(
          feedContrast(label.style!.color!, colors().background),
          greaterThanOrEqualTo(4.5),
          reason: moveClass.name,
        );
      }
    });

    test('$name: the scrub line stands off the page, played part apart', () {
      final page = colors().background;
      final line = FeedScrubColors.of(colors());
      // The whole track, the played part and the thumb are marks: 3:1.
      expect(feedContrast(line.track, page), greaterThanOrEqualTo(3));
      expect(feedContrast(line.played, page), greaterThanOrEqualTo(3));
      expect(feedContrast(line.played, line.track), greaterThanOrEqualTo(3));
      // The counter is text, at rest and under a finger.
      expect(feedContrast(line.counter, page), greaterThanOrEqualTo(4.5));
      expect(feedContrast(line.counterHeld, page), greaterThanOrEqualTo(4.5));
    });

    testWidgets('$name: the scrub bubble reads on its surface', (tester) async {
      await _pump(tester, light, FeedMoveBubble(item: _item(null), ply: 1));
      // The thumb's own ink.
      final surface = colors().textPrimary;
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(
          feedContrast(_over(text.style!.color!, surface), surface),
          greaterThanOrEqualTo(4.5),
          reason: text.data,
        );
      }
    });

    testWidgets('$name: the puzzle rail shows its found moves', (tester) async {
      await _pump(
        tester,
        light,
        const PuzzleProgressRail(total: 3, found: 1, shown: 2, height: 200),
      );
      final page = colors().background;
      final fills = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(PuzzleProgressRail),
              matching: find.byType(ColoredBox),
            ),
          )
          .map((box) => box.color)
          .toSet();
      final found = light ? colors().textPrimary : colors().evalWhite;
      expect(fills, contains(found));
      // Found and shown segments stand off the page as marks do.
      expect(feedContrast(found, page), greaterThanOrEqualTo(3));
      expect(
        feedContrast(colors().textTertiary, page),
        greaterThanOrEqualTo(3),
      );
    });

    test('$name: the chart cursor is a visible mark', () {
      expect(
        feedContrast(colors().accentText, colors().surfaceRecessed),
        greaterThanOrEqualTo(3),
      );
    });
  }

  test('the board editor tray inks read on the tray in both themes', () {
    const tray = Color(0xFFA1ADAE);
    const ink = Color(0xFF263032);
    const inverse = Color(0xFFF4FAF9);
    expect(feedContrast(ink, tray), greaterThanOrEqualTo(4.5));
    expect(feedContrast(inverse, ink), greaterThanOrEqualTo(4.5));
  });
}

/// [color] composited over [surface] (text inks may carry alpha).
Color _over(Color color, Color surface) =>
    Color.alphaBlend(color, surface).withValues(alpha: 1);

Future<void> _pump(WidgetTester tester, bool light, Widget child) async {
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(393, 852)),
      child: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      home: Scaffold(
        body: Center(child: SizedBox(width: 361, child: child)),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

FeedItem _item(MoveClass? moveClass) {
  final start = Chess.initial;
  final move = start.parseSan('e4')!;
  final after = start.play(move);
  return FeedItem(
    game: GamesTourModel(
      gameId: 'contrast',
      whitePlayer: PlayerCard(
        name: 'White',
        federation: '',
        title: '',
        rating: 0,
        countryCode: '',
        team: null,
      ),
      blackPlayer: PlayerCard(
        name: 'Black',
        federation: '',
        title: '',
        rating: 0,
        countryCode: '',
        team: null,
      ),
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.whiteWins,
      roundId: 'r',
      tourId: 't',
    ),
    plies: [
      FeedPly(fen: start.fen),
      FeedPly(fen: after.fen, san: 'e4', uci: move.uci, moveClass: moveClass),
    ],
    reason: '',
    result: '1-0',
  );
}
