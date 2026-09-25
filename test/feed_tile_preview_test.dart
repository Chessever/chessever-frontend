import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/feed/feed_screen.dart'
    show feedCurrentEntryKeyProvider;
import 'package:chessever2/screens/feed/feed_visibility.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_tile_board.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryMiniBoard;
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ---------------------------------------------------------------- doubles

/// Feed as it stands once it has loaded this session: no sources, no disk.
class _LoadedFeed extends FeedNotifier {
  _LoadedFeed(this.items);

  final List<FeedItem> items;

  @override
  Future<List<FeedItem>> build() async => items;
}

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

const _start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _afterE4 = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
const _afterE5 =
    'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';

FeedItem _item(String id, {List<FeedPly>? plies}) {
  PlayerCard player(String name) => PlayerCard(
    name: name,
    federation: 'NOR',
    title: 'GM',
    rating: 2800,
    countryCode: 'NO',
    team: null,
  );
  return FeedItem(
    game: GamesTourModel(
      gameId: id,
      whitePlayer: player('Carlsen, Magnus'),
      blackPlayer: player('Nakamura, Hikaru'),
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.whiteWins,
      roundId: 'round-1',
      tourId: 'tour-1',
    ),
    plies:
        plies ??
        const [
          FeedPly(fen: _start),
          FeedPly(fen: _afterE4, san: 'e4', uci: 'e2e4'),
        ],
    reason: 'Brilliant finish',
  );
}

/// A container whose disk cache answers [cached] and counts its reads.
({ProviderContainer container, List<int> reads}) _container({
  List<FeedItem> cached = const [],
  List<Override> overrides = const [],
}) {
  final reads = <int>[0];
  final container = ProviderContainer(
    overrides: [
      feedFirstPageCacheReaderProvider.overrideWithValue(() async {
        reads[0]++;
        return cached;
      }),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return (container: container, reads: reads);
}

void main() {
  group('feedTilePreviewProvider', () {
    test('without a loaded Feed, reads the first cached game and never '
        'builds the Feed', () async {
      final a = _item('a');
      final (:container, :reads) = _container(cached: [a, _item('b')]);
      final sub = container.listen(feedTilePreviewProvider, (_, __) {});
      addTearDown(sub.close);

      expect(await container.read(feedTilePreviewProvider.future), a);
      expect(reads.single, 1);
      expect(container.exists(feedProvider), isFalse);
    });

    test('with nothing cached it is null', () async {
      final (:container, reads: _) = _container();
      final sub = container.listen(feedTilePreviewProvider, (_, __) {});
      addTearDown(sub.close);

      expect(await container.read(feedTilePreviewProvider.future), isNull);
    });

    test('prefers the Feed already loaded this session, and the game it '
        'would reopen on', () async {
      final first = _item('first');
      final second = _item('second');
      final (:container, :reads) = _container(
        cached: [_item('stale')],
        overrides: [
          feedProvider.overrideWith(() => _LoadedFeed([first, second])),
        ],
      );
      await container.read(feedProvider.future);

      final sub = container.listen(feedTilePreviewProvider, (_, __) {});
      addTearDown(sub.close);
      expect(await container.read(feedTilePreviewProvider.future), first);
      expect(reads.single, 0);

      // Feed resumes on the page the viewer left.
      container.read(feedCurrentEntryKeyProvider.notifier).state =
          'game:second';
      container.invalidate(feedTilePreviewProvider);
      expect(await container.read(feedTilePreviewProvider.future), second);
    });

    test('reads again when Feed opens and closes', () async {
      final (:container, :reads) = _container(cached: [_item('a')]);
      final sub = container.listen(feedTilePreviewProvider, (_, __) {});
      addTearDown(sub.close);
      await container.read(feedTilePreviewProvider.future);
      expect(reads.single, 1);

      container.read(feedScreenOpenProvider.notifier).state = true;
      await container.read(feedTilePreviewProvider.future);
      container.read(feedScreenOpenProvider.notifier).state = false;
      await container.read(feedTilePreviewProvider.future);
      expect(reads.single, 3);
      expect(container.exists(feedProvider), isFalse);
    });
  });

  group('feedTilePly', () {
    test('the first headline moment, else the final position', () {
      const headline = FeedPly(
        fen: _afterE4,
        uci: 'e2e4',
        moment: FeedMoment(
          type: FeedMomentType.sacrifice,
          label: 'Sacrifice',
          severity: 3,
        ),
      );
      final withHeadline = _item(
        'h',
        plies: const [
          FeedPly(fen: _start),
          headline,
          FeedPly(fen: _afterE5, uci: 'e7e5'),
        ],
      );
      expect(feedTilePly(withHeadline), same(headline));

      final plain = _item(
        'p',
        plies: const [
          FeedPly(fen: _start),
          FeedPly(fen: _afterE4, uci: 'e2e4'),
          FeedPly(fen: _afterE5, uci: 'e7e5'),
        ],
      );
      expect(feedTilePly(plain)!.fen, _afterE5);
      expect(feedTilePly(_item('e', plies: const [])), isNull);
    });
  });

  group('picture marks', () {
    test('a board side lands its squares on whole device pixels', () {
      // 44 at 3x is 16.5 device pixels a square: snapped down to 16.
      expect(hubPictureMarkSide(44, 3), closeTo(128 / 3, 1e-9));
      expect(hubPictureMarkSide(44, 2), 44);
      for (final dpr in const [1.0, 2.0, 2.625, 3.0, 3.5]) {
        final side = hubPictureMarkSide(44, dpr);
        final square = side * dpr / 8;
        expect(square, closeTo(square.roundToDouble(), 1e-6));
        expect(side, lessThanOrEqualTo(44));
        expect(44 - side, lessThan(8 / dpr));
      }
    });

    testWidgets('the Feed mark draws the board centred in the tile slot, '
        'or the pixel object before Feed has a page', (tester) async {
      Future<void> pump(FeedItem? item) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              boardSettingsProviderNew.overrideWith(_BoardSettings.new),
            ],
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  return Center(
                    child: SizedBox.square(
                      dimension: 44,
                      child: FeedTileBoard(item: item),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();
      }

      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetDevicePixelRatio);

      await pump(_item('a'));
      final board = find.byType(DiscoveryMiniBoard);
      expect(board, findsOneWidget);
      expect(tester.widget<DiscoveryMiniBoard>(board).fen, _afterE4);
      expect(tester.widget<DiscoveryMiniBoard>(board).lastMove, 'e2e4');
      final slot = tester.getRect(find.byType(FeedTileBoard));
      final drawn = tester.getRect(board);
      expect(drawn.width, closeTo(128 / 3, 1e-6));
      expect(drawn.center.dx, closeTo(slot.center.dx, 1e-6));
      expect(drawn.center.dy, closeTo(slot.center.dy, 1e-6));

      await pump(null);
      expect(find.byType(DiscoveryMiniBoard), findsNothing);
      expect(find.byType(HubPixelArtwork), findsOneWidget);
    });
  });
}
