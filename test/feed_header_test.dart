import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/feed/logic/feed_codec.dart';
import 'package:chessever2/screens/feed/logic/feed_opening.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/widgets/feed_classification.dart';
import 'package:chessever2/screens/feed/widgets/feed_clip.dart';
import 'package:chessever2/screens/feed/widgets/feed_post_header.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Feed post header: one line whatever the width or text size, the
/// signals it carries instead of captions, the opening it can set up, and
/// its colours in both themes.
void main() {
  group('the header is one line', () {
    List<FeedHeaderPart> parts() => [
      const FeedHeaderPart(
        id: 'signal',
        pieces: [
          FeedHeaderPiece.text('Your favorite', tone: FeedHeaderTone.secondary),
          FeedHeaderPiece.gap(5),
          FeedHeaderPiece.glyph(SizedBox(width: 12), width: 12),
          FeedHeaderPiece.gap(5),
          FeedHeaderPiece.text(
            'Maxime Vachier-Lagrave',
            tone: FeedHeaderTone.strong,
          ),
        ],
        compact: [
          FeedHeaderPiece.glyph(SizedBox(width: 12), width: 12),
          FeedHeaderPiece.gap(5),
          FeedHeaderPiece.text('Vachier-Lagrave', tone: FeedHeaderTone.strong),
        ],
        shrinkable: true,
      ),
      FeedHeaderPart(
        id: 'event',
        pieces: const [
          FeedHeaderPiece.text('Grand Chess Tour Superbet Classic Romania'),
        ],
        shrinkable: true,
        onTap: () {},
      ),
      FeedHeaderPart(
        id: 'opening',
        pieces: const [
          FeedHeaderPiece.text('C65', tone: FeedHeaderTone.strong),
          FeedHeaderPiece.gap(5),
          FeedHeaderPiece.text(
            'Ruy Lopez: Berlin Defense',
            tone: FeedHeaderTone.secondary,
          ),
        ],
        compact: const [
          FeedHeaderPiece.text('C65', tone: FeedHeaderTone.strong),
        ],
        shrinkable: true,
        onTap: () {},
      ),
    ];

    for (final width in [360.0, 393.0, 430.0]) {
      for (final scale in [1.0, 1.3]) {
        for (final (name, theme) in [
          ('light', () => AppTheme.lightTheme),
          ('dark', () => AppTheme.darkTheme),
        ]) {
          testWidgets('${width.toInt()}pt, ${scale}x, $name', (tester) async {
            await _initResponsive(tester);
            await tester.pumpWidget(
              MaterialApp(
                theme: theme(),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 800),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Scaffold(
                    body: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: FeedPostHeader(
                        height: 44,
                        leading: const SizedBox(width: 16, height: 16),
                        leadingWidth: 16,
                        parts: parts(),
                        compactOrder: const [0, 2],
                        shrinkOrder: const [1, 2, 0],
                      ),
                    ),
                  ),
                ),
              ),
            );
            expect(tester.takeException(), isNull);
            final header = find.byType(FeedPostHeader);
            expect(tester.getSize(header).height, 44);
            final rect = tester.getRect(header);
            for (final element
                in find
                    .descendant(of: header, matching: find.byType(Text))
                    .evaluate()) {
              final text = element.widget as Text;
              expect(text.maxLines, 1);
              final box = tester.getRect(find.byWidget(text));
              // Inside the header, one line tall, never past its edges.
              expect(box.left, greaterThanOrEqualTo(rect.left - 0.5));
              expect(box.right, lessThanOrEqualTo(rect.right + 0.5));
              expect(box.height, lessThan(rect.height));
            }
            // The opening and the event stay reachable at every size, each
            // a full target however short its text gets.
            expect(find.text('C65'), findsOneWidget);
            expect(
              find.byKey(const ValueKey('feed_header_event')),
              findsOneWidget,
            );
            for (final id in ['event', 'opening']) {
              final target = tester.getRect(
                find.byKey(ValueKey('feed_header_$id')),
              );
              expect(target.width, greaterThanOrEqualTo(44), reason: id);
              expect(target.height, greaterThanOrEqualTo(44), reason: id);
              expect(target.right, lessThanOrEqualTo(rect.right + 0.5));
            }
          });
        }
      }
    }
  });

  group('a bare code is still a full target', () {
    for (final scale in [1.0, 1.3]) {
      testWidgets('360pt, ${scale}x', (tester) async {
        await _initResponsive(tester);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(360, 800),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FeedPostHeader(
                    height: 44,
                    parts: [
                      FeedHeaderPart(
                        id: 'opening',
                        pieces: const [
                          FeedHeaderPiece.text(
                            'E97',
                            tone: FeedHeaderTone.strong,
                          ),
                        ],
                        onTap: () {},
                      ),
                    ],
                    trailing: FeedHeaderPart(
                      id: 'difficulty',
                      pieces: const [
                        FeedHeaderPiece.text(
                          'All',
                          tone: FeedHeaderTone.secondary,
                        ),
                      ],
                      onTap: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final header = tester.getRect(find.byType(FeedPostHeader));
        final opening = tester.getRect(
          find.byKey(const ValueKey('feed_header_opening')),
        );
        expect(opening.width, greaterThanOrEqualTo(44));
        // The code still starts the line; the target grows past it.
        expect(
          tester.getRect(find.text('E97')).left,
          closeTo(header.left, 0.5),
        );
        final difficulty = tester.getRect(
          find.byKey(const ValueKey('feed_header_difficulty')),
        );
        expect(difficulty.width, greaterThanOrEqualTo(44));
        // A short label on the right stays flush with the edge.
        expect(
          tester.getRect(find.text('All')).right,
          closeTo(header.right, 1),
        );
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        semantics.dispose();
      });
    }
  });

  group('signals, not captions', () {
    test('a follow caption from an old cache becomes the favorite mark', () {
      final signal = feedSignalFromReason('Because you follow Ding Liren')!;
      expect(signal.kind, FeedSignalKind.favorite);
      expect(signal.name, 'Ding Liren');
      expect(
        feedSignalFromReason("Today's miniature · 12 moves")!.kind,
        FeedSignalKind.miniature,
      );
      expect(feedSignalFromReason('Brilliant finish'), isNull);
      expect(feedSignalFromReason('Top board today'), isNull);
    });

    test('the cache keeps the mark, and leaves streaks to the live wall', () {
      final item = _item(
        signal: const FeedSignal(FeedSignalKind.favorite, name: 'Wesley So'),
      );
      final back = decodeFlowFeedCache(
        encodeFlowFeedCache([item]),
        now: DateTime(2026, 9, 24),
      ).single;
      expect(back.signal, item.signal);

      final streak = _item(
        signal: const FeedSignal(
          FeedSignalKind.streak,
          name: 'Ding Liren',
          count: 6,
        ),
      );
      final streakBack = decodeFlowFeedCache(
        encodeFlowFeedCache([streak]),
        now: DateTime(2026, 9, 24),
      ).single;
      expect(streakBack.signal, isNull);
    });
  });

  group('the opening sets up its position', () {
    test("the game's own position after its named line", () {
      final item = _item(eco: 'C20', opening: "King's pawn game");
      // "King's pawn game" is 1.e4 e5: the game's position after ply 2.
      expect(feedOpeningFen(item.game, item.plies), item.plies[2].fen);
    });

    test('the deepest catalogue line the game played through', () {
      final item = _item(eco: 'C20', opening: null);
      final fen = feedOpeningFen(item.game, item.plies)!;
      expect(fen, item.plies[2].fen);
    });

    test('no position for a missing, unknown or Chess960 code', () {
      expect(feedOpeningFen(_item(eco: null).game, _item().plies), isNull);
      expect(feedOpeningFen(_item(eco: '?').game, _item().plies), isNull);
      final shuffled = _item(
        startFen: 'bqnbrkrn/pppppppp/8/8/8/8/PPPPPPPP/BQNBRKRN w - - 0 1',
      );
      expect(feedOpeningFen(shuffled.game, shuffled.plies), isNull);
    });
  });

  group('time control', () {
    GamesTourModel game(String? tc, {String slug = ''}) =>
        _item().game.copyWith(timeControl: tc, tourSlug: slug);

    test('the recorded time control first', () {
      expect(
        feedTimeControlOf(game('standard'), '')!.asset,
        PngAsset.classicalIcon,
      );
      expect(feedTimeControlOf(game('RAPID'), '')!.asset, PngAsset.rapidIcon);
      expect(feedTimeControlOf(game('blitz'), '')!.asset, PngAsset.blitzIcon);
    });

    test("then the event's own words; never a guess", () {
      expect(feedTimeControlOf(game(null), 'Titled Tuesday')!.label, 'Blitz');
      expect(
        feedTimeControlOf(game(null), 'World Rapid Championship')!.label,
        'Rapid',
      );
      expect(feedTimeControlOf(game(null), 'Sinquefield Cup'), isNull);
    });
  });

  group('contrast in both themes', () {
    double contrast(Color a, Color b) => feedContrast(a, b);

    for (final (name, colors) in [
      ('light', AppColors.light),
      ('dark', AppColors.dark),
    ]) {
      test('$name: move-class words read on the page', () {
        for (final moveClass in MoveClass.values) {
          final base = name == 'light'
              ? feedClassColor(moveClass)
              : feedClassTextColor(moveClass);
          final text = feedReadableOn(base, colors.background);
          expect(
            contrast(text, colors.background),
            greaterThanOrEqualTo(4.5),
            reason: '$name ${moveClass.name}',
          );
          // The hue survives the walk.
          final before = HSLColor.fromColor(base).hue;
          final after = HSLColor.fromColor(text).hue;
          expect((before - after).abs(), lessThan(2), reason: moveClass.name);
        }
      });

      test('$name: header inks read on the page', () {
        final page = colors.background;
        expect(contrast(colors.textPrimary, page), greaterThanOrEqualTo(4.5));
        expect(contrast(colors.textSecondary, page), greaterThanOrEqualTo(4.5));
        // The separator dot is decoration, but still a clear mark.
        expect(contrast(colors.textTertiary, page), greaterThanOrEqualTo(3));
        // The favorite heart is an icon: 3:1.
        expect(contrast(colors.danger, page), greaterThanOrEqualTo(3));
      });
    }
  });
}

/// The app theme reads the responsive scale, which needs a first frame.
Future<void> _initResponsive(WidgetTester tester) => tester.pumpWidget(
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

FeedItem _item({
  String? eco = 'C20',
  String? opening = "King's pawn game",
  String? startFen,
  FeedSignal? signal,
}) {
  final start = startFen == null
      ? Chess.initial
      : Chess.fromSetup(Setup.parseFen(startFen));
  Position position = start;
  final plies = <FeedPly>[FeedPly(fen: position.fen)];
  for (final san
      in startFen == null ? ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5'] : ['e4', 'e5']) {
    final move = position.parseSan(san)!;
    position = position.play(move);
    plies.add(FeedPly(fen: position.fen, san: san, uci: move.uci));
  }
  return FeedItem(
    game: GamesTourModel(
      gameId: 'g',
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
      eco: eco,
      openingName: opening,
    ),
    plies: plies,
    reason: '',
    result: '1-0',
    signal: signal,
  );
}
